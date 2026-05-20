#!/bin/bash
#
# strip_unused_content_scope_pages.sh
#
# Removes macOS-only pages from ContentScopeScripts bundles embedded in the iOS app.
# iOS only uses "duckplayer" and "special-error" — the rest (onboarding, new-tab,
# history, release-notes, errorpage) are macOS web UIs that add ~20 MB of waste.
#
# Usage:
#   As a Run Script build phase (after "Embed Frameworks"):
#     ${SRCROOT}/strip_unused_content_scope_pages.sh
#
#   Standalone (for testing):
#     ./strip_unused_content_scope_pages.sh /path/to/DuckDuckGo.app
#

set -euo pipefail

# Skip during SwiftUI Preview builds. Previews write into the same .app bundle
# this script mutates, which can leave previews in an inconsistent state.
# Stripping is a release-size optimization, not required for correctness.
if [[ "${ENABLE_PREVIEWS:-NO}" == "YES" || "${ENABLE_XOJIT_PREVIEWS:-NO}" == "YES" ]]; then
    echo "Skipping ContentScopeScripts strip for SwiftUI Preview build."
    exit 0
fi

# Pages to remove (macOS-only or unused)
UNUSED_PAGES=("onboarding" "new-tab" "history" "release-notes" "errorpage")

# Resolve the .app path
if [[ -n "${1:-}" ]]; then
    APP_PATH="$1"
elif [[ -n "${TARGET_BUILD_DIR:-}" && -n "${WRAPPER_NAME:-}" ]]; then
    APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
elif [[ -n "${BUILT_PRODUCTS_DIR:-}" && -n "${PRODUCT_NAME:-}" ]]; then
    APP_PATH="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
else
    echo "error: No .app path provided and Xcode build variables not set." >&2
    exit 1
fi

echo "Stripping unused ContentScopeScripts pages from: ${APP_PATH}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: App bundle not found at $APP_PATH" >&2
    exit 1
fi

BUNDLE_NAME="ContentScopeScripts_ContentScopeScripts.bundle"
TOTAL_SAVED=0

while IFS= read -r -d '' bundle_path; do
    pages_dir="${bundle_path}/pages"
    if [[ ! -d "$pages_dir" ]]; then
        continue
    fi

    # Determine context for logging
    rel_path="${bundle_path#"$APP_PATH"/}"

    for page in "${UNUSED_PAGES[@]}"; do
        page_dir="${pages_dir}/${page}"
        if [[ -d "$page_dir" ]]; then
            page_size=$(du -sk "$page_dir" | cut -f1)
            TOTAL_SAVED=$((TOTAL_SAVED + page_size))
            rm -rf "$page_dir"
            echo "  Stripped ${page}/ (${page_size} KB) from ${rel_path}"
        fi
    done
done < <(find "$APP_PATH" -name "$BUNDLE_NAME" -type d -print0)

if [[ $TOTAL_SAVED -gt 0 ]]; then
    echo "Total saved: $((TOTAL_SAVED / 1024)) MB"
else
    echo "Nothing to strip (already clean or bundle not found)."
fi
