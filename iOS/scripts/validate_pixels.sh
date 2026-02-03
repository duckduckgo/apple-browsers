#!/bin/bash

# validate_pixels.sh
# Prints pixel validation logs from the iOS Simulator.
#
# Usage:
#   ./validate_pixels.sh

set -e

BUNDLE_ID="com.duckduckgo.mobile.ios"

# Check for a booted simulator
if ! xcrun simctl list devices booted 2>/dev/null | grep -q "Booted"; then
    echo "Error: No iOS Simulator is currently booted."
    echo "Please start a simulator and run your app before validating pixels."
    exit 1
fi

# Get the app container path
CONTAINER_PATH=$(xcrun simctl get_app_container booted "${BUNDLE_ID}" data 2>/dev/null)
if [[ -z "${CONTAINER_PATH}" ]]; then
    echo "Error: Could not find app container for ${BUNDLE_ID}."
    echo "Make sure the app is installed on the simulator."
    exit 1
fi

LOG_FILE="${CONTAINER_PATH}/Library/Caches/pixel-validation-log.txt"

if [[ ! -f "${LOG_FILE}" ]]; then
    echo "No pixel logs found."
    echo ""
    echo "Make sure you:"
    echo "  1. Built and ran a debug build in the Simulator"
    echo "  2. Triggered some pixels during your session"
    exit 0
fi

cat "${LOG_FILE}"
