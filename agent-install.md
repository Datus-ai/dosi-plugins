# Install Dosi — instructions for coding agents

> **For humans:** paste this into your coding agent (Claude Code, Codex,
> DeepSeek Harness, Gemini CLI, Grok, Cursor, …):
>
> `Install Dosi by following https://raw.githubusercontent.com/Datus-ai/dosi-plugins/main/agent-install.md`

---

**For coding agents.** You are installing Dosi — a local semantic layer
(metrics, lineage, ontology over the user's warehouse) — plus its skills, for
the agent you are running in. Fetch this file with `curl -fsSL`, not a
summarizing web fetch: summaries drop flags.

## Rules

1. Never ask the user to paste a password, token or key into the chat, and
   never open `profiles.yml`, `.env*`, `dosi-connections.yaml` or warehouse
   CLI configs. Connections are set up later by the `dosi-connect` skill.
2. Do not change files outside the user's home tool directories and this
   project without asking.
3. Ask no questions during install unless a step fails. Install is network
   once; everything after runs locally.
4. Finish with the verification step and a two-line summary. No tutorial —
   the skills introduce features when the user needs them.

## Step 1 — Which agent are you?

Use what you know about yourself; when unsure, check: `CLAUDECODE=1` or a
`claude` binary → Claude Code; `codex` → Codex; `dsh` → DeepSeek Harness;
`gemini` → Gemini CLI; `grok` → Grok; otherwise "other".

## Step 2 — Install the plugin / skills

**Claude Code**

```bash
claude plugin marketplace add Datus-ai/dosi-plugins
claude plugin install dosi@dosi-plugins --scope user
```

Then ask the user to type `/reload-plugins` (a slash command you cannot run
yourself). The plugin installs the dosi binary in the background on the next
session start — skip Step 3.

**Codex**

```bash
codex plugin marketplace add Datus-ai/dosi-plugins
```

then tell the user to open `/plugins` and install "dosi". The plugin installs
the dosi binary itself on first use — skip Step 3. Codex's sandbox blocks
network by default: cloud warehouses need network access enabled for dosi
commands.

**DeepSeek Harness**

Tell the user to open **Plugins → Add plugin** and enter
`https://github.com/Datus-ai/dosi-plugins` (DSH installs plugins with `pnpm`,
which must be on PATH), or run:

```bash
npx @deepseek-ai/dsh plugin --profile web add github:Datus-ai/dosi-plugins
```

The plugin installs the dosi binary itself on first use — skip Step 3. It
runs dosi through the CLI in each session's workspace, not as an MCP server.

**Gemini CLI**

```bash
gemini extensions install https://github.com/Datus-ai/dosi-plugins
```

**Grok / GitHub Copilot CLI** — they read Claude Code plugins; use the
Claude Code lines with the agent's own `plugin` command if it has one,
otherwise the "other" route.

**Other agents**

```bash
npx -y skills add Datus-ai/dosi-plugins --skill '*'
```

or copy `skills/*` from the repository into the agent's skills directory
(`~/.agents/skills/` is read by several agents).

## Step 3 — Install the dosi binary (Gemini CLI, Grok and other agents)

```bash
curl -fsSL https://dosi.datus.ai/install.sh | sh
```

Mainland China: `curl -fsSL https://dosi.datus.ai/install.sh | DOSI_SOURCE=oss sh`.
It installs `dosi` (with DuckDB built in) to `~/.local/bin`; make sure that is
on PATH.

## Step 4 — Verify

```bash
dosi info --format json | head -n 5
```

Expect `"engine_version"`. Then, without connecting anything:

```bash
EX=$(dosi info --format json | sed -n 's/.*"examples_dir": "\(.*\)".*/\1/p')
dosi --model "$EX/orders/model.yaml" list metrics
```

## Step 5 — Tell the user (two lines, nothing more)

In the user's language:

```
✓ Dosi installed (<version>, runs locally).
  Just ask me a data question, e.g. "revenue by channel last month"; I'll walk you through connecting a database when it's needed.
```
