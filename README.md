# Dosi plugins for coding agents

**English** | [简体中文](README.zh-CN.md)

Ask data questions in Claude Code (and other coding agents) and get answers
computed from governed metrics. [Dosi](https://dosi.datus.ai) is a local
semantic layer built on Apache Ossie (formerly OSI). From inside the agent it can:

- connect to your warehouse or a local file
- generate a semantic model
- answer questions with metrics (and show the SQL when you ask)
- show metric lineage
- build an ontology, once your questions need one

Everything runs on your machine. There is no setup wizard. Install the plugin,
ask a question, and the plugin introduces each feature when you need it.

## Install

### Claude Code

Type at the Claude Code prompt:

```
/plugin marketplace add Datus-ai/dosi-plugins
/plugin install dosi@dosi-plugins
```

Then run `/reload-plugins`, or start a new session. On its first start the
plugin downloads the newest dosi release in the background (about 10
seconds), so there is nothing else to install. Later, say "upgrade dosi" in
the conversation to move to a newer release; the plugin also mentions one
when it is out.

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

### 2. Build a semantic model, about 2 min

> Build a semantic model for this data

Claude reads the schema, writes `dosi/model.yaml` (Apache Ossie) and
validates it. Expected: 3 datasets, 2 relationships and about 9 metrics.
You then get **at most three questions** about business meaning, for
example "should revenue include cancelled orders?". Each comes with a
recommended answer; pick one or say "use the recommendations".

### 3. Ask with metrics, about 15 s

> What is revenue by region and month?

Expected: a one-sentence answer, a table, and a one-line footer with the
source and row count. Ask follow-ups freely: "only north", "by week",
"month over month?", or "show me the SQL".

### 4. See how a number is computed, about 15 s

> How is revenue calculated?

Expected: a lineage tree in the chat (table → dataset → metric).
`/dosi lineage revenue` opens the full graph in a pane; ask for a lineage
page to get a self-contained HTML file.

### 5. Ask for records, about 20 s

> List the 10 largest orders with customer region and product category

Expected: row-level results through `dosi select`, with joins chosen for
you. Then try another entity question:

> Which customers order the most?

### 6. Build an ontology when it is offered, about 1.5 min

After a few entity questions (counted by your questions, not by the queries
behind them), the plugin offers an ontology **once**, at the end of an
answer: your questions involve several business entities; a few minutes
spent on an ontology lets you ask by business concept. Build it now?

Answer "build it now". The assistant writes `dosi/ontology.yaml` and
`dosi/mapping.yaml` in the conversation with the concepts Customer, Order
and Product and their links, validates them, and asks only if something is
genuinely ambiguous. If you answer "later", it asks again only after 10
more questions.

### 7. Ask by business concept, about 20 s

> In each product category, which region's customers buy the most?

Expected: the answer is computed through concept paths such as
`Order.placed_by.region` and `Order.purchases.category`, which you can
reuse in later questions.

## In Claude Code: status, pane and result tables

In Claude Code the plugin also draws its own interface. None of it changes
what Claude reads, and every step above works the same without it.

- **Status line**: the live state of the project, for example
  `dosi · duckdb:local · 3 ds · 8 metrics · ontology 3`. It updates after
  every dosi command and every edit to `dosi/*.yaml`.
- **`/dosi`**: the connection, the model file and whether it validates,
  counts of datasets, metrics and dimensions, the ontology, and the next
  step. `/dosi metrics` lists every metric with its description.
- **`/dosi lineage [metric]`**: opens a lineage pane. In the terminal it
  draws a tree, either what a metric is computed from or what depends on a
  table. In Claude Code Desktop it also draws the full graph with the
  selected path highlighted. Press `h` to write the HTML page as well.
- **A band above the prompt**, only when there is something to act on:
  the model has validation issues, the ontology offer is pending (with
  buttons to answer it), or there is data in the folder but no connection yet.
- **Result rows**: a `dosi … --format json` result shows as a table, with
  the source and row count underneath and the SQL one click away. A failed
  command shows as the error, its cause and what to try next.

## Your own data

Start Claude Code in your project folder and just ask a data question. The
plugin behaves the same way as in the tutorial, with one difference in
step 1:

| What the folder has | What step 1 does |
|---|---|
| a dbt project (`dbt_project.yml`, `~/.dbt/profiles.yml`) | Converts your profiles with `dosi migrate conf` and asks which target to use. The project's current target is recommended |
| a Cube `.env` | Converts the `CUBEJS_DB_*` settings the same way |
| `.duckdb` / `.sqlite` files | Connects directly, as in the tutorial |
| nothing | Asks where your data lives (only what you have not said already), then writes the connection |

Claude never sees your passwords. For a password it writes a `${NAME}`
placeholder and asks you to fill it in yourself: replace it in
`dosi-connections.yaml` (git-ignored; a plain password there is fine), or put
`NAME=...` in `~/.config/dosi/secrets.env`. The next call picks it up, no
restart. Browser-SSO logins (`authenticator: externalbrowser`) are not
supported yet; use key-pair auth or a password instead.

## What's inside

| Part | What it does |
|---|---|
| `skills/dosi-connect` | Connects to a warehouse or local file. Converts dbt / Cube settings with `dosi migrate conf`. Secrets never enter the chat |
| `skills/dosi-model` | Generates and edits `dosi/model.yaml` (Apache Ossie) |
| `skills/dosi-query` | Answers with metrics (`query`), records (`select`) and change attribution (`attribute`) |
| `skills/dosi-view` | Shows metric lineage and the ontology graph, in the chat and as a local HTML page |
| `skills/dosi-ontology` | Builds `dosi/ontology.yaml` and answers questions by business concept |
| `skills/dosi-upgrade` | Says which dosi runs and installs a newer release when you ask |
| `agents/dosi-modeler`, `agents/dosi-ontologist` | Run modeling or ontology building in the background, when you ask for that |
| `hooks/` | Installs the newest dosi release, validates every model edit, blocks reads of connection configs, and decides which feature to suggest next. `register.tsx` is the Claude Code interface: status line, `/dosi`, the band, the lineage pane and result tables |
| `bin/dosi` | Runs the dosi release the plugin installed: the newest one on first use, never one older than `DOSI_MIN_VERSION`. Say "upgrade dosi" (`bin/dosi-upgrade`) to install a newer one |
| `bin/dosi-reconcile`, `bin/dosi-fill-derived` | Modeling helpers: check metrics against reference numbers cell by cell; write derived metrics' expansions from dosi |
| `.codex-plugin/`, `dsh/` | The same skills and hooks for Codex and DeepSeek Harness |

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
