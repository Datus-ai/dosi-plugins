// Pure parsers for the dosi mod: CLI JSON and project files → the shapes the
// state contract declares. No `$` here, so the tests can run them as is.
import type { DosiConnection, DosiEdge, DosiGraph, DosiIssue, DosiMetric, DosiNode } from '../types'

type Json = Record<string, unknown>

const asList = (v: unknown): Json[] => (Array.isArray(v) ? (v as Json[]) : [])
const asText = (v: unknown): string => (typeof v === 'string' ? v : v == null ? '' : String(v))

/**
 * The JSON document in a tool's output text. Bash merges stderr warnings and,
 * on a non-zero exit, prefixes the exit code, so the document is the first
 * line opening with `{` or `[` up to its last closing bracket.
 */
export function extractJson(text: string): unknown {
  const trimmed = text.trim()
  try {
    return JSON.parse(trimmed)
  } catch {
    // fall through to the line scan
  }
  const lines = trimmed.split('\n')
  for (let i = 0; i < lines.length; i++) {
    const head = lines[i]?.trimStart() ?? ''
    if (!head.startsWith('{') && !head.startsWith('[')) continue
    const rest = lines.slice(i).join('\n')
    const close = Math.max(rest.lastIndexOf('}'), rest.lastIndexOf(']'))
    try {
      return JSON.parse(rest.slice(0, close + 1))
    } catch {
      // keep scanning
    }
  }
  return undefined
}

/**
 * Connection names, types and the default flag from `dosi-connections.yaml`.
 * Reads only those three keys line by line; every other value (hosts, users,
 * `${VAR}` references) is skipped and never leaves this function.
 */
export function parseConnections(yaml: string): DosiConnection[] {
  const out: DosiConnection[] = []
  let inBlock = false
  let entryIndent = -1
  for (const raw of yaml.split('\n')) {
    const line = raw.replace(/\s+#.*$/, '')
    if (!line.trim()) continue
    const indent = line.length - line.trimStart().length
    if (indent === 0) {
      inBlock = /^datasources\s*:/.test(line)
      entryIndent = -1
      continue
    }
    if (!inBlock) continue
    const key = /^(\s*)([A-Za-z0-9_.-]+)\s*:\s*(.*)$/.exec(line)
    if (!key) continue
    const [, , name = '', value = ''] = key
    if (entryIndent < 0 || indent === entryIndent) {
      entryIndent = indent
      out.push({ name, type: '', isDefault: false })
      continue
    }
    const last = out[out.length - 1]
    if (!last || indent <= entryIndent) continue
    if (name === 'type') last.type = value.replace(/^['"]|['"]$/g, '')
    if (name === 'default') last.isDefault = /^true$/i.test(value)
  }
  return out
}

/** The `ASK:` line of `dosi-progress peek`: the question and its options. */
export function parseAsk(peek: string): { id: string; text: string; options: string[] } | null {
  const first = peek.split('\n')[0] ?? ''
  if (!first.startsWith('ASK: ')) return null
  const [text = '', ...options] = first.slice(5).split(' | ').map(s => s.trim())
  const id = /dosi-progress answer (\S+)/.exec(peek)?.[1] ?? ''
  return id ? { id, text, options } : null
}

export function parseMetrics(json: unknown): DosiMetric[] {
  return asList(json).map(m => ({
    name: asText(m.name),
    kind: asText(m.kind),
    datasets: asList(m.datasets).map(asText),
    description: asText(m.description),
  }))
}

export function parseValidate(json: unknown): { issues: DosiIssue[]; warnings: number } {
  const doc = (json ?? {}) as Json
  const toIssue = (i: Json): DosiIssue => ({
    severity: asText(i.severity) || 'error',
    code: asText(i.code),
    location: asText(i.location),
    message: asText(i.message),
  })
  return {
    issues: [...asList(doc.issues), ...asList(doc.compile_errors)].map(toIssue),
    warnings: asList(doc.warnings).length,
  }
}

/** `dosi lineage dump` (graph contract v2), cut down to what the pane draws. */
export function parseGraph(json: unknown): DosiGraph | null {
  const doc = json as Json | undefined
  if (!doc || !Array.isArray(doc.nodes) || !Array.isArray(doc.edges)) return null
  const layers = asList(doc.layers).map(l => asText(l.kind))
  const nodes: DosiNode[] = asList(doc.nodes).map(n => {
    const d = (n.detail ?? {}) as Json
    const detail = asText(d.expression) || asText(d.description) || asText(d.source) || asText(d.table)
    return {
      id: asText(n.id),
      kind: asText(n.kind),
      layer: typeof n.layer === 'number' ? n.layer : 0,
      label: asText(n.label) || asText(n.name),
      detail,
    }
  })
  const edges: DosiEdge[] = asList(doc.edges).map(e => ({
    source: asText(e.source),
    target: asText(e.target),
    kind: asText(e.kind),
  }))
  return { layers, nodes, edges }
}
