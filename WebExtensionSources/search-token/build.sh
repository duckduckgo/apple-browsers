#!/bin/bash
# Regenerates search-token-extension.zip from this source directory into the
# WebExtensions package's BundledWebExtensions folder. Files are placed at the
# zip root to match the other bundled extensions.
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SRC_DIR/../.." && pwd)"
OUT="$REPO_ROOT/SharedPackages/WebExtensions/Sources/WebExtensions/BundledWebExtensions/search-token-extension.zip"
rm -f "$OUT"
cd "$SRC_DIR"
zip -q -X -r "$OUT" manifest.json rules
echo "Built $OUT"
unzip -l "$OUT"
