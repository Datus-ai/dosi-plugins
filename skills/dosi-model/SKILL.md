---
name: dosi-model
description: Create or change the Apache Ossie semantic model (dosi/model.yaml) — datasets, relationships, metrics, time dimensions — and check it against reference numbers. Use when the user wants to build a semantic model or metric layer, add a table or metric, change a metric's definition, or when a data question arrives and the project has no dosi/model.yaml yet.
allowed-tools:
  - Bash(dosi *)
  - Bash(dosi-reconcile *)
  - Bash(dosi-fill-derived *)
  - mcp__plugin_dosi_dosi__validate_model
  - mcp__plugin_dosi_dosi__list_metrics
  - mcp__plugin_dosi_dosi__list_datasets
  - mcp__plugin_dosi_dosi__list_dimensions
  - mcp__plugin_dosi_dosi__describe_metric
  - mcp__plugin_dosi_dosi__describe_dataset
  - mcp__plugin_dosi_dosi__run_query
---

# Build and change the semantic model

Write to the user in the language they write in, every progress line
included.

The model is one file, `dosi/model.yaml`: Apache Ossie (formerly OSI) with
dosi's `DATUS` extensions. You write it with the file editor; dosi validates
and runs it.

`dosi`, `dosi-reconcile` and `dosi-fill-derived` are on PATH in Claude Code;
in other agents they are in the plugin's `bin/` folder, two levels above
this file. Use business terms; do not quote these instructions.
Never open `dosi-connections.yaml`, `secrets.env`, `.env*` or `profiles.yml`.

## Tools

- Before `dosi/model.yaml` exists, every model tool answers `no_model`.
  That is expected: write the model, do not retry or restart.
- **The warehouse**: dosi runs only the model's own queries. Tables,
  columns, sample rows and code values come from the user's own database
  client: read [references/warehouse-clients.md](references/warehouse-clients.md)
  before the first look.
- **The DATUS extensions**: [references/datus-contract.yaml](references/datus-contract.yaml)
  is dosi's contract for every extension key (`window`, `derive`, `time`,
  `lod`, `parameter_declaration`, …) with an example of each. Read a
  capability's block before using it and never invent keys.
  [references/ossie-authoring.md](references/ossie-authoring.md) shows the
  layering on one small model.
- **Validate**: in Claude Code a hook validates every save of `dosi/*.yaml`.
  Elsewhere run `dosi validate --format json` after each batch. Fix problems
  silently; tell the user only after three failed fixes in a row.
- **Query**: `run_query`, or `dosi query --execute --format json`. The MCP
  server reloads the model after every save.
- **Derived metrics**: `dosi-fill-derived` (step 4).
- **Check against reference numbers**: `dosi-reconcile` (step 5).

Work from the project folder with relative paths. Read and search this
plugin's references and dosi's examples (the `examples_dir` in `dosi info
--format json`) with the file tools (Read, Grep, Glob), not the shell. Keep
scratch files (reference rows, notes) under `dosi/build/`; `mkdir -p
dosi/build` creates it. Run dosi commands as they are, without pipes or
redirections.

## Building a model, or a new part of one

Modeling takes minutes: before each step, tell the user in one line what
you are doing.

**1. Scope.** The outputs the user asked for: named metrics, a document's
indicator list, the columns of a report. For a quick question with no model
yet: the fact table behind it, the dimensions it groups or filters by, and
3–8 metrics.

**2. Evidence.** For each output, read the SQL that produces it (files the
user points at or that you find) back to its source tables, and keep its
filters, grouping, join behavior and NULL handling; the SQL is evidence of
the definition, not a shape to copy. Read the documents the user names; when
a document and the SQL disagree, ask. Look at the live tables with the
user's client: columns, a few rows, the distinct values of codes you filter
on. Batch questions into few queries.

**3. Design.**
- Datasets bound to tables or views, preferably detailed ones rather than
  pre-aggregated reports, so metrics work at any grain. A dataset whose
  `source` is SQL only for a row set the model cannot express otherwise.
- Fields for every column a metric or query reads; business time marked
  `dimension: {is_time: true}`, with the `time` extension when it is stored
  as text or a number.
- Relationships many → one, with keys only from evidence.
- Metrics in layers, each reusing the one below: base aggregates → derived
  (filters, ratios, compositions with `derive`) → windows (rank, share,
  rolling, period over period with `window`) → compositions over those.
  Never compute a rank or score inside a dataset's SQL.

**4. Write** `dosi/model.yaml` layer by layer, saving after each layer so
validation catches problems early. Use the file editor; never generate or
patch the model with a script. Names are snake_case; every metric gets a
description of what the number means.

A derived metric (`derive` filter or compose) also needs its expansion as
the core `expression`. Do not work it out by hand: write any aggregate over
a field the metric reads as a placeholder, and after the batch run
`dosi-fill-derived` once. It writes every expansion from dosi's own
computation and validates again. Until then validation reports
`derive_expression_mismatch`, which is expected.

**5. Check.** When the user has reference numbers (a published report
table, or the SQL behind one), check each output against them as soon as it
exists:

```bash
dosi-reconcile --reference dosi/build/ref.tsv \
  --key metric_time__month=month --key region=region \
  --check revenue=revenue --check order_count=orders \
  --group-by metric_time:month,customers.region
```

- `--reference`: the reference rows with a header line, written by the
  user's client into `dosi/build/` (`.tsv`, `.csv`, or a `.json` array).
- `--key <group-by item>=<column>` for each grouping key; `--check
  <metric>=<column>` for each metric, or `--same-names`.
- It prints passed / failed per metric with the cells that differ. Fix
  differences the definition supports and rerun. Never tune a metric to the
  reference (summing stored totals, narrowing the population).
- Without reference numbers, run each new metric once and check that the
  result is plausible.

**6. Report** in a few lines: what the model holds, what was checked and
how, and any choice that departs from a document. Then answer the user's
original question with the dosi-query skill, if there was one.

## Changing an existing model

- **Adding a table or metric**: read the relevant part of the model, add it
  in the same layered way, validate, check the new output.
- **Changing what a metric means** (its expression, filter, window or
  population): ask first whether to try it or change the model.
  - Try it: copy the model to `dosi/build/trial.yaml`, edit the copy, query
    it with `dosi --model dosi/build/trial.yaml query …`, show the
    difference, and delete the copy afterwards. Trial numbers are not the
    model's.
  - Change it: edit the metric, rename it when its meaning changes, tell the
    user what uses the old name, validate and check again.
- **A broken model**: validate, read the errors, fix the smallest thing.

The dosi-modeler subagent (Claude Code) runs the same flow in the
background; use it only when the user asks for that.

## Rules

- Never invent a column, code value or business meaning: every field names
  a column you saw, every filter value is one you saw in the data or SQL.
- `DOSI_MODEL` points at `dosi/model.yaml`; pass `--model` only for another
  file.
