// Lineage drawing for the dosi pane: a text tree for every surface, and an
// SVG layered DAG where the surface has `Svg`. Pure functions of the graph.
import type { DosiGraph, DosiNode } from '../types'

export type TreeRow = { prefix: string; node: DosiNode }

const KIND_LABEL: Record<string, string> = {
  physical_table: 'table',
  dataset: 'dataset',
  metric_atomic: 'metric',
  metric_derived: 'derived',
}

export const kindLabel = (kind: string): string => KIND_LABEL[kind] ?? kind.replace(/_/g, ' ')

/** Upstream for a metric, downstream for a table or dataset. */
export const isUpstream = (id: string): boolean => id.startsWith('metric:')

/**
 * The tree under `focus`: what it is computed from (a metric) or what depends
 * on it (a table or dataset). Joins are lateral, not lineage, so they are
 * left out; a node reached twice is drawn once more, marked, and not walked.
 */
export function lineageTree(graph: DosiGraph, focus: string): TreeRow[] {
  const byId = new Map(graph.nodes.map(n => [n.id, n]))
  const up = isUpstream(focus)
  const next = new Map<string, string[]>()
  for (const e of graph.edges) {
    if (e.kind === 'join') continue
    const [from, to] = up ? [e.target, e.source] : [e.source, e.target]
    next.set(from, [...(next.get(from) ?? []), to])
  }
  const rows: TreeRow[] = []
  const seen = new Set<string>()
  const walk = (id: string, lead: string, branch: string) => {
    const node = byId.get(id)
    if (!node) return
    rows.push({ prefix: lead + branch, node })
    if (seen.has(id)) return
    seen.add(id)
    const kids = next.get(id) ?? []
    const childLead = lead + (branch === '' ? '' : branch === '└─ ' ? '   ' : '│  ')
    kids.forEach((kid, i) => walk(kid, childLead, i === kids.length - 1 ? '└─ ' : '├─ '))
  }
  walk(focus, '', '')
  return rows
}

/** The ids on the tree under `focus`, for highlighting. */
export function lineageIds(graph: DosiGraph, focus: string): Set<string> {
  return new Set(lineageTree(graph, focus).map(r => r.node.id))
}

/** Choices for the focus picker: metrics first, then tables. */
export function focusChoices(graph: DosiGraph): { value: string; label: string }[] {
  const pick = (kinds: string[]) =>
    graph.nodes
      .filter(n => kinds.includes(n.kind))
      .map(n => ({ value: n.id, label: `${kindLabel(n.kind)} · ${n.label}` }))
  return [...pick(['metric_atomic', 'metric_derived']), ...pick(['physical_table', 'dataset'])]
}

const escapeXml = (s: string): string =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

const clip = (s: string, n: number): string => (s.length > n ? `${s.slice(0, n - 1)}…` : s)

const TONE: Record<string, string> = {
  physical_table: '#6b7f99',
  dataset: '#3d8a7a',
  metric_atomic: '#c07a2c',
  metric_derived: '#9a5bb5',
}

/**
 * A layered DAG: one column per layer (table → dataset → metric → derived),
 * edges as curves, the focus's lineage drawn strong and the rest faded.
 * Hover shows each node's detail through `<title>` (Svg `isInteractive`).
 */
export function lineageSvg(graph: DosiGraph, focus: string): string {
  const lit = lineageIds(graph, focus)
  const W = 168
  const H = 26
  const GAP_X = 56
  const GAP_Y = 10
  const PAD = 12
  const layerCount = Math.max(1, ...graph.nodes.map(n => n.layer + 1))
  const columns: DosiNode[][] = Array.from({ length: layerCount }, () => [])
  for (const n of graph.nodes) columns[n.layer]?.push(n)
  const pos = new Map<string, { x: number; y: number }>()
  columns.forEach((col, i) =>
    col.forEach((n, j) => pos.set(n.id, { x: PAD + i * (W + GAP_X), y: PAD + 18 + j * (H + GAP_Y) })),
  )
  const tallest = Math.max(1, ...columns.map(c => c.length))
  const width = PAD * 2 + layerCount * W + (layerCount - 1) * GAP_X
  const height = PAD * 2 + 18 + tallest * (H + GAP_Y)
  const parts: string[] = []
  columns.forEach((_, i) => {
    const name = graph.layers[i] ?? ''
    parts.push(
      `<text x="${PAD + i * (W + GAP_X)}" y="${PAD + 8}" font-size="11" fill="#888">${escapeXml(kindLabel(name))}</text>`,
    )
  })
  for (const e of graph.edges) {
    const a = pos.get(e.source)
    const b = pos.get(e.target)
    if (!a || !b) continue
    const on = lit.has(e.source) && lit.has(e.target) && e.kind !== 'join'
    const dash = e.kind === 'join' ? ' stroke-dasharray="3 3"' : ''
    const x1 = a.x + W
    const y1 = a.y + H / 2
    const x2 = b.x
    const y2 = b.y + H / 2
    const d =
      e.kind === 'join'
        ? `M${a.x + W / 2},${a.y + H} C${a.x + W / 2 + 24},${(y1 + y2) / 2} ${b.x + W / 2 + 24},${(y1 + y2) / 2} ${b.x + W / 2},${b.y}`
        : `M${x1},${y1} C${x1 + GAP_X / 2},${y1} ${x2 - GAP_X / 2},${y2} ${x2},${y2}`
    parts.push(
      `<path d="${d}" fill="none" stroke="${on ? '#c07a2c' : '#999'}" stroke-opacity="${on ? 0.9 : 0.3}" stroke-width="${on ? 1.6 : 1}"${dash}/>`,
    )
  }
  for (const n of graph.nodes) {
    const p = pos.get(n.id)
    if (!p) continue
    const tone = TONE[n.kind] ?? '#888'
    const on = lit.has(n.id)
    const isFocus = n.id === focus
    parts.push(
      `<g opacity="${on ? 1 : 0.45}"><title>${escapeXml(`${kindLabel(n.kind)} ${n.label}${n.detail ? `\n${n.detail}` : ''}`)}</title>` +
        `<rect x="${p.x}" y="${p.y}" width="${W}" height="${H}" rx="5" fill="${tone}" fill-opacity="${isFocus ? 0.35 : 0.14}" stroke="${tone}" stroke-width="${isFocus ? 2 : 1}"/>` +
        `<text x="${p.x + 8}" y="${p.y + H / 2 + 4}" font-size="12" font-family="ui-monospace, monospace" fill="${tone}">${escapeXml(clip(n.label, 22))}</text></g>`,
    )
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}">${parts.join('')}</svg>`
}
