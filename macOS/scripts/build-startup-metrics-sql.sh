#!/bin/bash
#
# build-startup-metrics-sql.sh
#
# Extracts startup time metrics from xcresult bundle test
# attachments and generates SQL insert statements for ClickHouse
# reporting.
#
# Usage: build-startup-metrics-sql.sh --runner <runner> --xcresult-path <path> --suite <suite> --run-id <id> --branch <branch> --commit-hash <hash> --start-time <time>
#
# Required:
#   --runner        - The runner identifier (e.g., "macos-15-xlarge")
#   --xcresult-path - Path to the .xcresult bundle
#   --suite         - Test suite name to match (e.g., "StartupPerformanceTests")
#   --run-id        - GitHub Actions run ID
#   --branch        - Git branch name
#   --commit-hash   - Git commit SHA
#   --start-time    - Job start time (format: "YYYY-MM-DD HH:MM:SS")
#
# Output:
#   - stdout                 - SQL INSERT statements for ClickHouse
#

set -euo pipefail


# Parameters Validation
RUNNER=""
XCRESULT_PATH=""
SUITE=""
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
        --suite)
            SUITE="$2"
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

if [[ -z "$RUNNER" || -z "$XCRESULT_PATH" || -z "$SUITE" || -z "$RUN_ID" || -z "$BRANCH" || -z "$COMMIT_HASH" || -z "$START_TIME" ]]; then
    echo "Error: All parameters are required"
    echo "Usage: $0 --runner <runner> --xcresult-path <path> --suite <suite> --run-id <id> --branch <branch> --commit-hash <hash> --start-time <time>"
    exit 1
fi

echo "Extracting attachments from: $XCRESULT_PATH" >&2

# Step 1: Export attachments from xcresult
xcrun xcresulttool export attachments \
    --path "$XCRESULT_PATH" \
    --output-path "$SUITE" \
    --test-id "$SUITE" >&2

# Step 2: Read the manifest and collect all attachment contents with their test ID
manifest="$SUITE/manifest.json"
raw_metrics="$(jq -r '
    .[] |
    .testIdentifier as $test_id |
    .attachments[].exportedFileName |
    "\($test_id)\t\(.)"
' "$manifest" | while IFS=$'\t' read -r test_id filename; do
    jq --arg test_id "$test_id" '. + {test_id: ($test_id | split("/") | .[-1] | rtrimstr("()"))}' "$SUITE/$filename"
done | jq -s '.')"

rm -f "$manifest"

# Step 3: Format as SQL INSERT statements (output to stdout)
jq -r \
    --arg runner "$RUNNER" \
    --arg run_id "$RUN_ID" \
    --arg branch "$BRANCH" \
    --arg commit_hash "$COMMIT_HASH" \
    --arg start_time "$START_TIME" \
'
def sql_quote(v): "'\''" + v + "'\''";

.[] | "INSERT INTO native_apps.macos_performance_startup_time_test_results (
    run_id,
    runs_on,
    start_time,
    test_id,
    branch,
    commit_hash,
    session_restoration,
    windows,
    standard_tabs,
    pinned_tabs,
    app_delegate_init,
    main_menu_init,
    app_will_finish_launching,
    app_did_finish_launching_before_state_restoration,
    app_did_finish_launching_after_state_restoration,
    app_state_restoration,
    init_to_will_finish_launching,
    app_will_finish_to_did_finish_launching,
    time_to_interactive
) VALUES (
    \($run_id),
    \(sql_quote($runner)),
    \(sql_quote($start_time)),
    \(sql_quote(.test_id)),
    \(sql_quote($branch)),
    \(sql_quote($commit_hash)),
    \(.sessionRestoration),
    \(.windows),
    \(.standardTabs),
    \(.pinnedTabs),
    \(.appDelegateInit),
    \(.mainMenuInit),
    \(.appWillFinishLaunching),
    \(.appDidFinishLaunchingBeforeRestoration),
    \(.appDidFinishLaunchingAfterRestoration),
    \(.appStateRestoration),
    \(.appDelegateInitToWillFinishLaunching),
    \(.appWillFinishToDidFinishLaunching),
    \(.timeToInteractive)
);"
' <<< "$raw_metrics"
