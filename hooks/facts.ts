// What the dosi mod knows about the project, gathered through `$` and never
// through the model: the progress engine, the CLI's JSON and file existence.
// The connections file is read here for names and types only (parse.ts).
import { atom, read, update } from 'claude-code'
import type { EngineInterface } from 'claude-code'

import type { DosiFacts } from '../types'
import { extractJson, parseAsk, parseConnections, parseGraph, parseMetrics, parseValidate } from './parse'

const facts = atom({ plugin: 'dosi', key: 'facts' } as const, null)
const graph = atom({ plugin: 'dosi', key: 'graph' } as const, null)

type Run = { code: number; out: string }

async function sh($: EngineInterface, root: string, argv: string[]): Promise<Run> {
  try {
    const run = await $.process.run(['sh', ...argv], {
      cwd: root,
      env: { CLAUDE_PROJECT_DIR: root },
      timeoutMs: 15000,
    })
    return { code: run.exitCode, out: run.stdout }
  } catch {
    return { code: -1, out: '' }
  }
}

export async function progress($: EngineInterface, args: string[]): Promise<string> {
  const root = await $.session.root()
  const run = await sh($, root, [`${$.plugin.root}/bin/dosi-progress`, ...args])
  return run.code === 0 ? run.out.trim() : ''
}

/** The installed dosi through the plugin's shim, JSON out, parsed. */
export async function dosi($: EngineInterface, root: string, args: string[]): Promise<unknown> {
  const run = await sh($, root, [`${$.plugin.root}/bin/dosi`, '--format', 'json', ...args])
  return extractJson(run.out)
}

async function mtime($: EngineInterface, path: string): Promise<number> {
  try {
    return (await $.fs.stat(path)).mtimeMs
  } catch {
    return 0
  }
}

/** What step 1 could connect from, by existence only (as session-start.sh). */
async function sources($: EngineInterface, root: string): Promise<string[]> {
  const found: string[] = []
  const has = (p: string) => $.fs.exists(`${root}/${p}`).catch(() => false)
  if (await has('dbt_project.yml')) found.push('dbt')
  if (await has('.env')) found.push('.env')
  try {
    const files = (await $.fs.list(root)).filter(f => f.kind === 'file')
    for (const f of files) {
      if (/\.(duckdb|sqlite|parquet|csv)$/.test(f.name)) found.push(f.name)
    }
  } catch {
    // an unreadable folder only means nothing found
  }
  return found.slice(0, 4)
}

/**
 * Re-reads the facts when a file they come from changed (or when `force`),
 * and writes them to state; the status line, band and pane redraw from it.
 */
export async function refresh($: EngineInterface, force = false): Promise<DosiFacts | null> {
  const root = await $.session.root()
  const modelPath = `${root}/dosi/model.yaml`
  const ontologyPath = `${root}/dosi/ontology.yaml`
  const connPath = `${root}/dosi-connections.yaml`
  const [m, o, c] = await Promise.all([mtime($, modelPath), mtime($, ontologyPath), mtime($, connPath)])
  const [stage, peek] = await Promise.all([progress($, ['stage']), progress($, ['peek'])])
  const signature = `${m}|${o}|${c}`
  const prev = await read($, facts)
  if (!force && prev && prev.signature === signature && prev.isBinReady) {
    const next = { ...prev, stage: stage || prev.stage, ask: parseAsk(peek) }
    await update($, facts, () => next)
    return next
  }

  const connections = c ? parseConnections(await $.fs.read(connPath).catch(() => '')) : []
  let isBinReady = true
  let model: DosiFacts['model'] = null
  let ontology: DosiFacts['ontology'] = null
  if (m) {
    const [ds, ms, dims, val, lin] = await Promise.all([
      dosi($, root, ['list', 'datasets']),
      dosi($, root, ['list', 'metrics']),
      dosi($, root, ['list', 'dimensions']),
      dosi($, root, ['validate']),
      dosi($, root, ['lineage', 'dump']),
    ])
    const code = (ds as { code?: string } | undefined)?.code
    isBinReady = code !== 'dosi_installing' && code !== 'install_failed'
    const checked = parseValidate(val)
    model = {
      path: 'dosi/model.yaml',
      datasets: Array.isArray(ds) ? ds.length : 0,
      metrics: parseMetrics(ms),
      dimensions: Array.isArray(dims) ? dims.length : 0,
      issues: checked.issues,
      warnings: checked.warnings,
    }
    await update($, graph, () => parseGraph(lin))
  } else {
    await update($, graph, () => null)
  }
  if (o) {
    const described = (await dosi($, root, ['describe'])) as { concepts?: { name?: string }[] } | undefined
    ontology = {
      path: 'dosi/ontology.yaml',
      concepts: (described?.concepts ?? []).map(x => String(x.name ?? '')).filter(Boolean),
    }
  }
  const next: DosiFacts = {
    stage: stage || 'S0',
    ask: parseAsk(peek),
    isBinReady,
    sources: m ? [] : await sources($, root),
    connections,
    model,
    ontology,
    signature,
  }
  await update($, facts, () => next)
  return next
}

/** The status line: the live facts in one short line. */
export function statusText(f: DosiFacts | null): string {
  if (!f) return 'dosi'
  if (!f.isBinReady) return 'dosi · installing'
  const parts = ['dosi']
  const conn = f.connections.find(x => x.isDefault) ?? f.connections[0]
  if (conn) parts.push(conn.type ? `${conn.type}:${conn.name}` : conn.name)
  if (f.model) {
    parts.push(`${f.model.datasets} ds · ${f.model.metrics.length} metrics`)
    const errors = f.model.issues.length
    if (errors) parts.push(`⚠ ${errors} issue${errors === 1 ? '' : 's'}`)
  } else if (!conn) {
    parts.push('not connected')
  } else {
    parts.push('no model')
  }
  if (f.ontology) parts.push(`ontology ${f.ontology.concepts.length}`)
  return parts.join(' · ')
}
