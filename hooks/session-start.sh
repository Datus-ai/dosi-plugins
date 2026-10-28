#!/bin/sh
# SessionStart: make dosi usable with zero setup, and tell Claude — in at
# most five lines — where this project stands and the ONE next step.
#
#   * starts the dosi install in the background when none is usable (never
#     waits on it), and checks for a newer release at most once a day
#   * exports DOSI_BIN / DOSI_PLUGIN_DATA / DOSI_MODEL / DOSI_ONTOLOGY /
#     DOSI_EXAMPLES for every later Bash call through $CLAUDE_ENV_FILE
#   * detects config sources by EXISTENCE ONLY — it never opens profiles.yml,
#     .env or dosi-connections.yaml (RFC D5)
DOSI_LIB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DOSI_LIB_ROOT
. "$DOSI_LIB_ROOT/hooks/lib.sh"

proj=$(dosi_project)
data=$(dosi_data)
bindir=$(dosi_bin_dir)
progress="$DOSI_LIB_ROOT/bin/dosi-progress"

# 1. Binary: detached, so a first-run download never blocks the session.
dosi_bin_ready || dosi_install_in_background
# A newer release: checked in the background at most once a day; what the
# last check found is mentioned below, and installed only when the user asks.
latest_file="$data/bin/.latest"
if [ -z "${DOSI_DEV_BIN_DIR:-}" ] \
   && { [ ! -f "$latest_file" ] || [ -n "$(find "$latest_file" -mtime +0 2>/dev/null)" ]; }; then
  nohup sh "$DOSI_LIB_ROOT/bin/dosi-upgrade" --check >/dev/null 2>&1 < /dev/null &
fi

# 2. What exists here (existence only).
model=""; onto=""
[ -f "$proj/dosi/model.yaml" ] && model="$proj/dosi/model.yaml"
[ -f "$proj/dosi/ontology.yaml" ] && onto="$proj/dosi/ontology.yaml"
found=""; cfg=0
add() { found="${found:+${found}, }$1"; }
[ -f "$proj/dosi-connections.yaml" ] && add "dosi-connections.yaml"
{ [ -f "$proj/dbt_project.yml" ] || [ -f "$proj/profiles.yml" ] || [ -f "$HOME/.dbt/profiles.yml" ] \
  || [ -n "${DBT_PROFILES_DIR:-}" ]; } && { add "dbt profiles"; cfg=1; }
[ -f "$proj/.env" ] && { add ".env (maybe Cube)"; cfg=1; }
local_files=$(find "$proj" -maxdepth 1 -type f \( -name '*.duckdb' -o -name '*.parquet' -o -name '*.csv' -o -name '*.sqlite' -o -name '*.db' \) 2>/dev/null \
  | head -n 3 | sed "s|^$proj/||" | tr '\n' ' ' | sed 's/ $//')
[ -n "$local_files" ] && add "local data files $local_files"

# 3. Environment for later Bash calls (and a pointer for the mod, which
#    gets neither CLAUDE_PLUGIN_DATA nor the env file).
mkdir -p "$HOME/.cache/dosi-plugins" && printf '%s\n' "$data" > "$HOME/.cache/dosi-plugins/data-dir"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    printf "export DOSI_PLUGIN_DATA='%s'\n" "$data"
    printf "export DOSI_BIN='%s'\n" "$bindir/dosi"
    # The shim first: another dosi on the user's PATH (e.g. ~/.local/bin)
    # must not shadow the release this plugin installed.
    printf "export PATH='%s':\"\$PATH\"\n" "$DOSI_LIB_ROOT/bin"
    [ -n "$model" ] && printf "export DOSI_MODEL='%s'\n" "$model"
    [ -n "$onto" ] && printf "export DOSI_ONTOLOGY='%s'\n" "$onto"
    [ -f "$proj/dosi/mapping.yaml" ] && printf "export DOSI_MAPPING='%s'\n" "$proj/dosi/mapping.yaml"
    # The bundled example models (install.sh puts them under the data dir).
    [ -d "$data/share/dosi/examples" ] && printf "export DOSI_EXAMPLES='%s'\n" "$data/share/dosi/examples"
  } >> "$CLAUDE_ENV_FILE"
fi

# 4. Progress: what a previous session already reached.
export CLAUDE_PROJECT_DIR="$proj"
"$progress" record session
[ -n "$model" ] && "$progress" record model
[ -n "$onto" ] && "$progress" record ontology
# Local files count as connected only when nothing points at a warehouse:
# a stray .duckdb next to a dbt project must not skip choosing a connection.
{ [ -f "$proj/dosi-connections.yaml" ] || { [ -n "$local_files" ] && [ $cfg -eq 0 ]; }; } \
  && "$progress" record connected
if [ -n "$model" ] && dosi_bin_ready; then
  n=$(DOSI_MODEL="$model" "$bindir/dosi" --format json list datasets 2>/dev/null | grep -c '"source"')
  "$progress" record datasets "${n:-0}"
  "$progress" record relationships "$(grep -c 'from_columns' "$model" 2>/dev/null || echo 0)"
fi
stage=$("$progress" stage)

# 5. A few lines of context, one next step.
if [ -n "$model" ]; then
  where="model dosi/model.yaml${onto:+ + dosi/ontology.yaml}"
else
  where="no semantic model yet"
fi
if [ -z "$model" ] && [ "$stage" = S0 ]; then
  if [ -n "$found" ]; then
    next="On the first data question, connect with the dosi-connect skill from what was found (check that files exist, never open them), then build a model with dosi-model."
  else
    next="On the first data question, use the dosi-connect skill and ask where the data lives."
  fi
elif [ -z "$model" ]; then
  next="Connected, no model yet: on a data question, use the dosi-model skill to build a small model for that question first."
else
  next="Data questions go through the dosi-query skill."
fi

ctx="[dosi] Stage $stage · $where · found: ${found:-no connection config or local data files}
[dosi] Next: $next
[dosi] Rules: answer data questions with dosi's tools (MCP server dosi: run_query, select, describe_metric, ...; without it the CLI: dosi query/select/show), never with hand-written SQL over tables the model covers. Look at the warehouse only with the user's own client, never with a password on the command line. Never open profiles.yml, .env, dosi-connections.yaml or secrets.env, nor offer to: list connections with list_connections, and for a change tell the user which line to edit. Report errors as what happened / why / next step.
[dosi] Write every line the user sees, short progress lines included, in the language the user writes in."
current=$(dosi_current_version)
latest=$(cat "$latest_file" 2>/dev/null)
if [ -z "${DOSI_DEV_BIN_DIR:-}" ] && [ -n "$current" ] && [ -n "$latest" ] \
   && ! dosi_version_ge "$current" "$latest"; then
  ctx="$ctx
[dosi] dosi $latest is out (this machine runs $current). Once in this session, at the end of an answer, tell the user in one line that saying \"upgrade dosi\" installs it. Never upgrade unless asked."
fi
case "$stage" in
  S0|S1|S2|S3) ctx="$ctx
[dosi] Do not bring up ontologies unless the user does." ;;
esac

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$(json_str "$ctx")"
