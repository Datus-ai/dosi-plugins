# Shared helpers for the dosi plugin's hook scripts and bin/ wrappers.
# POSIX sh: hooks run under whatever /bin/sh the machine has, and jq is
# optional (a sed fallback reads the few flat string fields we need).

# Plugin root: the directory holding .claude-plugin/. Callers set
# DOSI_LIB_ROOT before sourcing when CLAUDE_PLUGIN_ROOT is not exported
# (bin/ wrappers run inside Bash tool calls, where it is not).
dosi_root() {
  printf '%s\n' "${CLAUDE_PLUGIN_ROOT:-${DOSI_LIB_ROOT:?}}"
}

# The oldest dosi release this plugin works with. The plugin installs the
# newest release, and upgrades when the user asks; it never runs one older
# than this. Kept in DOSI_MIN_VERSION, not in plugin.json: without a manifest
# version Claude Code versions the plugin by git commit.
dosi_min_version() {
  tr -d ' \n' < "$(dosi_root)/DOSI_MIN_VERSION"
}

# Exit 0 when version $1 is $2 or newer: numeric major.minor.patch, and a
# pre-release (0.1.15-dev.1) sorts before its release. An empty $1 is never
# new enough.
dosi_version_ge() {
  [ -n "$1" ] || return 1
  awk -v a="$1" -v b="$2" '
    function parse(v, R,    core, p, n, parts, i) {
      sub(/^v/, "", v)
      p = index(v, "-")
      if (p) { R["pre"] = substr(v, p + 1); core = substr(v, 1, p - 1) }
      else { R["pre"] = ""; core = v }
      sub(/\+.*/, "", core)
      n = split(core, parts, ".")
      for (i = 1; i <= 3; i++) R[i] = (i <= n ? parts[i] + 0 : 0)
    }
    BEGIN {
      parse(a, A); parse(b, B)
      for (i = 1; i <= 3; i++) { if (A[i] > B[i]) exit 0; if (A[i] < B[i]) exit 1 }
      if (A["pre"] == B["pre"] || A["pre"] == "") exit 0
      if (B["pre"] == "") exit 1
      exit (A["pre"] >= B["pre"]) ? 0 : 1
    }'
}

# Persistent per-plugin data dir. Bash tool calls get DOSI_PLUGIN_DATA,
# which session-start exports for them; hooks and the MCP launcher get
# CLAUDE_PLUGIN_DATA. DOSI_PLUGIN_DATA wins: another plugin's hooks can leave
# their own CLAUDE_PLUGIN_DATA in the shell environment (a codex plugin did),
# and only a dosi data dir is trusted from that variable.
dosi_data() {
  d="${DOSI_PLUGIN_DATA:-}"
  if [ -z "$d" ]; then
    case "${CLAUDE_PLUGIN_DATA:-}" in
      */dosi|*/dosi-*) d=$CLAUDE_PLUGIN_DATA ;;
    esac
  fi
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

# Where the binaries (dosi, dosi-server) live: each installed release in
# <data>/bin/<version>/, and <data>/bin/current pointing at the one in use.
# DOSI_DEV_BIN_DIR points at a local engine build instead (development).
dosi_bin_dir() {
  if [ -n "${DOSI_DEV_BIN_DIR:-}" ]; then
    printf '%s\n' "$DOSI_DEV_BIN_DIR"
    return
  fi
  printf '%s/bin/current\n' "$(dosi_data)"
}

# The release bin/current points at; empty before the first install.
dosi_current_version() {
  l=$(readlink "$(dosi_data)/bin/current" 2>/dev/null) || return 0
  basename "$l"
}

# The binaries are usable: a verified install no older than the plugin's
# minimum, or a development build.
dosi_bin_ready() {
  if [ -n "${DOSI_DEV_BIN_DIR:-}" ]; then
    [ -x "$DOSI_DEV_BIN_DIR/dosi" ]
    return
  fi
  dir=$(dosi_bin_dir)
  [ -x "$dir/dosi" ] && [ -f "$dir/.ok" ] \
    && dosi_version_ge "$(dosi_current_version)" "$(dosi_min_version)"
}

# Where releases come from: DOSI_SOURCE, else the OSS mirror in mainland
# China (GitHub is often unreachable there), else GitHub.
dosi_source() {
  if [ -n "${DOSI_SOURCE:-}" ]; then
    printf '%s\n' "$DOSI_SOURCE"
    return
  fi
  case "${TZ:-}$(cat /etc/timezone 2>/dev/null)$(readlink /etc/localtime 2>/dev/null)" in
    *Shanghai*|*Chongqing*|*Harbin*|*Urumqi*) echo oss ;;
    *) echo github ;;
  esac
}

# Start the installer detached, so no caller waits on a download.
dosi_install_in_background() {
  if command -v setsid >/dev/null 2>&1; then
    setsid sh "$(dosi_root)/hooks/ensure-binary.sh" >/dev/null 2>&1 < /dev/null &
  else
    nohup sh "$(dosi_root)/hooks/ensure-binary.sh" >/dev/null 2>&1 < /dev/null &
  fi
}

# Where the user may keep connection secrets as KEY=VALUE lines, outside the
# project (optional; a password written straight into dosi-connections.yaml
# works as well). The CLI shim and the MCP server both read it.
dosi_secrets_file() {
  printf '%s\n' "${DOSI_SECRETS_FILE:-$HOME/.config/dosi/secrets.env}"
}

# Export the secrets file's variables that the environment does not set.
# Values are never printed.
dosi_load_secrets() {
  f=$(dosi_secrets_file)
  [ -r "$f" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line#export }
    case "$line" in ''|'#'*|*[!A-Za-z0-9_=]*=*) ;; esac
    key=${line%%=*}
    case "$key" in ''|*[!A-Za-z0-9_]*) continue ;; esac
    [ "$key" = "$line" ] && continue
    eval "[ -n \"\${$key+x}\" ]" && continue
    val=${line#*=}
    case "$val" in \"*\") val=${val#\"}; val=${val%\"} ;; \'*\') val=${val#\'}; val=${val%\'} ;; esac
    export "$key=$val"
  done < "$f"
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
# Byte mode (LC_ALL=C): only ASCII is escaped, so UTF-8 text passes through
# untouched and a stray invalid byte cannot make awk fail.
json_str() {
  printf '%s' "$1" | LC_ALL=C awk 'BEGIN { ORS = "" }
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t")
      if (NR > 1) printf "\\n"
      print }'
}
