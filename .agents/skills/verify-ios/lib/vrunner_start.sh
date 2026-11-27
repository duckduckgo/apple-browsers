#!/bin/bash
# Start the verify-ios XCUITest runner on one simulator and wait until it answers.
# usage: VRUNNER_TOKEN=<token> vrunner_start.sh <udid> <port> <path/to/VRunner-iOS_*.xctestrun> <log dir> <pid file>
# The token comes from the environment and goes to curl on stdin, so it never shows in `ps`.
# The xcodebuild pid is written to <pid file> before waiting, so a caller that is cancelled mid-start can still stop it.
# Prints one JSON line with the pids it started (xcodebuild and its DTServiceHub children); the driver records them.
set -u
UDID=$1; PORT=$2; XTR=$3; LOGS=$4; PIDFILE=$5
mkdir -p "$LOGS"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$LOGS/runner-$UDID-$STAMP.log"
RB="$LOGS/runner-$UDID-$STAMP.xcresult"
T0=$(date +%s)
# -collect-test-diagnostics never: avoids a multi-minute `simctl diagnose` when the test ends
TEST_RUNNER_VRUNNER_TOKEN=$VRUNNER_TOKEN TEST_RUNNER_VRUNNER_PORT=$PORT TEST_RUNNER_VRUNNER_BUNDLE=com.duckduckgo.mobile.ios nohup xcodebuild test-without-building \
  -xctestrun "$XTR" -destination "platform=iOS Simulator,id=$UDID" -only-testing VRunnerUITests-iOS/VRunner/testServe \
  -collect-test-diagnostics never -resultBundlePath "$RB" > "$LOG" 2>&1 &
PID=$!
echo "$PID" > "$PIDFILE"
for _ in $(seq 1 240); do
  if printf '{"op":"ping","token":"%s"}' "$VRUNNER_TOKEN" | curl -s -m 1 -X POST --data-binary @- "http://127.0.0.1:$PORT/" 2>/dev/null | grep -q '"ok":true'; then
    HUBS=$(pgrep -P $PID DTServiceHub | awk '{printf "%s\"%s\"", (NR>1?",":""), $1}')
    echo "{\"ok\":true,\"xcodebuildPid\":$PID,\"hubPids\":[$HUBS],\"port\":$PORT,\"readySecs\":$(( $(date +%s) - T0 )),\"log\":\"$LOG\"}"
    exit 0
  fi
  ps -p $PID >/dev/null || break
  sleep 0.5
done
echo "{\"ok\":false,\"xcodebuildPid\":$PID,\"hubPids\":[],\"port\":$PORT,\"log\":\"$LOG\"}"
exit 1
