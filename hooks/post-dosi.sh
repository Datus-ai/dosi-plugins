#!/bin/sh
# PostToolUse (Bash): feed the progress engine from dosi commands that ran.
DOSI_LIB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DOSI_LIB_ROOT
. "$DOSI_LIB_ROOT/hooks/lib.sh"

payload=$(cat)
cmd=$(printf '%s' "$payload" | json_get command)
case "$cmd" in
  *dosi\ *|dosi) ;;
  *) exit 0 ;;
esac
p="$DOSI_LIB_ROOT/bin/dosi-progress"
flat=$(printf '%s' "$payload" | tr -d ' \n')
has() { printf '%s' "$flat" | grep -q "$1"; }

case "$cmd" in
  *"connection test"*) has '\\"ok\\":true\|"ok":true' && "$p" record connected ;;
  *"migrate conf"*) has 'status\\*"*:\\*"ok' && ! printf '%s' "$cmd" | grep -q -- '--detect' && "$p" record connected ;;
esac
# A subagent's trial queries (dosi-modeler checking its model) are not the
# user getting an answer: agent_id is present only inside a subagent.
in_subagent=0
has '"agent_id":"[^"]' && in_subagent=1
[ $in_subagent -eq 1 ] && exit 0
case "$cmd" in
  *" select "*"--execute"*|*" select "*"--execute") "$p" record select; "$p" record answered ;;
  *" query "*"--execute"*|*" query "*"--execute") has 'rows' && "$p" record answered ;;
esac
case "$cmd" in *" lineage "*) "$p" record lineage ;; esac
has 'ambiguous_join_path' && "$p" record ambiguous
exit 0
