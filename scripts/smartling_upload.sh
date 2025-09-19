#!/bin/bash
set -euo pipefail

# Smartling Upload Script
# Uploads translation files to a Smartling job
# Supports both iOS and macOS platforms

PLATFORM="$1"
JOB_NAME="${2:-}"

if [ -z "$PLATFORM" ]; then
    echo "Error: Platform is required"
    echo "Usage: $0 <platform> [job-name]"
    echo "  platform: iOS or macOS"
    exit 1
fi

if [ -z "$JOB_NAME" ]; then
    # If no job name provided, use current git branch
    JOB_NAME="$(git rev-parse --abbrev-ref HEAD)"
fi

echo "Uploading translations for platform: $PLATFORM"
echo "Job name: $JOB_NAME"

if [ "$PLATFORM" = "iOS" ]; then
    # Upload iOS files (XLIFF and stringsdict)
    echo "Uploading iOS files..."
    ./scripts/loc_tool.sh upload \
        --job-name "$JOB_NAME" \
        --files ./iOS/scripts/assets/loc/en.xcloc/Localized\ Contents/en.xliff \
                ./iOS/DuckDuckGo/en.lproj/Localizable.stringsdict
elif [ "$PLATFORM" = "macOS" ]; then
    # Upload macOS file (XLIFF only)
    echo "Uploading macOS files..."
    ./scripts/loc_tool.sh upload \
        --job-name "$JOB_NAME" \
        --files ./macOS/scripts/assets/loc/en.xliff
else
    echo "Error: Unknown platform '$PLATFORM'. Must be 'iOS' or 'macOS'"
    exit 1
fi

echo "✅ Upload complete"