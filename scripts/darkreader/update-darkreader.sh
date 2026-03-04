#!/usr/bin/env bash
#
# Updates the bundled DarkReader Chrome MV3 extension to a specific version
# (or latest), builds it, and applies DuckDuckGo patches.
#
# Usage:
#   ./update-darkreader.sh              # update to the latest release tag
#   ./update-darkreader.sh v4.9.130     # update to a specific tag
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/SharedPackages/WebExtensions/Sources/WebExtensions/BundledWebExtensions"
WORK_DIR="$(mktemp -d)"
EXT_DIR="$WORK_DIR/darkreader-chrome-mv3"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------
if [[ $# -ge 1 ]]; then
    TAG="$1"
else
    echo "Fetching latest DarkReader release tag..."
    TAG="$(git ls-remote --tags --refs --sort=-v:refname https://github.com/darkreader/darkreader.git 'v*' \
        | head -1 \
        | sed 's|.*refs/tags/||')"
    if [[ -z "$TAG" ]]; then
        echo "Error: could not determine latest release tag." >&2
        exit 1
    fi
fi

VERSION="${TAG#v}"   # strip leading 'v' → e.g. "4.9.130"

echo "==> Updating DarkReader to ${TAG} (version ${VERSION})"

# ---------------------------------------------------------------------------
# Clone & build Chrome MV3 extension
# ---------------------------------------------------------------------------
echo "==> Cloning darkreader@${TAG}..."
git clone --depth 1 --branch "$TAG" https://github.com/darkreader/darkreader.git "$WORK_DIR/darkreader"

echo "==> Installing dependencies..."
(cd "$WORK_DIR/darkreader" && npm install)

echo "==> Building Chrome MV3 extension..."
(cd "$WORK_DIR/darkreader" && npm run build -- --chrome-mv3)

# ---------------------------------------------------------------------------
# Find and extract build output
# ---------------------------------------------------------------------------
BUILD_ZIP="$WORK_DIR/darkreader/build/release/darkreader-chrome-mv3.zip"
if [[ ! -f "$BUILD_ZIP" ]]; then
    echo "Error: Chrome MV3 build did not produce expected zip." >&2
    echo "Looking for build output..."
    find "$WORK_DIR/darkreader/build" -name "*.zip" -o -name "*mv3*" 2>/dev/null || true
    exit 1
fi

echo "==> Built darkreader-chromium-mv3.zip ($(wc -c < "$BUILD_ZIP" | tr -d ' ') bytes)"

# ---------------------------------------------------------------------------
# Extract into extension directory
# ---------------------------------------------------------------------------
rm -rf "$EXT_DIR"
mkdir -p "$EXT_DIR"
unzip -q "$BUILD_ZIP" -d "$EXT_DIR"

echo "==> Extracted Chrome MV3 extension to $EXT_DIR"

# ---------------------------------------------------------------------------
# Apply DuckDuckGo patches (JS patches + manifest updates + repackage)
# ---------------------------------------------------------------------------
echo ""
"$SCRIPT_DIR/patch-darkreader.sh" "$EXT_DIR"

# ---------------------------------------------------------------------------
# Copy final zip to BundledWebExtensions
# ---------------------------------------------------------------------------
ZIP_OUT="$WORK_DIR/darkreader-chrome-mv3.zip"
cp "$ZIP_OUT" "$BUNDLE_DIR/darkreader.zip"
cp "$WORK_DIR/darkreader/LICENSE" "$BUNDLE_DIR/DarkReader-LICENSE.txt"
echo ""
echo "==> Copied to $BUNDLE_DIR/darkreader.zip"
echo "==> Copied to $BUNDLE_DIR/DarkReader-LICENSE.txt"

echo ""
echo "Done! DarkReader updated to ${VERSION}."
