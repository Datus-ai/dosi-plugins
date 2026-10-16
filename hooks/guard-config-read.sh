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
  echo "已拦截：`$1` 会打开数仓连接配置（可能含密钥），不要这样做。连接由 dosi 处理：用 \`dosi migrate conf --detect --format json\` 看有哪些来源，用 \`dosi migrate conf --from dbt|cube --format json\` 生成 dosi 连接（输出不含任何值）。只需要知道文件在不在时，用 test -f。" >&2
  exit 2
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
    bad=$(printf '%s\n' "$cmd" | sed 's/&&/;/g; s/||/;/g' | tr ';|' '\n\n' | while IFS= read -r seg; do
      printf '%s\n' "$seg" | grep -Eq "$guarded" || continue
      first=$(printf '%s\n' "$seg" | awk '{print $1}')
      case "$first" in
        dosi|*/dosi|ls|test|"["|stat) : ;;
        *) printf '%s\n' "$seg" | sed 's/^[[:space:]]*//'; break ;;
      esac
    done)
    [ -n "$bad" ] && deny "$bad" ;;
esac
exit 0
