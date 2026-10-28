# Error → what the user sees

Every dosi error under `--format json` carries `code`, `message`, and often
`hint`, `candidates`, `suggested_retry`. Say it in three lines, in the
user's language; never paste the raw JSON or a stack trace; give exactly
one next step.

```
✗ <what happened, in the user's terms>
  Why: <one-sentence cause>
  Next: <one action>
```

| code | What happened | Next step | Fix it yourself? |
|---|---|---|---|
| `dosi_installing` | (say nothing) | wait ~5 s and rerun the same command, up to 6 times | yes |
| `install_failed` | dosi could not be installed | the `hint` command (in mainland China: `DOSI_SOURCE=oss`) | no |
| `missing_env` | the password for `<name>` is not filled in | replace `${<VAR>}` in dosi-connections.yaml, or put `<VAR>=…` in ~/.config/dosi/secrets.env (never in the chat) | no |
| `auth_failed` | `<name>` refused the login | the user checks the user name and password | no |
| `unsupported_auth` | `<profile>` uses a login dosi does not support yet | key-pair or password (give the template) | no |
| `network_blocked` | `<host>` cannot be reached from here | VPN or proxy; or the agent's network permission | no |
| `connection_failed` | cannot connect to `<host>` | check host and port | no |
| `sql_rejected` | the warehouse rejected the query | fix it from the message (table, column, dialect) | yes |
| `unsupported_dialect` | dosi does not support `<warehouse>` yet | the supported ones: `dialects` in `dosi info --format json` | no |
| `connection_not_found` | there is no connection `<name>` | pick one from `list_connections` (`dosi connection list --format json`), or rerun `migrate conf` | partly |
| validate `compile_errors` / `issues` | (say nothing) | fix the model; tell the user only after 3 failed fixes | yes |
| `detail_fanout`, `ambiguous_join_path` | (say nothing) | rerun with `suggested_retry`; ask only if the readings differ in business meaning | yes |
| `unknown_metric`, `unknown_field` | there is no `<x>` | the closest `candidates`: use one if the intent is clear, else ask | partly |
