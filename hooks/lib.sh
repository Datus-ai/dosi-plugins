# Shared helpers for the dosi plugin's hook scripts and bin/ wrappers.
# POSIX sh: hooks run under whatever /bin/sh the machine has, and jq is
# optional (a sed fallback reads the few flat string fields we need).

# Plugin root: the directory holding .claude-plugin/. Callers set
# DOSI_LIB_ROOT before sourcing when CLAUDE_PLUGIN_ROOT is not exported
# (bin/ wrappers run inside Bash tool calls, where it is not).
dosi_root() {
  printf '%s\n' "${CLAUDE_PLUGIN_ROOT:-${DOSI_LIB_ROOT:?}}"
}

# The plugin version — also the dosi version it pins (RFC Q3: one-to-one).
# The dosi release this plugin pins (RFC Q3). Kept in DOSI_VERSION, not in
# plugin.json: without a manifest version Claude Code versions the plugin by
# git commit, so plugin-only fixes reach users without a dosi release.
dosi_plugin_version() {
  tr -d ' \n' < "$(dosi_root)/DOSI_VERSION"
}

# Persistent per-plugin data dir. Hooks get CLAUDE_PLUGIN_DATA; Bash tool
# calls get DOSI_PLUGIN_DATA, which session-start exports for them.
dosi_data() {
  d="${CLAUDE_PLUGIN_DATA:-${DOSI_PLUGIN_DATA:-}}"
  # Last resort (the Claude Code mod runs us with neither): the pointer
  # session-start leaves behind.
  [ -n "$d" ] || d=$(cat "$HOME/.cache/dosi-plugins/data-dir" 2>/dev/null)
  [ -n "$d" ] || d="$HOME/.cache/dosi-plugins"
  mkdir -p "$d" 2>/dev/null
  printf '%s\n' "$d"
}

dosi_project() {
  printf '%s\n' "${CLAUDE_PROJECT_DIR:-$PWD}"
}

# Where the pinned binary lives once installed.
dosi_bin_dir() {
  printf '%s/bin/%s\n' "$(dosi_data)" "$(dosi_plugin_version)"
}

# Read one top-level-ish string field from JSON on stdin: json_get key.
# Good enough for hook payloads (tool_input.file_path, .command, ...).
json_get() {
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$1" '[.. | objects | select(has($k)) | .[$k]][0] // empty | if type == "string" then . else tostring end' 2>/dev/null
  else
    tr '\n' ' ' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\(\([^\"\\\\]\|\\\\.\)*\)\".*/\1/p" | head -n 1
  fi
}

# JSON-escape a string (for additionalContext and error payloads).
json_str() {
  printf '%s' "$1" | awk 'BEGIN { ORS = "" }
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t")
      if (NR > 1) printf "\\n"
      print }'
}
