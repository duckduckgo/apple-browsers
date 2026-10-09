#!/bin/bash

set -euo pipefail

# Parse PR comments to extract the latest Smartling upload job for each platform
# Usage: ./pr_comment_parser.sh <pr_number>
#
# Outputs:
# - Sets GITHUB_OUTPUT with jobs, a JSON array of {platform, job_id}
# - Exits with error if no job details found

PR_NUMBER="${1:-}"

if [ -z "$PR_NUMBER" ]; then
	echo "❌ Error: PR number is required"
	exit 1
fi

echo "🔍 Parsing PR comments for job details..."

JQ_FILTER='.[] | select(.user.login=="github-actions[bot]") | .body
	| capture("<!-- smartling-metadata:platform=(?<platform>[^,]+),job_id=(?<job_id>[^,]+),action=upload -->")
	| select(.job_id != "N/A")'

UPLOADS=$(gh api --paginate \
	"repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
	--jq "$JQ_FILTER" \
	2>/dev/null || echo "")

if [ -z "$UPLOADS" ]; then
	echo "❌ Error: Could not find valid job ID in PR comments"
	exit 1
fi

JOBS=$(echo "$UPLOADS" | jq -sc 'reduce .[] as $upload ({}; .[$upload.platform] = $upload.job_id)
	| to_entries | map({platform: .key, job_id: .value})')

echo "$JOBS" | jq -r '.[] | "✅ Using latest job details: platform=\(.platform), job_id=\(.job_id)"'

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "jobs=$JOBS" >> "$GITHUB_OUTPUT"
fi

echo "::notice::Successfully parsed job details: $JOBS"

exit 0
