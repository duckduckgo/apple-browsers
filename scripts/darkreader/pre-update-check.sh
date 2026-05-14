#!/usr/bin/env bash
#
# pre-update-check.sh
#
# Runs pre-update validation checks for the DarkReader extension.
# Compares the current bundled version against a target version to surface
# potential issues before running update-darkreader.sh.
#
# Usage:
#   ./pre-update-check.sh              # check against the latest release tag
#   ./pre-update-check.sh v4.9.130     # check against a specific tag
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/SharedPackages/WebExtensions/Sources/WebExtensions/BundledWebExtensions"
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
    TAG="$(git ls-remote --tags --refs --sort=-v:refname https://github.com/darkreader/darkreader.git 'v*' \
        | head -1 \
        | sed 's|.*refs/tags/||')"
    if [[ -z "$TAG" ]]; then
        echo "Error: could not determine latest release tag." >&2
        exit 1
    fi
fi

VERSION="${TAG#v}"

# ---------------------------------------------------------------------------
# Extract current bundle
# ---------------------------------------------------------------------------
CURRENT_DIR="$WORK_DIR/current"
mkdir -p "$CURRENT_DIR"

if [[ -f "$BUNDLE_DIR/darkreader.zip" ]]; then
    unzip -q "$BUNDLE_DIR/darkreader.zip" -d "$CURRENT_DIR"
else
    echo "Error: current darkreader.zip not found at $BUNDLE_DIR" >&2
    exit 1
fi

# Find manifest in extracted bundle (may be in a subdirectory)
CURRENT_MANIFEST="$(find "$CURRENT_DIR" -maxdepth 2 -name manifest.json | head -1)"

if [[ -z "$CURRENT_MANIFEST" ]]; then
    echo "Error: manifest.json not found in current bundle" >&2
    exit 1
fi

CURRENT_VERSION="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('version','unknown'))" "$CURRENT_MANIFEST")"
echo "==> Pre-update check: ${CURRENT_VERSION} -> ${TAG} (${VERSION})"
echo ""

PASS=0
WARN=0
FAIL=0

pass() { echo "  PASS: $1"; ((PASS++)) || true; }
warn() { echo "  WARN: $1"; ((WARN++)) || true; }
fail() { echo "  FAIL: $1"; ((FAIL++)) || true; }

# ---------------------------------------------------------------------------
# Clone and build new version
# ---------------------------------------------------------------------------
echo "==> Cloning darkreader@${TAG}..."
git clone --depth 1 --branch "$TAG" https://github.com/darkreader/darkreader.git "$WORK_DIR/darkreader"

echo "==> Installing dependencies..."
(cd "$WORK_DIR/darkreader" && npm install --silent)

echo "==> Building Chrome MV3 extension..."
(cd "$WORK_DIR/darkreader" && npm run build -- --chrome-mv3)

BUILD_ZIP="$WORK_DIR/darkreader/build/release/darkreader-chrome-mv3.zip"
if [[ ! -f "$BUILD_ZIP" ]]; then
    echo "Error: Chrome MV3 build did not produce expected zip." >&2
    exit 1
fi

NEW_DIR="$WORK_DIR/new"
mkdir -p "$NEW_DIR"
unzip -q "$BUILD_ZIP" -d "$NEW_DIR"

NEW_MANIFEST="$(find "$NEW_DIR" -maxdepth 2 -name manifest.json | head -1)"
NEW_BG_JS="$(find "$NEW_DIR" -maxdepth 3 -path "*/background/index.js" | head -1)"

echo ""

# ---------------------------------------------------------------------------
# 1. License check
# ---------------------------------------------------------------------------
echo "--- License ---"

NEW_LICENSE="$WORK_DIR/darkreader/LICENSE"
CURRENT_LICENSE="$BUNDLE_DIR/DarkReader-LICENSE.txt"

if [[ ! -f "$NEW_LICENSE" ]]; then
    fail "LICENSE file not found in upstream repo"
