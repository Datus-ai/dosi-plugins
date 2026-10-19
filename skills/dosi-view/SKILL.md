---
name: dosi-view
description: Show how a metric is computed and where its data comes from — metric lineage (tables → datasets → metrics → derived metrics), and the ontology's concept graph when one exists. Use when the user asks "how is X calculated", "where does this number come from", "what depends on this table", or asks to see / draw the lineage, the model or the ontology graph.
allowed-tools:
  - Bash(dosi *)
  - Bash(dosi-progress *)
---

# Show lineage and graphs

Two outputs, always both: a short answer **in the conversation**, and the
full interactive graph as a **local HTML page** (self-contained, opens over
`file://`, no network).

## "How is <metric> computed?"

1. The definition: `dosi list metrics --format json` → the metric's kind and
   description; the expression is in `dosi/model.yaml`.
2. The upstream chain from the graph:

   ```bash
   dosi lineage dump --format json
   ```

   JSON with `nodes` (`id`, `kind`: `physical_table` | `dataset` |
   `metric_atomic` | `metric_derived` | concept kinds when an ontology is
   loaded; `name`, `label`, `detail`) and `edges` (`source`, `target`,
   `kind`). Walk edges backwards from `metric:<name>`.
3. Answer as a small text tree, top = the metric:

   ```
   revenue（聚合：SUM(orders.amount)，仅 completed）
   └─ orders（数据集）
      └─ analytics.marts.orders（物理表）
   ```

   Then one sentence in business terms. If the user wants to see how a
   specific query is planned, `dosi explain --metrics <m> --group-by <g>`.

## "Show me the lineage / the graph"

```bash
dosi lineage view
```

In Claude Code, first point the user to `/dosi lineage <metric>`: it opens
the same graph in a pane inside Claude Code (a tree in the terminal, the full
graph in Desktop), with no browser needed. Write the HTML page when the user
asks for a page or a file, or in any other agent:

Writes the HTML page and opens it in the default browser; it prints the path.
In a remote or headless session (SSH, container, no display) use
`dosi lineage view --no-open --out "${TMPDIR:-/tmp}/dosi-lineage.html"` and give the user the
path to open. When an ontology exists (`DOSI_ONTOLOGY` is set), the same page
carries the concept layer — that *is* the ontology graph.

For "what depends on table X" walk the edges forwards from
`table:<schema.table>` and list the datasets and metrics reached.

Add `--redact-sql` to either command when the user wants to share the page
without SQL text.

## Ontology questions without a picture

"Customer 和 Store 之间有哪些路径？" → `dosi paths --from Customer --to Store`,
answered in the conversation. "有哪些概念？" → `dosi describe`.

## Close

At the end run `dosi-progress next`: append a `HINT:` line verbatim; ask an
`ASK:` line with AskUserQuestion and record the answer; add nothing otherwise.
