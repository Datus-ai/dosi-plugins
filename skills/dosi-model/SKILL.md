---
name: dosi-model
description: Create or change the Apache Ossie semantic model (dosi/model.yaml) — datasets, relationships, metrics, time dimensions. Use when the user wants to build a semantic model, add or fix a metric, or when a data question arrives and the project has no dosi/model.yaml yet.
allowed-tools:
  - Bash(dosi *)
  - Bash(dosi-progress *)
---

# Build and change the semantic model

The model lives at `dosi/model.yaml` (Apache Ossie, formerly OSI). Every save
is validated automatically by a hook; if it fails, the problems come back to
you — fix them silently. Tell the user only if three fixes in a row fail.

## From scratch (no dosi/model.yaml)

The user usually got here by asking a data question. Keep the first model
**small** — it exists to answer that question in about two minutes.

1. Make sure a connection works (otherwise run the **dosi-connect** skill).
2. **Q3** — AskUserQuestion "先建多大范围？":
   - "只建与这个问题相关的表（推荐，约 2 分钟）"
   - "整个 schema"
   - "我来指定表"
3. Delegate to the **dosi-modeler** subagent (Agent tool,
   `subagent_type: "dosi:dosi-modeler"`). Pass: the user's question, the
   connection name and dialect, the chosen scope, and any dbt project path
   (`dbt_project.yml` location — its model `.yml` files carry column
   descriptions; `profiles.yml` is off limits).
   While it works, show the user one progress line, e.g.
   `建模中：读取表结构 → 起草 → 校验`.
4. The subagent returns: the file path, a validation summary, and **at most 3
   business ambiguities** with candidate meanings. Ask each with
   AskUserQuestion (**Q4**), recommended reading first. Apply the answers to
   `dosi/model.yaml` yourself (the hook re-validates).
5. Tell the user in two lines what exists now, e.g.
   `已生成 dosi/model.yaml：4 个数据集、3 条关联、11 个指标，校验通过。`
   Then answer their original question with the **dosi-query** skill.

## Small changes (model exists)

Add a metric, fix an expression, mark a time dimension: edit
`dosi/model.yaml` directly, following
[references/ossie-authoring.md](references/ossie-authoring.md). Check with:

```bash
dosi list metrics --format json
dosi list dimensions --metric <name> --format json
dosi validate --format json
```

**Q8** — before changing the meaning of an existing metric (its expression or
filter, not just its description), ask: "修改 `<metric>` 的口径？" with
"确认修改" / "先看 diff". Additions need no confirmation.

## Rules

- Never invent a column: every field expression must name a real column the
  modeler saw. Never guess business meaning silently — that is what Q4 is for.
- Names are snake_case; metric descriptions say what the number means in
  business terms ("已完成订单的金额，不含退款").
- `DOSI_MODEL` is already set to `dosi/model.yaml` by the session; pass
  `--model` only for another file.

At the end of your reply run `dosi-progress next`: append a `HINT:` line
verbatim; ask an `ASK:` line with AskUserQuestion and record the answer with
the command it prints; add nothing if it prints nothing.
