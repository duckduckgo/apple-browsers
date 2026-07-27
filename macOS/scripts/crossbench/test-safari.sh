#!/usr/bin/env bash
#
# test-safari.sh — measure Safari navigation-to-LCP against Web Page Replay.
#
# Safari has no command-line host remapping, and safaridriver does not honor the
# WebDriver proxy capability. During this run only, Safari's per-app HTTP and
# HTTPS proxy preferences point to a local forward proxy:
#
#   Safari -> httpproxy.py -> tsproxy -> WPR
#
# This does not modify the macOS system proxy. Any pre-existing values for both
# Safari preference keys are captured before mutation and restored on normal
# exit or a signal; absent keys are deleted again. Existing non-string values
# are rejected before mutation because they cannot be restored losslessly with
# the `defaults` command.
#
# WPR uses its P-256 ECDSA key pair and --no-archive-certificates. WebDriver
# requests acceptInsecureCerts=true, so no WPR certificate is installed in or
# trusted by any keychain.
#
# Traffic shaping defaults to the Windows/Chrome US-broadband profile: 28 ms
# RTT, 50,000 Kbps down, 10,000 Kbps up, TCP window 10. Every load is measured;
# replay needs no DNS/CDN warm-up. An unavailable archive never causes a live
# network fallback.
#
# Prerequisites: run provision-macos.sh and enable Safari remote automation.
#
# Usage:
#   ./test-safari.sh [--sites a.com,b.com] [--reps N] [--out FILE] [--yes]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=macOS/scripts/crossbench/wpr-config.sh
. "$SCRIPT_DIR/wpr-config.sh"

MEASURED_REPS="${MEASURED_REPS:-10}"
SITES_OVERRIDE=""
RESULTS_FILE=""
ASSUME_YES="${ASSUME_YES:-}"

CROSSBENCH_DIR="${CROSSBENCH_DIR:-$HOME/Developer/crossbench-upstream}"
WPR_DIR="${WPR_DIR:-$HOME/Developer/mac-perf-runner/wpr-archives}"
WPR_ARCHIVES_PREPARED="${WPR_ARCHIVES_PREPARED:-0}"
WPR_MANIFEST="$WPR_DIR/manifest.tsv"
WPR_BIN="${WPR_BIN:-$HOME/Developer/mac-perf-runner/bin/wpr}"
WPR_HTTP_PORT="${WPR_HTTP_PORT:-18080}"
WPR_HTTPS_PORT="${WPR_HTTPS_PORT:-18081}"
WPR_CERT_FILE="${WPR_CERT_FILE:-$CROSSBENCH_DIR/third_party/webpagereplay/ecdsa_cert.pem}"
WPR_KEY_FILE="${WPR_KEY_FILE:-$CROSSBENCH_DIR/third_party/webpagereplay/ecdsa_key.pem}"

TSPROXY_PY="${TSPROXY_PY:-$HOME/Developer/mac-perf-runner/bin/tsproxy.py}"
TSPROXY_PORT="${TSPROXY_PORT:-9997}"
SHAPE="${SHAPE:-1}"
SHAPE_RTT_MS="${SHAPE_RTT_MS:-$WPR_US_BROADBAND_RTT_MS}"
SHAPE_IN_KBPS="${SHAPE_IN_KBPS:-$WPR_US_BROADBAND_IN_KBPS}"
SHAPE_OUT_KBPS="${SHAPE_OUT_KBPS:-$WPR_US_BROADBAND_OUT_KBPS}"
SHAPE_WINDOW="${SHAPE_WINDOW:-$WPR_US_BROADBAND_WINDOW}"

HTTPPROXY_PY="${HTTPPROXY_PY:-$SCRIPT_DIR/httpproxy.py}"
HTTPPROXY_PORT="${HTTPPROXY_PORT:-9998}"
SAFARI_AUTOMATION_PY="${SAFARI_AUTOMATION_PY:-$SCRIPT_DIR/safari-automation.py}"
SAFARIDRIVER_PORT="${SAFARIDRIVER_PORT:-8790}"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
PYTHON_BIN="${PYTHON_BIN:-}"

SAFARI_DOMAIN="com.apple.Safari"
SAFARI_HTTP_PROXY_KEY="WebKit2HTTPProxy"
SAFARI_HTTPS_PROXY_KEY="WebKit2HTTPSProxy"
SAFARI_APP="${SAFARI_APP:-/Applications/Safari.app}"
LOAD_WINDOW="12s"
LOAD_WINDOW_MS=12000
LOAD_WINDOW_SECONDS=12
LCP_SETTLE_MS="${LCP_SETTLE_MS:-600}"

