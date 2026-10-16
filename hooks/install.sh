#!/bin/sh
# Dosi installer — https://dosi.datus.ai/install.sh
#
#   curl -fsSL https://dosi.datus.ai/install.sh | sh
#
# Reads manifest.json from the latest release, downloads the archive matching
# this OS and CPU, verifies its SHA-256, and installs `dosi` and `dosi-server`.
# Dosi ships for Linux and macOS.
#
#   DOSI_VERSION=0.1.13  install a specific version instead of the latest
#   DOSI_INSTALL_DIR     install location (default: ~/.local/bin)
#   DOSI_SOURCE          which source to fetch BOTH the manifest and the
#                        archive from: github (default), oss, or cloudflare.
#                        Picks exactly one — no automatic fallback between
#                        them, so a failure in the chosen source fails the
#                        install outright rather than silently trying
#                        another. Mainland China installs should pass
#                        DOSI_SOURCE=oss.
#   DOSI_OSS_MIRROR      base URL for the Aliyun OSS mirror, used only when
#                        DOSI_SOURCE=oss. Defaults to the dosi-dist bucket.
#   DOSI_MIRROR          base URL for the Cloudflare mirror, used only when
#                        DOSI_SOURCE=cloudflare. Defaults to the Cloudflare
#                        mirror.
#   DOSI_MANIFEST_URL    fetch the manifest from exactly this URL, overriding
#                        DOSI_SOURCE's manifest resolution (the archive still
#                        follows DOSI_SOURCE)
#   DOSI_SHAPE=lean      install the lean build: the executables alone, with no
#                        libduckdb. Compiles SQL and reaches every warehouse
#                        connector; local DuckDB execution then needs a `duckdb`
#                        CLI on your PATH. Default is the full engine, which
#                        runs DuckDB in process.
#
# An environment variable rather than a flag because `curl … | sh` has no way to
# pass arguments (it would take `sh -s -- --lean`).
#
# POSIX sh on purpose: this runs on whatever /bin/sh a minimal container has.
set -eu

DIST_REPO="${DOSI_DIST_REPO:-Datus-ai/dosi-dist}"
INSTALL_DIR="${DOSI_INSTALL_DIR:-$HOME/.local/bin}"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed"; }
need curl
need tar

# --- pick the target triple ---------------------------------------------------
os=$(uname -s)
arch=$(uname -m)
case "$os" in
  Linux) case "$arch" in
           x86_64|amd64) target=x86_64-unknown-linux-gnu ;;
           aarch64|arm64) target=aarch64-unknown-linux-gnu ;;
           *) die "unsupported Linux architecture: $arch" ;;
         esac ;;
  # Not every release carries every macOS target: Intel is opt-in per dispatch
  # and is often left out. Naming the triple anyway is deliberate — the lookup
  # below then fails with "no build for x86_64-apple-darwin", which says what
  # is missing, rather than claiming Dosi does not run on this OS at all.
  Darwin) case "$arch" in
            arm64) target=aarch64-apple-darwin ;;
            x86_64) target=x86_64-apple-darwin ;;
            *) die "unsupported macOS architecture: $arch" ;;
          esac ;;
  *) die "Dosi ships for Linux and macOS; this is $os" ;;
esac

# The shape is a suffix on the manifest key, so it selects the archive without
# any schema change: "x86_64-unknown-linux-gnu" or "…-lean".
shape="${DOSI_SHAPE:-engine}"
case "$shape" in
  engine) ;;
  lean) target="$target-lean" ;;
  *) die "DOSI_SHAPE must be 'engine' or 'lean', not '$shape'" ;;
esac

# --- pick a source, then resolve the release -----------------------------------
# GitHub Releases downloads from mainland China run at tens of KB/s, and the
# default archive is ~68 MB. Aliyun OSS and the Cloudflare mirror the docs
# already answer on (#129) serve the same files, faster, from mainland China.
#
# DOSI_SOURCE picks exactly one of the three — no automatic fallback between
# them. A source that is down or serving a bad copy fails the install
# outright rather than silently retrying elsewhere: which source gets used
# should never be a guess. Mainland China installs should pass
# DOSI_SOURCE=oss.
#
# Both the manifest and the archive come from whichever source is chosen.
# That means a mirror is no longer purely bandwidth the way a GitHub-only
# manifest would keep it: a corrupted or substituted mirror archive used to
# always fail the checksum GitHub's own manifest supplied. Sourcing both from
# the same mirror means a compromised OSS or Cloudflare mirror could now
# serve a bad archive alongside a matching bad checksum. Ordinary corruption
# (a truncated or bit-flipped transfer) is still caught either way; a mirror
# that is deliberately lying is not.
DOSI_SOURCE="${DOSI_SOURCE:-github}"
case "$DOSI_SOURCE" in
  github) ;;
  oss) mirror_base="${DOSI_OSS_MIRROR:-https://dosi-dist.oss-cn-beijing.aliyuncs.com}" ;;
  cloudflare) mirror_base="${DOSI_MIRROR:-https://dosi.datus.ai/dl}" ;;
  *) die "DOSI_SOURCE must be 'github', 'oss', or 'cloudflare', not '$DOSI_SOURCE'" ;;
esac

if [ -n "${DOSI_MANIFEST_URL:-}" ]; then
  manifest_url="$DOSI_MANIFEST_URL"