elif [[ ! -f "$CURRENT_LICENSE" ]]; then
    fail "Current bundled license file not found: $CURRENT_LICENSE"
elif ! diff -q "$CURRENT_LICENSE" "$NEW_LICENSE" > /dev/null 2>&1; then
    fail "License has changed — review diff below and escalate for review"
    echo ""
    diff -u "$CURRENT_LICENSE" "$NEW_LICENSE" || true
else
    pass "License unchanged"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. Manifest permissions check
# ---------------------------------------------------------------------------
echo "--- Manifest Permissions ---"

# Compare upstream-to-upstream (strip permissions added by our patches)
PATCHED_PERMS="nativeMessaging"

if [[ -n "$CURRENT_MANIFEST" && -n "$NEW_MANIFEST" ]]; then
    CURRENT_PERMS="$(python3 -c "
import json,sys
patched = set(sys.argv[2].split(','))
perms = [p for p in json.load(open(sys.argv[1])).get('permissions',[]) if p not in patched]
print('\n'.join(sorted(perms)))
" "$CURRENT_MANIFEST" "$PATCHED_PERMS")"
    NEW_PERMS="$(python3 -c "import json,sys; print('\n'.join(sorted(json.load(open(sys.argv[1])).get('permissions',[]))))" "$NEW_MANIFEST")"

    ADDED="$(comm -13 <(echo "$CURRENT_PERMS") <(echo "$NEW_PERMS"))"
    REMOVED="$(comm -23 <(echo "$CURRENT_PERMS") <(echo "$NEW_PERMS"))"

    if [[ -n "$ADDED" ]]; then
        warn "New permissions added upstream: $ADDED"
    fi
    if [[ -n "$REMOVED" ]]; then
        warn "Permissions removed upstream: $REMOVED"
    fi
    if [[ -z "$ADDED" && -z "$REMOVED" ]]; then
        pass "Permissions unchanged"
    fi
else
    fail "Could not compare manifests"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Patch compatibility check
# ---------------------------------------------------------------------------
echo "--- Patch Compatibility ---"

if [[ -z "$NEW_BG_JS" ]]; then
    fail "background/index.js not found in new version"
else
    check_pattern() {
        local name="$1"
        local pattern="$2"
        if grep -qF "$pattern" "$NEW_BG_JS"; then
            pass "$name"
        else
            fail "$name — pattern not found in background/index.js"
        fi
    }

    check_pattern "automation.mode patch target" \
        'isEdge && isMobile ? true : false'

    check_pattern "fetchNews patch target" \
        'fetchNews: true,'

    check_pattern "syncSettings patch target" \
        'syncSettings: true,'

    check_pattern "onInstalled + setUninstallURL patch target" \
        'chrome.tabs.create({url: getHelpURL()});'

    check_pattern "getConnectionMessage patch target" \
        'static async getConnectionMessage('
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Manifest structure check
# ---------------------------------------------------------------------------
echo "--- Manifest Structure ---"

if [[ -n "$NEW_MANIFEST" ]]; then
    if python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert 'background' in m" "$NEW_MANIFEST" 2>/dev/null; then
        pass "Manifest has background entry"
    else
        fail "Manifest missing background entry"
    fi

    if python3 -c "import json,sys; m=json.load(open(sys.argv[1])); assert m.get('manifest_version') == 3" "$NEW_MANIFEST" 2>/dev/null; then
        pass "Manifest version is 3"
    else
        fail "Manifest version is not 3"
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Site fix changes
# ---------------------------------------------------------------------------
echo "--- Site Fix Changes ---"

# Extract site names from config files (sections separated by ===... lines)
extract_sites() {
    local config_dir="$1"
    for config in dynamic-theme-fixes.config static-themes.config inversion-fixes.config; do
        local file="$config_dir/$config"
        [[ -f "$file" ]] || continue
        python3 -c "
import sys
with open(sys.argv[1]) as f:
    content = f.read()
import re
sections = re.split(r'={10,}', content)
for section in sections:
    lines = section.strip().split('\n')
    if lines and lines[0].strip():
        first = lines[0].strip()
        if '.' in first or '*' in first:
            print(first)
" "$file"
    done | sort -u
}

