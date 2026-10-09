#!/bin/bash

set -euo pipefail

ACTION="${1:-}"
PR_NUMBER="${2:-}"
JOBS_JSON="${3:-}"

if [ -z "$ACTION" ] || [ -z "$PR_NUMBER" ] || [ -z "$JOBS_JSON" ]; then
	echo "❌ Error: Action, PR number and jobs are required"
	echo "Usage: $0 <approve|download|check_status> <pr_number> <jobs_json>"
	exit 1
fi

case "$ACTION" in
	approve|download|check_status) ;;
	*)
		echo "❌ Error: Unknown action '$ACTION'"
		exit 1
		;;
esac

set_credentials() {
	case "$1" in
		iOS)
			export SMARTLING_USER_ID="$IOS_SMARTLING_USER_ID"
			export SMARTLING_USER_SECRET="$IOS_SMARTLING_USER_SECRET"
			export SMARTLING_PROJECT_ID="$IOS_SMARTLING_PROJECT_ID"
			;;
		macOS)
			export SMARTLING_USER_ID="$MACOS_SMARTLING_USER_ID"
			export SMARTLING_USER_SECRET="$MACOS_SMARTLING_USER_SECRET"
			export SMARTLING_PROJECT_ID="$MACOS_SMARTLING_PROJECT_ID"
			;;
		*)
			echo "❌ Error: Unknown platform '$1'"
			return 1
			;;
	esac
}

read_output() {
	local file="$1"
	local key="$2"
	grep "^$key=" "$file" | tail -1 | cut -d= -f2 || true
}

job_status() {
	local job_id="$1"
	local platform="$2"
	local output_file
	output_file=$(mktemp)
	GITHUB_OUTPUT="$output_file" ./scripts/smartling/smartling_status_check.sh "$job_id" "$platform" >&2 || true
	read_output "$output_file" status_result
}

run_action() {
	local platform="$1"
	local job_id="$2"
	local output_file
	output_file=$(mktemp)

	case "$ACTION" in
		approve)
			local status
			status=$(job_status "$job_id" "$platform")
			if [ "$status" == "in_progress" ] || [ "$status" == "ready" ]; then
				echo "⏭️  $platform job $job_id is already authorized (status: $status), skipping" >&2
				echo "skipped"
				return
			fi
			GITHUB_OUTPUT="$output_file" ./scripts/smartling/smartling_approve.sh "$job_id" "$platform" >&2 || true
			read_output "$output_file" approve_success
			;;
		download)
			GITHUB_OUTPUT="$output_file" ./scripts/smartling/smartling_download.sh "$job_id" "$platform" false >&2 || true
			read_output "$output_file" download_result
			;;
		check_status)
			GITHUB_OUTPUT="$output_file" ./scripts/smartling/smartling_status_check.sh "$job_id" "$platform" >&2 || true
			read_output "$output_file" status_result
			;;
	esac
}

RESULTS=""

while IFS=$'\t' read -r platform job_id <&3; do
	echo "▶️  Running $ACTION for $platform job $job_id"

	if ! set_credentials "$platform"; then
		RESULTS="$RESULTS failed"
		continue
	fi

	message_file="${ACTION}_message.txt"
	rm -f "$message_file"

	result=$(run_action "$platform" "$job_id")
	result="${result:-failed}"
	echo "Result for $platform: $result"
	RESULTS="$RESULTS $result"

	if [ "$result" == "skipped" ]; then
		continue
	fi

	if [ -f "$message_file" ]; then
		cat "$message_file" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
		./scripts/smartling/pr_comment_poster.sh "$PR_NUMBER" "$message_file" "$platform" "$job_id" "$ACTION" || true
	fi
done 3< <(echo "$JOBS_JSON" | jq -r '.[] | [.platform, .job_id] | @tsv')

has_result() {
	[[ " $RESULTS " == *" $1 "* ]]
}

case "$ACTION" in
	approve)
		if has_result false || has_result failed; then
			COMBINED="failed"
		else
			COMBINED="success"
		fi
		./scripts/smartling/pr_label_manager.sh after_approve "$PR_NUMBER" "$COMBINED"
		;;
	download)
		if has_result failed; then
			COMBINED="failed"
		elif has_result deletions_pr_created; then
			COMBINED="deletions_pr_created"
		else
			COMBINED="success"
		fi
		./scripts/smartling/pr_label_manager.sh after_download "$PR_NUMBER" "$COMBINED"
		;;
	check_status)
		if has_result failed || has_result unknown; then
			COMBINED="unknown"
		elif has_result awaiting_authorization; then
			COMBINED="awaiting_authorization"
		elif has_result in_progress; then
			COMBINED="in_progress"
		else
			COMBINED="ready"
		fi
		./scripts/smartling/pr_label_manager.sh check_status "$PR_NUMBER" "$COMBINED"
		;;
esac

echo "::notice::Smartling $ACTION results:$RESULTS (combined: $COMBINED)"

exit 0
