#!/bin/bash

set -euo pipefail

# Manage PR labels for Smartling workflow
# Usage: ./pr_label_manager.sh <action> <pr_number> [success_status] [trigger_label]
#
# Actions:
#   after_upload <pr_number> <success|failed> <trigger_label>
#   after_approve <pr_number> <success|failed>
#   after_download <pr_number> <success|failed|no_changes|deletions_pr_created>
#   check_status <pr_number> <ready|in_progress|awaiting_authorization|unknown>

ACTION="${1:-}"
PR_NUMBER="${2:-}"
STATUS="${3:-}"
TRIGGER_LABEL="${4:-}"

if [ -z "$ACTION" ] || [ -z "$PR_NUMBER" ]; then
	echo "❌ Error: Action and PR number are required"
	echo "Usage: $0 <action> <pr_number> [status] [trigger_label]"
	exit 1
fi

declare -a LABELS=()
LABELS_CHANGED=false

load_labels() {
	local current_labels
	current_labels="$(gh api "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/labels" \
		--jq '.[].name')"
	while IFS= read -r label; do
		[[ -n "$label" ]] && LABELS+=("$label")
	done <<< "$current_labels"
}

has_label() {
	local label="$1"
	local current
	for current in "${LABELS[@]}"; do
		if [[ "$current" == "$label" ]]; then
			return 0
		fi
	done
	return 1
}

add_label() {
	local label="$1"
	if has_label "$label"; then
		return
	fi
	echo "  Adding label: $label"
	LABELS+=("$label")
	LABELS_CHANGED=true
}

remove_label() {
	local label="$1"
	local current
	local kept=()
	for current in "${LABELS[@]}"; do
		if [[ "$current" != "$label" ]]; then
			kept+=("$current")
		fi
	done
	if [[ ${#kept[@]} -ne ${#LABELS[@]} ]]; then
		echo "  Removing label: $label"
		LABELS_CHANGED=true
	fi
	LABELS=("${kept[@]}")
}

apply_labels() {
	local labels_json
	if [[ "$LABELS_CHANGED" != "true" ]]; then
		echo "  Labels already up to date"
		return
	fi
	if [[ ${#LABELS[@]} -eq 0 ]]; then
		labels_json="[]"
	else
		labels_json="$(printf '%s\n' "${LABELS[@]}" | jq -R . | jq -s .)"
	fi
	jq -n --argjson labels "$labels_json" '{labels: $labels}' \
		| gh api -X PUT "repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER/labels" \
			--input - >/dev/null
}

echo "🏷️  Managing PR labels for action: $ACTION (status: ${STATUS:-N/A})"
load_labels

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
			# Success: remove in-progress, no additional labels
			remove_label "translation in progress"
			echo "✅ Download successful - removed in-progress label"
		elif [ "$STATUS" == "deletions_pr_created" ]; then
			echo "⚠️ Deletions detected - created review PR, marked for review"
		else
			# Failure: ensure in-progress is present
			if ! has_label "translation in progress"; then
				add_label "translation in progress"
			fi
			echo "❌ Download failed - kept in-progress"
		fi
		;;

	check_status)
		echo "🔍 Processing status check labels..."

		# Always remove the trigger label
		remove_label "check translation status"

		# Set labels based on current job status
		case "$STATUS" in
			"ready")
				# Translation is complete
				remove_label "needs translation authorization"
				remove_label "translation in progress"
				add_label "translations ready"
				echo "✅ Status check: translations are ready"
				;;
			"in_progress")
				# Translation is in progress
				remove_label "needs translation authorization"
				remove_label "translations ready"
				add_label "translation in progress"
				echo "⏳ Status check: translation in progress"
				;;
			"awaiting_authorization")
				# Translation needs authorization
				remove_label "translation in progress"
				remove_label "translations ready"
				add_label "needs translation authorization"
				echo "⏸️ Status check: needs authorization"
				;;
			*)
				echo "❓ Status check: unknown status, no label changes"
				;;
		esac
		;;

	*)
		echo "❌ Error: Unknown action '$ACTION'"
		echo "Valid actions: after_upload, after_approve, after_download, check_status"
		exit 1
		;;
esac

apply_labels
echo "✨ Label management complete"
exit 0
