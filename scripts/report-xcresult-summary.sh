#!/bin/bash

set -eo pipefail

print_usage_and_exit() {
	local reason=$1

	cat <<- EOF
	Usage:
	  $ $(basename "$0") <path-to-xcresult>

	Extracts failed and crashed tests from an xcresult bundle and appends a
	markdown section to \$GITHUB_STEP_SUMMARY (or stdout when running locally).
	Crashes don't appear in xcbeautify's JUnit output, so this surfaces them
	alongside regular failures.

	Exits silently if no failures are found.
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

failures=$(jq '[.testFailures // []] | flatten' <<< "$json")
total=$(jq 'length' <<< "$failures")

if [[ "$total" -eq 0 ]]; then
	exit 0
fi

crash_count=$(jq '[.[] | select(.failureText | test("crash"; "i"))] | length' <<< "$failures")
fail_count=$((total - crash_count))

{
	echo "## Test summary"
	echo ""
	if [[ "$crash_count" -gt 0 && "$fail_count" -gt 0 ]]; then
		echo "$total failed tests ($fail_count assertion failures, $crash_count crashed)."
	elif [[ "$crash_count" -gt 0 ]]; then
		echo "$crash_count test(s) crashed."
	else
		echo "$fail_count test(s) failed."
	fi
	echo ""
	echo "| Target | Test | Reason |"
	echo "| ------ | ---- | ------ |"
	jq -r '
		.[]
		| (if (.failureText | test("crash"; "i")) then "💥" else "❌" end) as $icon
		| "| \(.targetName) | `\(.testIdentifierString)` | \($icon) \(.failureText) |"
	' <<< "$failures"
} >> "$out"
