#!/bin/bash
set -euo pipefail

# Submits a platform's exported strings to a new Smartling job and authorizes it
# when the maximum USD estimate is within the threshold.
# Writes outcome, job_id, total_strings, max_usd and reason to GITHUB_OUTPUT.

usage() {
	echo "Usage: $0 <iOS|macOS> --job-name <name> --job-prefix <prefix> --file-uri-prefix <prefix> [--threshold <usd>]" >&2
	echo "  e.g. $0 iOS --job-name 'Release iOS 7.200.0' --job-prefix 'Release iOS ' --file-uri-prefix release/ios/7.200.0" >&2
	exit 1
}

PLATFORM="${1:-}"
shift || true

JOB_NAME=""
JOB_PREFIX=""
FILE_URI_PREFIX=""
THRESHOLD="500.00"

while [ $# -gt 0 ]; do
	case "$1" in
		--job-name) JOB_NAME="${2:-}"; shift 2 ;;
		--job-prefix) JOB_PREFIX="${2:-}"; shift 2 ;;
		--file-uri-prefix) FILE_URI_PREFIX="${2:-}"; shift 2 ;;
		--threshold) THRESHOLD="${2:-}"; shift 2 ;;
		*) usage ;;
	esac
done

case "$PLATFORM" in
	iOS)
		FILES=(
			"./iOS/scripts/assets/loc/en.xcloc/Localized Contents/en.xliff"
			"./iOS/DuckDuckGo/en.lproj/Localizable.stringsdict"
		)
		;;
	macOS)
		FILES=("./macOS/scripts/assets/loc/en.xliff")
		;;
	*)
		usage
		;;
esac

if [ -z "$JOB_NAME" ] || [ -z "$JOB_PREFIX" ] || [ -z "$FILE_URI_PREFIX" ] || [ -z "$THRESHOLD" ]; then
	usage
fi

RESULT_FILE="${RUNNER_TEMP:-/tmp}/smartling-submit-${PLATFORM}.json"

./scripts/smartling/loc_tool.sh submit \
	--job-name "$JOB_NAME" \
	--job-prefix "$JOB_PREFIX" \
	--file-uri-prefix "$FILE_URI_PREFIX" \
	--files "${FILES[@]}" \
	--threshold "$THRESHOLD" \
	--result-file "$RESULT_FILE"

outcome="$(jq -r '.outcome' "$RESULT_FILE")"
job_id="$(jq -r '.job_id' "$RESULT_FILE")"
total_strings="$(jq -r '.total_strings' "$RESULT_FILE")"
max_usd="$(jq -r '.max_usd' "$RESULT_FILE")"
reason="$(jq -r '.reason' "$RESULT_FILE")"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "outcome=$outcome"
		echo "job_id=$job_id"
		echo "total_strings=$total_strings"
		echo "max_usd=$max_usd"
		echo "reason=$reason"
	} >> "$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "## $PLATFORM Smartling job: $JOB_NAME"
		echo
		echo "- Outcome: \`$outcome\`"
		echo "- Job ID: \`${job_id:-none}\`"
		echo "- Untranslated strings: \`$total_strings\`"
		echo "- Maximum USD estimate: \`${max_usd:-unavailable}\`"
		echo "- Threshold: \`$THRESHOLD\`"
		[ -z "$reason" ] || echo "- Reason: $reason"
	} >> "$GITHUB_STEP_SUMMARY"
fi
