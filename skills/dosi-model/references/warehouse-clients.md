# Looking at the warehouse: the user's own client

dosi runs only the queries a model defines. What the model cannot tell you
yet (tables and columns, a few rows, the codes a filter uses, a view's
definition, reference numbers) comes from the database client the user
already has, set up so that it logs in by itself.

## Rules

- Read-only statements only: `SELECT`, `SHOW`, `DESCRIBE`, `EXPLAIN`,
  `information_schema`. Always with a `LIMIT` unless it is an aggregate.
- Each call asks the user for permission, so make each one count: one
  statement per question, the columns of several tables in one
  `information_schema` query (`WHERE table_schema = 'db' AND table_name IN
  (…)`), never a bare list of every table.
- Never put a password, token or key on the command line or in an
  environment variable (`-p<password>`, `MYSQL_PWD=`, `PGPASSWORD=`), never
  open the client's settings (`~/.my.cnf`, `~/.mylogin.cnf`, `~/.pgpass`,
  `~/.pg_service.conf`, `~/.snowsql/`, `~/.databrickscfg`), and never install
  a client.

## Which command

The command the user named in this conversation, or the one saved in
`dosi/build/client.txt`, or, for a user the user said has no password, the
plain command below. Otherwise ask once (question tool), the line for the
connection's type below first, and save the answer, the command only, to
`dosi/build/client.txt` with the file editor.

| Warehouse | Command that logs in by itself | The user sets it up once, in their own terminal |
|---|---|---|
| MySQL, StarRocks, Doris, TiDB | `mysql --login-path=<name> -D <db> -B -e "<sql>"` | `mysql_config_editor set --login-path=<name> --host=<host> --port=<port> --user=<user> --password` (asks for the password itself) |
| PostgreSQL | `psql "service=<name>" -X --csv -c "<sql>"` | a `[<name>]` block in `~/.pg_service.conf` and a line in `~/.pgpass` |
| Snowflake | `snowsql -c <name> -o output_format=csv -o header=true -o timing=false -o friendly=false -q "<sql>"` | a `[connections.<name>]` block in `~/.snowsql/config` |
| BigQuery | `bq query --nouse_legacy_sql --format=csv --max_rows=100 '<sql>'` | `gcloud auth login` |
| DuckDB file | `duckdb -readonly <file.duckdb> -csv -c "<sql>"` | nothing |

A user with no password needs no setup: `mysql -h <host> -P <port> -u
<user> -D <db> -B -e "<sql>"` logs in as it is. Any other warehouse: ask
which command they use; it must log in without a password on the line.

The user has no such client and does not want one: say what that leaves
out (seeing columns and values, checking against reference numbers) and go
on from the SQL files and documents. A column you could not see is not
invented: it comes from the SQL that reads it, or you ask. Once a dataset
names its columns, dosi itself shows rows of it (`select` with a `limit`).

Tell the user how to set the client up in one short block, for them to type
in their own terminal (in Claude Code, prefixed with `!`); the client asks
for the password itself, so it never passes through this conversation.

## Reference numbers for dosi-reconcile

Write the reference query's rows to a file under `dosi/build/` with a
header line: `mysql -B … > dosi/build/ref.tsv`, `psql --csv … >
dosi/build/ref.csv`, and so on. `dosi-reconcile --reference` reads `.tsv`,
`.csv` or a `.json` array of objects.
