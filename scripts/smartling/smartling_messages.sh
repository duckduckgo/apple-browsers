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
		$0 download <output_file> <platform> <job_id> <project_id> [success|no_changes|failed] [error_type]

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

	if [ "$result" = "success" ]; then
		cat > "$OUTPUT_FILE" <<- EOF
		## 🌍 Smartling Translation Job Created

		**Job ID:** \`$job_id\`
		**Platform:** $platform

		🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

		**Next:** Run workflow with:
		• Platform: \`$platform\`
		• Action: \`approve\`
		• Job ID: \`$job_id\`
		EOF
	else
		cat > "$OUTPUT_FILE" <<- EOF
		## ❌ Smartling Upload Failed

		**Platform:** $platform
		**Error:** Upload failed - check workflow logs

		**Next steps:**
		1. Check that export files exist by running the export locally
		2. Ensure Smartling credentials are configured
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

	if [ "$result" = "success" ]; then
		cat > "$OUTPUT_FILE" <<- EOF
		## ✅ Smartling Job Approved

		**Job ID:** \`$job_id\`
		**Platform:** $platform

		Translation has been authorized and is now in progress.

		🔗 **[View in Smartling Dashboard](https://dashboard.smartling.com/app/projects/$project_id/account-jobs/$project_id:$job_id)**

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

		**Next steps:**
		• Run workflow with \`status\` action to check current job status
		• Verify the job ID is correct
		• Check Smartling dashboard for job details
		EOF
	fi
}

generate_download_message() {
	local platform="$1"
	local job_id="$2"
	local project_id="$3"
	local result="${4:-success}"
	local error_type="${5:-}"

	case "$result" in
		"success")
			cat > "$OUTPUT_FILE" <<- EOF
			## ✅ Translations Downloaded Successfully

			**Job ID:** \`$job_id\`
			**Platform:** $platform

			Translations have been imported and committed to this branch.
			EOF
			;;
		"no_changes")
			cat > "$OUTPUT_FILE" <<- EOF
			## ℹ️ No Translation Changes

			**Job ID:** \`$job_id\`
			**Platform:** $platform

			No changes were found to import.
			EOF
			;;
		"failed")
			if [ "$error_type" = "deletions" ]; then
				cat > "$OUTPUT_FILE" <<- EOF
				## ❌ Translation Download Failed

				**Job ID:** \`$job_id\`
				**Platform:** $platform
				**Error:** Translation import would delete existing keys. This usually happens when the main branch was merged after translation started.

				**Next steps:**
				1. **Option A:** Force the import by running download with \`force=true\`
				2. **Option B:** Merge main into your branch and create a new translation job
				EOF
			else
				cat > "$OUTPUT_FILE" <<- EOF
				## ❌ Translation Download Failed

				**Job ID:** \`$job_id\`
				**Platform:** $platform
				**Error:** Download failed - check workflow logs

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