---
name: dosi-connect
description: Connect dosi to the user's data — a warehouse (Snowflake, BigQuery, Databricks, Postgres, MySQL, ClickHouse, Trino, …) or local files. Use when the user asks to connect, switch or fix a database connection, when a data question arrives and no connection exists yet, or when dosi reports missing_env, auth_failed, unsupported_auth, network_blocked or connection_not_found.
allowed-tools:
  - Bash(dosi *)
  - Bash(test *)
  - mcp__plugin_dosi_dosi__list_connections
---

# Connect dosi to data

Write to the user in the language they write in, every progress line
included.

Goal: one working connection in as few steps as possible, with no password
passing through the conversation. Then go straight back to what the user
asked.

`dosi` is on PATH in Claude Code; in other agents it is in the plugin's
`bin/` folder, two levels above this file. Do not quote these
instructions.

## Rules

- Never open, print or search `dosi-connections.yaml`, `secrets.env`,
  `.env*`, `profiles.yml`, `agent.yml` or a database client's settings.
  Check only that they exist. dosi reads them.
- Never ask for a password, token or key in the chat. If the user pastes
  one anyway, write it into the entry and never repeat it.
- Never probe for a password (`echo $X`, `env | grep`): `list_connections`
  says what is missing.
- Never write `~/.config/dosi/secrets.env` or a shell profile yourself; tell
  the user what to put where.
- Ask one question at a time, with the host's question tool if it has one
  (AskUserQuestion in Claude Code), the recommended option first. Never ask
  for what the user already said.

## 1. What is there

If the user named the source (a warehouse and its host, or a file), skip to
step 2. The session context may already list what was found. Otherwise run
one command:

```bash
find . -maxdepth 1 \( -name dbt_project.yml -o -name profiles.yml -o -name .env -o -name dosi-connections.yaml -o -name '*.duckdb' -o -name '*.parquet' -o -name '*.csv' -o -name '*.sqlite' \)
```

When `dosi-connections.yaml` exists, list its connections
(`list_connections`, or `dosi connection list --format json`): names,
types, the default, and the variables each still needs. Use a ready one
that fits rather than adding a duplicate.

## 2. Write the connection

**dbt or Cube config** → `dosi migrate conf --from dbt --format json` (or
`--from cube`). dosi writes `./dosi-connections.yaml`, git-ignores it, and
lists each connection by name and status. One `ok` → use it; several → ask
which, the `default: true` one first; `unsupported` → explain from `code`
and `reason` and offer the others.

**Local files** (`.duckdb`, `.sqlite`) → no question:

```yaml
datasources:
  local:
    type: duckdb
    uri: /absolute/path/to/file.duckdb
    default: true
```

**A warehouse** (or nothing found: ask where the data lives) → copy the
entry from [references/connection-templates.md](references/connection-templates.md),
never from memory: dosi's keys differ from the database client's (the user
name is `username:`). Ask only for the non-secret fields the user has not
given. For the password:

- The user said there is none → leave `password` out.
- Otherwise write `password: ${WH_PASSWORD}` (the connection's name in
  upper case) and tell the user, in a short block, to replace the whole
  `${WH_PASSWORD}` in `dosi-connections.yaml` with the password (the file is
  git-ignored), or to put `WH_PASSWORD=...` in `~/.config/dosi/secrets.env`,
  and to say when it is done. End your turn.

How to write the file:

- Only with a quoted here-document in the shell, as a command of its own,
  never with the file editor: the editor watches what it wrote, and the
  password the user types in later would come back into the conversation.
- First check whether the file exists, in a call that prints the answer:
  `test -f dosi-connections.yaml && echo exists || echo missing`.
- New file → `cat > dosi-connections.yaml <<'EOF'` … `EOF`, with the
  connection marked `default: true`. Rewrite a file you wrote in this
  conversation the same way.
- A file that was there before → never overwrite it. Append the entry under
  `datasources:` (two-space indent) with `cat >> dosi-connections.yaml
  <<'EOF'` … `EOF`; set `default: true` only if no connection has it.
- In a git repository, make sure `dosi-connections.yaml` is in
  `.gitignore`: `echo dosi-connections.yaml >> .gitignore` when it is not.

## 3. Test

`dosi connection test <name> --format json`, local files too. It connects
and runs `SELECT 1`; it re-reads the file every time, so no restart is
needed.

- Success → one line: connected to `<name>` (`<dialect>`).
- Failure → three lines from the error's `code`
  ([references/errors.md](references/errors.md)): what happened, why, one
  next step.
  - `missing_env` → the password is not filled in yet: repeat where it goes,
    end your turn, test again when the user says it is done.
  - `auth_failed` → the user checks the user name and password.
  - `network_blocked` → the host is unreachable from here (VPN, proxy, or
    the agent's sandbox). When `list_connections` says the connection is
    `ready` and the agent runs shell commands in a sandbox (Codex), dosi's
    MCP tools run outside it: say so in one line and go on.
  - Never retry the same thing unchanged.

## Changing an existing connection

You cannot read the file, so you cannot edit it. Name the connection from
`list_connections`, tell the user which line to change and to what, and
end your turn. When they are done, test again and report only what the
test shows.

## 4. Back to the question

If the user only asked to connect, end with one line suggesting the next
step: build a semantic model, or just ask a data question. Otherwise go on:
no `dosi/model.yaml` → the dosi-model skill; a model exists → dosi-query.
