#!/bin/sh
# Installing the newest dosi, checking for and installing a newer one, and the
# minimum version — without the network: a fake installer "installs" the
# release named in $T/latest, and the manifest dosi-upgrade reads says the same.
set -u
src=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
T=$(mktemp -d)
trap 'sleep 1; rm -rf "$T"' EXIT
mkdir -p "$T/plugin" "$T/home" "$T/proj"
cp -R "$src/bin" "$src/hooks" "$T/plugin/"
P=$T/plugin
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=$((fails + 1)); }
expect() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1: wanted [$3] in [$2]" ;; esac; }

cat > "$T/fake-install.sh" <<'EOF'
v=$(cat "$FAKE_LATEST")
[ "$v" = fail ] && { echo "network down"; exit 1; }
mkdir -p "$DOSI_INSTALL_DIR"
printf '#!/bin/sh\necho "dosi %s"\n' "$v" > "$DOSI_INSTALL_DIR/dosi"
printf '#!/bin/sh\necho "dosi-server %s"\n' "$v" > "$DOSI_INSTALL_DIR/dosi-server"
chmod +x "$DOSI_INSTALL_DIR/dosi" "$DOSI_INSTALL_DIR/dosi-server"
EOF
release() {
  printf '%s\n' "$1" > "$T/latest"
  printf '{"name": "dosi", "version": "%s", "artifacts": [{"version": "x"}]}\n' "$1" > "$T/manifest.json"
}
min() { printf '%s\n' "$1" > "$P/DOSI_MIN_VERSION"; }

export HOME="$T/home" DOSI_PLUGIN_DATA="$T/data" FAKE_LATEST="$T/latest" \
  DOSI_INSTALLER="$T/fake-install.sh" DOSI_MANIFEST_URL="file://$T/manifest.json" \
  CLAUDE_PROJECT_DIR="$T/proj"
unset DOSI_DEV_BIN_DIR CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA DOSI_SOURCE 2>/dev/null
current() { readlink "$T/data/bin/current"; }

# Version order.
DOSI_LIB_ROOT=$P sh -c '. "$DOSI_LIB_ROOT/hooks/lib.sh"
  dosi_version_ge 0.1.16 0.1.15 && dosi_version_ge 0.1.15 0.1.15 && dosi_version_ge 0.1.10 0.1.9 \
  && ! dosi_version_ge 0.1.14 0.1.15 && ! dosi_version_ge 0.1.15-dev.1 0.1.15 \
  && dosi_version_ge 0.1.15 0.1.15-dev.1 && ! dosi_version_ge "" 0.1.15' \
  && ok "version order" || bad "version order"

# First install: the newest release, whatever the minimum.
min 0.1.15; release 0.1.16
out=$(sh "$P/hooks/ensure-binary.sh")
expect "first install prints the release" "$out" "0.1.16"
[ "$(current)" = 0.1.16 ] && ok "current points at the newest" || bad "current is $(current)"
expect "the shim runs it" "$("$P/bin/dosi" --version)" "dosi 0.1.16"

# Checking and upgrading.
expect "check: up to date" "$("$P/bin/dosi-upgrade" --check)" '"current":"0.1.16","latest":"0.1.16","newer":false'
release 0.1.17
expect "check: newer out" "$("$P/bin/dosi-upgrade" --check)" '"latest":"0.1.17","newer":true'
expect "check remembers the newest" "$(cat "$T/data/bin/.latest")" "0.1.17"
expect "upgrade installs it" "$("$P/bin/dosi-upgrade")" '"from":"0.1.16","to":"0.1.17","changed":true'
[ "$(current)" = 0.1.17 ] && [ -f "$T/data/bin/0.1.16/.ok" ] \
  && ok "current moved, the old release kept" || bad "after upgrade: current $(current)"
expect "upgrade again: nothing to do" "$("$P/bin/dosi-upgrade")" '"changed":false'

# Session start mentions a newer release, once it is known.
release 0.1.18
"$P/bin/dosi-upgrade" --check >/dev/null
expect "session context names the newer release" "$(sh "$P/hooks/session-start.sh" </dev/null)" "dosi 0.1.18 is out (this machine runs 0.1.17)"

# The minimum: a current release below it is not used, and a newest release
# below it is refused with the reason.
min 0.1.20
DOSI_LIB_ROOT=$P sh -c '. "$DOSI_LIB_ROOT/hooks/lib.sh"; ! dosi_bin_ready' \
  && ok "below the minimum is not ready" || bad "below the minimum counted as ready"
sh "$P/hooks/ensure-binary.sh" >/dev/null 2>&1
[ $? -eq 3 ] && ok "newest below the minimum: install refused" || bad "install not refused"
expect "the reason names both versions" "$(cat "$T/data/bin/.failed")" "needs dosi 0.1.20 or newer, and the newest release is 0.1.18"
expect "the shim reports it" "$("$P/bin/dosi" --version)" '"code":"install_failed"'

# A failed download leaves the current release in place.
min 0.1.15; release fail
sh "$P/hooks/ensure-binary.sh" --upgrade >/dev/null 2>&1
[ $? -eq 3 ] && [ "$(current)" = 0.1.17 ] && ok "failed download keeps current" || bad "failed download: current $(current)"
expect "and says why" "$(cat "$T/data/bin/.failed")" "network down"

[ $fails -eq 0 ] && echo "upgrade: all cases pass" || exit 1
