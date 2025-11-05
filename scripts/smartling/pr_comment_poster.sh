#!/bin/bash

set -euo pipefail

# Post PR comment with Smartling operation results
# Usage: ./pr_comment_poster.sh <pr_number> <message_file> <platform> <job_id> <action>

PR_NUMBER="${1:-}"
MESSAGE_FILE="${2:-}"
PLATFORM="${3:-}"
JOB_ID="${4:-}"
ACTION="${5:-}"

if [ -z "$PR_NUMBER" ] || [ -z "$MESSAGE_FILE" ]; then
	echo "❌ Error: PR number and message file are required"
	echo "Usage: $0 <pr_number> <message_file> <platform> <job_id> <action>"
	exit 1
fi

if [ ! -f "$MESSAGE_FILE" ]; then
	echo "⚠️  Warning: Message file not found: $MESSAGE_FILE"
	exit 0
fi

echo "💬 Posting PR comment..."

# Read the message content
MESSAGE=$(<"$MESSAGE_FILE")

# Add metadata comment for future parsing
METADATA_COMMENT=""
if [ -n "$PLATFORM" ] && [ -n "$JOB_ID" ] && [ -n "$ACTION" ]; then
	METADATA_COMMENT="

<!-- smartling-metadata:platform=$PLATFORM,job_id=$JOB_ID,action=$ACTION -->"
fi

# Create the full comment body
COMMENT_BODY="$MESSAGE$METADATA_COMMENT"

# Post the comment using gh CLI with stdin to prevent injection
if ! echo "$COMMENT_BODY" | gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/comments" \
	--field body=@- 2>&1; then
	echo "❌ Failed to post comment to PR #$PR_NUMBER"
	exit 1
fi

echo "✅ Comment posted successfully to PR #$PR_NUMBER"

exit 0