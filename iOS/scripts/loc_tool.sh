#!/bin/sh

set -euo pipefail

# Entry point for localization workflows
# Subcommands: upload | approve | status | download

# Location of the script
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# Location of the iOS scripts
IOS_SCRIPTS_DIR="$SCRIPT_DIR"
# Location of the Swift CLI
TOOL_DIR="$IOS_SCRIPTS_DIR/LocalizationTool"
# Location of the Swift CLI binary after building
TOOL_BIN="$TOOL_DIR/.build/release/localization-tool"
# Location of the XLIFF files
XLIFF_DIR="$IOS_SCRIPTS_DIR/assets/loc/en.xcloc/Localized Contents"
# Location of the stringsdict file
STRINGSDICT="$IOS_SCRIPTS_DIR/../DuckDuckGo/en.lproj/Localizable.stringsdict"

# Source the common functions
. "$SCRIPT_DIR/../../scripts/loc_export_common.sh"

usage() {
  cat <<EOF
Usage:
  $0 upload
  $0 approve --job-id <id>
  $0 status --job-id <id>
  $0 download --job-id <id> [--out-dir <path>]

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

# Build the Swift CLI once up-front for all commands
run_in_directory "$TOOL_DIR" swift build -c release >/dev/null

case "$cmd" in
  upload)
    # Export XLIFF
    # NO_OPEN will prevent opening Finder
    NO_OPEN=1 "$IOS_SCRIPTS_DIR/loc_export.sh"
    
    XLIFF=$(ls -1 "$XLIFF_DIR"/*.xliff 2>/dev/null | head -n 1 || true)
    [ -n "$XLIFF" ] || { echo "No .xliff found in $XLIFF_DIR" >&2; exit 1; }

    echo "[loc_tool] Using XLIFF: $XLIFF"
    echo "[loc_tool] Using STRINGSDICT: $STRINGSDICT"

    # Run CLI
    # Use the current git branch as the job name
    JOB_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    CMD=("$TOOL_BIN" upload --job-name "$JOB_NAME" --xliff "$XLIFF" --stringsdict "$STRINGSDICT")
    run_in_directory "$TOOL_DIR" "${CMD[@]}"
    ;;
  *)
    usage; exit 1;;
esac


