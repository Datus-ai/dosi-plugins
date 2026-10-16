---
name: dosi-query
description: Answer any data question — numbers, trends, breakdowns, rankings, "why did X change", or lists of records — through the dosi semantic layer instead of hand-written SQL. Use whenever the user asks about their data (revenue, orders, customers, users, any KPI) in a project that uses dosi or has a database connection.
allowed-tools:
  - Bash(dosi *)
  - Bash(dosi-progress *)
---

# Answer data questions with dosi

Every number comes from a metric the model defines, compiled by dosi. Never
write SQL by hand against tables the model covers, never re-derive a metric,
never invent a metric or field name.

## 0. Preconditions (silent)

- No connection and no local data → run the **dosi-connect** skill first.
- No `dosi/model.yaml` → run the **dosi-model** skill (it builds a minimal
  model for this question), then come back.
- `DOSI_MODEL` (and `DOSI_ONTOLOGY` when there is one) are already exported;
  don't pass `--model` unless you mean another file.

## 1. Aggregate or records?

| The user wants | Command |
|---|---|
| a number, trend, breakdown, ranking, comparison | `dosi query` |
| a list of rows ("哪些客户", "列出最大的 100 单") | `dosi select` |
| why a metric moved between two periods | `dosi attribute` |

When the question is about specific entities ("哪些客户", "列出…的门店"), run
`dosi-progress record entity_question` once.

## 2. Discover (only what you don't know yet)

```bash
dosi list metrics --format json
dosi list dimensions --metric <metric> --format json   # best first; is_dimension=true are worth grouping by
```

## 3. Run

```bash
dosi query --format json --execute \
  --metrics revenue,order_count \
  --group-by customers.region,metric_time:month \
  --where "customers.region <> 'test'" \
  --start-time 2026-09-01 --end-time 2026-10-01 \
  --order -revenue --limit 20
```

```bash
dosi select --format json --execute \
  --from orders --fields orders.order_id,orders.amount,customers.region \
  --where "orders.amount > 1000" --order -amount --limit 100
```

```bash
dosi attribute --format json --metric revenue \
  --baseline 2026-08-01..2026-09-01 --current 2026-09-01..2026-10-01
```

Flags, grains, filters and parameters:
[references/query-shapes.md](references/query-shapes.md).

`--execute` uses the connection marked `default: true`; add
`--connection <name>` for another. Local DuckDB without a connection profile:
`--db <file.duckdb>`.

**Q5 — first execution against a cloud warehouse in this session**: before
running, AskUserQuestion "执行这条查询吗？" with "执行（推荐）" /
"先只看 SQL" / "本次会话都直接执行". Show the SQL (run once without
`--execute` to get it). Local DuckDB never asks. After "本次会话都直接执行",
never ask again this session.

## 4. Show the answer

1. The answer in one sentence first.
2. A Markdown table (≤ 20 rows; say how many in total if more).
3. One small line: `<dialect> · <connection> · <n> rows`.
4. The SQL dosi generated, in a ```sql block — always, short or long.

## 5. When dosi says no (fix it yourself first)

- `unknown_metric` / `unknown_field`: use `candidates`. If one is clearly
  meant, use it and say so; if not, show the top 3 and ask.
- `detail_fanout`, `ambiguous_join_path`, `InvalidRelationshipPath`: rerun
  with `suggested_retry` without bothering the user. Ask (AskUserQuestion)
  only when the candidate paths are different business meanings
  ("下单客户" vs "收货客户").
- No metric covers the question: say so plainly and offer to add one (the
  **dosi-model** skill). Do not answer with hand-written SQL.
- `dosi_installing`: wait a few seconds and rerun, up to 6 times, silently.
- Anything else: three lines — `✗ 发生了什么` / `原因：…` / `下一步：<one action>`
  (table in the dosi-connect skill's references/errors.md).

## 6. Ontology

Do not mention ontologies unless the user does or `dosi-progress next` brings
it up. When `DOSI_ONTOLOGY` is set, concept paths work wherever fields do
(`--from Customer`, `--group-by Order.placed_by.region`); see the
**dosi-ontology** skill.

## 7. Close

At the very end run `dosi-progress next`:
- `HINT: <text>` → append `<text>` verbatim as your last line.
- `ASK: <question> | <a> | <b> | <c>` → AskUserQuestion with those options in
  that order, then run the `dosi-progress answer …` command it prints with
  yes / later / never. On yes for `h_ontology`, continue with the
  **dosi-ontology** skill; on yes for `h_team`, commit `dosi/` (never
  `dosi-connections.yaml`).
- nothing → add nothing.
