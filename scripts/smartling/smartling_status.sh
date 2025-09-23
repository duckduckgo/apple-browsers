#!/bin/bash
set -euo pipefail

# Smartling Status Check Script
# Checks the status of a Smartling translation job
# Generates status_message.txt for GitHub Actions

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

echo "Checking status for job: $JOB_ID"
echo "Platform: $PLATFORM"

# Capture the loc_tool.sh output
output=$(./scripts/smartling/loc_tool.sh status --job-id "$JOB_ID" 2>&1) || status_failed=1

echo "$output"

if [ "${status_failed:-0}" = "0" ]; then
	# Extract status and progress from output
	status=$(echo "$output" | grep -o 'STATUS=[^[:space:]]*' | cut -d= -f2 || echo "UNKNOWN")
	percent=$(echo "$output" | grep -o 'PERCENT=[^[:space:]]*' | cut -d= -f2 || echo "0")
	
	echo "STATUS=$status"
	echo "PERCENT=$percent"
	
	# Generate status message
	./scripts/smartling/smartling_messages.sh status status_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" "$status" "$percent"
	echo "✅ Status check complete"
	exit 0
else
	# For status checks, we don't have a specific "failed" message type in smartling_messages.sh
	# We'll just echo the error but still exit 1 to indicate failure
	echo "❌ Status check failed"
	echo "Could not retrieve status for job $JOB_ID"
	exit 1
fi
