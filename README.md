# Dosi plugins for coding agents

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

## First five minutes

Start in a project folder that has your dbt project, a Cube `.env`, or a local
`.duckdb` file. Then ask:

> 上个月各渠道收入多少？ / What was revenue by channel last month?

What happens next:

1. **Connect.** The plugin detects your dbt or Cube settings and asks you to
   pick a connection. If it finds none, it asks where your data lives.
   Passwords never pass through the chat. When a variable is missing, you set
   it yourself with `! export NAME=...`.
2. **Model.** You choose how much to model. The default is only the tables
   this question needs, which takes about 2 minutes. A subagent writes
   `dosi/model.yaml` and validates it. It asks only about real business
   ambiguities, such as "should revenue exclude refunds?".
3. **Answer.** You get a table, plus the exact SQL that dosi compiled and ran.

You can ask follow-ups in plain language. Some features appear only when
they become useful:

| Ask | You get |
|---|---|
| "How is revenue calculated?" | Metric lineage: a tree in the chat, plus a local HTML graph |
| "Which customers…" / "List the…" | Row-level detail through `dosi select` |
| (after several entity questions) | A single offer to build an ontology, so you can ask by business concept |
| `/dosi` | Your current stage, connection and model status, and the next step |

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
| `bin/dosi` | Runs the dosi version this plugin pins. The plugin version always equals the dosi version |

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
