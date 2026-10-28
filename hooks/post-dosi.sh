#!/bin/sh
# PostToolUse (Bash | dosi MCP tools): feed the progress engine from the dosi
# calls that ran, whichever channel ran them. On the first query of a turn
# that has a one-time hint or question due, hand it to the assistant now, so
# it ends this answer with it (instead of a Stop hook forcing an extra
# message after the answer).
DOSI_LIB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DOSI_LIB_ROOT
. "$DOSI_LIB_ROOT/hooks/lib.sh"

payload=$(cat)
tool=$(printf '%s' "$payload" | json_get tool_name)
p="$DOSI_LIB_ROOT/bin/dosi-progress"
flat=$(printf '%s' "$payload" | tr -d ' \n')
has() { printf '%s' "$flat" | grep -q "$1"; }
# A subagent's trial queries (a modeler checking its model) are not the user
# getting an answer: agent_id is present only inside a subagent.
in_subagent=0
has '"agent_id":"[^"]' && in_subagent=1
# The hint or question due now, as context for the rest of this turn.
offer() {
  [ $in_subagent -eq 0 ] || return 0
  out=$("$p" next --pending 2>/dev/null)
  case "$out" in
    HINT:*)
      hint=$(printf '%s\n' "$out" | sed -n 's/^HINT: //p' | head -n 1)
      msg="If this turn gives the user numbers computed from the model, end that answer with this one line, in the user's language (this turn only; not after trial or intermediate results): ${hint}" ;;
    ASK:*)
      q=$(printf '%s\n' "$out" | sed -n 's/^ASK: //p' | head -n 1)
      id=$(printf '%s\n' "$out" | sed -n 's/.*dosi-progress answer \(h_[a-z_]*\).*/\1/p' | head -n 1)
      msg="After your answer to this turn is written in full, ask the user this one question, in the user's language, as the last step (question and options are separated by |; the first option is the recommended one): ${q}. Record the choice with \`dosi-progress answer ${id} yes|later|never\` (the options in order are yes, later, never). On yes: an ontology question goes on with the dosi-ontology skill; a commit question commits only the dosi/ folder, never dosi-connections.yaml. Do not explain where the question comes from." ;;
    *) return 0 ;;
  esac
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$(json_str "$msg")"
}
# A tool error carries "error" with a code; a success carries rows.
failed=0
has '"is_error":true\|\\"error\\":{' && failed=1

case "$tool" in
  mcp__plugin_dosi_dosi__*)
    [ $failed -eq 1 ] && exit 0
    case "${tool#mcp__plugin_dosi_dosi__}" in
      run_query) [ $in_subagent -eq 0 ] && "$p" record queried && offer ;;
      select) [ $in_subagent -eq 0 ] && { "$p" record select; "$p" record queried; offer; } ;;
      attribute_metric) [ $in_subagent -eq 0 ] && "$p" record queried && offer ;;
    esac
    has 'ambiguous_join_path' && "$p" record ambiguous
    exit 0 ;;
  Bash) ;;
  *) exit 0 ;;
esac

cmd=$(printf '%s' "$payload" | json_get command)
case "$cmd" in
  *dosi\ *|dosi) ;;
  *) exit 0 ;;
esac
case "$cmd" in
  *"connection test"*) has '\\"ok\\":true\|"ok":true' && "$p" record connected ;;
  *"migrate conf"*) has 'status\\*"*:\\*"ok' && ! printf '%s' "$cmd" | grep -q -- '--detect' && "$p" record connected ;;
esac
[ $in_subagent -eq 1 ] && exit 0
case "$cmd" in
  *" select "*"--execute"*|*" select "*"--execute") "$p" record select; "$p" record queried; offer ;;
  *" query "*"--execute"*|*" query "*"--execute") has 'rows' && "$p" record queried && offer ;;
esac
case "$cmd" in *" lineage "*) "$p" record lineage ;; esac
has 'ambiguous_join_path' && "$p" record ambiguous
exit 0
