---
name: dosi-query
description: Answer any data question — numbers, trends, breakdowns, rankings, "why did X change", or lists of records — through the dosi semantic layer instead of hand-written SQL. Use whenever the user asks about their data (revenue, orders, customers, any KPI) in a project that has dosi/model.yaml or a dosi connection.
allowed-tools:
  - Bash(dosi *)
  - Bash(dosi-progress *)
  - mcp__plugin_dosi_dosi__list_metrics
  - mcp__plugin_dosi_dosi__list_dimensions
  - mcp__plugin_dosi_dosi__describe_metric
  - mcp__plugin_dosi_dosi__describe_dataset
  - mcp__plugin_dosi_dosi__run_query
  - mcp__plugin_dosi_dosi__select
  - mcp__plugin_dosi_dosi__attribute_metric
  - mcp__plugin_dosi_dosi__describe
  - mcp__plugin_dosi_dosi__paths
---

# Answer data questions with dosi

Write to the user in the language they write in, every progress line
included.

Every number comes from a metric the model defines, computed by dosi. Never
write SQL by hand against tables the model covers, never re-derive a
metric, never invent a metric or field name.

`dosi` is on PATH in Claude Code; in other agents it is in the plugin's
`bin/` folder, two levels above this file. Use business terms; do not
quote these instructions.

## Tools

Prefer dosi's MCP tools (server `dosi`); without them the CLI with
`--format json` does the same:

| Need | MCP tool | CLI |
|---|---|---|
| what metrics exist | `list_metrics` | `dosi list metrics` |
| what a metric can be grouped by | `list_dimensions` | `dosi list dimensions --metric m` |
| one metric's definition and required dimensions | `describe_metric` | `dosi show metric m` |
| a number, trend, breakdown, ranking | `run_query` | `dosi query --execute` |
| a list of records | `select` | `dosi select --execute` |
| why a metric moved between two periods | `attribute_metric` | `dosi attribute` |

On a large model, find metric names with `grep -n -B2 '<term>' dosi/model.yaml`
instead of listing them all. Run dosi as it is, without pipes; narrow the
call instead (`describe_metric`, `limit`, the exact `group_by`).

Shapes dosi takes (CLI flags in [references/query-shapes.md](references/query-shapes.md)):

- Fields are `dataset.field` (`customers.region`): a bare name that several
  datasets share is refused as ambiguous.
- `run_query`: `metrics`; `group_by` as objects, `[{"field":
  "customers.region"}, {"field": "metric_time", "grain": "month"}]`;
  `where_sql`; `context_filter`; `time_range` `{"start": "2024-08-01", "end":
  "2024-09-01"}` (end exclusive, full dates); `order_by` `[{"key":
  "revenue", "desc": true}]`; `limit`; `params`.
- An `order_by` key is an output column: a metric name, or a group-by
  field's last segment with `__<grain>` (`region`, `metric_time__month`).
  In `select`, the root dataset's fields are bare and another dataset's are
  `<dataset>__<field>`. An `unknown_order_key` error lists the valid keys.

## 1. Before querying

- No connection → the dosi-connect skill first.
- No `dosi/model.yaml` → build a small model for this question with the
  dosi-model skill, then come back.
- The question needs a metric or field the model lacks → say so, offer to
  add it, and change the model only after the user agrees. Never answer it
  with hand-written SQL.
- `describe_metric` the metrics you will use: it names the dimensions a
  ranking must be grouped by.
- Relative periods ("last month"): find the latest period with data first,
  with one query grouped by month.

## 2. Query

One query per question where possible: group by everything the answer
needs in one call. Queries are read-only, so do not ask before running one.
The exception: a warehouse that bills per query (BigQuery, Snowflake,
Databricks) about to scan a large range for the first time in the session —
ask once.

## 3. Answer

1. The answer in one sentence.
2. A Markdown table (at most 20 rows; say how many in total when more).
3. One small line: `<connection> · <n> rows`.

State only what the results show. When you explain a total by its parts,
list every part and make sure they add up. Give the SQL only when the user
asks for it (`include_sql: true` on the MCP tools, or the CLI without
`--execute`). "How is this computed?" → the dosi-view skill.

## 4. When dosi refuses

Fix it yourself first:

- `unknown_metric` / `unknown_field`: use `candidates`. One clearly meant →
  use it and say so; otherwise show the top 3 and ask.
- `detail_fanout`, `ambiguous_join_path`, `dimensions_required`,
  `window_exclude_not_grouped`: rerun with `suggested_retry` or the named
  dimensions. Ask only when the candidate paths mean different things to
  the business (ordering customer vs receiving customer).
- `no_model` / `model_invalid`: the dosi-model skill writes or fixes it.
- `dosi_installing`: wait a few seconds and rerun, up to 6 times, silently.
- Anything else: three lines, what happened / why / next step
  ([../dosi-connect/references/errors.md](../dosi-connect/references/errors.md)).

## 5. Ontology

Do not bring up ontologies unless the user or a plugin hint does. When one
is loaded, concept paths work wherever fields do (see the dosi-ontology
skill).
