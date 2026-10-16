#!/bin/sh
# PostToolUse (Write | Edit | MultiEdit): every edit of dosi/*.yaml is
# validated at once. Problems go back to Claude (exit 2) to fix silently —
# the user hears about it only if repair keeps failing (RFC §3.4).
DOSI_LIB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DOSI_LIB_ROOT
. "$DOSI_LIB_ROOT/hooks/lib.sh"

payload=$(cat)
file=$(printf '%s' "$payload" | json_get file_path)
proj=$(dosi_project)
case "$file" in
  "$proj"/dosi/*.yaml|"$proj"/dosi/*.yml|dosi/*.yaml|dosi/*.yml) ;;
  *) exit 0 ;;
esac

model="$proj/dosi/model.yaml"
onto="$proj/dosi/ontology.yaml"
set --
[ -f "$model" ] && set -- "$@" --model "$model"
[ -f "$onto" ] && set -- "$@" --ontology "$onto"
[ $# -gt 0 ] || exit 0

dosi="$DOSI_LIB_ROOT/bin/dosi"
out=$(unset DOSI_MODEL DOSI_ONTOLOGY; "$dosi" "$@" --format json validate 2>&1)
rc=$?
[ $rc -eq 3 ] && exit 0   # binary still installing: nothing to check yet

clean=1
[ $rc -ne 0 ] && clean=0
if [ $clean -eq 1 ]; then
  if command -v jq >/dev/null 2>&1; then
    n=$(printf '%s' "$out" | jq '((.issues // []) | length) + ((.compile_errors // []) | length)' 2>/dev/null)
    [ "${n:-1}" = 0 ] || clean=0
  else
    printf '%s' "$out" | tr -d ' \n' | grep -q '"issues":\[\]' || clean=0
    printf '%s' "$out" | tr -d ' \n' | grep -q '"compile_errors":\[\]' || clean=0
  fi
fi

progress="$DOSI_LIB_ROOT/bin/dosi-progress"
if [ $clean -eq 1 ]; then
  [ -f "$model" ] && "$progress" record model
  [ -f "$onto" ] && "$progress" record ontology
  if [ -f "$model" ]; then
    n=$(unset DOSI_ONTOLOGY; "$dosi" --model "$model" --format json list datasets 2>/dev/null | grep -c '"source"')
    "$progress" record datasets "${n:-0}"
    "$progress" record relationships "$(grep -c 'from_columns' "$model" 2>/dev/null || echo 0)"
  fi
  exit 0
fi

{
  echo "dosi validate 没通过（$file）。请直接修复并重新保存，不用告诉用户；连续 3 次修不好再按「发生了什么 / 原因 / 下一步」告知用户。"
  printf '%s\n' "$out" | head -n 60
} >&2
exit 2
