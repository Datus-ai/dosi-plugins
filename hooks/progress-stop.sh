#!/bin/sh
# Stop (Claude Code): the turn is over. One user question counts as one
# answer however many queries it took (dosi-progress turn). Hints and
# questions are handed to the assistant during the turn by post-dosi.sh, so
# this hook never blocks the stop: a blocked stop made the assistant send
# the hint as a message of its own, and the terminal showed a hook notice.
DOSI_LIB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DOSI_LIB_ROOT
. "$DOSI_LIB_ROOT/hooks/lib.sh"

cat >/dev/null
"$DOSI_LIB_ROOT/bin/dosi-progress" turn >/dev/null 2>&1
exit 0
