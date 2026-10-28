#!/bin/sh
# Cases for hooks/allow-dosi.sh's Bash rules: sh tests/allow.sh.
# Needs jq and python3 (to build the JSON payload).
here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fails=0
check() {
  want=$1 cmd=$2
  payload=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":"/work/proj","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  out=$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR=/work/proj sh "$here/hooks/allow-dosi.sh")
  case "$out" in *'"allow"'*) got=allow ;; *) got=ask ;; esac
  if [ "$got" != "$want" ]; then echo "FAIL want=$want got=$got: $cmd"; fails=$((fails + 1)); fi
}
nl='
'
# Plain plugin commands.
check allow 'dosi validate --format json'
check allow 'dosi query --format json --execute --metrics revenue --group-by customers.region --where "customers.region = '"'north'"'" --limit 10'
check allow "dosi select --format json --execute --from orders --fields orders.order_id,orders.amount --where 'orders.amount > 100'"
check allow 'dosi-reconcile --reference dosi/build/ref.tsv --key region=region --same-names --group-by customers.region'
check allow 'dosi-fill-derived'
check allow 'dosi-upgrade --check'
check allow 'dosi-progress answer h_ontology later'
check allow 'dosi --model dosi/build/trial.yaml query --format json --execute --metrics revenue'
check ask 'dosi query --where "$(cat dosi/build/w.sql)" --format json'
check ask 'dosi query --where "`id`"'
check ask 'dosi validate --format json | head'
check ask 'dosi validate --format json 2>&1'
check ask 'dosi validate; rm -rf ~'
check ask 'dosi validate && touch x'
check ask 'dosi validate & touch /tmp/x'
check ask "dosi validate${nl}rm -rf ~"
check ask 'dosi lineage view --out /tmp/x.html'
check ask 'dosi lineage view --out "/tmp/x.html"'
check ask 'dosi lineage view --out ../x.html'
check ask 'dosi --model ~/m.yaml validate'
check ask 'dosi query --metrics *'
check ask 'DOSI_MODEL=x dosi validate'
check ask 'dosix validate'
check ask 'mysql --login-path=wh -B -e "SELECT 1"'
# The connections file, by here-document only.
check allow "cat > dosi-connections.yaml <<'EOF'${nl}datasources:${nl}  wh:${nl}    type: postgres${nl}EOF"
check allow "cat >> /work/proj/dosi-connections.yaml <<'EOF'${nl}  wh:${nl}    type: postgres${nl}EOF${nl}"
check ask "cat > dosi-connections.yaml <<EOF${nl}\$(rm -rf ~)${nl}EOF"
check ask "cat > dosi-connections.yaml <<'EOF'${nl}x${nl}EOF${nl}rm -rf ~"
check ask "test -f x || cat > dosi-connections.yaml <<'EOF'${nl}x${nl}EOF"
check ask "cat > ../dosi-connections.yaml <<'EOF'${nl}x${nl}EOF"
check ask "cat > dosi/model.yaml <<'EOF'${nl}x${nl}EOF"
# ... then one plain plugin command, on the next line or after &&.
check allow "cat > dosi-connections.yaml <<'EOF'${nl}datasources:${nl}  local:${nl}    type: duckdb${nl}EOF${nl}dosi connection test local --format json"
check allow "cat > dosi-connections.yaml <<'EOF' && dosi connection test local --format json${nl}datasources:${nl}EOF"
check allow "cat > dosi-connections.yaml <<'EOF'${nl}x${nl}EOF${nl}${nl}dosi connection test local --format json${nl}"
check ask "cat > dosi-connections.yaml <<'EOF'${nl}x${nl}EOF${nl}dosi connection test local; rm -rf ~"
check ask "cat > dosi-connections.yaml <<'EOF'${nl}x${nl}EOF${nl}dosi connection test local${nl}dosi validate"
check ask "cat > dosi-connections.yaml <<'EOF' && dosi connection test local${nl}x${nl}EOF${nl}dosi validate"
check ask "cat > dosi-connections.yaml <<'EOF' && rm -rf ~${nl}x${nl}EOF"
check ask "cat > dosi-connections.yaml <<'EOF'${nl}x${nl}EOF${nl}dosi query --where \"\$(id)\""
check ask "cat > dosi-connections.yaml <<'EOF'${nl}x${nl}EOF${nl}dosi lineage view --out /tmp/x.html"
check ask "cat > dosi/model.yaml <<'EOF'${nl}x${nl}EOF${nl}dosi validate"
check ask "cat > dosi-connections.yaml <<EOF${nl}x${nl}EOF${nl}dosi validate"
check allow 'echo dosi-connections.yaml >> .gitignore'
check ask 'echo x >> .gitignore'
check ask 'echo dosi-connections.yaml >> .gitignore; rm -rf ~'
check allow 'mkdir -p dosi/build'
check allow 'mkdir -p /work/proj/dosi/build'
check ask 'mkdir -p dosi/build && rm -rf ~'
check ask 'mkdir -p /tmp/x'
[ $fails -eq 0 ] && echo "allow-dosi.sh: all cases pass" || exit 1
