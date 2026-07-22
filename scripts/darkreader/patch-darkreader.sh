#!/bin/bash
#
# patch-darkreader.sh
#
# Patches the upstream Dark Reader Chrome MV3 extension for embedded use
# inside a WKWebExtension (DuckDuckGo iOS/macOS browser).
#
# Usage:
#   ./patch-darkreader.sh <path-to-extracted-extension>
#
# Typically called by update-darkreader.sh after building from source,
# but can also be run standalone after manually extracting an extension.
#
# What it patches:
#   - automation.enabled  → true  (follow system color scheme)
#   - automation.mode     → AutomationMode.SYSTEM
#   - fetchNews           → false (no network calls to darkreader.org)
#   - syncSettings        → false (no chrome.storage.sync round-trips)
#   - Disables chrome.tabs.create on install (no help page popup)
#   - Disables chrome.runtime.setUninstallURL (no uninstall redirect)
#   - Bounds native exclusion checks so Dark Reader's fallback cannot remain stuck
#   - Uses a Safari background page and retries document connections after an idle wake-up
#   - Uses a restrained Wikipedia fallback while the background process wakes
#   - Detects Wikipedia's automatic/system dark theme
#   - Adds a DuckDuckGo patch component to the manifest version
#   - Adds browser_specific_settings for DuckDuckGo extension ID

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path-to-extracted-extension>" >&2
    exit 1
fi

EXT_DIR="$1"
BG_JS="$EXT_DIR/background/index.js"
INJECT_JS="$EXT_DIR/inject/index.js"
FALLBACK_JS="$EXT_DIR/inject/fallback.js"
DETECTOR_HINTS="$EXT_DIR/config/detector-hints.config"
MANIFEST="$EXT_DIR/manifest.json"
ZIP_OUT="$(dirname "$EXT_DIR")/darkreader-chrome-mv3.zip"

if [ ! -f "$BG_JS" ]; then
    echo "Error: $BG_JS not found. Make sure the extension is extracted." >&2
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "Error: $MANIFEST not found." >&2
    exit 1
fi

if [ ! -f "$FALLBACK_JS" ]; then
    echo "Error: $FALLBACK_JS not found." >&2
    exit 1
fi

if [ ! -f "$INJECT_JS" ]; then
    echo "Error: $INJECT_JS not found." >&2
    exit 1
fi

if [ ! -f "$DETECTOR_HINTS" ]; then
    echo "Error: $DETECTOR_HINTS not found." >&2
    exit 1
fi

# ===========================================================================
# Patch background/index.js
# ===========================================================================
echo "Patching $BG_JS..."

FAIL=0

# Helper: literal find-and-replace via python3 (handles any characters safely)
replace_literal() {
    local target_file="$1"
    local description="$2"
    local find_str="$3"
    local replace_str="$4"
    local alternative_find_str="${5:-}"

    python3 -c "
import sys

with open(sys.argv[1], 'r') as f:
    content = f.read()

find_str = sys.argv[2]
replace_str = sys.argv[3]

if replace_str in content:
    print('  – ' + sys.argv[4] + ' (already applied)')
elif find_str in content:
    content = content.replace(find_str, replace_str, 1)
    with open(sys.argv[1], 'w') as f:
        f.write(content)
    print('  ✓ ' + sys.argv[4])
elif sys.argv[5] and sys.argv[5] in content:
    content = content.replace(sys.argv[5], replace_str, 1)
    with open(sys.argv[1], 'w') as f:
        f.write(content)
    print('  ✓ ' + sys.argv[4] + ' (updated legacy patch)')
else:
    print('  ✗ ' + sys.argv[4] + ' (pattern not found — upstream may have changed)', file=sys.stderr)
    sys.exit(1)
" "$target_file" "$find_str" "$replace_str" "$description" "$alternative_find_str" || FAIL=1
}

# 1. automation: follow system color scheme by default
replace_literal "$BG_JS" "automation.mode → SYSTEM" \
    'enabled: isEdge && isMobile ? true : false,
            mode:
                isEdge && isMobile
                    ? AutomationMode.SYSTEM
                    : AutomationMode.NONE,' \
    'enabled: true,
            mode: AutomationMode.SYSTEM,'

# 2. fetchNews → false
replace_literal "$BG_JS" "fetchNews → false" \
    "fetchNews: true," \
    "fetchNews: false,"

# 3. syncSettings → false
replace_literal "$BG_JS" "syncSettings → false" \
    "syncSettings: true," \
    "syncSettings: false,"

# 4. Disable help page tab on install and uninstall URL
replace_literal "$BG_JS" "Disable onInstalled tab + setUninstallURL" \
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

