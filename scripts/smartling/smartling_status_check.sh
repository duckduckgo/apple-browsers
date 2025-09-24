#!/bin/bash
set -euo pipefail

# Smartling Status Check Script
# Checks translation job status and updates PR labels accordingly
# Usage: ./smartling_status_check.sh <job_id> <platform>

JOB_ID="$1"
PLATFORM="$2"

if [ -z "$JOB_ID" ]; then
	echo "Error: Job ID is required"
	echo "Usage: $0 <job-id> <platform>"
	exit 1
fi

if [ -z "$PLATFORM" ]; then
	echo "Error: Platform is required"
	echo "Usage: $0 <job-id> <platform>"
	echo "  platform: iOS or macOS"
	exit 1
fi

echo "Checking translation status for job: $JOB_ID (Platform: $PLATFORM)"

# Use the existing status script to check job status and write the uniform message file
./scripts/smartling/smartling_status.sh "$JOB_ID" "$PLATFORM" check_status_message.txt

# Parse the status from the output (the status script creates check_status_message.txt)
if [ ! -f "check_status_message.txt" ]; then
	echo "❌ Failed to get status information"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "status_result=failed" >> "$GITHUB_OUTPUT"
	fi
	echo "Failed to check translation status" > status_check_message.txt
	exit 1
fi

# Extract the status from the message file
STATUS_INFO=$(cat check_status_message.txt)

# Determine the job status for label management
if echo "$STATUS_INFO" | grep -q "Status.*COMPLETED"; then
	LABEL_STATUS="ready"
	echo "✅ Translation job is completed"
elif echo "$STATUS_INFO" | grep -q "Status.*IN_PROGRESS"; then
	LABEL_STATUS="in_progress"
	echo "⏳ Translation job is in progress"
elif echo "$STATUS_INFO" | grep -q "Status.*AWAITING_AUTHORIZATION"; then
	LABEL_STATUS="awaiting_authorization"
	echo "⏸️ Translation job is awaiting authorization"
else
	LABEL_STATUS="unknown"
	echo "❓ Translation job status is unknown or failed"
fi

# Set output for workflow
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "status_result=$LABEL_STATUS" >> "$GITHUB_OUTPUT"
fi

exit 0