#!/bin/bash

set -euo pipefail

# Parse PR comments to extract Smartling job details
# Usage: ./pr_comment_parser.sh <pr_number>
#
# Outputs:
# - Sets GITHUB_OUTPUT with job_id and platform
# - Exits with error if no job details found

PR_NUMBER="${1:-}"

if [ -z "$PR_NUMBER" ]; then
	echo "❌ Error: PR number is required"
	exit 1
fi

echo "🔍 Parsing PR comments for job details..."

# Fetch all comments from the PR
COMMENTS=$(gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" --jq '.[].body' 2>/dev/null || echo "")

if [ -z "$COMMENTS" ]; then
	echo "❌ Error: Could not fetch PR comments or no comments found"
	exit 1
fi

JOB_ID=""
PLATFORM=""

# First, try to find metadata in HTML comments (most reliable)
while IFS= read -r comment; do
	# Look for metadata comment
	if [[ "$comment" =~ \<\!--\ smartling-metadata:platform=([^,]+),job_id=([^,]+),action=upload\ --\> ]]; then
		PLATFORM="${BASH_REMATCH[1]}"
		JOB_ID="${BASH_REMATCH[2]}"
		echo "✅ Found job details from metadata: platform=$PLATFORM, job_id=$JOB_ID"
		break
	fi
done <<< "$COMMENTS"

# Fallback: parse from visible content if no metadata found
if [ -z "$JOB_ID" ] || [ -z "$PLATFORM" ]; then
	echo "⚠️  No metadata found, trying to parse from comment content..."

	# Reverse the order to get the most recent first
	COMMENTS_REVERSED=$(echo "$COMMENTS" | tac)

	while IFS= read -r comment; do
		# Look for job ID pattern
		if [[ "$comment" =~ \*\*Job\ ID:\*\*\ \`([a-zA-Z0-9]+)\` ]]; then
			JOB_ID="${BASH_REMATCH[1]}"
		fi

		# Look for platform pattern
		if [[ "$comment" =~ \*\*Platform:\*\*\ (iOS|macOS) ]]; then
			PLATFORM="${BASH_REMATCH[1]}"
		fi

		# If we found both, stop searching
		if [ -n "$JOB_ID" ] && [ -n "$PLATFORM" ]; then
			echo "✅ Found job details from content: platform=$PLATFORM, job_id=$JOB_ID"
			break
		fi
	done <<< "$COMMENTS_REVERSED"
fi

# Validate we found both values
if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "N/A" ]; then
	echo "❌ Error: Could not find valid job ID in PR comments"
	exit 1
fi

if [ -z "$PLATFORM" ]; then
	echo "❌ Error: Could not find platform in PR comments"
	exit 1
fi

# Output for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "job_id=$JOB_ID" >> "$GITHUB_OUTPUT"
	echo "platform=$PLATFORM" >> "$GITHUB_OUTPUT"
fi

# Also output to stdout for debugging
echo "::notice::Successfully parsed job details - Platform: $PLATFORM, Job ID: $JOB_ID"

exit 0