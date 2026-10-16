#!/bin/sh
# SessionStart: make dosi usable with zero setup, and tell Claude — in at
# most five lines — where this project stands and the ONE next step.
#
#   * starts the pinned-binary install in the background (never waits on it)
#   * exports DOSI_BIN / DOSI_PLUGIN_DATA / DOSI_MODEL / DOSI_ONTOLOGY for
#     every later Bash call through $CLAUDE_ENV_FILE
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
if [ ! -f "$bindir/.ok" ]; then
  if command -v setsid >/dev/null 2>&1; then
    setsid sh "$DOSI_LIB_ROOT/hooks/ensure-binary.sh" >/dev/null 2>&1 < /dev/null &
  else
    nohup sh "$DOSI_LIB_ROOT/hooks/ensure-binary.sh" >/dev/null 2>&1 < /dev/null &
  fi
fi

# 2. What exists here (existence only).
model=""; onto=""
[ -f "$proj/dosi/model.yaml" ] && model="$proj/dosi/model.yaml"
[ -f "$proj/dosi/ontology.yaml" ] && onto="$proj/dosi/ontology.yaml"
found=""; cfg=0
add() { found="${found:+$found、}$1"; }
[ -f "$proj/dosi-connections.yaml" ] && add "dosi 连接配置"
{ [ -f "$proj/dbt_project.yml" ] || [ -f "$proj/profiles.yml" ] || [ -f "$HOME/.dbt/profiles.yml" ] \
  || [ -n "${DBT_PROFILES_DIR:-}" ]; } && { add "dbt 配置"; cfg=1; }
[ -f "$proj/.env" ] && { add ".env（可能是 Cube）"; cfg=1; }
local_files=$(find "$proj" -maxdepth 1 -type f \( -name '*.duckdb' -o -name '*.parquet' -o -name '*.csv' -o -name '*.sqlite' -o -name '*.db' \) 2>/dev/null \
  | head -n 3 | sed "s|^$proj/||" | tr '\n' ' ' | sed 's/ $//')
[ -n "$local_files" ] && add "本地数据文件 $local_files"

# 3. Environment for later Bash calls (and a pointer for the mod, which
#    gets neither CLAUDE_PLUGIN_DATA nor the env file).
mkdir -p "$HOME/.cache/dosi-plugins" && printf '%s\n' "$data" > "$HOME/.cache/dosi-plugins/data-dir"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    printf "export DOSI_PLUGIN_DATA='%s'\n" "$data"
    printf "export DOSI_BIN='%s'\n" "$bindir/dosi"
    # The shim first: another dosi on the user's PATH (e.g. ~/.local/bin)
    # must not shadow the version this plugin pins.
    printf "export PATH='%s':\"\$PATH\"\n" "$DOSI_LIB_ROOT/bin"
    [ -n "$model" ] && printf "export DOSI_MODEL='%s'\n" "$model"
    [ -n "$onto" ] && printf "export DOSI_ONTOLOGY='%s'\n" "$onto"
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
if [ -n "$model" ] && [ -f "$bindir/.ok" ]; then
  n=$(DOSI_MODEL="$model" "$bindir/dosi" --format json list datasets 2>/dev/null | grep -c '"source"')
  "$progress" record datasets "${n:-0}"
  "$progress" record relationships "$(grep -c 'from_columns' "$model" 2>/dev/null || echo 0)"
fi
stage=$("$progress" stage)

# What this dosi can do. Plugin version == dosi version, so before the binary
# lands the answer is the same as after; ask the binary when it is there.
caps=""
if [ -f "$bindir/.ok" ]; then
  "$bindir/dosi" --help 2>/dev/null | grep -q '^  migrate' || caps="no-migrate"
else
  case "$(dosi_plugin_version)" in 0.1.13|0.1.12|0.1.11) caps="no-migrate" ;; esac
fi

# 5. At most five lines of context, one next step.
if [ -n "$model" ]; then
  where="模型 dosi/model.yaml${onto:+ + dosi/ontology.yaml}"
else
  where="还没有语义模型"
fi
if [ -z "$model" ] && [ "$stage" = S0 ]; then
  if [ -n "$found" ]; then
    next="用户第一次问数据问题时，用 dosi-connect skill 从已发现的配置生成连接（只检测文件是否存在，不要打开它们），再用 dosi-model 建模。"
  else
    next="用户第一次问数据问题时，用 dosi-connect skill，先用 AskUserQuestion 问数据在哪里。"
  fi
elif [ -z "$model" ]; then
  next="已有连接、还没有模型：用户问数据问题时，用 dosi-model skill 先建一个只覆盖这个问题的最小模型。"
else
  next="数据问题走 dosi-query skill；每次回答结束前运行 dosi-progress next，有输出就照做。"
fi

ctx="[dosi] 阶段 $stage · $where${found:+ · 发现：$found}
[dosi] 下一步：$next
[dosi] 规则：数据问题用 dosi 的指标或 select 回答，不要手写 SQL 查模型已覆盖的表；展示生成的 SQL；不要打开 profiles.yml、.env、dosi-connections.yaml；错误按「发生了什么 / 原因 / 下一步」转述。"
[ "$caps" = no-migrate ] && ctx="$ctx
[dosi] 这个 dosi 版本没有 migrate / connection / sql 命令：不要调用或探测它们。本地文件直接写 dosi-connections.yaml；数仓按 dosi-connect 的手动路径（${VAR} 模板）。"
case "$stage" in
  S0|S1|S2|S3) ctx="$ctx
[dosi] 当前阶段不要主动提 ontology，除非用户自己问到。" ;;
esac

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$(json_str "$ctx")"