elif [ "$DOSI_SOURCE" = github ]; then
  if [ -n "${DOSI_VERSION:-}" ]; then
    manifest_url="https://github.com/$DIST_REPO/releases/download/v$DOSI_VERSION/manifest.json"
  else
    manifest_url="https://github.com/$DIST_REPO/releases/latest/download/manifest.json"
  fi
elif [ -n "${DOSI_VERSION:-}" ]; then
  manifest_url="$mirror_base/v$DOSI_VERSION/manifest.json"
else
  manifest_url="$mirror_base/latest/manifest.json"
fi

info "resolving release for $target ($DOSI_SOURCE)"
manifest=$(curl -fsSL "$manifest_url") \
  || die "cannot fetch $manifest_url — check the version or your network"

# One-line-per-field extraction; avoids depending on jq being installed.
# `[^:]*` and not `.*` before the colon: the value is a URL and a greedy match
# would strip through the `https:` too.
unquote() { sed 's/^[^:]*: *"//; s/" *$//'; }
field() {
  printf '%s' "$manifest" \
    | tr ',{}' '\n\n\n' \
    | grep -A20 "\"$target\"" \
    | grep "\"$1\"" \
    | head -n1 \
    | unquote
}
version=$(printf '%s' "$manifest" | tr ',{}' '\n\n\n' | grep '"version"' | head -n1 | unquote)
file=$(field file)
url=$(field url)
sha=$(field sha256)

[ -n "$file" ] && [ -n "$url" ] && [ -n "$sha" ] \
  || die "release $version has no build for $target"

# --- pick the archive's URL -----------------------------------------------------
# The mirrors store the same v<version>/<file> tail GitHub's download URLs
# end in, so one suffix strip maps the GitHub URL onto either of them.
if [ "$DOSI_SOURCE" = github ]; then
  source_url="$url"
else
  source_url="$mirror_base/${url##*/download/}"
fi

# --- download and verify ------------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

info "downloading dosi $version ($target) from $DOSI_SOURCE"
# --connect-timeout: a source that accepts a connection but never answers
# should fail fast, not hang the install.
curl -fSL --connect-timeout 5 --progress-bar -o "$tmp/$file" "$source_url" \
  || die "download failed: $source_url"

info "verifying checksum"
# sha256sum first: it is the coreutils command and so the one present on a
# normal Linux box. shasum is the perl fallback, for images that ship perl but
# a stripped coreutils.
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$tmp/$file" | cut -d' ' -f1)
elif command -v shasum >/dev/null 2>&1; then
  actual=$(shasum -a 256 "$tmp/$file" | cut -d' ' -f1)
else
  die "neither sha256sum nor shasum found — cannot verify the download"
fi
[ "$actual" = "$sha" ] || die "checksum mismatch: expected $sha, got $actual"

# --- install ------------------------------------------------------------------
tar xzf "$tmp/$file" -C "$tmp"
stage="$tmp/dosi-$version-$target"
mkdir -p "$INSTALL_DIR"
for bin in dosi dosi-server; do
  install -m 0755 "$stage/$bin" "$INSTALL_DIR/$bin" 2>/dev/null \
    || { cp "$stage/$bin" "$INSTALL_DIR/$bin" && chmod 0755 "$INSTALL_DIR/$bin"; }
done

# DuckDB is a shared library, and the binaries find it through a relative
# rpath — $ORIGIN on Linux, @loader_path on macOS — i.e. next to themselves.
# It has to land in $INSTALL_DIR too, or every command fails at startup with
# "libduckdb.so: cannot open shared object file" (Linux) or "Library not
# loaded: @loader_path/libduckdb.dylib" (macOS).
for lib in libduckdb.so libduckdb.dylib; do
  [ -f "$stage/$lib" ] || continue
  install -m 0644 "$stage/$lib" "$INSTALL_DIR/$lib" 2>/dev/null \
    || { cp "$stage/$lib" "$INSTALL_DIR/$lib" && chmod 0644 "$INSTALL_DIR/$lib"; }
done

# The example models come with the archive and the tutorial runs against them,
# so they have to outlive $tmp — otherwise the first command in the docs fails
# with "no such file".
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/dosi"
rm -rf "$DATA_DIR/examples"
mkdir -p "$DATA_DIR"
cp -r "$stage/examples" "$DATA_DIR/examples"
cp "$stage/LICENSE" "$DATA_DIR/LICENSE" 2>/dev/null || true

info "installed dosi $version ($shape) to $INSTALL_DIR"
info "example models in $DATA_DIR/examples"

# The lean build has no DuckDB of its own: local execution shells out. Say so
# at install time rather than letting the first `--execute` fail with
# "cannot start duckdb CLI".
if [ "$shape" = lean ] && ! command -v duckdb >/dev/null 2>&1; then
  printf '\n\033[33mno `duckdb` on your PATH.\033[0m The lean build compiles SQL and reaches\nevery warehouse connector without it, but local DuckDB execution (--execute\nagainst --db) needs one: https://duckdb.org/docs/installation\n'
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*) : ;;
  *) printf '\n\033[33m%s is not on your PATH.\033[0m Add it:\n\n  export PATH="%s:$PATH"\n' \
       "$INSTALL_DIR" "$INSTALL_DIR" ;;
esac

printf '\nTry it:\n\n  export DOSI_EXAMPLES=%s/examples\n  dosi info\n  dosi validate --model $DOSI_EXAMPLES/orders/model.yaml\n\n' "$DATA_DIR"
