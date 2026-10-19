import { atom, memberOf, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { DosiFacts, DosiPaneTab } from '../types'
import { progress, refresh, statusText } from './facts'
import { extractJson } from './parse'
import { band, classify, markdownTable, pane, resultRow } from './views'

// L1 (Claude Code only): live facts in the status line and /dosi, a band above
// the prompt when there is something to act on, a lineage pane, and dosi JSON
// results drawn as tables. Presentation only: the model reads what it always
// did, and with the mod off every skill works the same (RFC §6.8, issue #5).

const PANE = 'dosi-lineage'
// The same values facts.ts writes: the scan wants each file's own const.
const facts = atom({ plugin: 'dosi', key: 'facts' } as const, null)
const graph = atom({ plugin: 'dosi', key: 'graph' } as const, null)
const calls = atom({ plugin: 'dosi', key: 'calls' } as const, {})
const tab = atom({ plugin: 'dosi', key: 'tab' } as const, 'lineage')
const focus = atom({ plugin: 'dosi', key: 'focus' } as const, '')
const htmlPath = atom({ plugin: 'dosi', key: 'htmlPath' } as const, '')
const isSqlOpen = atom({ plugin: 'dosi', key: 'isSqlOpen' } as const, false)

const RUNS_DOSI = /(^|[\s/;&|(])dosi\s/
const TOUCHES_DOSI = /(^|[\s/;&|(])dosi(-progress)?\s/
const DOSI_FILE = /(^|\/)(dosi\/(model|ontology)\.yaml|dosi-connections\.yaml)$/
const ANSWERS = ['yes', 'later', 'never'] as const

async function sync($: EngineInterface, force = false): Promise<DosiFacts | null> {
  try {
    const f = await refresh($, force)
    $.ui.status(statusText(f))
    return f
  } catch {
    // a status line is never worth failing anything over
    return null
  }
}

async function openPane($: EngineInterface, to?: DosiPaneTab, at?: string) {
  if (to) await update($, tab, () => to)
  if (at) await update($, focus, () => at)
  await $.ui.open({ id: PANE, title: 'dosi' })
}

function summary(f: DosiFacts | null, next: string): string {
  if (!f) return 'dosi: no facts yet (the plugin is still starting).'
  const lines: string[] = [`dosi · stage ${f.stage}${f.isBinReady ? '' : ' · binary still installing'}`]
  const def = f.connections.find(c => c.isDefault) ?? f.connections[0]
  const others = f.connections.filter(c => c !== def).map(c => c.name)
  lines.push(
    `connection  ${def ? `${def.type || '?'}:${def.name}${def.isDefault ? ' (default)' : ''}${others.length ? ` · also ${others.join(', ')}` : ''}` : f.sources.length ? `none yet · found ${f.sources.join(', ')}` : 'none yet'}`,
  )
  if (f.model) {
    const m = f.model
    const health = m.issues.length ? `✗ ${m.issues.length} issue${m.issues.length === 1 ? '' : 's'}` : '✓ valid'
    lines.push(
      `model       ${m.path} · ${health}${m.warnings ? ` (${m.warnings} warning${m.warnings === 1 ? '' : 's'})` : ''} · ${m.datasets} datasets · ${m.metrics.length} metrics · ${m.dimensions} dimensions`,
    )
    const names = m.metrics.map(x => x.name)
    if (names.length) lines.push(`metrics     ${names.slice(0, 6).join(', ')}${names.length > 6 ? ` … (+${names.length - 6})` : ''}`)
  } else {
    lines.push('model       none yet')
  }
  lines.push(
    `ontology    ${f.ontology ? `${f.ontology.path} · ${f.ontology.concepts.length} concepts: ${f.ontology.concepts.join(', ')}` : '—'}`,
  )
  const hint = next.split('\n')[0]?.replace(/^(HINT|ASK): /, '').split(' | ')[0]
  lines.push(`next        ${hint || 'ask a data question'}`)
  lines.push('more        /dosi lineage [metric] · /dosi metrics · /dosi refresh')
  return lines.join('\n')
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'dosi',
      description: 'Dosi: connection, model, metrics and the next step; /dosi lineage opens the lineage pane',
      argumentHint: '[lineage [metric] | metrics | refresh]',
    })
    await sync($, true)
    return next(e)
  })

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const isDosi = TOUCHES_DOSI.test(e.command)
    if (isDosi && RUNS_DOSI.test(e.command) && e.tool_use_id) {
      const id = e.tool_use_id
      await update($, calls, all => {
        const kept = Object.entries(all).slice(-49)
        return { ...Object.fromEntries(kept), [id]: e.command }
      })
    }
    const ran = await next(e)
    if (isDosi) await sync($)
    return ran
  }).catch(($, e, next) => next(e))

  on('tool.call', async ($, e, next) => {
    const ran = await next(e)
    const path = (e as { file_path?: unknown }).file_path
    if (['Write', 'Edit', 'MultiEdit'].includes(String(e.tool)) && typeof path === 'string' && DOSI_FILE.test(path)) {
      await sync($)
    }
    return ran
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'dosi' }, async ($, e) => {
    const [sub = '', arg = ''] = e.args.trim().split(/\s+/)
    if (sub === 'lineage' || sub === 'graph') {
      const f = await sync($)
      const at = arg ? (arg.includes(':') ? arg : `metric:${arg}`) : undefined
      await openPane($, 'lineage', at)
      return { text: f?.model ? `Lineage pane opened${arg ? ` on ${arg}` : ''}.` : 'No semantic model yet: the pane will fill once dosi/model.yaml exists.' }
    }
    if (sub === 'metrics') {
      const f = await sync($)
      const ms = f?.model?.metrics ?? []
      if (ms.length === 0) return { text: 'No metrics yet.' }
      return { text: markdownTable(ms.map(m => ({ metric: m.name, kind: m.kind, description: m.description })), 200) }
    }
    const f = await sync($, sub === 'refresh')
    return { text: summary(f, await progress($, ['peek'])) }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const els = $.ui.resolve(e)
    const [f, g, t, at, html] = await Promise.all([
      read($, facts),
      read($, graph),
      read($, tab),
      read($, focus),
      read($, htmlPath),
    ])
    return pane(els, {
      facts: f,
      graph: g,
      tab: t,
      focus: at,
      htmlPath: html,
      columns: e.props.bodyColumns,
      onTab: to => void update($, tab, () => to),
      onFocus: id => void update($, focus, () => id),
      onHtml: async () => {
        const root = await $.session.root()
        // Into the temp dir, as the dosi-view skill does: never the project.
        const write = 'out="${TMPDIR:-/tmp}/dosi-lineage.html"; sh "$0" lineage view --no-open --out "$out" >/dev/null && printf %s "$out"'
        const run = await $.process.run(['sh', '-c', write, `${$.plugin.root}/bin/dosi`], {
          cwd: root,
          env: { CLAUDE_PROJECT_DIR: root },
          timeoutMs: 20000,
        })
        const out = run.stdout.trim()
        if (run.exitCode === 0 && out) {
          await update($, htmlPath, () => out)
        } else {
          $.ui.toast('dosi: could not write the lineage page')
        }
      },
    })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || e.props.isWorking || e.props.view.agentId) return next(e)
    const f = await read($, facts)
    if (!f) return next(e)
    const els = $.ui.resolve(e)
    const drawn = band(els, f, {
      connect: () => void $.prompt.submit({ text: 'Connect to my data', asUser: true }),
      issues: () => void openPane($, 'issues'),
      answer: async i => {
        const ask = f.ask
        if (!ask) return
        await progress($, ['next'])
        await progress($, ['answer', ask.id, ANSWERS[i] ?? 'later'])
        if (i === 0) {
          await $.prompt.submit({ text: `${ask.text}\n→ ${ask.options[0] ?? ''}` })
        }
        await sync($)
      },
    })
    return drawn ?? next(e)
  })

  on('ui.render', { component: 'ToolResult' }, async ($, e, next) => {
    if (e.props.tool !== 'Bash') return next(e)
    const command = (await read($, calls))[e.props.tool_use_id]
    if (!command || !/--format[\s=]json/.test(command)) return next(e)
    const out = e.props.output
    const text =
      typeof out === 'string' ? out : out && typeof out === 'object' ? String((out as { stdout?: unknown }).stdout ?? '') : ''
    const doc = extractJson(text)
    if (classify(doc) === null) return next(e)
    const f = await read($, facts)
    const named = /--connection[\s=](\S+)/.exec(command)?.[1]
    const conn = named ?? (f?.connections.find(c => c.isDefault) ?? f?.connections[0])?.name
    const dialect = (doc as { dialect?: unknown }).dialect
    const source = [typeof dialect === 'string' ? dialect : '', conn ?? ''].filter(Boolean).join(':') || 'dosi'
    const sqlOpen = memberOf(isSqlOpen, e)
    const els = $.ui.resolve(e)
    return (
      resultRow(els, doc, {
        source,
        isSqlOpen: await read($, sqlOpen),
        toggleSql: () => void update($, sqlOpen, v => !v),
        openPane: () => void openPane($, 'lineage'),
      }) ?? next(e)
    )
  })
}
