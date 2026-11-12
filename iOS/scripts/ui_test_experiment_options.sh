#!/bin/bash
# Source in the caller and worker so invalid experiments fail before building or testing.
UI_TEST_EXECUTION_MODE=${UI_TEST_EXECUTION_MODE:-retry}
UI_TEST_ITERATIONS=${UI_TEST_ITERATIONS:-2}
APP_LOCK_RELAUNCH_GAP=${APP_LOCK_RELAUNCH_GAP:-0}
APP_LOCK_DISABLE_ANIMATIONS=${APP_LOCK_DISABLE_ANIMATIONS:-false}
SIMULATOR_LOG_LEVEL=${SIMULATOR_LOG_LEVEL:-debug}
UI_TEST_JOB_CAP=${UI_TEST_JOB_CAP:-default}

case "$UI_TEST_EXECUTION_MODE" in
  retry|repeat-all) ;;
  *) echo "::error::execution_mode must be retry or repeat-all."; return 1 ;;
esac
case "$UI_TEST_ITERATIONS" in
  [1-9]|1[0-9]|20) ;;
  *) echo "::error::iterations must be an integer from 1 to 20."; return 1 ;;
esac
case "$APP_LOCK_RELAUNCH_GAP" in
  0|1|2|5) ;;
  *) echo "::error::app_lock_relaunch_gap must be 0, 1, 2, or 5 seconds."; return 1 ;;
esac
case "$APP_LOCK_DISABLE_ANIMATIONS" in
  true|false) ;;
  *) echo "::error::app_lock_disable_animations must be true or false."; return 1 ;;
esac
case "$SIMULATOR_LOG_LEVEL" in
  debug) simulator_log_mode=level:debug,persist:debug ;;
  info) simulator_log_mode=level:info,persist:default ;;
  *) echo "::error::simulator_log_level must be debug or info."; return 1 ;;
esac
case "$UI_TEST_JOB_CAP" in
  default|8) production_parallel=8; internal_parallel=4 ;;
  1|4) production_parallel=$UI_TEST_JOB_CAP; internal_parallel=$UI_TEST_JOB_CAP ;;
  *) echo "::error::job_cap must be default, 1, 4, or 8."; return 1 ;;
esac
repetition_args=(-test-iterations "$UI_TEST_ITERATIONS")
if [[ "$UI_TEST_EXECUTION_MODE" == retry ]]; then
  repetition_args+=(-retry-tests-on-failure)
fi
repetition_args+=(-test-repetition-relaunch-enabled YES)
