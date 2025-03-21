#!/bin/bash

set -e

#
# Output passed arguments to stderr and exit.
#
die() {
	cat >&2 <<< "$*"
	exit 1
}

print_usage_and_exit() {
	local reason=$1

	cat <<- EOF
	Usage:
	  $ $(basename "$0") [-b <BSK-branch>] [-i <iOS-branch>] [-m <macOS-branch>] [-a <asana-task-url] [-t <PR-title>] [-y]

	Options:
	 -b <BSK-branch>     BSK branch to create the PR from (current branch is used if not provided)
	 -h                  Print this message
	 -i <iOS-branch>     iOS branch to create the PR from
	 -m <macOS-branch>   macOS branch to create the PR from
	 -a <asana-task-url> Asana Task URL
	 -t <PR-title>       Pull request title
	 -y                  Don't ask for confirmation
	EOF

	die "${reason}"
}

read_command_line_arguments() {
	while getopts 'a:b:hi:m:t:y' OPTION; do
		case "${OPTION}" in
			a)
				asana_task_url="${OPTARG}"
				;;
			b)
				bsk_branch="${OPTARG}"
				;;
			h)
				print_usage_and_exit
				;;
			i)
				ios_branch="${OPTARG}"
				;;
			m)
				macos_branch="${OPTARG}"
				;;
			t)
				pr_title="${OPTARG}"
				;;
			y)
				dont_ask=1
				;;
			*)
				print_usage_and_exit "Unknown option '${OPTION}'"
				;;
		esac
	done

	shift $((OPTIND-1))
}

read_arguments_as_needed() {
	if [[ -z "$bsk_branch" ]]; then
		local current_branch
		current_branch="$(git rev-parse --abbrev-ref HEAD)"
		read -rp "Name of the BSK branch (press Enter to use ${current_branch}): " bsk_branch
		if [[ -z "$bsk_branch" ]]; then
			bsk_branch="$current_branch"
		fi
	fi

	if [[ -z "$ios_branch" ]]; then
		read -rp "Name of the iOS branch (press Enter to use ${bsk_branch}): " ios_branch
		if [[ -z "$ios_branch" ]]; then
			ios_branch="$bsk_branch"
		fi
	fi

	if [[ -z "$macos_branch" ]]; then
		read -rp "Name of the macOS branch (press Enter to use ${ios_branch}): " macos_branch
		if [[ -z "$macos_branch" ]]; then
			macos_branch="$ios_branch"
		fi
	fi

	if [[ -z "$asana_task_url" ]]; then
	    local task_url_regex='^https://app.asana.com/[0-9]/[0-9]*/[0-9]*$'
        while ! [[ "$asana_task_url" =~ ${task_url_regex} ]]; do
			read -rp "Asana task URL: " asana_task_url
        done
	fi

	while [[ -z "$pr_title" ]]; do
		read -rp "Pull request title (will be set to all 3 PRs): " pr_title
	done
}

show_summary() {
	cat <<- EOF

	The script will:
	    * create Draft pull requests for the following branches:
	        * BSK: $bsk_branch
	        * iOS: $ios_branch
	        * macOS: $macos_branch
		* set pull requests' titles to "${pr_title}"
		* assign pull requests to yourself
	    * post the comment with links to PRs to Asana task at $asana_task_url

	EOF

	if [[ -z $dont_ask ]]; then
		local ans="N"
		printf '%s' "Continue? (y/N) "
		read -rsn1 ans
		echo

		if [[ "$ans" != "y" ]]; then
			exit 1
		fi
	fi
}

create_prs() {
	gh workflow run create-prs.yml \
		--ref "$bsk_branch" \
		-f ios-branch="$ios_branch" \
		-f macos-branch="$macos_branch" \
		-f asana-task-url="$asana_task_url" \
		-f pr-title="$pr_title" \
		-f token="$(gh auth token)"
}

main() {
	read_command_line_arguments "$@"

	echo "This script will automatically create Pull Requests for BSK, iOS and macOS repositories."
	if [[ -z "$bsk_branch" || -z "$ios_branch" || -z "$macos_branch" || -z "$asana_task_url" ]]; then
		cat <<- EOF
		Before you continue, ensure that:
		    * you have branches for all 3 repositories ready and pushed to remote.
		    * you have the link to the relevant Asana task.

		EOF
	fi

	read_arguments_as_needed
	show_summary

	create_prs
}

main "$@"