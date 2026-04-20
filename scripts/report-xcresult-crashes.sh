#!/bin/bash

set -eo pipefail

print_usage_and_exit() {
	local reason=$1

	cat <<- EOF
	Usage:
	  $ $(basename "$0") <path-to-xcresult>

	Extracts crashed tests from an xcresult bundle and appends a markdown section
	to \$GITHUB_STEP_SUMMARY (or stdout when running locally). Crashes don't
	appear in xcbeautify's JUnit output, so this surfaces them separately.

	Exits silently if no crashes are found.
	EOF

	if [[ -n "$reason" ]]; then
		echo "Error: $reason"
		exit 1
	fi

	exit 0
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	print_usage_and_exit
fi

xcresult="${1:-}"
if [[ -z "$xcresult" ]]; then
	print_usage_and_exit "missing xcresult path"
fi
if [[ ! -e "$xcresult" ]]; then
	print_usage_and_exit "xcresult not found at $xcresult"
fi

out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

json=$(xcrun xcresulttool get test-results summary --path "$xcresult" --format json)

crashes=$(jq '[.testFailures // [] | .[] | select(.failureText | test("crash"; "i"))]' <<< "$json")
crash_count=$(jq 'length' <<< "$crashes")

if [[ "$crash_count" -eq 0 ]]; then
	exit 0
fi

{
	echo "## 💥 Test crashes ($crash_count)"
	echo ""
	echo "These tests crashed and are not captured in the JUnit report."
	echo ""
	echo "| Target | Test | Reason |"
	echo "| ------ | ---- | ------ |"
	jq -r '.[] | "| \(.targetName) | `\(.testIdentifierString)` | \(.failureText) |"' <<< "$crashes"
} >> "$out"
