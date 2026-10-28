#!/bin/sh
# PostToolUse (Write | Edit | MultiEdit | Bash): every change to dosi/*.yaml
# is validated at once — whether the editor tool wrote it or a Bash command
# did (sed -i, a heredoc, a script). Problems go back to Claude (exit 2) to
# fix silently; the user hears about it only if repair keeps failing.
DOSI_LIB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DOSI_LIB_ROOT
. "$DOSI_LIB_ROOT/hooks/lib.sh"

payload=$(cat)
tool=$(printf '%s' "$payload" | json_get tool_name)
proj=$(dosi_project)
if [ "$tool" = apply_patch ]; then
  # Codex: the patch text names the files it touched.
  printf '%s' "$payload" | json_get command | grep -Eq '^\*\*\* (Add|Update) File: .*dosi/[^[:space:]]*\.ya?ml' || exit 0
  file="dosi/(patch)"
elif [ "$tool" = Bash ]; then
  cmd=$(printf '%s' "$payload" | json_get command)
  # Only commands that can have written a model file: one naming a
  # dosi/*.yaml together with something that writes.
  printf '%s' "$cmd" | grep -Eq 'dosi/[^[:space:]"'"'"']*\.ya?ml' || exit 0
  printf '%s' "$cmd" | grep -Eq '(^|[^0-9])>|sed[[:space:]]+(-[a-zA-Z]*i|--in-place)|\btee\b|\bmv\b|\bcp\b|python|perl|ruby|node|yq' || exit 0
  file="dosi/(bash)"
else
  file=$(printf '%s' "$payload" | json_get file_path)
  case "$file" in
    "$proj"/dosi/*.yaml|"$proj"/dosi/*.yml|dosi/*.yaml|dosi/*.yml) ;;
    *) exit 0 ;;
  esac
fi

model="$proj/dosi/model.yaml"
onto="$proj/dosi/ontology.yaml"
mapping="$proj/dosi/mapping.yaml"
set --
[ -f "$model" ] && set -- "$@" --model "$model"
[ -f "$onto" ] && set -- "$@" --ontology "$onto"
[ -f "$mapping" ] && set -- "$@" --mapping "$mapping"
[ $# -gt 0 ] || exit 0

dosi="$DOSI_LIB_ROOT/bin/dosi"
errf="${TMPDIR:-/tmp}/dosi-validate.$$"
# stdout is the JSON verdict; stderr carries notes and warnings that must not
# corrupt it.
out=$(unset DOSI_MODEL DOSI_ONTOLOGY DOSI_MAPPING; "$dosi" "$@" --format json validate 2>"$errf")
rc=$?
err=$(cat "$errf" 2>/dev/null); rm -f "$errf"
[ $rc -eq 3 ] && exit 0   # binary still installing: nothing to check yet

clean=1
[ $rc -ne 0 ] && clean=0
if [ $clean -eq 1 ]; then
  if command -v jq >/dev/null 2>&1; then
    n=$(printf '%s' "$out" | jq '((.issues // []) | length) + ((.compile_errors // []) | length)' 2>/dev/null)
    [ "${n:-1}" = 0 ] || clean=0
  else
    flat=$(printf '%s' "$out" | tr -d ' \n')
    printf '%s' "$flat" | grep -q '"issues":\[\]' || clean=0
    printf '%s' "$flat" | grep -q '"compile_errors":\[\]' || clean=0
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
  echo "dosi validate failed (${file}). Fix it and save again without telling the user; only after 3 failed fixes in a row, tell them: what happened / why / next step."
  # A parse failure leaves stdout empty and the reason on stderr.
  if [ -n "$out" ]; then printf '%s\n' "$out" | head -n 60; else printf '%s\n' "$err" | head -n 30; fi
  if printf '%s' "$out" | grep -q 'derive_expression_mismatch'; then
    echo "Derived metrics: do not write the expanded expression by hand. After a batch of them, run dosi-fill-derived once; it writes each expansion into model.yaml from the derive declaration."
  fi
} >&2
exit 2
