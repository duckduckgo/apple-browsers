#!/usr/bin/env bash
#
# Updates the bundled DarkReader API library to a specific version (or latest).
#
# Usage:
#   ./update-darkreader.sh              # update to the latest release tag
#   ./update-darkreader.sh v4.9.130     # update to a specific tag
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DARKREADER_DIR="$SCRIPT_DIR/darkreader"
WORK_DIR="$(mktemp -d)"

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
    TAG="$(git ls-remote --tags --sort=-v:refname https://github.com/darkreader/darkreader.git 'v*' \
        | head -1 \
        | sed 's|.*refs/tags/||')"
    if [[ -z "$TAG" ]]; then
        echo "Error: could not determine latest release tag." >&2
        exit 1
    fi
fi

VERSION="${TAG#v}"   # strip leading 'v' → e.g. "4.9.121"

echo "==> Updating DarkReader to ${TAG} (version ${VERSION})"

# ---------------------------------------------------------------------------
# Clone & build
# ---------------------------------------------------------------------------
echo "==> Cloning darkreader@${TAG}..."
git clone --depth 1 --branch "$TAG" https://github.com/darkreader/darkreader.git "$WORK_DIR/darkreader"

echo "==> Installing dependencies..."
(cd "$WORK_DIR/darkreader" && npm install --ignore-scripts)

echo "==> Building API library..."
(cd "$WORK_DIR/darkreader" && npm run api)

# ---------------------------------------------------------------------------
# Verify build output
# ---------------------------------------------------------------------------
API_JS="$WORK_DIR/darkreader/darkreader.js"
if [[ ! -f "$API_JS" ]]; then
    echo "Error: API build did not produce darkreader.js" >&2
    exit 1
fi

echo "==> Built darkreader.js ($(wc -c < "$API_JS" | tr -d ' ') bytes)"

# ---------------------------------------------------------------------------
# Copy into the extension
# ---------------------------------------------------------------------------
cp "$API_JS" "$DARKREADER_DIR/darkreader-api.js"

# ---------------------------------------------------------------------------
# Update version in manifest.json
# ---------------------------------------------------------------------------
# Use a simple Python one-liner to update the version in the JSON reliably.
python3 -c "
import json, sys
path = sys.argv[1]
version = sys.argv[2]
with open(path) as f:
    manifest = json.load(f)
manifest['version'] = version
with open(path, 'w') as f:
    json.dump(manifest, f, indent=4)
    f.write('\n')
" "$DARKREADER_DIR/manifest.json" "$VERSION"

echo "==> Updated manifest.json version to ${VERSION}"
echo ""
echo "Done! DarkReader updated to ${VERSION}."
echo "Files changed:"
echo "  $DARKREADER_DIR/darkreader-api.js"
echo "  $DARKREADER_DIR/manifest.json"
