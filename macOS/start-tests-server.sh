#!/bin/bash

# Starts tests-server in a watchdog subshell so unified logging records launch and exit,
# including SIGKILL which the Swift process cannot log itself.
# Intended to be invoked from Xcode scheme Test Pre-actions.
#
# Relies on xcodebuild variables:
#   BUILT_PRODUCTS_DIR         - location of the tests-server binary
#   METAL_LIBRARY_OUTPUT_DIR   - integration-test resources dir (used as cwd for file lookup)

os_log() {
    /usr/bin/logger -t tests-server -- "[tests-server] $*"
}

if [[ -z "${BUILT_PRODUCTS_DIR:-}" ]]; then
    echo "BUILT_PRODUCTS_DIR is not set" >&2
    os_log "🔴 BUILT_PRODUCTS_DIR is not set"
    exit 1
fi

server="${BUILT_PRODUCTS_DIR}/tests-server"
if [[ ! -x "${server}" ]]; then
    echo "tests-server not found or not executable at ${server}" >&2
    os_log "🔴 tests-server not found or not executable at ${server}"
    exit 1
fi

# Current work directory is used by tests-server for file lookup when no data= param is given.
if [[ -n "${METAL_LIBRARY_OUTPUT_DIR:-}" ]]; then
    cd "${METAL_LIBRARY_OUTPUT_DIR}" || {
        os_log "🔴 failed to cd to METAL_LIBRARY_OUTPUT_DIR=${METAL_LIBRARY_OUTPUT_DIR}"
        exit 1
    }
fi

killall tests-server 2>/dev/null || true

(
    os_log "watchdog launching ${server} cwd=$(pwd)"
    "${server}"
    status=$?
    if [[ "${status}" -eq 0 ]]; then
        os_log "watchdog: tests-server exited status=0"
    else
        os_log "🔴 watchdog: tests-server exited status=${status} (137=SIGKILL, 143=SIGTERM)"
    fi
) &

os_log "watchdog started, wrapper pid=$! cwd=$(pwd)"
