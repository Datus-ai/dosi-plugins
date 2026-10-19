// The dosi mod's drawings: the lineage pane, the band above the prompt and
// dosi result rows. Each takes the surface's element table from `$.ui.resolve`.
import type { ElementTable } from 'claude-code'

import type { DosiFacts, DosiGraph, DosiPaneTab } from '../types'
import { focusChoices, isUpstream, kindLabel, lineageSvg, lineageTree } from './lineage'

type Els = ElementTable

const KIND_COLOR: Record<string, string> = {
  physical_table: 'subtle',
  dataset: 'success',
  metric_atomic: 'warning',
  metric_derived: 'merged',
}

const cell = (v: unknown): string => {
  if (v === null || v === undefined) return '∅'
  const s = typeof v === 'number' ? (Number.isInteger(v) ? String(v) : v.toLocaleString('en-US', { maximumFractionDigits: 4 })) : String(v)
  return s.replace(/\|/g, '\\|').replace(/\n/g, ' ')
}

/** A Markdown table of up to `max` rows, columns in the order the rows give. */
export function markdownTable(rows: Record<string, unknown>[], max = 20): string {
  const cols = Object.keys(rows[0] ?? {})
  if (cols.length === 0) return '_no rows_'
  const head = `| ${cols.map(c => cell(c.replace(/__/g, '.'))).join(' | ')} |`
  const rule = `| ${cols.map(() => '---').join(' | ')} |`
  const body = rows.slice(0, max).map(r => `| ${cols.map(c => cell(r[c])).join(' | ')} |`)
  return [head, rule, ...body].join('\n')
}

export type Tab = { tab: DosiPaneTab; label: string; hotkey: string }

export function pane(
  els: Els,
  o: {
    facts: DosiFacts | null
    graph: DosiGraph | null
    tab: DosiPaneTab
    focus: string
    htmlPath: string
    columns: number
    onTab: (t: DosiPaneTab) => void
    onFocus: (id: string) => void
    onHtml: () => void
  },
) {
  const { Box, Text, Button, Markdown, Link } = els
  const issues = o.facts?.model?.issues ?? []
  const tabs: Tab[] = [
    { tab: 'lineage', label: 'Lineage', hotkey: 'l' },
    { tab: 'metrics', label: 'Metrics', hotkey: 'm' },
    { tab: 'issues', label: issues.length ? `Issues (${issues.length})` : 'Issues', hotkey: 'i' },
  ]
  const bar = (
    <Box key="tabs" flexDirection="row" gap={1}>
      {tabs.map(t => (
        <Button
          key={`tab-${t.tab}`}
          label={t.label}
          hotkey={t.hotkey}
          variant={t.tab === o.tab ? 'primary' : 'secondary'}
          onPress={() => o.onTab(t.tab)}
        />
      ))}
    </Box>
  )
  if (!o.facts?.model) {
    return (
      <Box flexDirection="column">
        {bar}
        <Text dimColor>No semantic model yet. Ask a data question, or say "build a semantic model".</Text>
      </Box>
    )
  }
  if (o.tab === 'metrics') {
    const rows = o.facts.model.metrics.map(m => ({
      metric: m.name,
      kind: m.kind,
      datasets: m.datasets.join(', '),
      description: m.description,
    }))
    return (
      <Box flexDirection="column">
        {bar}
        <Markdown key="metrics" text={markdownTable(rows, 200)} />
      </Box>
    )
  }
  if (o.tab === 'issues') {
    return (
      <Box flexDirection="column">
        {bar}
        {issues.length === 0 && <Text color="success">✓ dosi/model.yaml validates ({o.facts.model.warnings} warnings)</Text>}
        {issues.map(i => (
          <Box flexDirection="column" marginTop={1}>
            <Text color="error">✗ {i.code}</Text>
            <Text>{i.message}</Text>
            <Text dimColor>{i.location}</Text>
          </Box>
        ))}
      </Box>
    )
  }
  const g = o.graph
  if (!g || g.nodes.length === 0) {
    return (
      <Box flexDirection="column">
        {bar}
        <Text dimColor>The lineage graph is not available (the model does not validate yet).</Text>
      </Box>
    )
  }
  const choices = focusChoices(g)
  const focus = choices.some(c => c.value === o.focus) ? o.focus : (choices[0]?.value ?? '')
  const rows = lineageTree(g, focus)
  const picker =
    'Select' in els ? (
      <els.Select
        key="focus"
        label={isUpstream(focus) ? 'Computed from' : 'Used by'}
        value={focus}
        options={choices}
        onSelect={(v: string) => o.onFocus(v)}
      />
    ) : null
  const svg =
    'Svg' in els ? (
      <els.Svg
        source={lineageSvg(g, focus)}
        alt={rows.map(r => r.node.label).join(' ← ')}
        isInteractive
      />
    ) : null
  const room = Math.max(20, o.columns - 4)
  return (
    <Box flexDirection="column">
      {bar}
      {picker}
      {svg}
      <Box key="tree" flexDirection="column" marginTop={1}>
        {rows.map(r => (
          <Text wrap="truncate-end">
            <Text dimColor>{r.prefix}</Text>
            <Text color={KIND_COLOR[r.node.kind] ?? 'text'} bold={r.node.id === focus}>
              {r.node.label}
            </Text>
            <Text dimColor>
              {' '}
              {kindLabel(r.node.kind)}
              {r.node.detail && r.prefix.length + r.node.label.length + 12 < room ? ` · ${r.node.detail}` : ''}
            </Text>
          </Text>
        ))}
      </Box>
      <Box key="foot" flexDirection="row" gap={1} marginTop={1}>
        <Button key="html" label="Write HTML page" hotkey="h" onPress={() => o.onHtml()} />
        {o.htmlPath ? <Link href={`file://${o.htmlPath}`}>open {o.htmlPath}</Link> : null}
      </Box>
    </Box>
  )
}

