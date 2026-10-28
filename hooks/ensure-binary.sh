#!/bin/sh
# Install the newest dosi release into the plugin data dir and point
# bin/current at it. Each release lands in bin/<version>/ (with .ok once
# installed and verified); markers in bin/:
#   .lock    an install is running
#   .failed  last attempt's reason (the shim reports it as install_failed)
#
#   ensure-binary.sh            install when nothing usable is installed: no
#                               current release, or one older than the
#                               plugin's minimum (session start, the shim)
#   ensure-binary.sh --upgrade  install the newest release even when the
#                               current one is usable (dosi-upgrade); prints
#                               the installed version
#
# Runs detached from session-start and the shim, so a session never waits on
# a download. Network is used here and in `dosi-upgrade --check`, nowhere
# else at runtime (RFC D3). DOSI_INSTALLER replaces hooks/install.sh (tests).
DOSI_LIB_ROOT=${DOSI_LIB_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
. "$DOSI_LIB_ROOT/hooks/lib.sh"

[ -n "${DOSI_DEV_BIN_DIR:-}" ] && exit 0
upgrade=0
[ "${1:-}" = --upgrade ] && upgrade=1
[ $upgrade -eq 0 ] && dosi_bin_ready && exit 0

min=$(dosi_min_version)
bin="$(dosi_data)/bin"
mkdir -p "$bin"

# One installer at a time; a lock older than 10 minutes is stale.
if [ -f "$bin/.lock" ] && [ -z "$(find "$bin/.lock" -mmin +10 2>/dev/null)" ]; then
  [ $upgrade -eq 1 ] && { echo "another dosi install is running; try again in a minute" >&2; exit 4; }
  exit 0
fi
: > "$bin/.lock"
rm -f "$bin/.failed"
stage="$bin/.stage-$$"
trap 'rm -f "$bin/.lock"; rm -rf "$stage"' EXIT

# Mainland China: GitHub is often unreachable, the OSS mirror is not.
source_=$(dosi_source)

# No DOSI_VERSION: the installer resolves the newest release itself.
log="$bin/install.log"
mkdir -p "$stage"
if DOSI_INSTALL_DIR="$stage" DOSI_SOURCE="$source_" XDG_DATA_HOME="$(dosi_data)/share" \
   sh "${DOSI_INSTALLER:-$DOSI_LIB_ROOT/hooks/install.sh}" >"$log" 2>&1 \
   && ver=$("$stage/dosi" --version 2>/dev/null | awk '{print $2}') && [ -n "$ver" ]; then
  :
else
  tail -n 20 "$log" > "$bin/.failed" 2>/dev/null || echo "installer failed" > "$bin/.failed"
  exit 3
fi

if ! dosi_version_ge "$ver" "$min"; then
  echo "this plugin needs dosi $min or newer, and the newest release is $ver" > "$bin/.failed"
  exit 3
fi

# A release already installed is kept as it is: a running dosi-server may be
# using its files.
if [ ! -f "$bin/$ver/.ok" ]; then
  rm -rf "${bin:?}/$ver"
  mv "$stage" "$bin/$ver" && : > "$bin/$ver/.ok"
fi
ln -sfn "$ver" "$bin/current"
printf '%s\n' "$ver"
