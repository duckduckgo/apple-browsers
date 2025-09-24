#!/bin/bash
set -euo pipefail

# Smartling Approve Script
# Approves a Smartling translation job
# Generates approve_message.txt for GitHub Actions

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
	exit 1
fi

echo "Approving job: $JOB_ID"
echo "Platform: $PLATFORM"

# Capture the loc_tool.sh output
output=$(./scripts/smartling/loc_tool.sh approve --job-id "$JOB_ID" 2>&1) || approve_failed=1

echo "$output"

if [ "${approve_failed:-0}" = "0" ] && echo "$output" | grep -q "APPROVED=1"; then
	# Generate success message
	./scripts/smartling/smartling_messages.sh approve approve_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" success
	echo "✅ Job approved successfully"
	exit 0
else
	# Generate error message
	./scripts/smartling/smartling_messages.sh approve approve_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" failed
	echo "❌ Job approval failed"
	exit 1
fi
