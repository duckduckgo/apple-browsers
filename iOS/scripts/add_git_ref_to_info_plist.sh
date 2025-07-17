#!/bin/bash

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
BASE_DIR="${SCRIPT_DIR}/.."

GIT_BIN=$(xcrun -find git)
INFO_PLIST="${BASE_DIR}/DuckDuckGo/Info.plist"

SHORT_REVISION=$(${GIT_BIN} rev-parse --short HEAD) || exit 0
/usr/libexec/PlistBuddy -c "Add :ShortGitRevision string ${SHORT_REVISION}" "$INFO_PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :ShortGitRevision ${SHORT_REVISION}" "$INFO_PLIST"