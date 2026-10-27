# Connection templates

`dosi-connections.yaml` uses the Datus `datasources:` vocabulary. Mark one
entry `default: true`: queries without a named connection run on it, and SQL
is compiled in its dialect.

Write only what the user told you. A secret goes in as a `${VAR}` placeholder
that the user then fills: either they replace it in this file with the value
(the file is git-ignored; a literal password is fine there), or they add
`VAR=value` to `~/.config/dosi/secrets.env`. dosi reads both on every call, so
nothing needs a restart. An unfilled placeholder fails with `missing_env`
naming it. Never ask for the value in the chat.

## Snowflake (key-pair; recommended)

```yaml
datasources:
  snowflake:
    type: snowflake
    account: ${SNOWFLAKE_ACCOUNT}        # e.g. ab12345.us-east-2.aws
    username: ${SNOWFLAKE_USER}
    warehouse: COMPUTE_WH
    role: ANALYST                        # optional
    database: ANALYTICS
    schema: PUBLIC                       # optional
    private_key_file: ~/.config/dosi/snowflake_key.p8
    private_key_file_pwd: ${SNOWFLAKE_KEY_PASSPHRASE}   # omit if unencrypted
    default: true
```

Password instead of key: replace the two `private_key_*` lines with
`password: ${SNOWFLAKE_PASSWORD}`. Browser SSO (`externalbrowser`) is not
supported yet.

## BigQuery

```yaml
datasources:
  bigquery:
    type: bigquery
    project: my-gcp-project
    dataset: analytics
    credentials_path: ~/.gcp/service-account.json
    location: US                         # optional
    default: true
```

## Databricks

```yaml
datasources:
  databricks:
    type: databricks
    host: dbc-xxxx.cloud.databricks.com
    warehouse: <sql warehouse id>
    password: ${DATABRICKS_TOKEN}
    catalog: main
    schema: analytics                    # optional
    default: true
```

## Postgres (also GaussDB / DWS / Hologres-style wire)

```yaml
datasources:
  pg:
    type: postgres
    host: pg.internal
    port: 5432
    username: analyst
    password: ${PG_PASSWORD}
    database: analytics
    sslmode: prefer
    default: true
```

## MySQL-wire (MySQL, StarRocks, Doris, TiDB)

```yaml
datasources:
  starrocks:
    type: starrocks                      # or mysql / doris / tidb
    host: sr.internal
    port: 9030
    username: analyst
    password: ${SR_PASSWORD}
    database: analytics
    default: true
```

## ClickHouse, Trino, Oracle, SQLite

Same shape: `type: clickhouse | trino | oracle | sqlite`, with `host`, `port`,
`username`, `password: ${VAR}`, `database` (Trino also `catalog`, `schema`).
SQLite and DuckDB take the file's absolute path as it is: `uri: /Users/me/data/shop.duckdb`.
(In URL form an absolute path needs four slashes, `duckdb:////Users/...`; with three
it is relative to the working directory.)

The full key list per connector is in the dosi docs (Connectors).
