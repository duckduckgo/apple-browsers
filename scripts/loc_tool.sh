#!/bin/bash

set -euo pipefail

# Entry point for localization workflows
# Subcommands: upload | approve | status | download

# Location of the script
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# Location of the iOS scripts
IOS_SCRIPTS_DIR="$SCRIPT_DIR/../iOS/scripts"
# Location of the Swift CLI
TOOL_DIR="$SCRIPT_DIR/LocalizationTool"
# Location of the Swift CLI binary after building
TOOL_BIN="$TOOL_DIR/.build/release/localization-tool"
# Location of the XLIFF files
XLIFF_DIR="$IOS_SCRIPTS_DIR/assets/loc/en.xcloc/Localized Contents"
# Location of the stringsdict file
STRINGSDICT="$IOS_SCRIPTS_DIR/../DuckDuckGo/en.lproj/Localizable.stringsdict"

# Source the common functions
. "$SCRIPT_DIR/loc_export_common.sh"

usage() {
  cat <<EOF
Usage:
  $0 upload --job-name <name> --files <file1> [<file2> ...]
  $0 approve --job-id <id>
  $0 status --job-id <id>
  $0 download --job-id <id> [--out-dir <path>]
  $0 import --import-dir <path> [--force]

Requires env:
  SMARTLING_USER_ID, SMARTLING_USER_SECRET, SMARTLING_PROJECT_ID
EOF
}

cmd=${1:-}
shift || true

# Fail if credentials are missing
if [ -z "${SMARTLING_USER_ID:-}" ] || [ -z "${SMARTLING_USER_SECRET:-}" ] || [ -z "${SMARTLING_PROJECT_ID:-}" ]; then
  echo "Missing required env vars: SMARTLING_USER_ID, SMARTLING_USER_SECRET, SMARTLING_PROJECT_ID" >&2
  exit 1
fi

# Helper function to parse --job-id argument
parse_job_id() {
  if [ "$1" != "--job-id" ] || [ -z "${2:-}" ]; then
    echo "Usage: $0 $cmd --job-id <job-id>" >&2
    exit 1
  fi
  echo "$2"
}

# Build the Swift CLI once up-front for all commands
run_in_directory "$TOOL_DIR" swift build -c release >/dev/null

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

    # Run CLI
    CMD=("$TOOL_BIN" upload --job-name "$JOB_NAME" --files "${FILES[@]}")
    run_in_directory "$TOOL_DIR" "${CMD[@]}"
    ;;
  status)
    JOB_ID=$(parse_job_id "$@")
    
    # Run status check
    CMD=("$TOOL_BIN" status --job-id "$JOB_ID")
    run_in_directory "$TOOL_DIR" "${CMD[@]}"
    ;;
  approve)
    JOB_ID=$(parse_job_id "$@")
    
    # Run approval check
    CMD=("$TOOL_BIN" approve --job-id "$JOB_ID")
    run_in_directory "$TOOL_DIR" "${CMD[@]}"
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
      CMD=("$TOOL_BIN" download --job-id "$JOB_ID" --out-dir "$OUT_DIR")
    else
      CMD=("$TOOL_BIN" download --job-id "$JOB_ID")
    fi
    run_in_directory "$TOOL_DIR" "${CMD[@]}"
    ;;
  import)
    # Parse required --import-dir
    if [ "${1:-}" != "--import-dir" ] || [ -z "${2:-}" ]; then
      echo "Usage: $0 import --import-dir <path> [--force]" >&2
      exit 1
    fi
    IMPORT_DIR="$2"
    
    # Check for --force flag
    FORCE_FLAG=""
    if [ "${3:-}" = "--force" ]; then
      FORCE_FLAG="--force"
    fi
    
    # Run import
    if [ -n "$FORCE_FLAG" ]; then
      CMD=("$TOOL_BIN" import --import-dir "$IMPORT_DIR" --force)
    else
      CMD=("$TOOL_BIN" import --import-dir "$IMPORT_DIR")
    fi
    run_in_directory "$TOOL_DIR" "${CMD[@]}"
    ;;
  *)
    usage; exit 1;;
esac


