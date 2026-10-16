#!/bin/sh
# Install the dosi version this plugin pins into the plugin data dir, once.
# Runs detached from session-start (and from the shim as a fallback), so the
# session never waits on a download. Markers in the version dir:
#   .lock    an install is running        .ok      installed and verified
#   .failed  last attempt's log tail (the shim reports it as install_failed)
# Network is used here and nowhere else at runtime (RFC D3).
DOSI_LIB_ROOT=${DOSI_LIB_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
. "$DOSI_LIB_ROOT/hooks/lib.sh"

ver=$(dosi_plugin_version)
dir=$(dosi_bin_dir)
mkdir -p "$dir"

[ -f "$dir/.ok" ] && [ -x "$dir/dosi" ] && exit 0

# Reuse a matching dosi already on PATH (outside this plugin) instead of
# downloading a second copy.
old_ifs=$IFS; IFS=:
for p in $PATH; do
  case "$p" in "$DOSI_LIB_ROOT"/*) continue ;; esac
  if [ -x "$p/dosi" ] && [ "$("$p/dosi" --version 2>/dev/null | awk '{print $2}')" = "$ver" ]; then
    IFS=$old_ifs
    ln -sf "$p/dosi" "$dir/dosi" && : > "$dir/.ok" && exit 0
  fi
done
IFS=$old_ifs

# One installer at a time; a lock older than 10 minutes is stale.
if [ -f "$dir/.lock" ] && [ -z "$(find "$dir/.lock" -mmin +10 2>/dev/null)" ]; then
  exit 0
fi
: > "$dir/.lock"
rm -f "$dir/.failed"

# Mainland China: GitHub is often unreachable, the OSS mirror is not.
source_=${DOSI_SOURCE:-}
if [ -z "$source_" ]; then
  case "${TZ:-}$(cat /etc/timezone 2>/dev/null)$(readlink /etc/localtime 2>/dev/null)" in
    *Shanghai*|*Chongqing*|*Harbin*|*Urumqi*) source_=oss ;;
    *) source_=github ;;
  esac
fi

log="$dir/install.log"
if DOSI_VERSION="$ver" DOSI_INSTALL_DIR="$dir" DOSI_SOURCE="$source_" \
   XDG_DATA_HOME="$(dosi_data)/share" sh "$DOSI_LIB_ROOT/hooks/install.sh" >"$log" 2>&1 \
   && "$dir/dosi" --version >/dev/null 2>&1; then
  : > "$dir/.ok"
else
  tail -n 20 "$log" > "$dir/.failed" 2>/dev/null || echo "installer failed" > "$dir/.failed"
fi
rm -f "$dir/.lock"
