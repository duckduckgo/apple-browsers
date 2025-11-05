#!/bin/bash

set -euo pipefail

# Entry point for localization workflows
# Subcommands: upload | approve | status | download

# Location of the script
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# Source the common functions
. "$SCRIPT_DIR/../loc_export_common.sh"

usage() {
	cat <<- EOF
	Usage:
		$0 upload --job-name <name> --files <file1> [<file2> ...]
		$0 approve --job-id <id>
		$0 status --job-id <id>
		$0 download --job-id <id> [--out-dir <path>]

	Requires env:
		SMARTLING_USER_ID, SMARTLING_USER_SECRET, SMARTLING_PROJECT_ID
	EOF
}

cmd=${1:-}
shift || true

# Helper function to parse --job-id argument
parse_job_id() {
	if [ "$1" != "--job-id" ] || [ -z "${2:-}" ]; then
		echo "Usage: $0 $cmd --job-id <job-id>" >&2
		exit 1
	fi
	echo "$2"
}

# Python tool path
PYTHON_TOOL="$SCRIPT_DIR/localization_tool.py"

case "$cmd" in
	upload)
		# Parse required arguments
		JOB_NAME=""
		FILES=()

		while [ $# -gt 0 ]; do
			case "$1" in
				--job-name)
					JOB_NAME="$2"
					shift 2
					;;
				--files)
					shift
					# Collect all files until next option or end
					while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
						FILES+=("$1")
						shift
					done
					;;
				*)
					echo "Unknown option: $1" >&2
					usage
					exit 1
					;;
			esac
		done

		# Validate required arguments
		if [ -z "$JOB_NAME" ] || [ ${#FILES[@]} -eq 0 ]; then
			echo "Usage: $0 upload --job-name <name> --files <file1> [<file2> ...]" >&2
			exit 1
		fi

		# Validate file paths
		for file in "${FILES[@]}"; do
			[ -f "$file" ] || { echo "File not found: $file" >&2; exit 1; }
		done

		echo "[loc_tool] Job name: $JOB_NAME"
		echo "[loc_tool] Files to upload:"
		for file in "${FILES[@]}"; do
			echo "  - $file"
		done

		# Run Python CLI
		python3 "$PYTHON_TOOL" upload --job-name "$JOB_NAME" --files "${FILES[@]}"
		;;
	status)
		JOB_ID=$(parse_job_id "$@")

		# Run status check
		python3 "$PYTHON_TOOL" status --job-id "$JOB_ID"
		;;
	approve)
		JOB_ID=$(parse_job_id "$@")

		# Run approval check
		python3 "$PYTHON_TOOL" approve --job-id "$JOB_ID"
		;;
	download)
		JOB_ID=$(parse_job_id "$@")

		# Parse optional output directory
		OUT_DIR=""
		if [ "${3:-}" = "--out-dir" ] && [ -n "${4:-}" ]; then
			OUT_DIR="$4"
		fi

		# Run download
		if [ -n "$OUT_DIR" ]; then
			python3 "$PYTHON_TOOL" download --job-id "$JOB_ID" --out-dir "$OUT_DIR"
		else
			python3 "$PYTHON_TOOL" download --job-id "$JOB_ID"
		fi
		;;
	*)
		usage; exit 1;;
esac


