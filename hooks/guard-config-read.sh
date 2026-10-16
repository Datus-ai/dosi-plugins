#!/bin/sh
# PreToolUse (Read | Grep | Bash): connection configs are dosi's to read,
# never the agent's (RFC D5, §6.7). Blocks opening dbt profiles, .env files,
# dosi-connections.yaml, Datus agent.yml and warehouse CLI configs. Existence
# checks (ls, test, [ -f ]) and dosi's own commands stay allowed.
DOSI_LIB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$DOSI_LIB_ROOT/hooks/lib.sh"

payload=$(cat)
tool=$(printf '%s' "$payload" | json_get tool_name)

guarded='(profiles\.yml|dosi-connections\.ya?ml|\.snowsql/|\.databrickscfg|\.datus/conf/agent\.yml|conf/agent\.yml|(^|[/[:space:]"'"'"'=])\.env(\.[A-Za-z0-9_-]+)?($|[[:space:]"'"'"';|&)]))'

deny() {
  # printf with %s only: the blocked command must never be expanded or run.
  printf '%s\n' "已拦截：这条操作会打开数仓连接配置（可能含密钥），不要这样做：" "  $1" \
    "连接由 dosi 处理：dosi migrate conf --detect --format json 查看有哪些来源；" \
    "dosi migrate conf --from dbt|cube --format json 生成 dosi 连接（输出不含任何值）。" \
    "只需要知道文件在不在时，用 test -f <path>。" >&2
  exit 2
}

# First pipeline segment that touches a guarded path with anything other than
# an existence check or dosi itself. A function, not a case inside $(...):
# macOS /bin/sh (bash 3.2) cannot parse case patterns in command substitution.
first_bad_segment() {
  printf '%s\n' "$1" | sed 's/&&/;/g; s/||/;/g' | tr ';|' '\n\n' | while IFS= read -r seg; do
    printf '%s\n' "$seg" | grep -Eq "$guarded" || continue
    first=$(printf '%s\n' "$seg" | awk '{print $1}')
    if allowed_cmd "$first"; then continue; fi
    printf '%s\n' "$seg" | sed 's/^[[:space:]]*//'
    break
  done
}

allowed_cmd() {
  case "$1" in
    dosi|*/dosi|ls|test|"["|stat) return 0 ;;
    *) return 1 ;;
  esac
}

case "$tool" in
  Read|Grep|Glob|NotebookRead)
    for key in file_path path pattern glob; do
      v=$(printf '%s' "$payload" | json_get "$key")
      [ -n "$v" ] || continue
      if printf '%s\n' "$v" | grep -Eq "$guarded"; then deny "$v"; fi
    done ;;
  Bash)
    cmd=$(printf '%s' "$payload" | json_get command)
    printf '%s\n' "$cmd" | grep -Eq "$guarded" || exit 0
    # Judge each pipeline segment on its own: `dosi migrate conf ...` and
    # `test -f ~/.dbt/profiles.yml` are fine, `cat`/`grep`/`head` are not.
    bad=$(first_bad_segment "$cmd")
    [ -n "$bad" ] && deny "$bad" ;;
esac
exit 0
