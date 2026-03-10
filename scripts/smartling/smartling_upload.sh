#!/bin/bash
set -euo pipefail

# Smartling Upload Script
# Uploads translation files to a Smartling job
# Supports both iOS and macOS platforms

PLATFORM="$1"
JOB_NAME="${2:-}"
UPLOAD_SCOPE="${SMARTLING_UPLOAD_SCOPE:-full}"

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

# Always append date suffix to prevent naming conflicts
DATE_SUFFIX="$(date +%Y-%m-%d)"
JOB_NAME="${JOB_NAME}-${DATE_SUFFIX}"

echo "Uploading translations for platform: $PLATFORM"
echo "Job name: $JOB_NAME"
echo "Upload scope: $UPLOAD_SCOPE"

# Determine source files based on platform
if [ "$PLATFORM" = "iOS" ]; then
	SOURCE_FILES=(
		"./iOS/scripts/assets/loc/en.xcloc/Localized Contents/en.xliff"
		"./iOS/DuckDuckGo/en.lproj/Localizable.stringsdict"
	)
elif [ "$PLATFORM" = "macOS" ]; then
	SOURCE_FILES=(
		"./macOS/scripts/assets/loc/en.xliff"
	)
else
	echo "Error: Unknown platform '$PLATFORM'. Must be 'iOS' or 'macOS'"
	exit 1
fi

# Apply scoping if requested
UPLOAD_FILES=("${SOURCE_FILES[@]}")

if [ "$UPLOAD_SCOPE" = "scoped" ]; then
	echo "🔍 Scoping upload to branch-only changes..."
	scope_output=$(python3 ./scripts/smartling/prepare_scoped_upload.py \
		--platform "$PLATFORM" \
		--base-ref origin/main \
		--files "${SOURCE_FILES[@]}" 2>&1) || scope_failed=1

	echo "$scope_output"

	if [ "${scope_failed:-0}" = "1" ]; then
		echo "❌ Scoping failed — aborting upload (experimental mode does not fall back to full upload)"

		if [ -n "${GITHUB_OUTPUT:-}" ]; then
			echo "upload_success=false" >> "$GITHUB_OUTPUT"
			echo "job_id=" >> "$GITHUB_OUTPUT"
		fi

		./scripts/smartling/smartling_messages.sh upload upload_message.txt "$PLATFORM" "" "$SMARTLING_PROJECT_ID" failed
		exit 0
	fi

	# Extract scoped file paths from output (grep || true to avoid exit under set -e)
	scoped_files_line=$(echo "$scope_output" | { grep '^SCOPED_FILES=' || true; } | cut -d= -f2-)
	if [ -z "$scoped_files_line" ]; then
		echo "❌ No scoped files produced"

		if [ -n "${GITHUB_OUTPUT:-}" ]; then
			echo "upload_success=false" >> "$GITHUB_OUTPUT"
			echo "job_id=" >> "$GITHUB_OUTPUT"
		fi

		./scripts/smartling/smartling_messages.sh upload upload_message.txt "$PLATFORM" "" "$SMARTLING_PROJECT_ID" failed
		exit 0
	fi

	# Replace upload files with scoped versions
	IFS=' ' read -r -a UPLOAD_FILES <<< "$scoped_files_line"
	echo "✅ Scoped to ${#UPLOAD_FILES[@]} file(s)"

	# Extract unit count for observability in PR comments
	scoped_unit_count=$(echo "$scope_output" | { grep '^SCOPED_UNIT_COUNT=' || true; } | cut -d= -f2-)
	export SCOPED_UNIT_COUNT="${scoped_unit_count:-unknown}"
fi

# Upload
echo "Uploading ${PLATFORM} files..."
output=$(./scripts/smartling/loc_tool.sh upload \
		--job-name "$JOB_NAME" \
		--files "${UPLOAD_FILES[@]}" 2>&1) || upload_failed=1

echo "$output"

# Generate the message based on success/failure and set step outputs
if [ "${upload_failed:-0}" = "0" ] && echo "$output" | grep -q "JOB_ID="; then
	# Extract job ID and generate success message
	job_id=$(echo "$output" | grep -o 'JOB_ID=[^[:space:]]*' | cut -d= -f2)
	echo "JOB_ID=$job_id"  # Still output for any other consumers

	# Step outputs for GitHub Actions
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "upload_success=true" >> "$GITHUB_OUTPUT"
		echo "job_id=$job_id" >> "$GITHUB_OUTPUT"
	fi

	./scripts/smartling/smartling_messages.sh upload upload_message.txt "$PLATFORM" "$job_id" "$SMARTLING_PROJECT_ID" success
	echo "✅ Upload complete"
else
	# Step outputs for GitHub Actions (failure)
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "upload_success=false" >> "$GITHUB_OUTPUT"
		echo "job_id=" >> "$GITHUB_OUTPUT"
	fi

	# Generate error message
	./scripts/smartling/smartling_messages.sh upload upload_message.txt "$PLATFORM" "" "$SMARTLING_PROJECT_ID" failed
	echo "❌ Upload failed"
fi

# Always succeed the step; downstream logic branches on outputs
exit 0