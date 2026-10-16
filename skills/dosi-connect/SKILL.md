---
name: dosi-connect
description: Connect dosi to the user's data — a cloud warehouse (Snowflake, BigQuery, Databricks, Postgres, ClickHouse, Trino, StarRocks, …) or local files. Use when the user asks to connect / switch / fix a database connection, when a data question arrives and no connection exists yet, or when a dosi command fails with missing_env, auth_failed, unsupported_auth, network_blocked or connection_not_found.
allowed-tools:
  - Bash(dosi *)
  - Bash(dosi-progress *)
  - Bash(test *)
  - Bash(ls *)
---

# Connect dosi to data

Goal: one working connection with **no secret ever passing through this
conversation**, in as few steps as possible. Connecting is a means, not the
goal — when it works, go straight back to what the user originally asked.

## Hard rules

- **Never open, cat, grep or print** `profiles.yml`, `.env`, `.env.*`,
  `dosi-connections.yaml`, `agent.yml`, `~/.snowsql/*`, `~/.databrickscfg`.
  You may only check whether they exist (`test -f`). A hook blocks reads
  anyway; do not try to work around it. dosi reads them, you don't.
- **Never ask the user to paste a password, token or key into the chat.**
  Missing secrets are set by the user with `! export NAME=...` (the `!` prefix
  runs it in their shell; the value never reaches you).
- One question at a time, with AskUserQuestion, recommended option first.

## Step 1 — What is there?

The `[dosi]` SessionStart context already says what exists here (`发现：…`).
Use it; do not re-check. Only when that line is missing, run ONE command:

```bash
ls -1d dbt_project.yml profiles.yml .env dosi-connections.yaml *.duckdb *.parquet *.csv *.sqlite 2>/dev/null; test -f ~/.dbt/profiles.yml && echo '~/.dbt/profiles.yml'
```

If the context says this dosi has no `migrate` / `connection` commands, never
call them — take path B or C below. Otherwise `dosi migrate conf --detect
--format json` lists sources and would-be connections without writing.

## Step 2 — Pick the path

**A. dbt or Cube config found** → convert it:

```bash
dosi migrate conf --from dbt --format json      # or --from cube
```

dosi writes `./dosi-connections.yaml` (and git-ignores it). The output lists
each connection as `{"name","dialect","source","status","missing_env","code","reason","default"}`
— names and statuses only, never values.

- Exactly one connection with `status: ok` → use it, no question.
- Several → **Q1** (AskUserQuestion) "用哪个连接？": the one with
  `default: true` first, labelled "(推荐)" — for dbt it is the project's
  current target — then the others, then "手动配置".
- `status: unsupported` → explain with the 3-part format below using `code`
  and `reason` (e.g. `unsupported_auth`: browser SSO is not supported yet —
  suggest key-pair auth or password + env var). Offer the other connections.

**B. Only local files** (`.duckdb`, `.sqlite`) and no warehouse config →
no question, no test, no inspection. Write `dosi-connections.yaml` with the
Write tool (it holds no secret, so it does not need `.gitignore`):

```yaml
datasources:
  local:
    type: duckdb
    uri: duckdb:///<absolute path to file.duckdb>   # absolute path starts with /, giving duckdb:////…
    default: true
```

Do not open the database with the duckdb CLI or Python to look at it —
reading the schema is the dosi-modeler subagent's job. Reply one line
`✓ 已连接 local（duckdb，<file>）` and go to Step 4.

**C. Nothing found** → **Q2** "数据在哪里？": 当前目录的文件 / Snowflake /
BigQuery / Databricks / 其他（Postgres、ClickHouse、Trino、StarRocks…）.
For a warehouse, write `dosi-connections.yaml` from
[references/connection-templates.md](references/connection-templates.md):
every secret as `${VAR}`, non-secret identifiers (host, database, warehouse)
asked from the user only if they are not secret. Then list the variables the
user must export.

## Step 3 — Test (warehouses only, and only when `dosi connection` exists)

```bash
dosi connection test <name> --format json
```

Success: `{"name","dialect","ok":true,"latency_ms"}` → tell the user exactly
one line: `✓ 已连接 <name>（<dialect>，<latency> ms）`.

Failure: the error JSON has `code`, `message`, `hint`. Translate it with
[references/errors.md](references/errors.md) into three lines:

```
✗ <发生了什么>
  原因：<一句话原因>
  下一步：<一个动作>
```

- `missing_env` → next step is `! export <VAR>=...`; then wait for the user
  and test again.
- `auth_failed`, `network_blocked`, `unsupported_dialect` → one concrete
  action; do not retry blindly.

## Step 4 — Back to the question

If the user only asked to connect (no data question pending), end with one
line naming the next step: 下一步：说「给这些数据建个语义模型」，或者直接问一个数据问题。

Do not stop at "connected". If there is no `dosi/model.yaml`, continue with
the **dosi-model** skill to build a minimal model for the user's question;
otherwise answer it with **dosi-query**.

At the very end of your reply run `dosi-progress next`. If it prints a
`HINT:` line, append that sentence verbatim as the last line of your reply.
If it prints `ASK:`, ask it with AskUserQuestion (question | options) and
record the answer with the command it shows. If it prints nothing, add
nothing.
