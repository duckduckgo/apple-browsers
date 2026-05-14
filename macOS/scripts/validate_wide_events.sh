#!/bin/bash

# validate_wide_events.sh
# Validates wide event logs from the macOS app against definitions.
#
# Usage:
#   ./validate_wide_events.sh [bundle_id]
#
# The default bundle ID is com.duckduckgo.macos.browser.debug (DEBUG builds).
# Pass a different bundle ID for other build variants:
#
#   DeveloperID (unsandboxed when run from Xcode):
#     ./validate_wide_events.sh com.duckduckgo.macos.browser.debug   (default)
#     ./validate_wide_events.sh com.duckduckgo.macos.browser.review
#     ./validate_wide_events.sh com.duckduckgo.macos.browser.alpha
#     ./validate_wide_events.sh com.duckduckgo.macos.browser
#
#   App Store (sandboxed):
#     ./validate_wide_events.sh com.duckduckgo.mobile.ios.debug
#     ./validate_wide_events.sh com.duckduckgo.mobile.ios.review
#     ./validate_wide_events.sh com.duckduckgo.mobile.ios.alpha
#
# The script checks both the sandboxed container path and the unsandboxed
# user-level Caches (used when running from Xcode with sandbox disabled).

set -e

# Get the directory where the script is stored
SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
BASE_DIR="${SCRIPT_DIR}/.."

LOG_FILENAME="wide-event-validation-log.jsonl"
BUNDLE_ID="${1:-com.duckduckgo.macos.browser.debug}"
PIXEL_DEFINITIONS_PATH="${BASE_DIR}/PixelDefinitions"

SANDBOXED_LOG="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Caches/${LOG_FILENAME}"
UNSANDBOXED_LOG="${HOME}/Library/Caches/${LOG_FILENAME}"

if [[ -f "${SANDBOXED_LOG}" ]]; then
    LOG_FILE="${SANDBOXED_LOG}"
elif [[ -f "${UNSANDBOXED_LOG}" ]]; then
    LOG_FILE="${UNSANDBOXED_LOG}"
else
    echo "No wide event logs found for ${BUNDLE_ID}."
    echo ""
    echo "Make sure you:"
    echo "  1. Built and ran a debug build of the macOS app"
    echo "  2. Triggered some wide events during your session"
    exit 0
fi

cd "${BASE_DIR}"
npm run validate-pixel-defs
echo "Validating wide event log..."
npm run validate-wide-event-debug-logs "${PIXEL_DEFINITIONS_PATH}" "${LOG_FILE}"