# 5. Hook getConnectionMessage to check excluded domains via native messaging.
# WKWebExtension can occasionally leave sendNativeMessage unresolved. Bound the wait so
# Dark Reader can replace its deliberately coarse fallback stylesheet with the real theme.
replace_literal "$BG_JS" "Hook getConnectionMessage for bounded domain exclusion" \
    'static async getConnectionMessage(
            tabURL,
            url,
            isTopFrame,
            topFrameHasDarkTheme
        ) {
            await Extension.loadData();
            return Extension.getTabMessage(
                tabURL,
                url,
                isTopFrame,
                topFrameHasDarkTheme
            );
        }' \
    'static async getConnectionMessage(
            tabURL,
            url,
            isTopFrame,
            topFrameHasDarkTheme
        ) {
            await Extension.loadData();
            try {
                const response = await Promise.race([
                    chrome.runtime.sendNativeMessage(
                        "org.duckduckgo.web-extension.darkreader",
                        {featureName: "darkReader", method: "isDomainExcluded", params: {url: tabURL}}
                    ),
                    new Promise((resolve) => setTimeout(() => resolve(null), 500))
                ]);
                if (response && response.result && response.result.isExcluded) {
                    return {type: MessageTypeBGtoCS.CLEAN_UP};
                }
            } catch (e) {}
            return Extension.getTabMessage(
                tabURL,
                url,
                isTopFrame,
                topFrameHasDarkTheme
            );
        }' \
    'static async getConnectionMessage(
            tabURL,
            url,
            isTopFrame,
            topFrameHasDarkTheme
        ) {
            await Extension.loadData();
            try {
                const response = await chrome.runtime.sendNativeMessage(
                    "org.duckduckgo.web-extension.darkreader",
                    {featureName: "darkReader", method: "isDomainExcluded", params: {url: tabURL}}
                );
                if (response && response.result && response.result.isExcluded) {
                    return {type: MessageTypeBGtoCS.CLEAN_UP};
                }
            } catch (e) {}
            return Extension.getTabMessage(
                tabURL,
                url,
                isTopFrame,
                topFrameHasDarkTheme
            );
        }'

# ===========================================================================
# Patch inject/index.js
# ===========================================================================
echo ""
echo "Patching $INJECT_JS..."

# WebKit can reject or strand the first document-connect message while waking an idle
# extension background process. Keep this content script alive and retry until the
# background sends the theme (or clean-up) response for this script instance.
replace_literal "$INJECT_JS" "Allow document connection errors to be retried" \
    '    function sendMessage(message) {' \
    '    function sendMessage(message, errorHandler = cleanup) {'

replace_literal "$INJECT_JS" "Route document connection errors to the retry handler" \
    '                promise.then(responseHandler).catch(cleanup);' \
    '                promise.then(responseHandler).catch(errorHandler);'

replace_literal "$INJECT_JS" "Track document connection retries" \
    '    let unloaded = false;
    const scriptId = generateUID();' \
    '    let unloaded = false;
    let connectionRetryTimer = null;
    let connectionResponseReceived = false;
    const scriptId = generateUID();'

replace_literal "$INJECT_JS" "Cancel document connection retries during cleanup" \
    '    function cleanup() {
        unloaded = true;
        removeEventListener("pagehide", onPageHide);' \
    '    function cleanup() {
        unloaded = true;
        clearTimeout(connectionRetryTimer);
        removeEventListener("pagehide", onPageHide);'

replace_literal "$INJECT_JS" "Stop retries when the background responds" \
    '            return;
        }
        logInfoCollapsed(`onMessage[${message.type}]`, message);' \
    '            return;
        }
        connectionResponseReceived = true;
        clearTimeout(connectionRetryTimer);
        logInfoCollapsed(`onMessage[${message.type}]`, message);'

replace_literal "$INJECT_JS" "Retry a cold document connection" \
    '    function sendConnectionOrResumeMessage(type) {
        sendMessage({
            type,
            scriptId,
            data: {
                isDark: isSystemDarkModeEnabled(),
                isTopFrame: window === window.top
            }
        });
    }' \
    '    const maxConnectionAttempts = 4;
    const connectionRetryDelay = 500;
    function sendConnectionOrResumeMessage(type, attempt = 1) {
        if (attempt === 1) {
            connectionResponseReceived = false;
            clearTimeout(connectionRetryTimer);
        }
        sendMessage(
            {
                type,
                scriptId,
                data: {
                    isDark: isSystemDarkModeEnabled(),
                    isTopFrame: window === window.top
                }
            },
            () => {}
        );
        if (attempt < maxConnectionAttempts) {
            connectionRetryTimer = setTimeout(() => {
                if (!connectionResponseReceived && !unloaded) {
                    sendConnectionOrResumeMessage(type, attempt + 1);
                }
            }, connectionRetryDelay);
        }
    }'

