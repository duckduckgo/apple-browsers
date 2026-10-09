#!/bin/bash
#
# Works out what notify-failure in macos_ui_tests.yml reports to Asana for one task type,
# from the workflow run's artifact names (one per line on stdin).
#
# Usage:
#   ui_tests_rerun_report.sh report --type <production|internal|appstore> --attempt <n> --run-url <url>
#
# Prints GITHUB_OUTPUT lines: action (create|comment|none), failing_count, comment (when
# action is comment) and description_suffix (when failing_count is above 0).
#
# Note: This script is intended for CI use only. You shouldn't call it directly.

set -eo pipefail

marker_prefix="ui-result-macos-ui-"
gid_prefix="asana-task-gid-"
delimiter="EOF_UI_TESTS_RERUN_REPORT"

print_usage_and_exit() {
	cat <<- EOF >&2
	Usage:
	  $(basename "$0") report --type <production|internal|appstore> --attempt <n> --run-url <url>

	EOF
	echo "$1" >&2
	exit 2
}

read_command_line_arguments() {
	command="$1"
	case "${command}" in
		report) ;;
		*) print_usage_and_exit "Unknown command '${command}'" ;;
	esac
	shift 1

	while (( $# > 0 )); do
		case "$1" in
			--attempt) attempt="$2" ;;
			--type) type="$2" ;;
			--run-url) run_url="$2" ;;
			*) print_usage_and_exit "Unknown option '$1'" ;;
		esac
		shift 2 || print_usage_and_exit "Missing value for '$1'"
	done

	[[ "${attempt}" =~ ^[1-9][0-9]*$ ]] || print_usage_and_exit "Invalid --attempt '${attempt}'"
	[[ "${type}" =~ ^(production|internal|appstore)$ ]] || print_usage_and_exit "Invalid --type '${type}'"
	[[ -n "${run_url}" ]] || print_usage_and_exit "Missing --run-url"
}

# Prints one tab-separated line per leg of the task type:
# <latest attempt> <latest result> <result in this attempt, or -> <test>, macOS <os>, <mode>
legs_for_type() {
	awk -F'-' -v prefix="${marker_prefix}" -v type="${type}" -v attempt="${attempt}" '
		{
			if (index($0, prefix) != 1) next
			if (NF == 9) leg_type = $(NF - 4)
			else if (NF == 10 && $5 == "appstore") leg_type = "appstore"
			else next
			if (leg_type != type) next

			mode = $(NF - 4)
			marker_attempt = $(NF - 1)
			marker_result = $NF
			if (mode != "production" && mode != "internal") next
			if (marker_attempt !~ /^attempt[0-9]+$/) next
			if (marker_result != "pass" && marker_result != "fail") next

			n = substr(marker_attempt, 8) + 0
			key = $(NF - 3) ", macOS " $(NF - 2) ", " mode
			if (!(key in latest) || n > latest[key]) {
				latest[key] = n
				latest_result[key] = marker_result
			}
			if (n == attempt) current[key] = marker_result
		}
		END {
			for (key in latest) {
				print latest[key] "\t" latest_result[key] "\t" ((key in current) ? current[key] : "-") "\t" key
			}
		}
	' <<< "${listing}" | LC_ALL=C sort -t $'\t' -k4
}

print_output() {
	local name=$1
	local value=$2
	printf '%s<<%s\n%s\n%s\n' "${name}" "${delimiter}" "${value}" "${delimiter}"
}

report() {
	local legs
	local failing_count
	local has_gid=false
	local has_current
	local action

	legs="$(legs_for_type)"
	failing_count="$(awk -F'\t' '$2 == "fail"' <<< "${legs}" | grep -c . || true)"
	has_current="$(awk -F'\t' '$3 != "-" { found = 1 } END { print (found ? "true" : "false") }' <<< "${legs}")"
	if grep -qxF "${gid_prefix}${type}" <<< "${listing}"; then
		has_gid=true
	fi

	if [[ "${has_gid}" == "true" ]]; then
		if [[ "${has_current}" == "true" ]]; then
			action="comment"
		else
			action="none"
		fi
	elif (( failing_count > 0 )); then
		action="create"
	else
		action="none"
	fi

	echo "action=${action}"
	echo "failing_count=${failing_count}"

	if [[ "${action}" == "comment" ]]; then
		print_output "comment" "$(comment_text "${legs}" "${failing_count}")"
	fi
	if (( failing_count > 0 )); then
		print_output "description_suffix" "$(description_suffix_text "${legs}")"
	fi
}

comment_text() {
	local legs=$1
	local failing_count=$2
	local now_passing

	if (( failing_count == 0 )); then
		echo "UI Tests re-run (attempt ${attempt}): ✅ all previously failing combinations now pass"
		echo "${run_url}/attempts/${attempt}"
		return
	fi

	if (( failing_count == 1 )); then
		echo "UI Tests re-run (attempt ${attempt}): ❌ 1 combination still failing"
	else
		echo "UI Tests re-run (attempt ${attempt}): ❌ ${failing_count} combinations still failing"
	fi
	echo "${run_url}/attempts/${attempt}"
	echo
	echo "Still failing:"
	awk -F'\t' -v attempt="${attempt}" '
		$2 == "fail" { print "• " $4 (($1 < attempt) ? " (not re-run in this attempt)" : "") }
	' <<< "${legs}"

	now_passing="$(awk -F'\t' '$3 == "pass" { print "• " $4 }' <<< "${legs}")"
	if [[ -n "${now_passing}" ]]; then
		echo
		echo "Now passing:"
		echo "${now_passing}"
	fi
}

description_suffix_text() {
	local legs=$1
	echo "Failing combinations:"
	awk -F'\t' '$2 == "fail" { print "• " $4 }' <<< "${legs}"
}

main() {
	local command
	local attempt
	local type
	local run_url
	local listing

	read_command_line_arguments "$@"
	listing="$(cat)"

	report
}

main "$@"
