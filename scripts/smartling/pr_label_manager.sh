#!/bin/bash

set -euo pipefail

# Manage PR labels for Smartling workflow
# Usage: ./pr_label_manager.sh <action> <pr_number> [success_status] [trigger_label]
#
# Actions:
#   after_upload <pr_number> <success|failed> <trigger_label>
#   after_approve <pr_number> <success|failed>
#   after_download <pr_number> <success|failed|no_changes>

ACTION="${1:-}"
PR_NUMBER="${2:-}"
STATUS="${3:-}"
TRIGGER_LABEL="${4:-}"

if [ -z "$ACTION" ] || [ -z "$PR_NUMBER" ]; then
	echo "❌ Error: Action and PR number are required"
	echo "Usage: $0 <action> <pr_number> [status] [trigger_label]"
	exit 1
fi

# Function to remove a label (silent on failure)
remove_label() {
	local label="$1"
	local encoded="${label// /%20}"
	echo "  Removing label: $label"
	gh api -X DELETE "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/labels/$encoded" 2>/dev/null || echo "  (Label not found or already removed)"
}

# Function to add a label
add_label() {
	local label="$1"
	echo "  Adding label: $label"
	gh api -X POST "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/labels" \
		--field "labels[]=$label" 2>/dev/null || echo "  (Label already exists)"
}

# Function to check if a label exists
has_label() {
	local label="$1"
	gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/labels" \
		--jq ".[].name | select(. == \"$label\")" 2>/dev/null | grep -q "$label"
}

echo "🏷️  Managing PR labels for action: $ACTION (status: ${STATUS:-N/A})"

case "$ACTION" in
	after_upload)
		echo "📤 Processing upload labels..."

		# Always remove the trigger label
		if [ -n "$TRIGGER_LABEL" ]; then
			remove_label "$TRIGGER_LABEL"
		fi

		# Only add status label on success
		if [ "$STATUS" == "success" ]; then
			add_label "needs translation authorization"
			echo "✅ Upload successful - added awaiting-authorization label"
		else
			echo "❌ Upload failed - no status label added"
		fi
		;;

	after_approve)
		echo "✅ Processing approval labels..."

		# Always remove the trigger label
		remove_label "authorize translation"

		if [ "$STATUS" == "success" ]; then
			# Success: remove awaiting-authorization, add in-progress
			remove_label "needs translation authorization"
			add_label "translation in progress"
			echo "✅ Approval successful - moved to in-progress"
		else
			# Failure: ensure awaiting-authorization is present
			if ! has_label "needs translation authorization"; then
				add_label "needs translation authorization"
			fi
			echo "❌ Approval failed - restored awaiting-authorization"
		fi
		;;

	after_download)
		echo "📥 Processing download labels..."

		# Always remove the trigger label
		remove_label "download translations"

		if [ "$STATUS" == "success" ] || [ "$STATUS" == "no_changes" ]; then
			# Success: remove in-progress, add completed
			remove_label "translation in progress"
			add_label "translations ready"
			echo "✅ Download successful - marked as completed"
		else
			# Failure: ensure in-progress is present
			if ! has_label "translation in progress"; then
				add_label "translation in progress"
			fi
			echo "❌ Download failed - kept in-progress"
		fi
		;;

	*)
		echo "❌ Error: Unknown action '$ACTION'"
		echo "Valid actions: after_upload, after_approve, after_download"
		exit 1
		;;
esac

echo "✨ Label management complete"
exit 0