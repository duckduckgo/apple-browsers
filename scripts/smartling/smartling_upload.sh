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
	output=$(./scripts/smartling/loc_tool.sh upload \
			--job-name "$JOB_NAME" \
			--files ./iOS/scripts/assets/loc/en.xcloc/Localized\ Contents/en.xliff \
				./iOS/DuckDuckGo/en.lproj/Localizable.stringsdict 2>&1) || upload_failed=1
elif [ "$PLATFORM" = "macOS" ]; then
	# Upload macOS file (XLIFF only)
	echo "Uploading macOS files..."
	output=$(./scripts/smartling/loc_tool.sh upload \
			--job-name "$JOB_NAME" \
			--files ./macOS/scripts/assets/loc/en.xliff 2>&1) || upload_failed=1
else
	echo "Error: Unknown platform '$PLATFORM'. Must be 'iOS' or 'macOS'"
	exit 1
fi

echo "$output"

# Generate the message based on success/failure
if [ "${upload_failed:-0}" = "0" ] && echo "$output" | grep -q "JOB_ID="; then
	# Extract job ID and generate success message
	job_id=$(echo "$output" | grep -o 'JOB_ID=[^[:space:]]*' | cut -d= -f2)
	echo "JOB_ID=$job_id"  # Still output for any other consumers
	
	./scripts/smartling/smartling_messages.sh upload upload_message.txt "$PLATFORM" "$job_id" "$SMARTLING_PROJECT_ID" success
	echo "✅ Upload complete"
	exit 0
else
	# Generate error message
	./scripts/smartling/smartling_messages.sh upload upload_message.txt "$PLATFORM" "" "$SMARTLING_PROJECT_ID" failed
	echo "❌ Upload failed"
	exit 1
fi