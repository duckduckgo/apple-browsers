#!/bin/bash
set -euo pipefail

# Submits a platform's exported strings to a new Smartling job and authorizes it
# when the maximum USD estimate is at most --auto-authorize-max-usd.
# Writes job_name, outcome, job_id, total_strings (strings × locales), locales, max_usd, reason and failed
# (true when the submission failed, as opposed to a job left for review)
# to GITHUB_OUTPUT.

usage() {
	echo "Usage: $0 <iOS|macOS> --job-name <name> --pending-job-prefix <prefix> --file-uri-prefix <prefix> [--auto-authorize-max-usd <usd>]" >&2
	echo "  e.g. $0 iOS --job-name 'Release iOS 7.200.0' --pending-job-prefix 'Release iOS ' --file-uri-prefix release/ios/7.200.0" >&2
	exit 1
}

PLATFORM="${1:-}"
shift || true

JOB_NAME=""
PENDING_JOB_PREFIX=""
FILE_URI_PREFIX=""
AUTO_AUTHORIZE_MAX_USD="500.00"

while [ $# -gt 0 ]; do
	case "$1" in
		--job-name) JOB_NAME="${2:-}"; shift 2 ;;
		--pending-job-prefix) PENDING_JOB_PREFIX="${2:-}"; shift 2 ;;
		--file-uri-prefix) FILE_URI_PREFIX="${2:-}"; shift 2 ;;
		--auto-authorize-max-usd) AUTO_AUTHORIZE_MAX_USD="${2:-}"; shift 2 ;;
		*) usage ;;
	esac
done

case "$PLATFORM" in
	iOS)
		FILES=(
			"./iOS/scripts/assets/loc/en.xcloc/Localized Contents/en.xliff"
			"./iOS/DuckDuckGo/UserInterfaceResources/en.lproj/Localizable.stringsdict"
		)
		;;
	macOS)
		FILES=("./macOS/scripts/assets/loc/en.xliff")
		;;
	*)
		usage
		;;
esac

if [ -z "$JOB_NAME" ] || [ -z "$PENDING_JOB_PREFIX" ] || [ -z "$FILE_URI_PREFIX" ] || [ -z "$AUTO_AUTHORIZE_MAX_USD" ]; then
	usage
fi

RESULT_FILE="${RUNNER_TEMP:-/tmp}/smartling-submit-${PLATFORM}.json"

./scripts/smartling/loc_tool.sh submit \
	--job-name "$JOB_NAME" \
	--pending-job-prefix "$PENDING_JOB_PREFIX" \
	--file-uri-prefix "$FILE_URI_PREFIX" \
	--files "${FILES[@]}" \
	--auto-authorize-max-usd "$AUTO_AUTHORIZE_MAX_USD" \
	--result-file "$RESULT_FILE"

outcome="$(jq -r '.outcome' "$RESULT_FILE")"
job_id="$(jq -r '.job_id' "$RESULT_FILE")"
job_name="$(jq -r '.job_name' "$RESULT_FILE")"
total_strings="$(jq -r '.total_strings // empty' "$RESULT_FILE")"
locales="$(jq -r '.locales // empty' "$RESULT_FILE")"
max_usd="$(jq -r '.max_usd' "$RESULT_FILE")"
reason="$(jq -r '.reason' "$RESULT_FILE")"
failed="$(jq -r '.failed' "$RESULT_FILE")"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "job_name=$job_name"
		echo "outcome=$outcome"
		echo "job_id=$job_id"
		echo "total_strings=$total_strings"
		echo "locales=$locales"
		echo "max_usd=$max_usd"
		echo "reason=$reason"
		echo "failed=$failed"
	} >> "$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "## $PLATFORM Smartling job: $JOB_NAME"
		echo
		echo "- Outcome: \`$outcome\`"
		echo "- Job: \`${job_name:-none}\` (\`${job_id:-none}\`)"
		if [ -n "$total_strings" ]; then
			echo "- String translations: \`$total_strings\` across \`$locales\` locales"
		else
			echo "- String translations: unavailable"
		fi
		echo "- Maximum USD estimate: \`${max_usd:-unavailable}\`"
		echo "- Authorized automatically up to: \`$AUTO_AUTHORIZE_MAX_USD USD\`"
		[ -z "$reason" ] || echo "- Reason: $reason"
	} >> "$GITHUB_STEP_SUMMARY"
fi
