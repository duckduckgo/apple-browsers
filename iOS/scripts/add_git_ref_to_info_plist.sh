#!/bin/bash

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
BASE_DIR="${SCRIPT_DIR}/.."

GIT_BIN=$(xcrun -find git)
REVISION=$(${GIT_BIN} rev-parse --short HEAD) || exit 0
INFO_PLIST="${BASE_DIR}/DuckDuckGo/Info.plist"

# Try to add the key, if it fails (already exists), set it instead
/usr/libexec/PlistBuddy -c "Add :ShortGitReference string ${REVISION}" "$INFO_PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :ShortGitReference ${REVISION}" "$INFO_PLIST"