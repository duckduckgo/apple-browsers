#!/bin/bash
#
# build-memory-metrics.sh
#
# Extracts memory metrics from xcresult bundle and transforms them into
# averaged metrics JSON and SQL insert statements for ClickHouse reporting.
#
# Usage: build-memory-metrics.sh --runner <runner> --xcresult-path <path> --run-id <id> --branch <branch> --commit-hash <hash>
#
# Required:
#   --runner        - The runner identifier (e.g., "macos-15-xlarge")
#   --xcresult-path - Path to the .xcresult bundle
#   --run-id        - GitHub Actions run ID
#   --branch        - Git branch name
#   --commit-hash   - Git commit SHA
#
# Output:
#   - raw-metrics.json       - Raw metrics extracted from xcresult
#   - memory-metrics.json    - Transformed metrics with averages
#   - insert-statements.sql  - SQL INSERT statements for ClickHouse
#

set -euo pipefail

RUNNER=""
XCRESULT_PATH=""
RUN_ID=""
BRANCH=""
COMMIT_HASH=""

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
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$RUNNER" || -z "$XCRESULT_PATH" || -z "$RUN_ID" || -z "$BRANCH" || -z "$COMMIT_HASH" ]]; then
    echo "Error: All parameters are required"
    echo "Usage: $0 --runner <runner> --xcresult-path <path> --run-id <id> --branch <branch> --commit-hash <hash>"
    exit 1
fi

echo "Extracting metrics from: $XCRESULT_PATH"

# Extract raw metrics from xcresult
xcrun xcresulttool get test-results metrics \
    --path "$XCRESULT_PATH" \
    --compact > raw-metrics.json

# Transform to averaged metrics JSON for ClickHouse
jq --arg runner "$RUNNER" '[.[] | {
    test: .testIdentifier,
    runner: $runner,
    metrics: [.testRuns[0].metrics[] | {
        identifier: .identifier,
        displayName: .displayName,
        unit: .unitOfMeasurement,
        average: ((.measurements | add) / (.measurements | length))
    }]
}]' raw-metrics.json > memory-metrics.json

echo "=== Memory Metrics (Averaged) ==="
cat memory-metrics.json | jq .

# Generate SQL insert statements
echo ""
echo "Generating SQL insert statements..."

START_TIME=$(date -u '+%Y-%m-%d %H:%M:%S')

# Transform JSON to ClickHouse INSERT format
# Memory values are in MB, rounded to integer
jq -r --arg run_id "$RUN_ID" \
      --arg branch "$BRANCH" \
      --arg commit_hash "$COMMIT_HASH" \
      --arg start_time "$START_TIME" \
      --arg q "'" \
    '.[] | 
    (.metrics | map(select(.identifier | contains("initial"))) | .[0].average | floor) as $mem_start |
    (.metrics | map(select(.identifier | contains("final"))) | .[0].average | floor) as $mem_end |
    ($mem_end - $mem_start) as $mem_delta |
    "INSERT INTO native_apps.macos_performance_memory_test_results (run_id, runs_on, start_time, test_id, branch, commit_hash, memory_start, memory_end, memory_delta) VALUES (\($run_id), \($q)\(.runner)\($q), \($q)\($start_time)\($q), \($q)\(.test)\($q), \($q)\($branch)\($q), \($q)\($commit_hash)\($q), \($mem_start), \($mem_end), \($mem_delta));"
    ' memory-metrics.json > insert-statements.sql

echo "=== Generated SQL ==="
cat insert-statements.sql
