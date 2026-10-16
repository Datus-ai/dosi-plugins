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

# The first command in $1 that READS a guarded file: a reader (cat, grep,
# sed, cp, curl, an interpreter, ...) with the file as an input argument, or
# any command fed it with `<`. Writing it (`> f`, `>> f`), existence checks
# (test, ls, for ... do test -f), dosi itself and a grep whose PATTERN merely
# names the file are all fine. One awk program: macOS /bin/sh (bash 3.2)
# cannot parse case patterns inside $(...), and awk tokenizes far better.
first_bad_segment() {
  printf '%s\n' "$1" | awk -v re="$guarded" '
    function strip(t) { gsub(/^["\047]+|["\047;)]+$/, "", t); return t }
    {
      line = $0
      gsub(/&&|\|\||;|\||\(|\)|`|\$\(/, "\n", line)
      n = split(line, segs, "\n")
      for (i = 1; i <= n; i++) {
        m = split(segs[i], w, /[ \t]+/)
        k = 1
        while (k <= m && (w[k] == "" || w[k] ~ /^(do|then|else|!|time|sudo|command|exec|xargs)$/ || w[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) k++
        if (k > m) continue
        cmd = w[k]; sub(/.*\//, "", cmd)
        reader = cmd ~ /^(cat|tac|less|more|head|tail|bat|nl|grep|egrep|fgrep|rg|ag|ack|sed|awk|gawk|cut|sort|uniq|wc|strings|xxd|od|hexdump|base64|md5sum|sha256sum|cp|mv|scp|rsync|curl|wget|source|\.|python|python3|node|perl|ruby|php|jq|yq|diff|cmp|vi|vim|nano|emacs|code|open|tee|dd|iconv|column|paste|join|tr|zip|tar|gzip)$/
        pattern_first = cmd ~ /^(grep|egrep|fgrep|rg|ag|ack|sed|awk|gawk)$/
        seen_pattern = 0
        for (j = k + 1; j <= m; j++) {
          t = w[j]
          if (t == "<" || t ~ /^</) {             # input redirection
            f = (t == "<") ? w[j + 1] : substr(t, 2)
            if (strip(f) ~ re) { print segs[i]; exit }
            if (t == "<") j++
            continue
          }
          if (t ~ /^[0-9]*>>?$/) { j++; continue }  # `> file`: a write
          if (t ~ /^[0-9]*>/) continue              # `>file` / `2>/dev/null`
          if (t ~ /^-/) continue                    # an option
          if (pattern_first && !seen_pattern) { seen_pattern = 1; continue }
          if (reader && strip(t) ~ re) { print segs[i]; exit }
        }
      }
    }'
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
