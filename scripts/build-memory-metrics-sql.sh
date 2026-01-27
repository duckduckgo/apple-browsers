#!/bin/bash
#
# build-memory-metrics-sql.sh
#
# Extracts memory metrics from xcresult bundle and generates
# SQL insert statements for ClickHouse reporting.
#
# Usage: build-memory-metrics-sql.sh --runner <runner> --xcresult-path <path> --run-id <id> --branch <branch> --commit-hash <hash> --start-time <time>
#
# Required:
#   --runner        - The runner identifier (e.g., "macos-15-xlarge")
#   --xcresult-path - Path to the .xcresult bundle
#   --run-id        - GitHub Actions run ID
#   --branch        - Git branch name
#   --commit-hash   - Git commit SHA
#   --start-time    - Job start time (format: "YYYY-MM-DD HH:MM:SS")
#
# Output:
#   - raw-metrics.json       - Raw metrics extracted from xcresult (file)
#   - processed-metrics.json - Calculated memory metrics (file)
#   - stdout                 - SQL INSERT statements for ClickHouse
#

set -euo pipefail

RUNNER=""
XCRESULT_PATH=""
RUN_ID=""
BRANCH=""
COMMIT_HASH=""
START_TIME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --runner)
            RUNNER="$2"
            shift 2
            ;;
        --xcresult-path)
            XCRESULT_PATH="$2"
            shift 2
            ;;
        --run-id)
            RUN_ID="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --commit-hash)
            COMMIT_HASH="$2"
            shift 2
            ;;
        --start-time)
            START_TIME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$RUNNER" || -z "$XCRESULT_PATH" || -z "$RUN_ID" || -z "$BRANCH" || -z "$COMMIT_HASH" || -z "$START_TIME" ]]; then
    echo "Error: All parameters are required"
    echo "Usage: $0 --runner <runner> --xcresult-path <path> --run-id <id> --branch <branch> --commit-hash <hash> --start-time <time>"
    exit 1
fi

echo "Extracting metrics from: $XCRESULT_PATH" >&2

# Extract raw metrics from xcresult
xcrun xcresulttool get test-results metrics \
    --path "$XCRESULT_PATH" \
    --compact > raw-metrics.json

# Extract and calculate memory metrics (values in MB, rounded to integer)
jq '[.[] |
    {
        test_id: .testIdentifier,
        memory_start: (.testRuns[0].metrics | map(select(.identifier | contains("initial"))) | .[0].measurements | (add / length) | floor),
        memory_end: (.testRuns[0].metrics | map(select(.identifier | contains("final"))) | .[0].measurements | (add / length) | floor)
    } |
    . + { memory_delta: (.memory_end - .memory_start) }
]' raw-metrics.json > processed-metrics.json

# Format as SQL INSERT statements (output to stdout)
jq -r --arg runner "$RUNNER" \
      --arg run_id "$RUN_ID" \
      --arg branch "$BRANCH" \
      --arg commit_hash "$COMMIT_HASH" \
      --arg start_time "$START_TIME" \
      --arg q "'" \
    '.[] |
    "INSERT INTO native_apps.macos_performance_memory_test_results
        (run_id, runs_on, start_time, test_id, branch, commit_hash, memory_start, memory_end, memory_delta)
    VALUES
        (\($run_id), \($q)\($runner)\($q), \($q)\($start_time)\($q), \($q)\(.test_id)\($q), \($q)\($branch)\($q), \($q)\($commit_hash)\($q), \(.memory_start), \(.memory_end), \(.memory_delta));"
    ' processed-metrics.json