CURRENT_CONFIG_DIR="$(find "$CURRENT_DIR" -maxdepth 3 -type d -name config | head -1)"
NEW_CONFIG_DIR="$(find "$NEW_DIR" -maxdepth 3 -type d -name config | head -1)"

if [[ -n "$CURRENT_CONFIG_DIR" && -n "$NEW_CONFIG_DIR" ]]; then
    CURRENT_SITES="$(extract_sites "$CURRENT_CONFIG_DIR")"
    NEW_SITES="$(extract_sites "$NEW_CONFIG_DIR")"

    SITES_ADDED="$(comm -13 <(echo "$CURRENT_SITES") <(echo "$NEW_SITES"))"
    SITES_REMOVED="$(comm -23 <(echo "$CURRENT_SITES") <(echo "$NEW_SITES"))"

    ADDED_COUNT=0
    REMOVED_COUNT=0
    [[ -n "$SITES_ADDED" ]] && ADDED_COUNT="$(echo "$SITES_ADDED" | wc -l | tr -d ' ')"
    [[ -n "$SITES_REMOVED" ]] && REMOVED_COUNT="$(echo "$SITES_REMOVED" | wc -l | tr -d ' ')"

    if [[ "$ADDED_COUNT" -gt 0 || "$REMOVED_COUNT" -gt 0 ]]; then
        echo "  Sites with new/updated fixes (+$ADDED_COUNT, -$REMOVED_COUNT):"
        if [[ -n "$SITES_ADDED" ]]; then
            echo "$SITES_ADDED" | sed 's/^/    + /'
        fi
        if [[ -n "$SITES_REMOVED" ]]; then
            echo "$SITES_REMOVED" | sed 's/^/    - /'
        fi
    else
        echo "  No site fix changes"
    fi

    # Also diff dark-sites.config (sites already dark, no fixes needed)
    CURRENT_DARK="$(find "$CURRENT_CONFIG_DIR" -name dark-sites.config | head -1)"
    NEW_DARK="$(find "$NEW_CONFIG_DIR" -name dark-sites.config | head -1)"
    if [[ -f "$CURRENT_DARK" && -f "$NEW_DARK" ]]; then
        DARK_ADDED="$(comm -13 <(sort "$CURRENT_DARK") <(sort "$NEW_DARK"))"
        DARK_REMOVED="$(comm -23 <(sort "$CURRENT_DARK") <(sort "$NEW_DARK"))"
        DA_COUNT=0
        DR_COUNT=0
        [[ -n "$DARK_ADDED" ]] && DA_COUNT="$(echo "$DARK_ADDED" | wc -l | tr -d ' ')"
        [[ -n "$DARK_REMOVED" ]] && DR_COUNT="$(echo "$DARK_REMOVED" | wc -l | tr -d ' ')"

        if [[ "$DA_COUNT" -gt 0 || "$DR_COUNT" -gt 0 ]]; then
            echo ""
            echo "  Dark sites list changes (+$DA_COUNT, -$DR_COUNT):"
            if [[ -n "$DARK_ADDED" ]]; then
                echo "$DARK_ADDED" | sed 's/^/    + /'
            fi
            if [[ -n "$DARK_REMOVED" ]]; then
                echo "$DARK_REMOVED" | sed 's/^/    - /'
            fi
        fi
    fi
else
    echo "  Could not compare config directories"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "==========================================="
echo "  PASS: $PASS  |  WARN: $WARN  |  FAIL: $FAIL"
echo "==========================================="

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Some checks failed. Review the output above before running update-darkreader.sh."
    echo "Patch failures mean patch-darkreader.sh patterns need updating for this version."
    exit 1
fi

if [[ $WARN -gt 0 ]]; then
    echo ""
    echo "Warnings found. Review before proceeding with the update."
    exit 0
fi

echo ""
echo "All checks passed. Safe to proceed with: ./update-darkreader.sh ${TAG}"
