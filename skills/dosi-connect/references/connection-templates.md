# Connection templates

`dosi-connections.yaml` uses the Datus `datasources:` vocabulary. Every secret
is a `${VAR}` reference — dosi reads it from the environment when the
connection is used, and a missing one fails with `missing_env` naming it.
Mark one entry `default: true`; `--execute` without `--connection` uses it.

Write only what the user told you or what is non-secret. After writing, tell
the user which variables to set, as `! export NAME=...` lines.

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
SQLite and DuckDB take `uri: duckdb:///<abs path>` / `uri: sqlite:///<abs path>`.

The full key list per connector is in the dosi docs (Connectors).
