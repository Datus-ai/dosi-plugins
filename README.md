# Dosi plugins for coding agents

**English** | [简体中文](README.zh-CN.md)

Ask data questions in Claude Code (and other coding agents) and get answers
computed from governed metrics. [Dosi](https://dosi.datus.ai) is a local
semantic layer built on Apache Ossie (formerly OSI). From inside the agent it can:

- connect to your warehouse or a local file
- generate a semantic model
- answer questions with metrics, and show the SQL it ran
- show metric lineage
- build an ontology, once your questions need one

Everything runs on your machine. There is no setup wizard. Install the plugin,
ask a question, and the plugin introduces each feature when you need it.

> **Preview.** Importing dbt / Cube connection settings needs `dosi migrate conf`,
> which ships in the next dosi release. Until then, cloud warehouses are
> connected through a guided manual step. Local files (DuckDB, Parquet, CSV)
> work today.

## Install

### Claude Code

Type at the Claude Code prompt:

```
/plugin marketplace add Datus-ai/dosi-plugins
/plugin install dosi@dosi-plugins
```

Then run `/reload-plugins`, or start a new session. On its first start the
plugin downloads the dosi binary in the background (about 10 seconds), so
there is nothing else to install.

On Claude Code 2.1.275 or later, one line does both steps:
`/plugin install dosi --marketplace Datus-ai/dosi-plugins`. From a shell, run
`claude plugin install dosi --marketplace Datus-ai/dosi-plugins`.

### Any other coding agent

Say this to Codex, DeepSeek Harness, Gemini CLI, Grok, Cursor, or any other agent:

> Install Dosi by following https://raw.githubusercontent.com/Datus-ai/dosi-plugins/main/agent-install.md

The agent installs dosi and the skills in the way that agent supports.

## Tutorial: from zero to ontology in 10 minutes

Use the sample dataset (200k orders, with customers and products) in an empty folder:

```bash
mkdir dosi-try && cd dosi-try
curl -fsSLO https://dosi.datus.ai/orders-200k.duckdb
claude
```

Then type each prompt below in order. Every step was run end to end, and
the times are measured. At any point, `/dosi` shows where you are and what
to try next.

### 1. Connect, about 10 s

> Connect to my data

The plugin finds `orders-200k.duckdb` and connects with no questions.
Expected: a one-line confirmation that the `local` connection
(duckdb, `orders-200k.duckdb`) is up.

With your own data, this is where it detects your dbt project or Cube
`.env` and asks which connection to use (see [Your own data](#your-own-data)).

### 2. Build a semantic model, about 1 min

> Build a semantic model for this data

A subagent reads the schema, writes `dosi/model.yaml` (Apache Ossie) and
validates it. Expected: 3 datasets, 2 relationships and about 9 metrics.
You then get **at most three questions** about business meaning, for
example "should revenue include cancelled orders?". Each comes with a
recommended answer; pick one or say "use the recommendations".

### 3. Ask with metrics, about 15 s

> What is revenue by region and month?

Expected: a table, a one-line footer with the source and row count, and the
SQL dosi compiled. Ask follow-ups freely: "only north", "by week",
"month over month?".

### 4. See how a number is computed, about 15 s

> How is revenue calculated?

Expected: a lineage tree in the chat (table → dataset → metric), plus a
full interactive lineage page written locally. It opens in your browser
when one is available; otherwise you get the file path.

### 5. Ask for records, about 20 s

> List the 10 largest orders with customer region and product category

Expected: row-level results through `dosi select`, with joins chosen for
you. Then try another entity question:

> Which customers order the most?

### 6. Build an ontology when it is offered, about 1.5 min

After a couple of entity questions, the plugin offers an ontology **once**:
your questions involve several business entities, and asking by business
concept would be more accurate.

Answer "tell me more". A subagent drafts `dosi/ontology.yaml`
with the concepts Customer, Order and Product and their links, validates it,
and asks only if something is genuinely ambiguous. If you answer
"later", it asks again only after 10 more questions.

### 7. Ask by business concept, about 20 s

> In each product category, which region's customers buy the most?

Expected: the answer is computed through concept paths such as
`Order.placed_by.region` and `Order.purchases.category`, which you can
reuse in later questions.

## Your own data

Start Claude Code in your project folder and just ask a data question. The
plugin behaves the same way as in the tutorial, with one difference in
step 1:

| What the folder has | What step 1 does |
|---|---|
| a dbt project (`dbt_project.yml`, `~/.dbt/profiles.yml`) | Converts your profiles with `dosi migrate conf` and asks which target to use. The project's current target is recommended |
| a Cube `.env` | Converts the `CUBEJS_DB_*` settings the same way |
| `.duckdb` / `.sqlite` files | Connects directly, as in the tutorial |
| nothing | Asks where your data lives, then writes a connection whose secrets are `${VAR}` references |

Claude never sees your passwords. When a variable is missing, you set it
yourself with `! export NAME=...`. Browser-SSO logins
(`authenticator: externalbrowser`) are not supported yet; use key-pair
auth or a password variable instead.

## What's inside

| Part | What it does |
|---|---|
| `skills/dosi-connect` | Connects to a warehouse or local file. Converts dbt / Cube settings with `dosi migrate conf`. Secrets never enter the chat |
| `skills/dosi-model` | Generates and edits `dosi/model.yaml` (Apache Ossie) |
| `skills/dosi-query` | Answers with metrics (`query`), records (`select`) and change attribution (`attribute`) |
| `skills/dosi-view` | Shows metric lineage and the ontology graph, in the chat and as a local HTML page |
| `skills/dosi-ontology` | Builds `dosi/ontology.yaml` and answers questions by business concept |
| `agents/dosi-modeler`, `agents/dosi-ontologist` | Subagents that read schemas, so your main conversation stays clean |
| `hooks/` | Installs the pinned binary, validates every model edit, blocks reads of connection configs, and decides which feature to suggest next |
| `bin/dosi` | Runs the dosi release pinned in `DOSI_VERSION`. Plugin fixes ship on every commit; the dosi binary changes only when that file does |

### Files it creates in your project

```
dosi/model.yaml          # Apache Ossie semantic model: commit it
dosi/ontology.yaml       # only once you build an ontology: commit it
dosi-connections.yaml    # generated connections; may hold secrets, so it is added to .gitignore
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Plugin "dosi" not found in any marketplace` | Your Claude Code is older than 2.1.275. Use the two-line install above |
| `dosi_installing` | The first binary download is still running. Wait a few seconds; Claude retries on its own |
| `install_failed` behind a restricted network | Set `DOSI_SOURCE=oss` (Aliyun mirror), or `DOSI_SOURCE=cloudflare`, then start a new session |
| You want the feature suggestions to start over | `dosi-progress status` shows the state. Delete the project's file under `~/.claude/plugins/data/<plugin>/progress/` |

To uninstall, run `/plugin uninstall dosi@dosi-plugins`. That also removes
the downloaded binary.

## Privacy

Everything runs locally. The plugin makes two kinds of network request: the
one-time binary download, and the queries you run against your own
warehouse. There is no telemetry.

## License

Elastic License 2.0.
