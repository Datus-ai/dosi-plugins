# dosi query / select / attribute-metrics / attribute-dimensions — flag reference

Global flags (any position): `--model <file>` (env `DOSI_MODEL`),
`--ontology <file>` (env `DOSI_ONTOLOGY`), `--format text|json|arrow`,
`--connections <file>`.

## query — aggregates

| Flag | Meaning |
|---|---|
| `--metrics a,b` | required; metric names (or `Concept.metric` with an ontology) |
| `--group-by x,y` | `dataset.field[:grain]`; grain = day/week/month/quarter/year; `metric_time[:grain]` = each metric's primary time dimension |
| `--where "<sql>"` | condition on a selected metric filters result rows; on fields, filters rows before aggregation |
| `--context-filter "<sql>"` | always before aggregation — scopes the population (use it for "rank within region X") |
| `--start-time YYYY-MM-DD` / `--end-time YYYY-MM-DD` | inclusive start, exclusive end on the time dimension |
| `--time-dimension <field>` | which time field the range applies to |
| `--order k1,-k2` | output column names; `-` = descending |
| `--limit N` | |
| `--param NAME=VALUE[,VALUE…]` | bind a parameterized metric (repeatable) |
| `--execute` | run it; without it you get the SQL only |
| `--connection <name>` / `--db <file.duckdb>` | where to run |
| `--dialect <d>` | compile-only target; implied by the connection |
| `--pretty`, `--explain` | readable SQL / also the logical plan |

Examples:

```bash
dosi query --format json --execute --metrics revenue --group-by metric_time:month
dosi query --format json --execute --metrics revenue,order_count --group-by customers.region --order -revenue --limit 10
dosi query --format json --execute --metrics revenue --where "revenue > 1000" --group-by customers.region
```

`dosi explain --metrics … --group-by …` shows the plan without SQL — useful to
explain *how* a number is computed.

## select — records

| Flag | Meaning |
|---|---|
| `--from <dataset or Concept>` | required; the grain of the result (one row per …), not the SQL FROM |
| `--fields a,b` | required; `field`, `dataset.field`, or concept paths |
| `--where`, `--context-filter`, `--start-time`, `--end-time`, `--time-dimension`, `--order`, `--limit` | as above |

Related datasets are joined automatically. Refusals carry `suggested_retry`:
`detail_fanout` (the root would be multiplied — use the suggested root),
`ambiguous_join_path` (name the relationship prefix).

## attribute-metrics / attribute-dimensions — why did it change

`attribute-metrics` splits a metric's change between two periods over its
formula; `attribute-dimensions` splits it by the groups of one or more
fields. Each part gets its effect on the change, and the effects add up to
the change exactly.

```bash
dosi attribute-metrics --format json --metric avg_order_value \
  --baseline 2026-08-01..2026-09-01 --current 2026-09-01..2026-10-01
dosi attribute-dimensions --format json --metric revenue \
  --baseline 2026-08-01..2026-09-01 --current 2026-09-01..2026-10-01 \
  --dimensions customers.region,products.category --top-groups 20
```

| Flag | Meaning |
|---|---|
| `--metric m` | required; the metric whose change to split |
| `--baseline START..END` / `--current START..END` | required; half-open periods on the metric's time axis |
| `--time-dimension <field>` | another time axis to cut both periods on |
| `--where "<sql>"`, `--context-filter "<sql>"` | as in `query`; a condition on a metric is refused |
| `--param NAME=VALUE` | one value per parameter: an attribution explains one binding |
| `--group-by x,y` | only for a metric computed per row of a grouping (a rank, a share of a total, a change on the period before), with `--where` fixing each field to one value. Not what the change is split by |
| `--dimensions x,y` | `attribute-dimensions` only: the fields to split by, `dataset.field[:grain]`. Several are one drill-down, level by level; two separate views are two runs |
| `--top-groups N` | `attribute-dimensions` only: how many groups to list across all levels, 1 to 200 (default 20); the rest are summed under `others` |
| `--connection <name>` / `--db <file.duckdb>` | where to run |
| `--dry-run` | compile every statement a run would send and say whether anything refuses it, without running |

Without `--dimensions`, dosi answers `dimensions_required` with the
`candidates` worth splitting by — pick from those. A node of the
`attribute-metrics` tree that names a `metric` can itself be split with
`attribute-dimensions`.
