#!/bin/bash

# validate_wide_events.sh
# Displays the wide event validation log from the iOS Simulator.
#
# Usage:
#   ./validate_wide_events.sh

set -e

BUNDLE_ID="com.duckduckgo.mobile.ios"

# Check for a booted simulator
if ! xcrun simctl list devices booted 2>/dev/null | grep -q "Booted"; then
    echo "Error: No iOS Simulator is currently booted."
    echo "Please start a simulator and run your app before validating wide events."
    exit 1
fi

# Get the app container path
CONTAINER_PATH=$(xcrun simctl get_app_container booted "${BUNDLE_ID}" data 2>/dev/null)
if [[ -z "${CONTAINER_PATH}" ]]; then
    echo "Error: Could not find app container for ${BUNDLE_ID}."
    echo "Make sure the app is installed on the simulator."
    exit 1
fi

LOG_FILE="${CONTAINER_PATH}/Library/Caches/wide-event-validation-log.jsonl"

if [[ ! -f "${LOG_FILE}" ]]; then
    echo "No wide event logs found."
    echo ""
    echo "Make sure you:"
    echo "  1. Built and ran a debug build in the Simulator"
    echo "  2. Triggered some wide events during your session"
    exit 0
fi

echo "Wide event validation log:"
echo "=========================="
cat "${LOG_FILE}"
