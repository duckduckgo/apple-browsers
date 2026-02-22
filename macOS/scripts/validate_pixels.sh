#!/bin/bash

# validate_pixels.sh
# Validates pixel logs from the macOS app against pixel definitions.
#
# Usage:
#   ./validate_pixels.sh [bundle_id]
#
# The default bundle ID is com.duckduckgo.macos.browser.debug (DEBUG builds).
# Pass a different bundle ID for other build variants:
#
#   DeveloperID (unsandboxed when run from Xcode):
#     ./validate_pixels.sh com.duckduckgo.macos.browser.debug   (default)
#     ./validate_pixels.sh com.duckduckgo.macos.browser.review
#     ./validate_pixels.sh com.duckduckgo.macos.browser.alpha
#     ./validate_pixels.sh com.duckduckgo.macos.browser
#
#   App Store (sandboxed):
#     ./validate_pixels.sh com.duckduckgo.mobile.ios.debug
#     ./validate_pixels.sh com.duckduckgo.mobile.ios.review
#     ./validate_pixels.sh com.duckduckgo.mobile.ios.alpha

set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
BASE_DIR="${SCRIPT_DIR}/.."

LOG_FILENAME="pixelkit-validation-log.txt"
BUNDLE_ID="${1:-com.duckduckgo.macos.browser.debug}"
PIXEL_DEFINITIONS_PATH="${BASE_DIR}/PixelDefinitions"
PIXEL_PREFIX="Pixel fired: "

SANDBOXED_LOG="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Caches/${LOG_FILENAME}"
UNSANDBOXED_LOG="${HOME}/Library/Caches/${LOG_FILENAME}"

if [[ -f "${SANDBOXED_LOG}" ]]; then
    LOG_FILE="${SANDBOXED_LOG}"
elif [[ -f "${UNSANDBOXED_LOG}" ]]; then
    LOG_FILE="${UNSANDBOXED_LOG}"
else
    echo "No pixel logs found for ${BUNDLE_ID}."
    echo ""
    echo "Make sure you:"
    echo "  1. Built and ran a debug build of the macOS app"
    echo "  2. Triggered some pixels during your session"
    exit 0
fi

cd "${BASE_DIR}"
npm run validate-pixel-debug-logs "${PIXEL_DEFINITIONS_PATH}" "${LOG_FILE}" "${PIXEL_PREFIX}"
