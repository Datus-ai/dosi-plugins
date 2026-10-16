# Dosi plugins for coding agents

Ask your data questions inside Claude Code (and other coding agents) through
[Dosi](https://dosi.datus.ai), a local semantic layer over Apache Ossie
(formerly OSI): connect a warehouse, generate a semantic model, answer with
governed metrics, see lineage — and, when you need it, build an ontology.
Everything runs on your machine.

> **Preview.** Importing dbt / Cube connection settings needs `dosi migrate conf`,
> which ships in the next dosi release; until then the plugin falls back to a
> guided manual connection.

## Install

Claude Code — type at the prompt:

```
/plugin install dosi --marketplace Datus-ai/dosi-plugins
```

If that says the plugin is not found (Claude Code older than 2.1.275), add the
marketplace first:

```
/plugin marketplace add Datus-ai/dosi-plugins
/plugin install dosi@dosi-plugins
```

Or from a shell: `claude plugin install dosi --marketplace Datus-ai/dosi-plugins`.

Any coding agent — say:

> Install Dosi by following https://raw.githubusercontent.com/Datus-ai/dosi-plugins/main/agent-install.md

Then just ask a data question, e.g. *"上个月各渠道收入多少？"*. Dosi picks up
your dbt or Cube connection settings, builds a small model for the question,
and answers with the SQL shown.

## What's inside

| Part | What it does |
|---|---|
| `skills/dosi-connect` | Connects to a warehouse or local file; converts dbt / Cube settings with `dosi migrate conf` — secrets never enter the chat |
| `skills/dosi-model` | Generates and edits `dosi/model.yaml` (Apache Ossie) |
| `skills/dosi-query` | Answers questions with metrics (`query`), records (`select`) and change attribution (`attribute`) |
| `skills/dosi-view` | Metric lineage and the ontology graph, in chat and as a local HTML page |
| `skills/dosi-ontology` | Builds `dosi/ontology.yaml` and asks by business concept — suggested only once your questions need it |
| `agents/dosi-modeler`, `agents/dosi-ontologist` | Subagents that read schemas so your conversation doesn't have to |
| `hooks/` | Installs the pinned dosi binary in the background, validates every model edit, blocks reading connection configs, tracks which features to suggest next |
| `bin/dosi` | Runs the dosi version this plugin pins (plugin version = dosi version) |

## Privacy

Runs locally. The only network traffic is the one-time binary download and
your own warehouse queries. No telemetry.

## License

Elastic License 2.0.
