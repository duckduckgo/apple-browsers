#!/usr/bin/env bash
#
# Build WPR tools from the exact revision crossbench pins.
# The source checkout is also required at runtime by crossbench for WPR's
# deterministic.js and test certificate.
#
# Set WPR_SRC and at least one output:
#   WPR_BIN=/path/to/wpr
#   WPR_VALIDATOR_BIN=/path/to/validate-wpr

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=macOS/scripts/crossbench/wpr-config.sh
. "$SCRIPT_DIR/wpr-config.sh"

: "${WPR_SRC:?WPR_SRC must name the WebPageReplay source checkout}"
WPR_BIN="${WPR_BIN:-}"
WPR_VALIDATOR_BIN="${WPR_VALIDATOR_BIN:-}"
if [ -z "$WPR_BIN" ] && [ -z "$WPR_VALIDATOR_BIN" ]; then
  echo "ERROR: set WPR_BIN, WPR_VALIDATOR_BIN, or both." >&2
  exit 2
fi

if ! command -v go >/dev/null 2>&1; then
  echo "ERROR: Go 1.23 or newer is required." >&2
  exit 1
fi

if [ ! -e "$WPR_SRC/.git" ]; then
  # A normal crossbench clone leaves its uninitialized webpagereplay gitlink as
  # an empty directory. Replace only that safe placeholder; never overwrite an
  # unknown non-empty path. `-e` above deliberately accepts both a standalone
  # checkout's .git directory and an initialized submodule's .git file.
  if [ -e "$WPR_SRC" ] && ! rmdir "$WPR_SRC" 2>/dev/null; then
    echo "ERROR: $WPR_SRC exists but is not a git checkout or empty submodule; refusing to replace it." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$WPR_SRC")"
  git clone --quiet "$WEBPAGEREPLAY_GIT" "$WPR_SRC"
fi
if ! git -C "$WPR_SRC" cat-file -e "${WEBPAGEREPLAY_REV}^{commit}" 2>/dev/null; then
  git -C "$WPR_SRC" fetch --quiet origin "$WEBPAGEREPLAY_REV"
fi
git -C "$WPR_SRC" -c advice.detachedHead=false checkout --quiet --detach -f "$WEBPAGEREPLAY_REV"

if [ -n "$WPR_BIN" ]; then
  mkdir -p "$(dirname "$WPR_BIN")"
  go build -C "$WPR_SRC/src" -trimpath -buildvcs=false -o "$WPR_BIN" wpr.go
fi
if [ -n "$WPR_VALIDATOR_BIN" ]; then
  mkdir -p "$(dirname "$WPR_VALIDATOR_BIN")"
  go build -C "$WPR_SRC/src" -trimpath -buildvcs=false \
    -o "$WPR_VALIDATOR_BIN" "$SCRIPT_DIR/validate-wpr.go"
fi

echo "webpagereplay: $(git -C "$WPR_SRC" rev-parse HEAD)"
if [ -n "$WPR_BIN" ]; then
  echo "wpr:           $WPR_BIN"
fi
if [ -n "$WPR_VALIDATOR_BIN" ]; then
  echo "validator:     $WPR_VALIDATOR_BIN"
fi
