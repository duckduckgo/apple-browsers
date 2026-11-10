#!/bin/bash
# Regenerates native-messaging-test-extension.zip from this source directory into the
# WebExtensions package's BundledWebExtensions folder. It's a debug extension, installed
# only from Debug → Web Extensions, to test runtime nativeMessaging requests.
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SRC_DIR/../.." && pwd)"
OUT="$REPO_ROOT/SharedPackages/WebExtensions/Sources/WebExtensions/BundledWebExtensions/native-messaging-test-extension.zip"
rm -f "$OUT"
cd "$SRC_DIR"
zip -q -X "$OUT" manifest.json popup.html popup.css popup.js icons/icon-16.png icons/icon-32.png icons/icon-48.png icons/icon-128.png
echo "Built $OUT"
unzip -l "$OUT"
