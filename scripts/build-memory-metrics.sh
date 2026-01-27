#!/bin/bash
#
# build-memory-metrics.sh
#
# Extracts memory metrics from xcresult bundle and transforms them into
# averaged metrics JSON suitable for ClickHouse reporting.
#
# Usage: extract-memory-metrics.sh <runner> <xcresult-path>
#
# Arguments:
#   runner        - The runner identifier (e.g., "macos-26-xlarge")
#   xcresult-path - Path to the .xcresult bundle
#
# Output:
#   - raw-metrics.json    - Raw metrics extracted from xcresult
#   - memory-metrics.json - Transformed metrics with averages
#

set -euo pipefail

RUNNER="${1:-}"
XCRESULT_PATH="${2:-}"

if [[ -z "$RUNNER" || -z "$XCRESULT_PATH" ]]; then
    echo "Error: runner and xcresult-path arguments are required"
    echo "Usage: $0 <runner> <xcresult-path>"
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
