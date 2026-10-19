// The dosi mod's state contract: what its status line, band, pane and result
// rows draw from. Values are presentation only; every fact comes from the
// dosi CLI or files in the project, never from the model.

export type DosiConnection = { name: string; type: string; isDefault: boolean }

export type DosiIssue = { severity: string; code: string; location: string; message: string }

export type DosiMetric = { name: string; kind: string; datasets: string[]; description: string }

export type DosiNode = { id: string; kind: string; layer: number; label: string; detail: string }

export type DosiEdge = { source: string; target: string; kind: string }

export type DosiGraph = { layers: string[]; nodes: DosiNode[]; edges: DosiEdge[] }

export type DosiFacts = {
  /** S0..S6 from bin/dosi-progress. */
  stage: string
  /** A pending one-time question from `dosi-progress peek`: text and options. */
  ask: { id: string; text: string; options: string[] } | null
  /** False while the pinned binary is still downloading. */
  isBinReady: boolean
  /** What the project folder holds that step 1 can connect from. */
  sources: string[]
  connections: DosiConnection[]
  model: {
    path: string
    datasets: number
    metrics: DosiMetric[]
    dimensions: number
    issues: DosiIssue[]
    warnings: number
  } | null
  ontology: { path: string; concepts: string[] } | null
  /** mtimes of the files the facts were read from, to skip a refresh. */
  signature: string
}

export type DosiPaneTab = 'lineage' | 'metrics' | 'issues'

declare module 'claude-code' {
  interface PluginState {
    dosi: {
      facts: DosiFacts | null
      graph: DosiGraph | null
      /** tool_use_id → command, for the Bash calls that ran dosi. */
      calls: Record<string, string>
      tab: DosiPaneTab
      /** The node the lineage tab is centred on (`metric:x` or `table:y`). */
      focus: string
      /** Where the HTML page was last written, for the pane's link. */
      htmlPath: string
      /** Whether a result row shows its SQL, per tool_use_id. */
      isSqlOpen: StateFamily<boolean>
    }
  }
}
