#!/bin/bash
set -euo pipefail

# Smartling Message Generator
# Generates PR comment messages for Smartling workflow actions
# Usage: ./smartling_messages.sh <action> <output_file> [parameters...]

ACTION="$1"
OUTPUT_FILE="$2"
shift 2

usage() {
	cat <<- EOF
	Usage:
		$0 upload <output_file> <platform> <job_id> <project_id> [success|failed]
		$0 status <output_file> <platform> <job_id> <project_id> <status> <percent>
		$0 approve <output_file> <platform> <job_id> <project_id> [success|failed]
		$0 download <output_file> <platform> <job_id> <project_id> [success|no_changes|failed|deletions_pr_created] [error_type|branch_name]

	Actions:
		upload   - Generate upload result message
		status   - Generate job status message
		approve  - Generate approval result message
		download - Generate download result message
	EOF
}

generate_upload_message() {
	local platform="$1"
	local job_id="$2"
	local project_id="$3"
	local result="${4:-success}"
	local workflow_url="${WORKFLOW_URL:-}"
	local upload_scope="${SMARTLING_UPLOAD_SCOPE:-full}"
	local scoped_unit_count="${SCOPED_UNIT_COUNT:-}"

	# Build scope info line
	local scope_info="**Upload scope:** \`$upload_scope\`"
	if [ "$upload_scope" = "scoped" ] && [ -n "$scoped_unit_count" ]; then
		scope_info="$scope_info ($scoped_unit_count translation unit(s))"
	fi

	if [ "$result" = "success" ]; then
		cat > "$OUTPUT_FILE" <<- EOF
		## 🌍 Smartling Translation Job Created

		**Job ID:** \`$job_id\`
		**Platform:** $platform
		$scope_info

		🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

		${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}

		**Next:**
		* Review translation job
		$(if [ "$upload_scope" = "scoped" ]; then
			echo "* Authorize translation by adding the \`authorize translation experimental\` label"
		else
			echo "* Authorize translation by adding the \`authorize translation\` label"
		fi)
		EOF
	else
		cat > "$OUTPUT_FILE" <<- EOF
		## ❌ Smartling Upload Failed

		**Platform:** $platform
		$scope_info
		**Error:** Upload failed - check workflow logs

		${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}

		**Next steps:**
		1. Check that export files exist by running the export locally
		2. Ensure that there is no existing translation job for this platform and branch
		3. Re-run the workflow with \`upload\` action
		EOF
	fi
}

generate_status_message() {
	local platform="$1"
	local job_id="$2"
	local project_id="$3"
	local status="$4"
	local percent="$5"
	local workflow_url="${WORKFLOW_URL:-}"

	# Choose emoji based on status
	local emoji="🔄"
	case "$status" in
		"COMPLETED") emoji="✅" ;;
		"IN_PROGRESS") emoji="⏳" ;;
		"AWAITING_AUTHORIZATION") emoji="⏸️" ;;
	esac

	cat > "$OUTPUT_FILE" <<- EOF
	## $emoji Smartling Job Status

	**Job ID:** \`$job_id\`
	**Platform:** $platform
	**Status:** $status
	**Progress:** $percent%

	🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**
	${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}
	EOF

	# Add download suggestion if completed
	if [ "$status" = "COMPLETED" ]; then
		cat >> "$OUTPUT_FILE" <<- EOF

		**Next:** Download translations with:
		• Platform: \`$platform\`
		• Action: \`download\`
		• Job ID: \`$job_id\`
		EOF
	fi
}

generate_approve_message() {
	local platform="$1"
	local job_id="$2"
	local project_id="$3"
	local result="${4:-success}"
	local workflow_url="${WORKFLOW_URL:-}"

	if [ "$result" = "success" ]; then
		cat > "$OUTPUT_FILE" <<- EOF
		## ✅ Smartling Job Approved

		**Job ID:** \`$job_id\`
		**Platform:** $platform

		Translation has been authorized and is now in progress.

		🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

		${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}

		**Next:** Check status with:
		• Platform: \`$platform\`
		• Action: \`status\`
		• Job ID: \`$job_id\`
		EOF
	else
		cat > "$OUTPUT_FILE" <<- EOF
		## ❌ Smartling Approval Failed

		**Job ID:** \`$job_id\`
		**Platform:** $platform
		**Error:** Approval failed - check workflow logs

		🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

		${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}

		**Next steps:**
		• Verify the job ID is correct
		• Check if job has content to translate
		EOF
	fi
}

generate_download_message() {
	local platform="$1"
	local job_id="$2"
	local project_id="$3"
	local result="${4:-success}"
	local extra_param="${5:-}"
	local workflow_url="${WORKFLOW_URL:-}"

	case "$result" in
		"success")
			cat > "$OUTPUT_FILE" <<- EOF
			## ✅ Translations Downloaded Successfully

			**Job ID:** \`$job_id\`
			**Platform:** $platform

			🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

			${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}

			Translations have been imported and committed to this branch.
			EOF
			;;
		"no_changes")
			cat > "$OUTPUT_FILE" <<- EOF
			## ℹ️ No Translation Changes

			**Job ID:** \`$job_id\`
			**Platform:** $platform

			🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

			${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}

			No changes were found to import.
			EOF
			;;
		"deletions_pr_created")
			local branch_name="$extra_param"
			local pr_info=""
			if [ -f "deletions_pr_info.txt" ]; then
				# Source the PR info
				source deletions_pr_info.txt
				pr_info="🔗 **[Review the changes in PR #$PR_NUMBER]($PR_URL)**"
			fi

			cat > "$OUTPUT_FILE" <<- EOF
			## ⚠️ Translation PR Created for Review

			**Job ID:** \`$job_id\`
			**Platform:** $platform

			🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

			${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}

			⚠️ **Translations contain deletions or significant changes** that could result in data loss.

			Instead of applying these changes directly, a separate PR has been created for manual review:

			$pr_info

			**What to do next:**
			1. Review the changes in the PR linked above
			2. Verify that any deletions are intentional
			3. Test the changes to ensure functionality is preserved
			4. Merge the review PR if the changes are acceptable

			The current branch remains unchanged to prevent data loss.
			EOF
			;;
		"failed")
			if [ "$extra_param" = "deletions" ]; then
				cat > "$OUTPUT_FILE" <<- EOF
				## ❌ Translation Download Failed

				**Job ID:** \`$job_id\`
				**Platform:** $platform
				**Error:** Translation import would delete existing keys. This usually happens when the main branch was merged after translation started.

				🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

				${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}

				**Next steps:**
				1. **Option A:** Merge main into your branch and create a new translation job
				2. **Option B:** Review the changes manually to ensure they are correct
				EOF
			else
				cat > "$OUTPUT_FILE" <<- EOF
				## ❌ Translation Download Failed

				**Job ID:** \`$job_id\`
				**Platform:** $platform
				**Error:** Download failed - check workflow logs

				🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

				${workflow_url:+🔧 **[View Workflow Run]($workflow_url)**}

				**Next steps:**
				• Verify the job ID is correct
				• Check the workflow logs for more details
				EOF
			fi
			;;
	esac
}

# Main execution
case "$ACTION" in
	upload)
		if [ $# -lt 3 ]; then
			echo "Error: upload requires platform, job_id, project_id [result]" >&2
			usage
			exit 1
		fi
		generate_upload_message "$@"
		;;
	status)
		if [ $# -lt 5 ]; then
			echo "Error: status requires platform, job_id, project_id, status, percent" >&2
			usage
			exit 1
		fi
		generate_status_message "$@"
		;;
	approve)
		if [ $# -lt 3 ]; then
			echo "Error: approve requires platform, job_id, project_id [result]" >&2
			usage
			exit 1
		fi
		generate_approve_message "$@"
		;;
	download)
		if [ $# -lt 3 ]; then
			echo "Error: download requires platform, job_id, project_id [result] [error_type]" >&2
			usage
			exit 1
		fi
		generate_download_message "$@"
		;;
	*)
		echo "Error: Unknown action '$ACTION'" >&2
		usage
		exit 1
		;;
esac

echo "✅ Message written to $OUTPUT_FILE"