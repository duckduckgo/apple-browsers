#!/bin/bash

set -eo pipefail

workspace_id="137249556945"
project_id="1205237866452338"
workflow_id_custom_field_id="1205563320492190"
apple_team_id="1203552211911076"
asana_api_url="https://app.asana.com/api/1.0"
fallback_assignee_id="856498666990313" # (bwaresiak)

print_usage_and_exit() {
	local reason=$1

	cat <<- EOF
	Usage:
	  $ $(basename "$0") <create-task|close-task> [-h] [-t <title>] [-d <description>] [-m <closing_comment_message>]

	Actions:
	  create-task       Create a new task in Asana
	  close-task        Close an existing Asana task for the workflow ID provided in environment variable WORKFLOW_ID

	Options (only used for create-task):
	  -t <title>                    Asana task title
	  -d <description>              Asana task description
	  -m <closing_comment_message>  Closing comment message

	Note: This script is intended for CI use only. You shouldn't call it directly.
	EOF

	echo "${reason}"
	exit 1
}

read_command_line_arguments() {
	action="$1"
	case "${action}" in
		create-task)
			;;
		close-task)
			;;
		*)
			print_usage_and_exit "Unknown action '${action}'"
			;;
	esac

	shift 1

	case "${action}" in
		create-task)
			if (( $# < 2 )); then
				print_usage_and_exit "Missing arguments"
			fi
			;;
		close-task)
			if (( $# < 1 )); then
				print_usage_and_exit "Missing message argument"
			fi
			;;
	esac

	while getopts 'd:hm:t:' OPTION; do
		case "${OPTION}" in
			d)
				description="${OPTARG}"
				;;
			h)
				print_usage_and_exit
				;;
			m)
				message="${OPTARG}"
				;;
			t)
				title="${OPTARG}"
				;;
			*)
				print_usage_and_exit "Unknown option '${OPTION}'"
				;;
		esac
	done

	shift $((OPTIND-1))
}

create_task() {
	local task_name=$1
	local description
	local task_id
	local assignee_param
	description=$(sed -E -e 's/\\/\\\\/g' -e 's/"/\\"/g' <<< "$2")
	if [[ -n "${assignee}" ]]; then
		assignee_param="\"${assignee}\""
	else
		assignee_param="null"
	fi

	task_id=$(curl -X POST -s "${asana_api_url}/tasks?opt_fields=gid" \
		-H "Authorization: Bearer ${asana_personal_access_token}" \
		-H 'content-type: application/json' \
		-d "{
				\"data\": {
					\"assignee\": ${assignee_param},
					\"name\": \"${task_name}\",
					\"resource_subtype\": \"default_task\",
					\"notes\": \"${description}\",
					\"projects\": [
						\"${project_id}\"
					],
					\"custom_fields\": {
						\"${workflow_id_custom_field_id}\": \"${workflow_id}\"
					}
				}
			}" \
		| jq -r '.data.gid')

	return_code="$(curl -X POST -s "${asana_api_url}/sections/${section_id}/addTask" \
		-H "Authorization: Bearer ${asana_personal_access_token}" \
		-H 'content-type: application/json' \
		--write-out '%{http_code}' \
		--output /dev/null \
		-d "{\"data\": {\"task\": \"${task_id}\"}}")"

	[[ ${return_code} -eq 200 ]]
}

find_task_for_workflow_id() {
	local workflow_id=$1
	curl -s "${asana_api_url}/workspaces/${workspace_id}/tasks/search?opt_fields=gid&resource_subtype=default_task&projects.any=${project_id}&limit=1&custom_fields.${workflow_id_custom_field_id}.value=${workflow_id}" \
		-H "Authorization: Bearer ${asana_personal_access_token}" \
		| jq -r "if (.data | length) != 0 then .data[0].gid else empty end"
}

add_comment_to_task() {
	local task_id=$1
	local message
	local return_code
	message=$(sed -E -e 's/\\/\\\\/g' -e 's/"/\\"/g' <<< "$2")

	return_code="$(curl -X POST -s "${asana_api_url}/tasks/${task_id}/stories" \
		-H "Authorization: Bearer ${asana_personal_access_token}" \
		-H 'content-type: application/json' \
		--write-out '%{http_code}' \
		--output /dev/null \
		-d "{\"data\": {\"text\": \"${message}\"}}")"

	[[ ${return_code} -eq 201 ]]
}

close_task() {
	local task_id=$1
	local return_code

	return_code="$(curl -X PUT -s "${asana_api_url}/tasks/${task_id}" \
		-H "Authorization: Bearer ${asana_personal_access_token}" \
		-H 'content-type: application/json' \
		--write-out '%{http_code}' \
		--output /dev/null \
		-d "{\"data\": {\"completed\": true}}")"

	[[ ${return_code} -eq 200 ]]
}

validate_assignee() {
	local assignee=$1
	local pr_reviewers=$2

	if _is_user_in_apple_team "${assignee}"; then
		echo "${assignee}"
	else
		echo "Assignee $assignee not found in Apple team, checking PR reviewers" >&2

		# Check each PR reviewer if pr_reviewers is not empty
		if [[ -n "${pr_reviewers}" ]]; then
			gh_asana_mapping="$(gh api https://api.github.com/repos/duckduckgo/internal-github-asana-utils/contents/user_map.yml --jq .content | base64 -d)"

			# Split comma-separated reviewers and iterate through them
			IFS=',' read -ra reviewer_array <<< "${pr_reviewers}"
			for reviewer in "${reviewer_array[@]}"; do
				# Trim whitespace
				reviewer="$(echo "${reviewer}" | xargs)"
				reviewer_asana_id="$(yq -r ".${reviewer}" <<< "${gh_asana_mapping}")"
				echo "Checking reviewer: ${reviewer_asana_id}" >&2

				if _is_user_in_apple_team "${reviewer_asana_id}"; then
					echo "Found Apple team member reviewer: ${reviewer_asana_id}" >&2
					echo "${reviewer_asana_id}"
					return
				fi
			done
		fi

		echo "No Apple team members found among PR reviewers, using fallback" >&2
		echo "${fallback_assignee_id}"
	fi
}

_is_user_in_apple_team() {
	local user_id=$1

	curl -s "${asana_api_url}/teams/${apple_team_id}/users?opt_fields=gid" \
		-H "Authorization: Bearer ${asana_personal_access_token}" \
		| jq -e "any(.data[]?; .gid == \"${user_id}\")" > /dev/null
}

main() {
	local asana_personal_access_token="${ASANA_ACCESS_TOKEN}"
	local section_id="${ASANA_SECTION_ID}"
	local assignee="${ASANA_ASSIGNEE}"
	local workflow_id="${GITHUB_RUN_ID}"
	local pr_reviewers="${GITHUB_PR_REVIEWERS}"
	local action
	local title
	local description
	local message

	read_command_line_arguments "$@"

	case "${action}" in
		create-task)
			assignee="$(validate_assignee "${assignee}" "${pr_reviewers}")"
			create_task "${title}" "${description}" "${assignee}"
			;;
		close-task)
			task_id=$(find_task_for_workflow_id "${workflow_id}")
			if [[ -n "${task_id}" ]]; then
				add_comment_to_task "${task_id}" "${message}"
				close_task "${task_id}"
			else
				echo "No task found for workflow ID '${workflow_id}'"
			fi
			;;
		*)
			print_usage_and_exit "Unknown action '${action}'"
			;;
	esac
}

main "$@"
