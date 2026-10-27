---
name: dosi-upgrade
description: Check or update the dosi engine this plugin runs. Use when the user asks which dosi version is installed, whether there is a newer one, or to upgrade or update dosi.
allowed-tools:
  - Bash(dosi-upgrade *)
  - Bash(dosi-upgrade)
---

# Check and update dosi

Write to the user in the language they write in, every progress line
included.

The plugin installs the newest dosi release on first use and keeps it until
the user asks for a newer one. `dosi-upgrade` is on PATH in Claude Code; in
other agents it is in the plugin's `bin/` folder, two levels above this
file.

- Which version, or is there a newer one → `dosi-upgrade --check` prints
  `current`, `latest`, `newer`. Answer in one line.
- Upgrade → `dosi-upgrade`, without asking first. It prints `from`, `to`,
  `changed`. Say what changed in one line, then when it takes effect:
  - Claude Code: dosi commands now; the query tools after reconnecting dosi
    in `/mcp`, or in a new session.
  - Codex: in a new session.
  - Agents that run dosi only as a command: now.
- Never upgrade unless the user asked. When the session context says a newer
  release is out, mention it once, in one line at the end of an answer.
- `install_failed` / `latest_unknown`: the release list or the download
  could not be reached. Say so in three lines (what happened / why / next
  step): check the network; in mainland China set `DOSI_SOURCE=oss`.
- `dev_build`: this machine runs a development build on purpose
  (`DOSI_DEV_BIN_DIR`). Say so and change nothing.
