---
name: dosi-view
description: Show how a metric is computed and where its data comes from — metric lineage (tables → datasets → metrics → derived metrics), and the ontology's concept graph when one exists. Use when the user asks "how is X calculated", "where does this number come from", "what depends on this table", or asks to see the lineage, the model or the ontology graph.
allowed-tools:
  - Bash(dosi *)
  - mcp__plugin_dosi_dosi__describe_metric
  - mcp__plugin_dosi_dosi__describe_dataset
  - mcp__plugin_dosi_dosi__describe
  - mcp__plugin_dosi_dosi__paths
---

# Show lineage and graphs

Write to the user in the language they write in, every progress line
included.

`dosi` is on PATH in Claude Code; in other agents it is in the plugin's
`bin/` folder, two levels above this file. Use business terms.

## "How is <metric> computed?"

1. `describe_metric` (CLI `dosi show metric <name> --format json`): its
   `expr` says how it is computed from other metrics or fields.
2. Walk upstream: `describe_metric` on each metric it reads
   (`derive_members`, or `derive_base` for a filter or window) down to the
   base metrics, then `describe_dataset` for each base metric's datasets
   (the `source` is the table). Never fetch the whole graph for one metric.
3. Answer with a small tree, the metric on top, each line with its rule in
   business terms, then one sentence on what it means:

   ```
   avg_order_value (revenue / completed orders)
   ├─ revenue (amount of completed orders)
   │  └─ orders (dataset) ← shop.orders (table)
   └─ order_count (number of completed orders)
      └─ orders (dataset) ← shop.orders (table)
   ```

When a dataset's source is a view and the user asks which tables a number
comes from, name the tables the view reads, using the user's database
client ([../dosi-model/references/warehouse-clients.md](../dosi-model/references/warehouse-clients.md)).
To show how one query is planned: `dosi explain --metrics <m> --group-by <g>`.

## "Show me the lineage / the graph"

In Claude Code, point the user to `/dosi lineage <metric>` first: it opens
the graph in a pane, with no browser. When the user wants a page or a file,
or in other agents:

```bash
dosi lineage view
```

It writes a self-contained HTML page, opens it in the browser and prints
the path. Without a display (SSH, container) use `dosi lineage view
--no-open --out dosi/build/lineage.html` and give the path. When an
ontology exists, the same page shows the concept layer. Add `--redact-sql`
when the page will be shared.

"What depends on table X?": `dosi lineage dump --out dosi/build/lineage.json`,
then follow the edges forward from `table:<schema.table>`.

## Ontology questions

Paths between two concepts → `paths` (`dosi paths --from Customer --to
Product`). Which concepts exist → `describe`.
