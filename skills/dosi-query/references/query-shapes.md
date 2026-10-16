# dosi query / select / attribute — flag reference

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

## attribute — why did it change

```bash
dosi attribute --format json --metric revenue \
  --baseline 2026-08-01..2026-09-01 --current 2026-09-01..2026-10-01 \
  [--dimensions customers.region,products.category] [--where "<sql>"]
```

Without `--dimensions` dosi answers `dimensions_required` with the candidates
worth decomposing over — pick from those. The result ranks dimensions and
values by contribution; additive metrics use exact attribution, ratios use
LMDI (mix vs rate).