# shellcheck source=macOS/scripts/crossbench/dispositions-lib.sh
. "$SCRIPT_DIR/dispositions-lib.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --reps)  MEASURED_REPS="$2"; shift 2 ;;
    --sites) SITES_OVERRIDE="$2"; shift 2 ;;
    --out)   RESULTS_FILE="$2"; shift 2 ;;
    --yes|-y) ASSUME_YES="1"; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
if ! [[ "$MEASURED_REPS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --reps must be a positive integer." >&2
  exit 2
fi

log() { printf '\n=== %s ===\n' "$1"; }

SITES=()
while IFS= read -r site; do
  [ -z "$site" ] && continue
  [[ "$site" == \#* ]] && continue
  SITES+=("$site")
done < "$SCRIPT_DIR/wpr-sites.txt"
if [ -n "$SITES_OVERRIDE" ]; then
  IFS=',' read -r -a SITES <<< "$SITES_OVERRIDE"
fi
if [ "${#SITES[@]}" -eq 0 ]; then
  echo "ERROR: no sites selected." >&2
  exit 2
fi
NORMALIZED_SITES=()
for site in "${SITES[@]}"; do
  site="$(normalize_wpr_site "$site")"
  if ! [[ "$site" =~ ^[a-z0-9.-]+$ ]]; then
    echo "ERROR: invalid site hostname: $site" >&2
    exit 2
  fi
  if [ "${#NORMALIZED_SITES[@]}" -gt 0 ]; then
    for previous in "${NORMALIZED_SITES[@]}"; do
      if [ "$site" = "$previous" ]; then
        echo "ERROR: duplicate site hostname: $site" >&2
        exit 2
      fi
    done
  fi
  NORMALIZED_SITES+=("$site")
done
SITES=("${NORMALIZED_SITES[@]}")

if [ -z "$RESULTS_FILE" ]; then
  RESULTS_DIR="${RESULTS_DIR:-$PWD/crossbench-results}"
  mkdir -p "$RESULTS_DIR"
  RESULTS_FILE="$RESULTS_DIR/safari-lcp-$(date -u +%Y%m%dT%H%M%SZ).tsv"
fi

SAFARI_MARKETING_VERSION="$(defaults read "$SAFARI_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
SAFARI_BUILD_VERSION="$(defaults read "$SAFARI_APP/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo unknown)"
SAFARI_VERSION="$SAFARI_MARKETING_VERSION"
if [ "$SAFARI_BUILD_VERSION" != "unknown" ]; then
  SAFARI_VERSION="$SAFARI_MARKETING_VERSION ($SAFARI_BUILD_VERSION)"
fi
BROWSER_NAME=safari
BROWSER_VERSION="$SAFARI_VERSION"

WPR_PID=""
TSPROXY_PID=""
HTTPPROXY_PID=""
SAFARIDRIVER_PID=""
WPR_LOG=""
TSPROXY_LOG=""
HTTPPROXY_LOG=""
SAFARIDRIVER_LOG=""
PROXY_STATE_CAPTURED=""
PROXY_APPLIED=""
HTTP_PROXY_WAS_SET=0
HTTPS_PROXY_WAS_SET=0
HTTP_PROXY_VALUE=""
HTTPS_PROXY_VALUE=""
DIAGNOSTICS_DIR="${DIAGNOSTICS_DIR:-$PWD/safari-diagnostics}"

process_is_alive() {
  local pid="$1" state
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  state="$(
    ps -o stat= -p "$pid" 2>/dev/null |
      tr -d '[:space:]' ||
      true
  )"
  [ -n "$state" ] && [[ "$state" != Z* ]]
}

kill_pid() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  if process_is_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6; do
      if ! process_is_alive "$pid"; then
        wait "$pid" 2>/dev/null || true
        return 0
      fi
      sleep 0.5
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

capture_proxy_key() {
  local key="$1" state_name="$2" value_name="$3" value type
  if value="$(defaults read "$SAFARI_DOMAIN" "$key" 2>/dev/null)"; then
    type="$(defaults read-type "$SAFARI_DOMAIN" "$key" 2>/dev/null || true)"
    if [ "$type" != "Type is string" ]; then
      echo "ERROR: $SAFARI_DOMAIN $key has unsupported pre-existing type: $type" >&2
      echo "       Refusing to mutate it because exact restoration is not guaranteed." >&2
      return 1
    fi
    printf -v "$state_name" '%s' 1
    printf -v "$value_name" '%s' "$value"
  else
    printf -v "$state_name" '%s' 0
    printf -v "$value_name" '%s' ""
  fi
}

capture_proxy_state() {
  capture_proxy_key "$SAFARI_HTTP_PROXY_KEY" HTTP_PROXY_WAS_SET HTTP_PROXY_VALUE
  capture_proxy_key "$SAFARI_HTTPS_PROXY_KEY" HTTPS_PROXY_WAS_SET HTTPS_PROXY_VALUE
  PROXY_STATE_CAPTURED=1
}

restore_proxy_key() {
  local key="$1" was_set="$2" value="$3"
  if [ "$was_set" = "1" ]; then
    defaults write "$SAFARI_DOMAIN" "$key" -string "$value" || return 1
    verify_proxy_string "$key" "$value"
  else
    defaults delete "$SAFARI_DOMAIN" "$key" 2>/dev/null || true
    if defaults read "$SAFARI_DOMAIN" "$key" >/dev/null 2>&1; then
      echo "ERROR: could not remove Safari proxy preference $key." >&2
      return 1
    fi
  fi
}

verify_proxy_string() {
  local key="$1" expected="$2" actual type
  actual="$(defaults read "$SAFARI_DOMAIN" "$key" 2>/dev/null)" || return 1
  type="$(defaults read-type "$SAFARI_DOMAIN" "$key" 2>/dev/null)" || return 1
  if [ "$type" != "Type is string" ] || [ "$actual" != "$expected" ]; then
    echo "ERROR: Safari proxy preference $key did not retain the expected string value." >&2
    return 1
  fi
}

apply_proxy_state() {
  local proxy_url="http://127.0.0.1:$HTTPPROXY_PORT"
  capture_proxy_state
  # Mark before the first write so a failure during either write still restores
  # both keys from the snapshot.
  PROXY_APPLIED=1
  defaults write "$SAFARI_DOMAIN" "$SAFARI_HTTP_PROXY_KEY" \
    -string "$proxy_url"
  defaults write "$SAFARI_DOMAIN" "$SAFARI_HTTPS_PROXY_KEY" \
    -string "$proxy_url"
  verify_proxy_string "$SAFARI_HTTP_PROXY_KEY" "$proxy_url"
  verify_proxy_string "$SAFARI_HTTPS_PROXY_KEY" "$proxy_url"
}

restore_proxy_state() {
  local status=0
  [ -n "$PROXY_STATE_CAPTURED" ] || return 0
  restore_proxy_key "$SAFARI_HTTP_PROXY_KEY" "$HTTP_PROXY_WAS_SET" "$HTTP_PROXY_VALUE" || status=1
  restore_proxy_key "$SAFARI_HTTPS_PROXY_KEY" "$HTTPS_PROXY_WAS_SET" "$HTTPS_PROXY_VALUE" || status=1
  if [ "$status" -eq 0 ]; then
    PROXY_APPLIED=""
    PROXY_STATE_CAPTURED=""
  fi
  return "$status"
}

preserve_diagnostic() {
  local source="$1" name="$2"
  [ -n "$source" ] && [ -f "$source" ] || return 0
  mkdir -p "$DIAGNOSTICS_DIR"
  cp "$source" "$DIAGNOSTICS_DIR/$name"
}

cleanup() {
  local exit_code=$?
  trap - EXIT HUP INT TERM
  kill_pid "$SAFARIDRIVER_PID"
  # Keep the proxy chain alive until Safari's own preferences are restored.
  # This avoids leaving Safari pointed at a dead local endpoint if restoration
  # itself needs to communicate with its preferences service.
  if [ -n "$PROXY_APPLIED" ] && ! restore_proxy_state; then
    echo "ERROR: failed to restore Safari proxy preferences." >&2
    exit_code=1
  fi
  kill_pid "$HTTPPROXY_PID"
  kill_pid "$TSPROXY_PID"
  kill_pid "$WPR_PID"
  if [ "$exit_code" -ne 0 ]; then
    preserve_diagnostic "$SAFARIDRIVER_LOG" safaridriver.log
    preserve_diagnostic "$HTTPPROXY_LOG" httpproxy.log
    preserve_diagnostic "$TSPROXY_LOG" tsproxy.log
    preserve_diagnostic "$WPR_LOG" wpr.log
  fi
  [ -z "$SAFARIDRIVER_LOG" ] || rm -f "$SAFARIDRIVER_LOG"
  [ -z "$HTTPPROXY_LOG" ] || rm -f "$HTTPPROXY_LOG"
  [ -z "$TSPROXY_LOG" ] || rm -f "$TSPROXY_LOG"
  [ -z "$WPR_LOG" ] || rm -f "$WPR_LOG"
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

check_prerequisites() {
  if [ "$WPR_ARCHIVES_PREPARED" != "1" ]; then
    echo "ERROR: Safari requires validator-staged WPR archives (WPR_ARCHIVES_PREPARED=1)." >&2
    exit 2
  fi
  if [ ! -f "$WPR_MANIFEST" ]; then
    echo "ERROR: validated WPR manifest missing at $WPR_MANIFEST." >&2
    exit 2
  fi
  if [ -z "$PYTHON_BIN" ]; then
    command -v brew >/dev/null 2>&1 || {
      echo "ERROR: Homebrew not found. Run provision-macos.sh." >&2
      exit 1
    }
    PYTHON_BIN="$(brew --prefix "python@$PYTHON_VERSION")/bin/python$PYTHON_VERSION"
  fi
  command -v "$PYTHON_BIN" >/dev/null 2>&1 || {
    echo "ERROR: Python $PYTHON_VERSION not found at $PYTHON_BIN. Run provision-macos.sh." >&2
    exit 1
  }
  command -v safaridriver >/dev/null 2>&1 || {
    echo "ERROR: safaridriver not found." >&2
    exit 1
  }
  command -v defaults >/dev/null 2>&1 || {
    echo "ERROR: defaults not found." >&2
    exit 1
  }
  command -v shasum >/dev/null 2>&1 || {
    echo "ERROR: shasum not found." >&2
    exit 1
  }
  [ -d "$SAFARI_APP" ] || {
    echo "ERROR: Safari not found at $SAFARI_APP." >&2
    exit 1
  }
  [ -x "$WPR_BIN" ] || {
    echo "ERROR: WPR binary missing at $WPR_BIN. Run provision-macos.sh." >&2
    exit 1
  }
  [ -f "$WPR_CERT_FILE" ] || {
    echo "ERROR: WPR ECDSA certificate missing at $WPR_CERT_FILE." >&2
    exit 1
  }
  [ -f "$WPR_KEY_FILE" ] || {
    echo "ERROR: WPR ECDSA key missing at $WPR_KEY_FILE." >&2
    exit 1
  }
  [ -f "$TSPROXY_PY" ] || {
    echo "ERROR: pinned tsproxy missing at $TSPROXY_PY. Run provision-macos.sh." >&2
    exit 1
  }
  [ -f "$HTTPPROXY_PY" ] || {
    echo "ERROR: HTTP proxy helper missing at $HTTPPROXY_PY." >&2
    exit 1
  }
  [ -f "$SAFARI_AUTOMATION_PY" ] || {
    echo "ERROR: Safari automation helper missing at $SAFARI_AUTOMATION_PY." >&2
    exit 1
  }
}

confirm() {
  [ -n "$ASSUME_YES" ] && return 0
  cat >&2 <<EOF
This run temporarily sets Safari's per-app HTTP and HTTPS proxy preferences to
127.0.0.1:$HTTPPROXY_PORT. Their exact current string values (or absence) will
be restored on exit. No system proxy or keychain is changed.
EOF
  read -r -p "Proceed? [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Aborted." >&2; exit 1 ;;
  esac
}

wait_for_port() {
  local port="$1" timeout="$2" iteration
  for ((iteration = 0; iteration < timeout * 2; iteration++)); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
      exec 3>&-
      return 0
    fi
    sleep 0.5
  done
  return 1
}

assert_port_free() {
  local port="$1" label="$2"
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    exec 3>&-
    echo "ERROR: port $port ($label) is already in use." >&2
    return 1
  fi
}

set_validation_result() {
  local site="$1"
  local verdict reason status_chain final_url detail header row_count
  local archive_name expected_sha actual_sha

  VALIDATION_HANDOFF_ERROR=0
  VALIDATION_STATUS=error
  VALIDATION_REASON=archive_missing
  VALIDATION_HTTP_STATUS=-
  VALIDATION_DETAIL=-
  ARCHIVE_SHA256=-
  VALIDATED_ARCHIVE=""

  if [ ! -f "$WPR_MANIFEST" ]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_REASON=validation_manifest_missing
    VALIDATION_DETAIL="validated archive handoff did not contain manifest.tsv"
    return
  fi

  header="$(head -1 "$WPR_MANIFEST")"
  if [ "$header" != $'site\tarchive\tsha256\tarchive_bytes\tverdict\treason_code\thttp_status\tdetail\tstatus_chain\tfinal_url\tcontent_type\tblocked_marker' ]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_REASON=validation_manifest_schema_mismatch
    VALIDATION_DETAIL="validated archive manifest has an unsupported schema"
    return
  fi
  row_count="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { count++ } END { print count + 0 }' "$WPR_MANIFEST")"
  if [ "$row_count" -eq 0 ]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_REASON=validation_result_missing
    VALIDATION_DETAIL="site is absent from the WPR validation manifest"
    return
  fi
  if [ "$row_count" -ne 1 ]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_REASON=validation_result_ambiguous
    VALIDATION_DETAIL="site has multiple rows in the WPR validation manifest"
    return
  fi

  archive_name="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $2; exit }' "$WPR_MANIFEST")"
  expected_sha="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $3; exit }' "$WPR_MANIFEST")"
  verdict="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $5; exit }' "$WPR_MANIFEST")"
  if [ "$verdict" != "ok" ] && [ "$verdict" != "error" ]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_REASON=validation_verdict_invalid
    VALIDATION_DETAIL="validated archive manifest has an unsupported verdict"
    return
  fi
  if [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]]; then
    ARCHIVE_SHA256="$expected_sha"
  elif [ "$verdict" = "ok" ]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_REASON=validated_archive_hash_invalid
    VALIDATION_DETAIL="validator marked the site eligible without a valid SHA-256"
    return
  fi
  reason="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $6; exit }' "$WPR_MANIFEST")"
  VALIDATION_HTTP_STATUS="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $7; exit }' "$WPR_MANIFEST")"
  VALIDATION_HTTP_STATUS="${VALIDATION_HTTP_STATUS:--}"
  if [ "$VALIDATION_HTTP_STATUS" != "-" ] && ! [[ "$VALIDATION_HTTP_STATUS" =~ ^[1-5][0-9][0-9]$ ]]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_HTTP_STATUS=-
    VALIDATION_REASON=validation_http_status_invalid
    VALIDATION_DETAIL="validated archive manifest has an invalid HTTP status"
    return
  fi
  detail="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $8; exit }' "$WPR_MANIFEST")"
  status_chain="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $9; exit }' "$WPR_MANIFEST")"
  final_url="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $10; exit }' "$WPR_MANIFEST")"
  if [ "$verdict" = "ok" ]; then
    if ! [[ "$archive_name" =~ ^[a-zA-Z0-9._-]+\.wprgo$ ]]; then
      VALIDATION_HANDOFF_ERROR=1
      VALIDATION_REASON=validated_archive_name_invalid
      VALIDATION_DETAIL="validator returned an unsafe or unsupported archive filename"
      return
    fi
    VALIDATED_ARCHIVE="$WPR_DIR/$archive_name"
    if [ ! -f "$VALIDATED_ARCHIVE" ]; then
      VALIDATION_HANDOFF_ERROR=1
      VALIDATION_REASON=validated_archive_missing
      VALIDATION_DETAIL="validator marked the site eligible but its archive was not staged"
      VALIDATED_ARCHIVE=""
      return
    fi
    actual_sha="$(shasum -a 256 "$VALIDATED_ARCHIVE" | awk '{ print $1 }')"
    if [ -z "$expected_sha" ] || [ "$actual_sha" != "$expected_sha" ]; then
      VALIDATION_HANDOFF_ERROR=1
      VALIDATION_REASON=validated_archive_hash_mismatch
      VALIDATION_DETAIL="staged archive SHA-256 does not match the validation manifest"
      ARCHIVE_SHA256=-
      VALIDATED_ARCHIVE=""
      return
    fi
    VALIDATION_STATUS=ok
    VALIDATION_REASON=-
    return
  fi

  VALIDATION_REASON="${reason:-unknown_validation_failure}"
  VALIDATION_DETAIL="${detail:--}"
  if [ -n "$status_chain" ]; then
    VALIDATION_DETAIL="${VALIDATION_DETAIL}; status_chain=$status_chain"
  fi
  if [ -n "$final_url" ]; then
    VALIDATION_DETAIL="${VALIDATION_DETAIL}; final_url=$final_url"
  fi
}

start_wpr() {
  local archive="$1"
  assert_port_free "$WPR_HTTP_PORT" wpr-http || return 1
  assert_port_free "$WPR_HTTPS_PORT" wpr-https || return 1
  WPR_LOG="$(mktemp)"
  "$WPR_BIN" replay \
    --http-port="$WPR_HTTP_PORT" \
    --https-port="$WPR_HTTPS_PORT" \
    --https-cert-file="$WPR_CERT_FILE" \
    --https-key-file="$WPR_KEY_FILE" \
    --no-archive-certificates \
    "$archive" >"$WPR_LOG" 2>&1 &
  WPR_PID=$!
  if ! wait_for_port "$WPR_HTTP_PORT" 15 ||
      ! wait_for_port "$WPR_HTTPS_PORT" 15; then
    echo "ERROR: WPR failed to start. Log:" >&2
    cat "$WPR_LOG" >&2
    kill_pid "$WPR_PID"
    WPR_PID=""
    return 1
  fi
}

stop_wpr() {
  kill_pid "$WPR_PID"
  WPR_PID=""
  [ -z "$WPR_LOG" ] || rm -f "$WPR_LOG"
  WPR_LOG=""
}

start_tsproxy() {
  local -a shaping=()
  assert_port_free "$TSPROXY_PORT" tsproxy
  if [ "$SHAPE" = "1" ]; then
    shaping=(
      --rtt "$SHAPE_RTT_MS"
      --inkbps "$SHAPE_IN_KBPS"
      --outkbps "$SHAPE_OUT_KBPS"
      --window "$SHAPE_WINDOW"
    )
  fi
  TSPROXY_LOG="$(mktemp)"
  "$PYTHON_BIN" "$TSPROXY_PY" \
    --port "$TSPROXY_PORT" \
    --desthost 127.0.0.1 \
    --mapports "443:$WPR_HTTPS_PORT,*:$WPR_HTTP_PORT" \
    ${shaping[@]+"${shaping[@]}"} >"$TSPROXY_LOG" 2>&1 &
  TSPROXY_PID=$!
  if ! wait_for_port "$TSPROXY_PORT" 15; then
    echo "ERROR: tsproxy failed to start. Log:" >&2
    cat "$TSPROXY_LOG" >&2
    exit 1
  fi
}

start_http_proxy() {
  assert_port_free "$HTTPPROXY_PORT" httpproxy
  HTTPPROXY_LOG="$(mktemp)"
  "$PYTHON_BIN" "$HTTPPROXY_PY" \
    "$HTTPPROXY_PORT" "$TSPROXY_PORT" >"$HTTPPROXY_LOG" 2>&1 &
  HTTPPROXY_PID=$!
  if ! wait_for_port "$HTTPPROXY_PORT" 10; then
    echo "ERROR: HTTP proxy failed to start. Log:" >&2
    cat "$HTTPPROXY_LOG" >&2
    exit 1
  fi
}

start_safaridriver() {
  assert_port_free "$SAFARIDRIVER_PORT" safaridriver
  SAFARIDRIVER_LOG="$(mktemp)"
  safaridriver -p "$SAFARIDRIVER_PORT" >"$SAFARIDRIVER_LOG" 2>&1 &
  SAFARIDRIVER_PID=$!
  if ! wait_for_port "$SAFARIDRIVER_PORT" 15; then
    echo "ERROR: safaridriver failed to start. Log:" >&2
    cat "$SAFARIDRIVER_LOG" >&2
    exit 1
  fi
  if ! "$PYTHON_BIN" "$SAFARI_AUTOMATION_PY" "$SAFARIDRIVER_PORT" check; then
    echo "ERROR: Safari WebDriver session creation failed." >&2
    echo "       Ensure 'sudo safaridriver --enable' has run." >&2
    exit 1
  fi
}

proxy_log_line_count() {
  wc -l < "$HTTPPROXY_LOG" 2>/dev/null || echo 0
}

proxy_saw_requested_connect() {
  local line_before="$1" site="$2"
  awk -v line_before="$line_before" -v expected="CONNECT $site:443" \
    'NR > line_before && $0 == expected { found = 1 } END { exit !found }' \
    "$HTTPPROXY_LOG"
}

replay_services_alive() {
  local label pid
  for label in WPR tsproxy httpproxy safaridriver; do
    case "$label" in
      WPR) pid="$WPR_PID" ;;
      tsproxy) pid="$TSPROXY_PID" ;;
      httpproxy) pid="$HTTPPROXY_PID" ;;
      safaridriver) pid="$SAFARIDRIVER_PID" ;;
    esac
    if ! process_is_alive "$pid"; then
      echo "ERROR: $label exited unexpectedly." >&2
      return 1
    fi
  done
}

