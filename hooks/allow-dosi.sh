#!/bin/sh
# PreToolUse (Claude Code): the plugin's own calls go through without a
# permission prompt. Allowed:
#   * dosi's MCP tools (mcp__plugin_dosi_dosi__*): they read the model and
#     run only the queries it defines;
#   * the plugin's skills (dosi:*), and reading its own files and dosi's
#     bundled examples;
#   * writing dosi/** in the project with the file editor;
#   * one plain command of the plugin's (dosi, dosi-progress, dosi-reconcile,
#     dosi-fill-derived, dosi-upgrade): quoted arguments are fine, but no $,
#     backquote, redirection, pipe, chaining, glob, second line, or path
#     outside the project;
#   * writing dosi-connections.yaml with a quoted here-document and nothing
#     else (the file editor would echo the password back, see the guard),
#     `echo dosi-connections.yaml >> .gitignore`, and `mkdir -p dosi/build`.
# Everything else goes through the normal permission prompt. The config-read
# guard runs as well, and its deny wins.
DOSI_LIB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$DOSI_LIB_ROOT/hooks/lib.sh"

payload=$(cat)
tool=$(printf '%s' "$payload" | json_get tool_name)

allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# "yes" when $1 is one plain plugin command. Quoted strings are set aside
# first: single quotes are literal; double quotes may not hold $, ` or \.
plain_command() {
  printf '%s\n' "$1" | LC_ALL=C awk '
    NR > 1 { bad = 1 }
    NR == 1 { line = $0 }
    END {
      if (bad) { print "no"; exit }
      s = line; out = ""
      while (length(s) > 0) {
        c = substr(s, 1, 1)
        if (c == "\047" || c == "\"") {
          r = substr(s, 2); k = index(r, c)
          if (k == 0) { print "no"; exit }
          body = substr(r, 1, k - 1)
          if (c == "\"" && body ~ /[$`\\]/) { print "no"; exit }
          if (body ~ /^[\/~]/ || body ~ /\.\./) { print "no"; exit }
          out = out "Q"; s = substr(r, k + 1); continue
        }
        out = out c; s = substr(s, 2)
      }
      if (out !~ /^(dosi|dosi-progress|dosi-reconcile|dosi-fill-derived|dosi-upgrade)( |$)/) { print "no"; exit }
      if (out ~ /[^A-Za-z0-9 _.,:=\/@%+Q-]/) { print "no"; exit }
      if (out ~ /\.\./ || out ~ /(^| |=)\//) { print "no"; exit }
      print "yes"
    }'
}

# "yes" when $1 writes dosi-connections.yaml with a quoted here-document and
# does nothing else.
connections_heredoc() {
  printf '%s\n' "$1" | awk -v proj="$(dosi_project)" '
    NR == 1 {
      if ($0 !~ /^cat >>? ?[^ <>]+ <<-? ?(\047[A-Za-z_]+\047|"[A-Za-z_]+")$/) { bad = 1; exit }
      target = $0; sub(/^cat >>? ?/, "", target); sub(/ <<.*$/, "", target)
      if (target != "dosi-connections.yaml" && target != proj "/dosi-connections.yaml") { bad = 1; exit }
      tag = $0; sub(/^.*<<-? ?/, "", tag); gsub(/[\047"]/, "", tag)
      next
    }
    done && $0 != "" { bad = 1; exit }
    !done && $0 == tag { done = 1 }
    END { print (bad || !done) ? "no" : "yes" }'
}

case "$tool" in
  mcp__plugin_dosi_dosi__*) allow "dosi MCP tool" ;;
  Skill)
    case "$(printf '%s' "$payload" | json_get skill)" in
      dosi:*) allow "dosi skill" ;;
    esac ;;
  Read|Grep|Glob)
    file=$(printf '%s' "$payload" | json_get file_path)
    [ -n "$file" ] || file=$(printf '%s' "$payload" | json_get path)
    case "$file" in
      *..*|'') exit 0 ;;
      "$DOSI_LIB_ROOT"/*|"$DOSI_LIB_ROOT") allow "dosi plugin file" ;;
      "$(dosi_data)"/share/dosi/*) allow "dosi example" ;;
    esac ;;
  Write|Edit|MultiEdit)
    file=$(printf '%s' "$payload" | json_get file_path)
    proj=$(dosi_project)
    case "$file" in
      *..*) exit 0 ;;
      "$proj"/dosi/*|dosi/*) allow "dosi project file" ;;
    esac ;;
  Bash)
    cmd=$(printf '%s' "$payload" | json_get command)
    case "$cmd" in
      "echo dosi-connections.yaml >> .gitignore"|"echo 'dosi-connections.yaml' >> .gitignore")
        allow "dosi-connections.yaml into .gitignore" ;;
      "mkdir -p dosi/build"|"mkdir -p dosi"|"mkdir -p $(dosi_project)/dosi/build") allow "dosi scratch folder" ;;
    esac
    [ "$(connections_heredoc "$cmd")" = yes ] && allow "dosi-connections.yaml"
    [ "$(plain_command "$cmd")" = yes ] && allow "dosi command" ;;
esac
exit 0