# ===========================================================================
# Patch inject/fallback.js
# ===========================================================================
echo ""
echo "Patching $FALLBACK_JS..."

# The fallback runs before the background page is ready. Use Wikipedia's native-theme
# classes and a restrained site-specific palette instead of styling every descendant.
replace_literal "$FALLBACK_JS" "Define Wikipedia fallback context" \
    '        return null;
    }

    if (' \
    '        return null;
    }

    const isWikipedia =
        location.hostname === "wikipedia.org" ||
        location.hostname.endsWith(".wikipedia.org");

    if ('

replace_literal "$FALLBACK_JS" "Allow restrained fallback on Wikipedia" \
    '        matchMedia("(prefers-color-scheme: dark)").matches &&
        wasEnabledForHost() !== false &&
        !document.querySelector(".darkreader--fallback") &&' \
    '        matchMedia("(prefers-color-scheme: dark)").matches &&
        wasEnabledForHost() !== false &&
        !document.documentElement.matches(
            ".skin-theme-clientpref-night, .skin-theme-clientpref-os"
        ) &&
        !document.querySelector(".darkreader--fallback") &&' \
    '        matchMedia("(prefers-color-scheme: dark)").matches &&
        wasEnabledForHost() !== false &&
        !(
            location.hostname === "wikipedia.org" ||
            location.hostname.endsWith(".wikipedia.org")
        ) &&
        !document.documentElement.matches(
            ".skin-theme-clientpref-night, .skin-theme-clientpref-os"
        ) &&
        !document.querySelector(".darkreader--fallback") &&'

replace_literal "$FALLBACK_JS" "Use restrained Wikipedia fallback CSS" \
    '        const css = [
            "html, body, body :not(iframe) {",
            "    background-color: #181a1b !important;",
            "    border-color: #776e62 !important;",
            "    color: #e8e6e3 !important;",
            "}",
            "html, body {",
            "    opacity: 1 !important;",
            "    transition: none !important;",
            "}",
            '\''div[style*="background-color: rgb(135, 135, 135)"] {'\'',
            "    background-color: #878787 !important;",
            "}"
        ].join("\n");' \
    '        const css = (isWikipedia
            ? [
                  ":root {",
                  "    color-scheme: dark !important;",
                  "    --background-color-base: #101418 !important;",
                  "    --background-color-neutral-subtle: #202122 !important;",
                  "    --background-color-interactive-subtle: #27292d !important;",
                  "    --color-base: #eaecf0 !important;",
                  "    --color-emphasized: #ffffff !important;",
                  "    --color-subtle: #a2a9b1 !important;",
                  "    --color-progressive: #6b9eff !important;",
                  "}",
                  "html, body, #content, .mw-page-container, .mw-body, .mw-body-content,",
                  ".vector-header-container, .vector-sticky-header, .minerva-header, .header-container {",
                  "    background-color: #101418 !important;",
                  "    color: #eaecf0 !important;",
                  "}",
                  "a { color: #6b9eff !important; }",
                  "html, body {",
                  "    opacity: 1 !important;",
                  "    transition: none !important;",
                  "}"
              ]
            : [
                  "html, body, body :not(iframe) {",
                  "    background-color: #181a1b !important;",
                  "    border-color: #776e62 !important;",
                  "    color: #e8e6e3 !important;",
                  "}",
                  "html, body {",
                  "    opacity: 1 !important;",
                  "    transition: none !important;",
                  "}",
                  '\''div[style*="background-color: rgb(135, 135, 135)"] {'\'',
                  "    background-color: #878787 !important;",
                  "}"
              ]
        ).join("\n");'

replace_literal "$FALLBACK_JS" "Remove fallback when Wikipedia native dark theme initializes" \
    '        fallback.media = "screen";
        fallback.textContent = css;
        if (document.head) {' \
    '        fallback.media = "screen";
        fallback.textContent = css;
        if (isWikipedia) {
            const wikipediaThemeObserver = new MutationObserver(() => {
                if (
                    document.documentElement.matches(
                        ".skin-theme-clientpref-night, .skin-theme-clientpref-os"
                    )
                ) {
                    fallback.remove();
                    wikipediaThemeObserver.disconnect();
                }
            });
            wikipediaThemeObserver.observe(document.documentElement, {
                attributes: true,
                attributeFilter: ["class"]
            });
        }
        if (document.head) {' \
    '        fallback.media = "screen";
        fallback.textContent = css;
        if (
            location.hostname === "wikipedia.org" ||
            location.hostname.endsWith(".wikipedia.org")
        ) {
            const wikipediaThemeObserver = new MutationObserver(() => {
                if (
                    document.documentElement.matches(
                        ".skin-theme-clientpref-night, .skin-theme-clientpref-os"
                    )
                ) {
                    fallback.remove();
                    wikipediaThemeObserver.disconnect();
                }
            });
            wikipediaThemeObserver.observe(document.documentElement, {
                attributes: true,
                attributeFilter: ["class"]
            });
        }
        if (document.head) {'

# ===========================================================================
# Patch config/detector-hints.config
# ===========================================================================
echo ""
echo "Patching $DETECTOR_HINTS..."

# Dark Reader only applies themes when its system-theme automation is active,
# so Wikipedia's automatic preference is dark whenever this hint is evaluated.
replace_literal "$DETECTOR_HINTS" "Detect Wikipedia automatic dark theme" \
    '*.mediawiki.org
*.wikibooks.org
*.wikidata.org
*.wikifunctions.org
*.wikimedia.org
*.wikipedia.org
*.wikiquote.org
*.wikisource.org
wikisource.org
*.wiktionary.org
*.wikiversity.org
*.wikivoyage.org

TARGET
html

MATCH
.skin-theme-clientpref-night' \
    '*.mediawiki.org
*.wikibooks.org
*.wikidata.org
*.wikifunctions.org
*.wikimedia.org
*.wikipedia.org
*.wikiquote.org
*.wikisource.org
wikisource.org
*.wiktionary.org
*.wikiversity.org
*.wikivoyage.org

TARGET
html

MATCH
.skin-theme-clientpref-night
.skin-theme-clientpref-os'

if [ "$FAIL" -ne 0 ]; then
    echo ""
    echo "Warning: Some patches could not be applied. Review the output above." >&2
    exit 1
fi

# ===========================================================================
# Patch manifest.json
# ===========================================================================
echo ""
echo "Patching $MANIFEST..."

python3 -c "
import json, sys

path = sys.argv[1]

with open(path) as f:
    manifest = json.load(f)

background = manifest.get('background')
service_worker_background = {'service_worker': 'background/index.js'}
nonpersistent_background = {'scripts': ['background/index.js'], 'persistent': False}
legacy_persistent_background = {'scripts': ['background/index.js'], 'persistent': True}
if background == service_worker_background:
    manifest['background'] = nonpersistent_background
    print('  ✓ background → nonpersistent page')
elif background == legacy_persistent_background:
    manifest['background'] = nonpersistent_background
    print('  ✓ background → nonpersistent page (updated legacy patch)')
elif background == nonpersistent_background:
    print('  – background → nonpersistent page (already applied)')
else:
    print('  ✗ background patch (unexpected manifest background: ' + str(background) + ')', file=sys.stderr)
    sys.exit(1)

version = manifest.get('version')
version_parts = version.split('.') if isinstance(version, str) else []
if len(version_parts) == 3 and all(part.isdigit() for part in version_parts):
    manifest['version'] = version + '.1'
    print('  ✓ version → ' + manifest['version'])
elif len(version_parts) == 4 and version_parts[-1] in ('2', '3', '4', '5', '6', '7', '8') and all(part.isdigit() for part in version_parts):
    version_parts[-1] = '1'
    manifest['version'] = '.'.join(version_parts)
    print('  ✓ version → ' + manifest['version'] + ' (updated legacy patch)')
elif len(version_parts) == 4 and version_parts[-1] == '1' and all(part.isdigit() for part in version_parts):
    print('  – version → ' + version + ' (already applied)')
else:
    print('  ✗ version patch (unexpected manifest version: ' + str(version) + ')', file=sys.stderr)
    sys.exit(1)

manifest['browser_specific_settings'] = {
    'duckduckgo': {
        'id': 'org.duckduckgo.web-extension.darkreader'
    }
}
print('  ✓ browser_specific_settings → duckduckgo')

perms = manifest.get('permissions', [])
if 'nativeMessaging' not in perms:
    perms.append('nativeMessaging')
    manifest['permissions'] = perms
    print('  ✓ Added nativeMessaging permission')
else:
    print('  – nativeMessaging permission (already present)')

with open(path, 'w') as f:
    json.dump(manifest, f, indent=4)
    f.write('\n')
" "$MANIFEST"

# ===========================================================================
# Repackage the zip
# ===========================================================================
echo ""
echo "Repackaging $ZIP_OUT..."
rm -f "$ZIP_OUT"
(cd "$EXT_DIR" && zip -r "$ZIP_OUT" . -x ".*" -x "__MACOSX/*") > /dev/null

echo "Done. Patched extension packaged at: $ZIP_OUT"