measure_site() {
  local site="$1" archive rep before output lcp detail landed_url offsite field
  local field_count
  local automation_status site_harness_failed=0
  local unfinalized=0 no_metric=0 observed=0 recorded=0
  local -a values=()
  reset_measurement_counters

  set_validation_result "$site"
  archive="$VALIDATED_ARCHIVE"
  if [ -z "$archive" ]; then
    if [ "$VALIDATION_HANDOFF_ERROR" -eq 1 ]; then
      echo "  $site: validated WPR handoff is unusable; HARNESS FAILURE." >&2
      echo "::warning title=Harness failure::$site: $VALIDATION_REASON"
      HARNESS_FAILURES=$((HARNESS_FAILURES + 1))
      record_disposition "$site" infra_error
      return
    fi
    echo "  $site: excluded by WPR archive validation; SKIPPING." >&2
    echo "::warning title=Site excluded::$site did not pass WPR archive validation"
    record_disposition "$site" excluded
    return
  fi
  ELIGIBLE_SITES=$((ELIGIBLE_SITES + 1))

  if ! start_wpr "$archive"; then
    echo "::warning title=Harness failure::$site: WPR could not start"
    preserve_diagnostic "$WPR_LOG" "wpr-$site.log"
    stop_wpr
    HARNESS_FAILURES=$((HARNESS_FAILURES + 1))
    record_disposition "$site" infra_error
    return
  fi

  for ((rep = 1; rep <= MEASURED_REPS; rep++)); do
    if ! replay_services_alive; then
      site_harness_failed=1
      break
    fi
    before="$(proxy_log_line_count)"
    if output="$("$PYTHON_BIN" "$SAFARI_AUTOMATION_PY" \
        "$SAFARIDRIVER_PORT" measure "https://$site" \
        "$LCP_SETTLE_MS" "$LOAD_WINDOW_SECONDS" 2>&1)"; then
      automation_status=0
    else
      automation_status=$?
    fi
    if ! replay_services_alive; then
      printf '%s\n' "$output" | tail -20 >&2
      site_harness_failed=1
      break
    fi
    for field in detail landed_url landed_offsite lcp_ms; do
      field_count="$(printf '%s\n' "$output" | grep -c "^$field=" || true)"
      if [ "$field_count" -ne 1 ]; then
        echo "    attempt rep=$rep: automation emitted $field_count $field field(s) -> HARNESS FAILURE" >&2
        site_harness_failed=1
        no_metric=$((no_metric + 1))
        break
      fi
    done
    if [ "$field_count" -ne 1 ]; then
      continue
    fi
    lcp="$(printf '%s\n' "$output" | sed -n 's/^lcp_ms=//p' | tail -1)"
    detail="$(printf '%s\n' "$output" | sed -n 's/^detail=//p' | tail -1)"
    landed_url="$(printf '%s\n' "$output" | sed -n 's/^landed_url=//p' | tail -1)"
    offsite="$(printf '%s\n' "$output" | sed -n 's/^landed_offsite=//p' | tail -1)"
    observed=$((observed + 1))

    if [ "$automation_status" -ne 0 ]; then
      echo "::warning title=Harness failure::$site: Safari automation exited $automation_status on repetition $rep"
      printf '%s\n' "$output" | tail -20 >&2
      site_harness_failed=1
      no_metric=$((no_metric + 1))
      continue
    fi
    if ! proxy_saw_requested_connect "$before" "$site"; then
      echo "    attempt rep=$rep: no proxy CONNECT for $site:443 -> HARNESS FAILURE" >&2
      site_harness_failed=1
      no_metric=$((no_metric + 1))
      continue
    fi
    if [ "$offsite" != "0" ] && [ "$offsite" != "1" ]; then
      echo "    attempt rep=$rep: automation produced invalid landed_offsite=$offsite -> HARNESS FAILURE" >&2
      site_harness_failed=1
      no_metric=$((no_metric + 1))
      continue
    fi
    if ! [[ "$lcp" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
      echo "    attempt rep=$rep: automation produced invalid lcp_ms=$lcp -> HARNESS FAILURE" >&2
      site_harness_failed=1
      no_metric=$((no_metric + 1))
      continue
    fi
    if [ "$offsite" = "1" ]; then
      echo "    attempt rep=$rep: landed off-site at $landed_url -> HARNESS FAILURE" >&2
      site_harness_failed=1
      no_metric=$((no_metric + 1))
      continue
    fi
    if awk -v value="$lcp" 'BEGIN { exit !(value <= 0) }'; then
      echo "    attempt rep=$rep: LCP not finalized -> SKIPPED; detail=$detail" >&2
      unfinalized=$((unfinalized + 1))
      continue
    fi

    recorded=$((recorded + 1))
    values+=("$lcp")
    printf 'safari\t%s\t%s\t%d\t%s\n' \
      "$SAFARI_VERSION" "$site" "$recorded" "$lcp" >> "$RESULTS_FILE"
    echo "    attempt rep=$rep: lcp_ms=$lcp -> recorded; detail=$detail"
  done

  LAST_OBSERVED="$observed"
  LAST_RECORDED="$recorded"
  LAST_UNFINALIZED="$unfinalized"
  LAST_NO_METRIC="$no_metric"
  TOTAL_RECORDED=$((TOTAL_RECORDED + recorded))

  if ! process_is_alive "$WPR_PID"; then
    echo "  ERROR: WPR exited during $site replay. Log:" >&2
    cat "$WPR_LOG" >&2
    site_harness_failed=1
  fi
  if [ "$site_harness_failed" -ne 0 ]; then
    preserve_diagnostic "$WPR_LOG" "wpr-$site.log"
  fi
  stop_wpr

  echo "  $site: attempts=$MEASURED_REPS recorded=$recorded unfinalized=$unfinalized no-metric=$no_metric"
  if [ "$recorded" -gt 0 ]; then
    printf '  %s: lcp_ms=[%s] ' "$site" "$(IFS=,; echo "${values[*]}")"
    printf '%s\n' "${values[@]}" |
      awk '{ sum += $1; count++ } END { printf "mean=%.1f n=%d\n", sum/count, count }'
  fi
  if [ "$site_harness_failed" -ne 0 ]; then
    HARNESS_FAILURES=$((HARNESS_FAILURES + 1))
    record_disposition "$site" infra_error
  else
    record_disposition "$site" "$(classify_outcome)"
  fi
}

run_safari() {
  local shape_description=unshaped site
  HARNESS_FAILURES=0
  ELIGIBLE_SITES=0
  TOTAL_RECORDED=0
  if [ "$SHAPE" = "1" ]; then
    shape_description="${SHAPE_RTT_MS}ms RTT, ${SHAPE_IN_KBPS}/${SHAPE_OUT_KBPS} Kbps, window ${SHAPE_WINDOW}"
  fi
  log "Safari LCP (WPR replay, $shape_description) — ${#SITES[@]} sites, $MEASURED_REPS reps"
  echo "safari:  $SAFARI_VERSION"
  echo "results: $RESULTS_FILE"
  echo "route:   Safari prefs -> httpproxy:$HTTPPROXY_PORT -> tsproxy:$TSPROXY_PORT -> WPR"

  start_tsproxy
  start_http_proxy
  apply_proxy_state
  start_safaridriver

  for site in "${SITES[@]}"; do
    log "site: $site"
    measure_site "$site"
  done
  if [ "$HARNESS_FAILURES" -gt 0 ]; then
    echo "ERROR: $HARNESS_FAILURES site(s) had browser harness failures." >&2
    RUN_STATUS=1
  fi
  if [ "$ELIGIBLE_SITES" -gt 0 ] && [ "$TOTAL_RECORDED" -eq 0 ]; then
    echo "ERROR: eligible sites produced no usable LCP samples." >&2
    RUN_STATUS=1
  fi
}

check_prerequisites
confirm
printf 'browser\tbrowser_version\tsite\trep\tlcp_ms\n' > "$RESULTS_FILE"
init_dispositions_file
RUN_STATUS=0
run_safari
report_dispositions
log "Done"
echo "results:      $RESULTS_FILE"
echo "rows:         $(($(wc -l < "$RESULTS_FILE") - 1))"
echo "dispositions: $DISPOSITIONS_FILE"
exit "$RUN_STATUS"
