#!/bin/zsh

set -eu

start_epoch=$(date +%s)
script_dir=${0:A:h}
fixture_dir="$script_dir/fixtures"
requested_fixture_port=${PROMO_QUEUE_FIXTURE_PORT:-0}
device_id=${PROMO_QUEUE_DEVICE_ID:-}
run_stamp=$(date -u +%Y%m%dT%H%M%SZ)
artifact_root=${PROMO_QUEUE_ARTIFACT_ROOT:-"$script_dir/artifacts/$run_stamp"}
server_log="$artifact_root/fixture-server.log"
run_log="$artifact_root/run.log"
server_pid=""
server_state_dir=""
ready_file=""

finish() {
    exit_status=$?
    trap - EXIT INT TERM

    if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    if [[ -n "$ready_file" ]]; then
        rm -f "$ready_file"
    fi
    if [[ -n "$server_state_dir" ]]; then
        rmdir "$server_state_dir" 2>/dev/null || true
    fi

    elapsed_seconds=$(( $(date +%s) - start_epoch ))
    if [[ -d "$artifact_root" ]]; then
        {
            print -- "Elapsed seconds: $elapsed_seconds"
            print -- "Exit status: $exit_status"
        } | tee -a "$run_log"
    else
        print -- "Elapsed seconds: $elapsed_seconds"
        print -- "Exit status: $exit_status"
    fi
    exit "$exit_status"
}

interrupted() {
    exit 130
}

terminated() {
    exit 143
}

trap finish EXIT
trap interrupted INT
trap terminated TERM

if [[ -z "$device_id" ]]; then
    print -u2 -- "PROMO_QUEUE_DEVICE_ID must identify the dedicated simulator."
    exit 2
fi

if (( $# == 0 )); then
    print -u2 -- "Usage: PROMO_QUEUE_DEVICE_ID=<uuid> $0 <flow-or-directory> [...]"
    exit 2
fi

mkdir -p "$artifact_root/maestro-debug" "$artifact_root/screenshots"

metrics_fixture="$fixture_dir/remote-messaging-config-metrics.json"
whats_new_fixture="$fixture_dir/remote-messaging-config-cards-list-items.json"
expected_metrics_hash="c9f594ca2446f29455b107580b7438428365fb149ccf110c207404f5b60b7451"
expected_whats_new_hash="5755daedac5b7c6062fd2c4b0e22cf70759c676926ca97474eb988c9696e044d"
actual_metrics_hash=$(shasum -a 256 "$metrics_fixture" | awk '{print $1}')
actual_whats_new_hash=$(shasum -a 256 "$whats_new_fixture" | awk '{print $1}')

if [[ "$actual_metrics_hash" != "$expected_metrics_hash" ]]; then
    print -u2 -- "Pinned NTP RMF fixture checksum mismatch: $actual_metrics_hash"
    exit 1
fi
if [[ "$actual_whats_new_hash" != "$expected_whats_new_hash" ]]; then
    print -u2 -- "Pinned What's New fixture checksum mismatch: $actual_whats_new_hash"
    exit 1
fi

server_state_dir=$(mktemp -d "${TMPDIR:-/tmp}/promo-queue-fixtures.XXXXXX")
ready_file="$server_state_dir/port"
python3 "$script_dir/fixture_server.py" \
    --directory "$script_dir" \
    --port "$requested_fixture_port" \
    --ready-file "$ready_file" >"$server_log" 2>&1 &
server_pid=$!

for _ in {1..50}; do
    if [[ -s "$ready_file" ]]; then
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        print -u2 -- "Fixture server exited before publishing its port. See $server_log"
        exit 1
    fi
    sleep 0.1
done

if [[ ! -s "$ready_file" ]]; then
    print -u2 -- "Fixture server did not publish its port. See $server_log"
    exit 1
fi

fixture_port=$(<"$ready_file")

rmf_url="http://127.0.0.1:$fixture_port/fixtures/remote-messaging-config-metrics.json"
whats_new_url="http://127.0.0.1:$fixture_port/fixtures/remote-messaging-config-cards-list-items.json"
page_url="http://127.0.0.1:$fixture_port/fixtures/normal-page.html"
suggestion_url="http://127.0.0.1:$fixture_port/fixtures/suggestion-page.html"

for fixture_url in "$rmf_url" "$whats_new_url"; do
    ready=false
    for _ in {1..50}; do
        if curl --fail --silent --show-error "$fixture_url" | python3 -m json.tool >/dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 0.1
    done
    if [[ "$ready" != true ]]; then
        print -u2 -- "Fixture URL did not return valid JSON: $fixture_url"
        exit 1
    fi
done

command=(
    maestro --udid "$device_id" test
    --debug-output "$artifact_root/maestro-debug"
    --test-output-dir "$artifact_root/screenshots"
    -e "PROMO_QUEUE_RMF_URL=$rmf_url"
    -e "PROMO_QUEUE_WHATS_NEW_URL=$whats_new_url"
    -e "PROMO_QUEUE_PAGE_URL=$page_url"
    -e "PROMO_QUEUE_SUGGESTION_URL=$suggestion_url"
    -e "PROMO_QUEUE_ARTIFACTS=$artifact_root/screenshots"
    "$@"
)

{
    print -- "NTP RMF fixture: $rmf_url"
    print -- "What's New fixture: $whats_new_url"
    print -- "Normal page: $page_url"
    print -- "Suggestion page: $suggestion_url"
    print -- "Fixture server log: $server_log"
    print -- "Maestro artifacts: $artifact_root"
    print -- "Verified NTP RMF SHA-256: $actual_metrics_hash"
    print -- "Verified What's New SHA-256: $actual_whats_new_hash"
    print -r -- "Command: ${(q)command}"
    "${command[@]}"
} 2>&1 | tee "$run_log"
exit "${pipestatus[1]}"