export function band(
  els: Els,
  f: DosiFacts,
  on: { connect: () => void; issues: () => void; answer: (index: number) => void },
) {
  const { Box, Text, Button } = els
  if (f.ask) {
    const ask = f.ask
    return (
      <Box flexDirection="row" gap={1}>
        <Text color="claude">dosi</Text>
        <Text wrap="truncate-end">{ask.text}</Text>
        {ask.options.map((opt, i) => (
          <Button key={`ask-${i}`} label={opt} hotkey={String(i + 1)} variant={i === 0 ? 'primary' : 'secondary'} onPress={() => on.answer(i)} />
        ))}
      </Box>
    )
  }
  const issues = f.model?.issues ?? []
  if (issues.length > 0) {
    return (
      <Box flexDirection="row" gap={1}>
        <Text color="error">dosi ⚠</Text>
        <Text wrap="truncate-end">
          dosi/model.yaml: {issues.length} issue{issues.length === 1 ? '' : 's'} · {issues[0]?.message ?? ''}
        </Text>
        <Button key="issues" label="Show" hotkey="s" onPress={() => on.issues()} />
      </Box>
    )
  }
  if (f.stage === 'S0' && f.connections.length === 0 && f.sources.length > 0) {
    return (
      <Box flexDirection="row" gap={1}>
        <Text color="claude">dosi</Text>
        <Text wrap="truncate-end">found {f.sources.join(', ')}</Text>
        <Button key="connect" label="Connect" hotkey="c" variant="primary" onPress={() => on.connect()} />
      </Box>
    )
  }
  return null
}

type DosiDoc = Record<string, unknown>

/** What kind of dosi JSON a result row holds, or null to leave the row alone. */
export function classify(doc: unknown): 'rows' | 'error' | 'validate' | 'graph' | 'metrics' | null {
  if (Array.isArray(doc)) {
    const first = doc[0] as DosiDoc | undefined
    return first && 'name' in first && 'kind' in first && 'datasets' in first ? 'metrics' : null
  }
  if (!doc || typeof doc !== 'object') return null
  const d = doc as DosiDoc
  if (Array.isArray(d.rows)) return 'rows'
  if (typeof d.code === 'string' && typeof d.message === 'string') return 'error'
  if (Array.isArray(d.issues) && Array.isArray(d.warnings)) return 'validate'
  if (Array.isArray(d.nodes) && Array.isArray(d.edges)) return 'graph'
  return null
}

export function resultRow(
  els: Els,
  doc: unknown,
  o: { source: string; isSqlOpen: boolean; toggleSql: () => void; openPane: () => void },
) {
  const { Box, Text, Button, Markdown, Code } = els
  const kind = classify(doc)
  const d = doc as DosiDoc
  if (kind === 'rows') {
    const rows = d.rows as Record<string, unknown>[]
    const sql = typeof d.sql === 'string' ? d.sql : ''
    const more = rows.length > 20 ? ` · first 20 shown` : ''
    return (
      <Box flexDirection="column">
        <Markdown key="table" text={markdownTable(rows)} />
        <Box flexDirection="row" gap={1}>
          <Text dimColor>
            {o.source} · {rows.length} row{rows.length === 1 ? '' : 's'}
            {more}
          </Text>
          {sql ? <Button key="sql" plain label={o.isSqlOpen ? 'SQL ▾' : 'SQL ▸'} onPress={() => o.toggleSql()} /> : null}
        </Box>
        {o.isSqlOpen && sql ? <Code source={sql} language="sql" /> : null}
      </Box>
    )
  }
  if (kind === 'error') {
    const candidates = Array.isArray(d.candidates) ? (d.candidates as unknown[]).map(String) : []
    const hint = typeof d.hint === 'string' ? d.hint : candidates.length ? `did you mean: ${candidates.slice(0, 6).join(', ')}` : ''
    return (
      <Box flexDirection="column">
        <Text color="error">✗ {String(d.code)}</Text>
        <Text>{String(d.message).split('\n')[0]}</Text>
        {hint ? <Text dimColor>→ {hint}</Text> : null}
      </Box>
    )
  }
  if (kind === 'validate') {
    const issues = [...(d.issues as DosiDoc[]), ...((d.compile_errors as DosiDoc[] | undefined) ?? [])]
    const warnings = (d.warnings as unknown[]).length
    if (issues.length === 0) {
      return <Text color="success">✓ model validates{warnings ? ` · ${warnings} warning${warnings === 1 ? '' : 's'}` : ''}</Text>
    }
    return (
      <Box flexDirection="column">
        {issues.slice(0, 8).map(i => (
          <Text>
            <Text color="error">✗ {String(i.code ?? '')}</Text> {String(i.message ?? '')}
          </Text>
        ))}
      </Box>
    )
  }
  if (kind === 'graph') {
    const count = (k: string) => (d.nodes as DosiDoc[]).filter(n => n.kind === k).length
    return (
      <Box flexDirection="row" gap={1}>
        <Text dimColor>
          lineage · {count('physical_table')} tables · {count('dataset')} datasets ·{' '}
          {count('metric_atomic') + count('metric_derived')} metrics
        </Text>
        <Button key="pane" plain label="open lineage pane" onPress={() => o.openPane()} />
      </Box>
    )
  }
  if (kind === 'metrics') {
    const rows = (doc as DosiDoc[]).map(m => ({
      metric: m.name,
      kind: m.kind,
      description: m.description,
    }))
    return <Markdown key="metrics" text={markdownTable(rows, 50)} />
  }
  return null
}
