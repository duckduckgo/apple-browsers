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
	# Set step outputs and generate success message
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "approve_success=true" >> "$GITHUB_OUTPUT"
	fi
	./scripts/smartling/smartling_messages.sh approve approve_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" success
	echo "✅ Job approved successfully"
else
	# Set step outputs and generate error message
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "approve_success=false" >> "$GITHUB_OUTPUT"
	fi
	./scripts/smartling/smartling_messages.sh approve approve_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" failed
	echo "❌ Job approval failed"
fi

# Always succeed the step; downstream logic branches on outputs
exit 0
