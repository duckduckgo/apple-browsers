#!/bin/bash
set -euo pipefail

PLATFORM="${1:-}"
THRESHOLD="${2:-500.00}"
RESULT_FILE="${RUNNER_TEMP:-/tmp}/smartling-nightly-${PLATFORM}.json"
DATE_SUFFIX="$(date -u +%Y-%m-%d)"

case "$PLATFORM" in
	iOS)
		JOB_PREFIX="Nightly iOS - "
		FILES=(
			"./iOS/scripts/assets/loc/en.xcloc/Localized Contents/en.xliff"
			"./iOS/DuckDuckGo/en.lproj/Localizable.stringsdict"
		)
		;;
	macOS)
		JOB_PREFIX="Nightly macOS - "
		FILES=("./macOS/scripts/assets/loc/en.xliff")
		;;
	*)
		echo "Usage: $0 <iOS|macOS> [threshold]" >&2
		exit 1
		;;
esac

JOB_NAME="${JOB_PREFIX}${DATE_SUFFIX}"

./scripts/smartling/loc_tool.sh nightly \
	--job-name "$JOB_NAME" \
	--job-prefix "$JOB_PREFIX" \
	--files "${FILES[@]}" \
	--threshold "$THRESHOLD" \
	--result-file "$RESULT_FILE"

outcome="$(jq -r '.outcome' "$RESULT_FILE")"
job_id="$(jq -r '.job_id' "$RESULT_FILE")"
total_strings="$(jq -r '.total_strings' "$RESULT_FILE")"
max_usd="$(jq -r '.max_usd' "$RESULT_FILE")"
reason="$(jq -r '.reason' "$RESULT_FILE")"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "outcome=$outcome" >> "$GITHUB_OUTPUT"
	echo "job_id=$job_id" >> "$GITHUB_OUTPUT"
	echo "total_strings=$total_strings" >> "$GITHUB_OUTPUT"
	echo "max_usd=$max_usd" >> "$GITHUB_OUTPUT"
	echo "reason=$reason" >> "$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "## $PLATFORM Smartling nightly"
		echo
		echo "- Outcome: \`$outcome\`"
		echo "- Job ID: \`${job_id:-none}\`"
		echo "- Untranslated strings: \`$total_strings\`"
		echo "- Maximum USD estimate: \`${max_usd:-unavailable}\`"
		[ -z "$reason" ] || echo "- Reason: $reason"
	} >> "$GITHUB_STEP_SUMMARY"
fi
