#!/bin/bash
#
# patch-darkreader.sh
#
# Patches the upstream Dark Reader Chrome MV3 extension for embedded use
# inside a WKWebExtension (DuckDuckGo iOS/macOS browser).
#
# Usage:
#   1. Download / update the upstream darkreader-chrome-mv3 extension into
#      the "darkreader-chrome-mv3 2" directory (unzipped).
#   2. Run this script from the darkreader/ directory:
#        ./patch-darkreader.sh
#   3. The script patches background/index.js in place and repackages
#      darkreader-chrome-mv3.zip.
#
# What it patches:
#   - automation.enabled  → true  (follow system color scheme)
#   - automation.mode     → AutomationMode.SYSTEM
#   - fetchNews           → false (no network calls to darkreader.org)
#   - syncSettings        → false (no chrome.storage.sync round-trips)
#   - Disables chrome.tabs.create on install (no help page popup)
#   - Disables chrome.runtime.setUninstallURL (no uninstall redirect)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXT_DIR="$SCRIPT_DIR/darkreader-chrome-mv3"
BG_JS="$EXT_DIR/background/index.js"
ZIP_OUT="$SCRIPT_DIR/darkreader-chrome-mv3.zip"

if [ ! -f "$BG_JS" ]; then
    echo "Error: $BG_JS not found. Make sure the extension is extracted." >&2
    exit 1
fi

echo "Patching $BG_JS..."

FAIL=0

# Helper: literal find-and-replace via python3 (handles any characters safely)
replace_literal() {
    local description="$1"
    local find_str="$2"
    local replace_str="$3"

    python3 -c "
import sys

with open(sys.argv[1], 'r') as f:
    content = f.read()

find_str = sys.argv[2]
replace_str = sys.argv[3]

if find_str in content:
    content = content.replace(find_str, replace_str, 1)
    with open(sys.argv[1], 'w') as f:
        f.write(content)
    print('  ✓ ' + sys.argv[4])
elif replace_str in content:
    print('  – ' + sys.argv[4] + ' (already applied)')
else:
    print('  ✗ ' + sys.argv[4] + ' (pattern not found — upstream may have changed)', file=sys.stderr)
    sys.exit(1)
" "$BG_JS" "$find_str" "$replace_str" "$description" || FAIL=1
}

# 1. automation: follow system color scheme by default
replace_literal "automation.mode → SYSTEM" \
    'enabled: isEdge && isMobile ? true : false,
            mode:
                isEdge && isMobile
                    ? AutomationMode.SYSTEM
                    : AutomationMode.NONE,' \
    'enabled: true,
            mode: AutomationMode.SYSTEM,'

# 2. fetchNews → false
replace_literal "fetchNews → false" \
    "fetchNews: true," \
    "fetchNews: false,"

# 3. syncSettings → false
replace_literal "syncSettings → false" \
    "syncSettings: true," \
    "syncSettings: false,"

# 4. Disable help page tab on install and uninstall URL
replace_literal "Disable onInstalled tab + setUninstallURL" \
    'chrome.runtime.onInstalled.addListener(({reason}) => {
            if (reason === "install") {
                chrome.tabs.create({url: getHelpURL()});
            }
        });
        chrome.runtime.setUninstallURL(UNINSTALL_URL);' \
    '// DuckDuckGo: Disabled help page and uninstall URL for embedded use.
        // chrome.runtime.onInstalled.addListener(({reason}) => {
        //     if (reason === "install") {
        //         chrome.tabs.create({url: getHelpURL()});
        //     }
        // });
        // chrome.runtime.setUninstallURL(UNINSTALL_URL);'

if [ "$FAIL" -ne 0 ]; then
    echo ""
    echo "Warning: Some patches could not be applied. Review the output above." >&2
    exit 1
fi

# Repackage the zip
echo ""
echo "Repackaging $ZIP_OUT..."
rm -f "$ZIP_OUT"
(cd "$EXT_DIR" && zip -r "$ZIP_OUT" . -x ".*" -x "__MACOSX/*") > /dev/null

echo "Done. Patched extension packaged at: $ZIP_OUT"
