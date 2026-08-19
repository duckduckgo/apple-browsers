#!/usr/bin/env bash
#
# Measure DuckDuckGo Review/debug navigation-to-LCP against validated WPR
# archives. Every repetition launches a fresh app and SOCKS5 tsproxy:
#
#   DuckDuckGo WKWebView -> tsproxy -> WPR
#
# There is no live-network fallback, forward HTTP proxy, Safari preference
# mutation, or keychain mutation.
#
# Usage:
#   ./test-ddg.sh [--sites a.com,b.com] [--reps N] [--out FILE]
#
set -euo pipefail
# Everything this script emits is machine-readable, so no text handling may
# follow the operator's locale. Under a comma-decimal locale awk renders an
# LCP of 1000.0 ms as "1000,0" in the TSV that CI ingests; character ranges
# and sort order would vary the same way. LC_NUMERIC alone is not enough
# because LC_ALL overrides it, so pin the whole environment to C.
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=macOS/scripts/crossbench/wpr-config.sh
. "$SCRIPT_DIR/wpr-config.sh"
# shellcheck source=macOS/scripts/crossbench/dispositions-lib.sh
. "$SCRIPT_DIR/dispositions-lib.sh"

MEASURED_REPS="${MEASURED_REPS:-10}"
SITES_OVERRIDE=""
RESULTS_FILE=""

WPR_DIR="${WPR_DIR:-$HOME/Developer/mac-perf-runner/wpr-archives}"
WPR_ARCHIVES_PREPARED="${WPR_ARCHIVES_PREPARED:-0}"
WPR_MANIFEST="$WPR_DIR/manifest.tsv"
WPR_BIN="${WPR_BIN:-$HOME/Developer/mac-perf-runner/bin/wpr}"
WPR_HTTP_PORT="${WPR_HTTP_PORT:-18080}"
WPR_HTTPS_PORT="${WPR_HTTPS_PORT:-18081}"
WPR_SRC="${WPR_SRC:-$HOME/Developer/mac-perf-runner/webpagereplay}"
WPR_CERT_FILE="${WPR_CERT_FILE:-$WPR_SRC/ecdsa_cert.pem}"
WPR_KEY_FILE="${WPR_KEY_FILE:-$WPR_SRC/ecdsa_key.pem}"

TSPROXY_PY="${TSPROXY_PY:-$HOME/Developer/mac-perf-runner/bin/tsproxy.py}"
TSPROXY_PORT="${TSPROXY_PORT:-9997}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
DDG_AUTOMATION_PY="${DDG_AUTOMATION_PY:-$SCRIPT_DIR/ddg-automation.py}"
DDG_LAUNCHER="${DDG_LAUNCHER:-$SCRIPT_DIR/launch-ddg-app.sh}"
WATCHDOG_PY="${WATCHDOG_PY:-$SCRIPT_DIR/run-with-watchdog.py}"
DDG_APP="${DDG_APP:-/Applications/DuckDuckGo Review.app}"
DDG_EXECUTABLE="${DDG_EXECUTABLE:-}"
AUTOMATION_PORT="${AUTOMATION_PORT:-8788}"
DDG_AUTOMATION_HOST="${DDG_AUTOMATION_HOST:-::1}"

LOAD_WINDOW_SECONDS="${LOAD_WINDOW_SECONDS:-12}"
ALLOW_TEST_OVERRIDES="${ALLOW_TEST_OVERRIDES:-0}"
LCP_SETTLE_MS="${LCP_SETTLE_MS:-600}"
REPETITION_TIMEOUT_SECONDS="${REPETITION_TIMEOUT_SECONDS:-60}"
SERVICE_START_TIMEOUT_SECONDS="${SERVICE_START_TIMEOUT_SECONDS:-15}"
AUTOMATION_READY_TIMEOUT_SECONDS="${AUTOMATION_READY_TIMEOUT_SECONDS:-30}"

DIAGNOSTICS_DIR="${DIAGNOSTICS_DIR:-$PWD/ddg-diagnostics}"
MAX_SITE_DIAGNOSTICS="${MAX_SITE_DIAGNOSTICS:-5}"
MAX_DIAGNOSTIC_BYTES="${MAX_DIAGNOSTIC_BYTES:-5242880}"
MAX_TOTAL_DIAGNOSTIC_BYTES="${MAX_TOTAL_DIAGNOSTIC_BYTES:-26214400}"
MAX_LIVE_LOG_BYTES="${MAX_LIVE_LOG_BYTES:-10485760}"
SITE_DIAGNOSTICS=0
DIAGNOSTIC_BYTES_WRITTEN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --reps) MEASURED_REPS="$2"; shift 2 ;;
    --sites) SITES_OVERRIDE="$2"; shift 2 ;;
    --out) RESULTS_FILE="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

bounded_integer() {
  local name="$1" minimum="$2" maximum="$3" value
  value="${!name}"
  if ! [[ "$value" =~ ^[0-9]+$ ]] ||
      [ "$value" -lt "$minimum" ] ||
      [ "$value" -gt "$maximum" ]; then
    echo "ERROR: $name must be an integer in $minimum..$maximum." >&2
    exit 2
  fi
}

bounded_integer MEASURED_REPS 1 20
bounded_integer REPETITION_TIMEOUT_SECONDS 1 300
bounded_integer SERVICE_START_TIMEOUT_SECONDS 1 30
bounded_integer AUTOMATION_READY_TIMEOUT_SECONDS 1 120
bounded_integer LCP_SETTLE_MS 0 5000
bounded_integer MAX_SITE_DIAGNOSTICS 0 22
bounded_integer MAX_DIAGNOSTIC_BYTES 1 10485760
bounded_integer MAX_TOTAL_DIAGNOSTIC_BYTES 1 104857600
bounded_integer MAX_LIVE_LOG_BYTES 1024 104857600
bounded_integer LOAD_WINDOW_SECONDS 0 120
if [ "$ALLOW_TEST_OVERRIDES" != 1 ] && [ "$LOAD_WINDOW_SECONDS" != 12 ]; then
  echo "ERROR: LOAD_WINDOW_SECONDS is fixed at 12 outside test fakes." >&2
  exit 2
fi
LOAD_WINDOW="${LOAD_WINDOW_SECONDS}s"
LOAD_WINDOW_MS=$((LOAD_WINDOW_SECONDS * 1000))

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
  for previous in ${NORMALIZED_SITES[@]+"${NORMALIZED_SITES[@]}"}; do
    if [ "$site" = "$previous" ]; then
      echo "ERROR: duplicate site hostname: $site" >&2
      exit 2
    fi
  done
  NORMALIZED_SITES+=("$site")
done
SITES=("${NORMALIZED_SITES[@]}")
if [ "${#SITES[@]}" -gt 22 ]; then
  echo "ERROR: at most 22 sites may be measured in one run." >&2
  exit 2
fi

for port_name in WPR_HTTP_PORT WPR_HTTPS_PORT TSPROXY_PORT AUTOMATION_PORT; do
  bounded_integer "$port_name" 1 65535
done
PORT_VALUES=("$WPR_HTTP_PORT" "$WPR_HTTPS_PORT" "$TSPROXY_PORT" "$AUTOMATION_PORT")
for ((left = 0; left < ${#PORT_VALUES[@]}; left++)); do
  for ((right = left + 1; right < ${#PORT_VALUES[@]}; right++)); do
    if [ "${PORT_VALUES[$left]}" = "${PORT_VALUES[$right]}" ]; then
      echo "ERROR: replay and automation ports must be distinct." >&2
      exit 2
    fi
  done
done

if [ -z "$RESULTS_FILE" ]; then
  RESULTS_DIR="${RESULTS_DIR:-$PWD/crossbench-results}"
  mkdir -p "$RESULTS_DIR"
  RESULTS_FILE="$RESULTS_DIR/ddg-lcp-$(date -u +%Y%m%dT%H%M%SZ).tsv"
fi

DDG_MARKETING_VERSION="${DDG_MARKETING_VERSION:-unknown}"
DDG_BUILD_VERSION="${DDG_BUILD_VERSION:-unknown}"
DDG_BUNDLE_ID="${DDG_BUNDLE_ID:-unknown}"
BROWSER_NAME=ddg

WPR_PID=""
TSPROXY_PID=""
DDG_PID=""
WPR_LOG=""
TSPROXY_LOG=""
DDG_LOG=""
# Replay checks consume the WPR and tsproxy logs, so only the app diagnostic
# log may be trimmed while its producer is running.
DDG_LOG_MONITOR_PID=""
AUTOMATION_TOKEN_VALUE=""
RUN_FATAL=0
SHARED_SERVICE_FAILURE=0
HANDOFF_FAILURES=0
ELIGIBLE_SITES=0
TOTAL_RECORDED=0
FAILURE_PRIORITY=0
SHARED_FAILURE_STAGE=shaping
SHARED_FAILURE_REASON=tsproxy_unavailable
SHARED_FAILURE_DETAIL="replay service was unavailable"

process_is_alive() {
  local pid="$1" state
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
  [ -n "$state" ] && [[ "$state" != Z* ]]
}

cap_live_log() {
  local path="$1" size keep temp
  [ -n "$path" ] && [ -f "$path" ] || return 0
  size="$(stat -f %z "$path" 2>/dev/null || wc -c < "$path" 2>/dev/null || echo 0)"
  [ "$size" -gt "$MAX_LIVE_LOG_BYTES" ] || return 0
  keep=$((MAX_LIVE_LOG_BYTES / 2))
  temp="$path.trim.$$"
  tail -c "$keep" "$path" > "$temp"
  cat "$temp" > "$path"
  rm -f "$temp"
}

monitor_live_log() {
  local path="$1"
  while true; do
    cap_live_log "$path"
    sleep 1
  done
}

stop_log_monitor() {
  local monitor_pid="$1" path="$2"
  if [ -n "$monitor_pid" ]; then
    kill "$monitor_pid" 2>/dev/null || true
    wait "$monitor_pid" 2>/dev/null || true
  fi
  cap_live_log "$path"
}

stop_exact_pid() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  if process_is_alive "$pid"; then
    kill "$pid" 2>/dev/null || return 1
    for _ in 1 2 3 4 5 6; do
      if ! process_is_alive "$pid"; then
        wait "$pid" 2>/dev/null || true
        return 0
      fi
      sleep 0.5
    done
    kill -9 "$pid" 2>/dev/null || return 1
    for _ in 1 2 3 4; do
      process_is_alive "$pid" || {
        wait "$pid" 2>/dev/null || true
        return 0
      }
      sleep 0.25
    done
    return 1
  fi
  wait "$pid" 2>/dev/null || true
}

preserve_diagnostic() {
  local source="$1" name="$2" remaining bytes
  [ -n "$source" ] && [ -f "$source" ] || return 0
  remaining=$((MAX_TOTAL_DIAGNOSTIC_BYTES - DIAGNOSTIC_BYTES_WRITTEN))
  [ "$remaining" -gt 0 ] || return 0
  bytes="$MAX_DIAGNOSTIC_BYTES"
  [ "$bytes" -le "$remaining" ] || bytes="$remaining"
  mkdir -p "$DIAGNOSTICS_DIR"
  tail -c "$bytes" "$source" > "$DIAGNOSTICS_DIR/$name"
  bytes="$(wc -c < "$DIAGNOSTICS_DIR/$name")"
  DIAGNOSTIC_BYTES_WRITTEN=$((DIAGNOSTIC_BYTES_WRITTEN + bytes))
}

preserve_site_diagnostics() {
  local site="$1"
  if [ "$SITE_DIAGNOSTICS" -lt "$MAX_SITE_DIAGNOSTICS" ]; then
    preserve_diagnostic "$WPR_LOG" "wpr-$site.log"
    SITE_DIAGNOSTICS=$((SITE_DIAGNOSTICS + 1))
  fi
}

finish_app_log() {
  local site="$1" rep="$2" preserve="$3"
  if [ "$preserve" = 1 ] &&
      [ "$SITE_DIAGNOSTICS" -lt "$MAX_SITE_DIAGNOSTICS" ]; then
    preserve_diagnostic "$DDG_LOG" "ddg-$site-rep-$rep.log"
    SITE_DIAGNOSTICS=$((SITE_DIAGNOSTICS + 1))
  fi
  # Keep the path and monitor available for the EXIT cleanup retry if the
  # owned app process could not be stopped.
  [ -z "$DDG_PID" ] || return 0
  [ -z "$DDG_LOG" ] || rm -f "$DDG_LOG"
  DDG_LOG=""
}

finish_tsproxy_log() {
  local site="$1" rep="$2" preserve="$3"
  if [ "$preserve" = 1 ] &&
      [ "$SITE_DIAGNOSTICS" -lt "$MAX_SITE_DIAGNOSTICS" ]; then
    preserve_diagnostic "$TSPROXY_LOG" "tsproxy-$site-rep-$rep.log"
    SITE_DIAGNOSTICS=$((SITE_DIAGNOSTICS + 1))
  fi
  [ -z "$TSPROXY_PID" ] || return 0
  [ -z "$TSPROXY_LOG" ] || rm -f "$TSPROXY_LOG"
  TSPROXY_LOG=""
}

finish_repetition_logs() {
  finish_app_log "$@"
  finish_tsproxy_log "$@"
}

stop_app() {
  local status=0
  if [ -n "$DDG_PID" ]; then
    if ! stop_exact_pid "$DDG_PID"; then
      echo "ERROR: could not safely stop DuckDuckGo PID $DDG_PID." >&2
      status=1
    else
      DDG_PID=""
    fi
  fi
  if [ "$status" -eq 0 ]; then
    stop_log_monitor "$DDG_LOG_MONITOR_PID" "$DDG_LOG"
    DDG_LOG_MONITOR_PID=""
  fi
  AUTOMATION_TOKEN_VALUE=""
  return "$status"
}

# shellcheck disable=SC2329  # Invoked indirectly by the EXIT trap below.
cleanup() {
  local exit_code=$?
  trap - EXIT HUP INT TERM
  if ! stop_app; then
    exit_code=1
  fi
  if stop_exact_pid "$WPR_PID"; then
    WPR_PID=""
  else
    exit_code=1
  fi
  if stop_exact_pid "$TSPROXY_PID"; then
    TSPROXY_PID=""
  else
    exit_code=1
  fi
  if [ "$exit_code" -ne 0 ]; then
    preserve_diagnostic "$DDG_LOG" ddg.log
    preserve_diagnostic "$WPR_LOG" wpr.log
    preserve_diagnostic "$TSPROXY_LOG" tsproxy.log
  fi
  [ -n "$DDG_PID" ] || [ -z "$DDG_LOG" ] || rm -f "$DDG_LOG"
  [ -n "$WPR_PID" ] || [ -z "$WPR_LOG" ] || rm -f "$WPR_LOG"
  [ -n "$TSPROXY_PID" ] || [ -z "$TSPROXY_LOG" ] || rm -f "$TSPROXY_LOG"
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_port() {
  local port="$1" timeout="$2" host="${3:-127.0.0.1}" iteration
  for ((iteration = 0; iteration < timeout * 2; iteration++)); do
    if (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
      exec 3>&-
      return 0
    fi
    sleep 0.5
  done
  return 1
}

wait_for_port_free() {
  local port="$1" timeout="$2" host="${3:-127.0.0.1}" iteration
  for ((iteration = 0; iteration < timeout * 4; iteration++)); do
    if ! (exec 3<>"/dev/tcp/$host/$port") 2>/dev/null; then
      return 0
    fi
    exec 3>&-
    sleep 0.25
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

read_app_metadata() {
  local plist="$DDG_APP/Contents/Info.plist"
  local marketing_version build_version bundle_id executable_name
  [ -f "$plist" ] || {
    echo "ERROR: DuckDuckGo Info.plist missing at $plist." >&2
    return 1
  }
  marketing_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
  build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || true)"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
  if [ "$ALLOW_TEST_OVERRIDES" = 1 ]; then
    [ "$DDG_MARKETING_VERSION" != unknown ] || DDG_MARKETING_VERSION="$marketing_version"
    [ "$DDG_BUILD_VERSION" != unknown ] || DDG_BUILD_VERSION="$build_version"
    [ "$DDG_BUNDLE_ID" != unknown ] || DDG_BUNDLE_ID="$bundle_id"
  else
    DDG_MARKETING_VERSION="$marketing_version"
    DDG_BUILD_VERSION="$build_version"
    DDG_BUNDLE_ID="$bundle_id"
    DDG_EXECUTABLE=""
  fi
  for value in "$DDG_MARKETING_VERSION" "$DDG_BUILD_VERSION" "$DDG_BUNDLE_ID"; do
    if [ -z "$value" ] || [[ "$value" == *$'\t'* ]] ||
        [[ "$value" == *$'\n'* ]] || [[ "$value" == *$'\r'* ]]; then
      echo "ERROR: DuckDuckGo Info.plist metadata is missing or malformed." >&2
      return 1
    fi
  done
  if [ -z "$DDG_EXECUTABLE" ]; then
    if [ -z "$executable_name" ] || [[ "$executable_name" == */* ]]; then
      echo "ERROR: DuckDuckGo executable name is missing or unsafe." >&2
      return 1
    fi
    DDG_EXECUTABLE="$DDG_APP/Contents/MacOS/$executable_name"
  fi
  BROWSER_VERSION="$DDG_MARKETING_VERSION ($DDG_BUILD_VERSION)"
}

check_prerequisites() {
  if [ "$WPR_ARCHIVES_PREPARED" != "1" ]; then
    echo "ERROR: DDG requires validator-staged WPR archives (WPR_ARCHIVES_PREPARED=1)." >&2
    exit 2
  fi
  [ -f "$WPR_MANIFEST" ] || {
    echo "ERROR: validated WPR manifest missing at $WPR_MANIFEST." >&2
    exit 2
  }
  for command in "$PYTHON_BIN" shasum ps; do
    command -v "$command" >/dev/null 2>&1 || {
      echo "ERROR: required command unavailable: $command" >&2
      exit 1
    }
  done
  [ -d "$DDG_APP" ] || {
    echo "ERROR: DuckDuckGo app not found at $DDG_APP." >&2
    exit 1
  }
  read_app_metadata || exit 1
  case "$DDG_BUNDLE_ID" in
    *.review|*.debug) ;;
    *)
      echo "ERROR: DDG replay automation requires a Review or debug build; got $DDG_BUNDLE_ID." >&2
      exit 1
      ;;
  esac
  [ -x "$DDG_EXECUTABLE" ] || {
    echo "ERROR: DuckDuckGo executable missing at $DDG_EXECUTABLE." >&2
    exit 1
  }
  [ -x "$WPR_BIN" ] || {
    echo "ERROR: WPR binary missing at $WPR_BIN. Run provision-macos.sh." >&2
    exit 1
  }
  [ -f "$WPR_CERT_FILE" ] && [ -f "$WPR_KEY_FILE" ] || {
    echo "ERROR: WPR ECDSA key pair is unavailable." >&2
    exit 1
  }
  [ -f "$TSPROXY_PY" ] || {
    echo "ERROR: pinned tsproxy missing at $TSPROXY_PY." >&2
    exit 1
  }
  [ -f "$DDG_AUTOMATION_PY" ] && [ -x "$DDG_LAUNCHER" ] &&
      [ -f "$WATCHDOG_PY" ] || {
    echo "ERROR: DDG automation helpers are unavailable." >&2
    exit 1
  }
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
    VALIDATION_DETAIL="site has multiple validation rows"
    return
  fi

  archive_name="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $2; exit }' "$WPR_MANIFEST")"
  expected_sha="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $3; exit }' "$WPR_MANIFEST")"
  verdict="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $5; exit }' "$WPR_MANIFEST")"
  if [ "$verdict" != ok ] && [ "$verdict" != error ]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_REASON=validation_verdict_invalid
    VALIDATION_DETAIL="validated archive manifest has an unsupported verdict"
    return
  fi
  if [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]]; then
    ARCHIVE_SHA256="$expected_sha"
  elif [ "$verdict" = ok ]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_REASON=validated_archive_hash_invalid
    VALIDATION_DETAIL="eligible archive has no valid SHA-256"
    return
  fi
  reason="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $6; exit }' "$WPR_MANIFEST")"
  VALIDATION_HTTP_STATUS="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $7; exit }' "$WPR_MANIFEST")"
  VALIDATION_HTTP_STATUS="${VALIDATION_HTTP_STATUS:--}"
  if [ "$VALIDATION_HTTP_STATUS" != - ] &&
      ! [[ "$VALIDATION_HTTP_STATUS" =~ ^[1-5][0-9][0-9]$ ]]; then
    VALIDATION_HANDOFF_ERROR=1
    VALIDATION_HTTP_STATUS=-
    VALIDATION_REASON=validation_http_status_invalid
    VALIDATION_DETAIL="validated archive manifest has an invalid HTTP status"
    return
  fi
  detail="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $8; exit }' "$WPR_MANIFEST")"
  status_chain="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $9; exit }' "$WPR_MANIFEST")"
  final_url="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $10; exit }' "$WPR_MANIFEST")"

  if [ "$verdict" = ok ]; then
    if ! [[ "$archive_name" =~ ^[a-zA-Z0-9._-]+\.wprgo$ ]]; then
      VALIDATION_HANDOFF_ERROR=1
      VALIDATION_REASON=validated_archive_name_invalid
      VALIDATION_DETAIL="validator returned an unsafe archive filename"
      return
    fi
    VALIDATED_ARCHIVE="$WPR_DIR/$archive_name"
    if [ ! -f "$VALIDATED_ARCHIVE" ]; then
      VALIDATION_HANDOFF_ERROR=1
      VALIDATION_REASON=validated_archive_missing
      VALIDATION_DETAIL="eligible archive was not staged"
      VALIDATED_ARCHIVE=""
      return
    fi
    actual_sha="$(shasum -a 256 "$VALIDATED_ARCHIVE" | awk '{print $1}')"
    if [ "$actual_sha" != "$expected_sha" ]; then
      VALIDATION_HANDOFF_ERROR=1
      VALIDATION_REASON=validated_archive_hash_mismatch
      VALIDATION_DETAIL="staged archive SHA-256 does not match manifest"
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
  [ -z "$status_chain" ] || VALIDATION_DETAIL="$VALIDATION_DETAIL; status_chain=$status_chain"
  [ -z "$final_url" ] || VALIDATION_DETAIL="$VALIDATION_DETAIL; final_url=$final_url"
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
    "$archive" >>"$WPR_LOG" 2>&1 &
  WPR_PID=$!
  if ! wait_for_port "$WPR_HTTP_PORT" "$SERVICE_START_TIMEOUT_SECONDS" ||
      ! wait_for_port "$WPR_HTTPS_PORT" "$SERVICE_START_TIMEOUT_SECONDS"; then
    if ! stop_exact_pid "$WPR_PID"; then
      set_shared_failure cleanup unsafe_wpr_cleanup \
        "WPR failed to stop after startup failure"
    else
      WPR_PID=""
    fi
    return 1
  fi
}

stop_wpr() {
  if ! stop_exact_pid "$WPR_PID"; then
    return 1
  fi
  WPR_PID=""
  [ -z "$WPR_LOG" ] || rm -f "$WPR_LOG"
  WPR_LOG=""
  return 0
}

start_tsproxy() {
  assert_port_free "$TSPROXY_PORT" tsproxy || return 1
  TSPROXY_LOG="$(mktemp)"
  "$PYTHON_BIN" "$TSPROXY_PY" \
    --port "$TSPROXY_PORT" \
    --desthost 127.0.0.1 \
    --mapports "443:$WPR_HTTPS_PORT,*:$WPR_HTTP_PORT" \
    --rtt "$WPR_US_BROADBAND_RTT_MS" \
    --inkbps "$WPR_US_BROADBAND_IN_KBPS" \
    --outkbps "$WPR_US_BROADBAND_OUT_KBPS" \
    --window "$WPR_US_BROADBAND_WINDOW" \
    -vvv >>"$TSPROXY_LOG" 2>&1 &
  TSPROXY_PID=$!
  if ! process_is_alive "$TSPROXY_PID" ||
      ! wait_for_port "$TSPROXY_PORT" "$SERVICE_START_TIMEOUT_SECONDS" ||
      ! process_is_alive "$TSPROXY_PID"; then
    echo "ERROR: tsproxy failed to start." >&2
    if stop_exact_pid "$TSPROXY_PID"; then
      TSPROXY_PID=""
    else
      set_shared_failure cleanup unsafe_tsproxy_cleanup \
        "tsproxy failed to stop after startup failure"
    fi
    return 1
  fi
  return 0
}

stop_tsproxy() {
  if ! stop_exact_pid "$TSPROXY_PID"; then
    return 1
  fi
  TSPROXY_PID=""
  return 0
}

stop_repetition_tsproxy() {
  local rep="$1" status=0
  if ! process_is_alive "$TSPROXY_PID"; then
    set_runtime_failure 60 shaping tsproxy_exited "repetition=$rep"
    status=1
  fi
  if ! stop_tsproxy; then
    set_shared_failure cleanup unsafe_tsproxy_cleanup "repetition=$rep"
    status=1
  fi
  return "$status"
}

tsproxy_line_count() {
  wc -l < "$TSPROXY_LOG" 2>/dev/null || echo 0
}

tsproxy_saw_site() {
  local line_before="$1" site="$2"
  awk -v first="$line_before" -v expected="Resolving b'$site':443" \
    'NR > first && index($0, expected) { found=1 } END { exit !found }' \
    "$TSPROXY_LOG"
}

start_app() {
  assert_port_free "$AUTOMATION_PORT" automation || return 1
  AUTOMATION_TOKEN_VALUE="$("$PYTHON_BIN" -c 'import secrets; print(secrets.token_hex(32))')"
  DDG_LOG="$(mktemp)"
  # The app opens its startup window only outside UI-test mode, so it runs here
  # as a normal launch — which also arms the Sparkle updater. Turn automatic
  # checks off: they would reach the network outside the replay proxy and could
  # update the very build under measurement.
  if ! DDG_PID="$(
    AUTOMATION_TOKEN="$AUTOMATION_TOKEN_VALUE" \
      "$DDG_LAUNCHER" "$DDG_APP" "$DDG_EXECUTABLE" "$DDG_LOG" -- \
      -automationPort "$AUTOMATION_PORT" \
      -isOnboardingCompleted true \
      -webViewProxy "socks5://127.0.0.1:$TSPROXY_PORT" \
      -acceptInsecureCerts true \
      -SUEnableAutomaticChecks false
  )"; then
    echo "ERROR: DuckDuckGo could not be launched through LaunchServices." >&2
    return 1
  fi
  monitor_live_log "$DDG_LOG" &
  DDG_LOG_MONITOR_PID=$!
  if ! wait_for_port "$AUTOMATION_PORT" 20 "$DDG_AUTOMATION_HOST"; then
    echo "ERROR: DuckDuckGo automation server did not become ready." >&2
    return 1
  fi
  # The check polls both the content blocker and the first tab, and the window
  # can appear well after the port does, so the budget is generous.
  local attempts=$((AUTOMATION_READY_TIMEOUT_SECONDS * 2))
  while [ "$attempts" -gt 0 ]; do
    if AUTOMATION_TOKEN="$AUTOMATION_TOKEN_VALUE" \
        DDG_AUTOMATION_HOST="$DDG_AUTOMATION_HOST" \
        "$PYTHON_BIN" "$DDG_AUTOMATION_PY" "$AUTOMATION_PORT" check; then
      return 0
    fi
    process_is_alive "$DDG_PID" || return 1
    attempts=$((attempts - 1))
    sleep 0.5
  done
  echo "ERROR: DuckDuckGo did not report a ready window and content blocker." >&2
  return 1
}

shutdown_app() {
  local status=0
  if process_is_alive "$DDG_PID"; then
    AUTOMATION_TOKEN="$AUTOMATION_TOKEN_VALUE" \
      DDG_AUTOMATION_HOST="$DDG_AUTOMATION_HOST" \
      "$PYTHON_BIN" "$DDG_AUTOMATION_PY" "$AUTOMATION_PORT" shutdown \
      >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6; do
      process_is_alive "$DDG_PID" || break
      sleep 0.5
    done
  fi
  stop_app || status=1
  if ! wait_for_port_free "$AUTOMATION_PORT" 3 "$DDG_AUTOMATION_HOST"; then
    echo "ERROR: automation port $AUTOMATION_PORT remained in use after shutdown." >&2
    status=1
  fi
  return "$status"
}

set_runtime_failure() {
  local priority="$1" stage="$2" reason="$3" detail="$4"
  if [ "$priority" -gt "$FAILURE_PRIORITY" ]; then
    FAILURE_PRIORITY="$priority"
    FAILURE_STAGE="$stage"
    FAILURE_REASON="$reason"
    FAILURE_DETAIL="$detail"
  fi
}

set_shared_failure() {
  local stage="$1" reason="$2" detail="$3"
  RUN_FATAL=1
  SHARED_SERVICE_FAILURE=1
  SHARED_FAILURE_STAGE="$stage"
  SHARED_FAILURE_REASON="$reason"
  SHARED_FAILURE_DETAIL="$detail"
  set_runtime_failure 100 "$stage" "$reason" "$detail"
}

reset_site_counters() {
  reset_measurement_counters
  FAILURE_PRIORITY=0
}

measure_site() {
  local site="$1" rep before output command_status status_file
  local watchdog_state watchdog_code watchdog_cleanup watchdog_extra
  local watchdog_lines cleanup_failed tsproxy_failed
  local lcp detail landed_url offsite field field_count
  local site_failed=0 observed=0 recorded=0 unfinalized=0 no_metric=0
  reset_site_counters
  set_validation_result "$site"

  if [ "$VALIDATION_HANDOFF_ERROR" -eq 1 ]; then
    HANDOFF_FAILURES=$((HANDOFF_FAILURES + 1))
    RUN_FATAL=1
    set_runtime_failure 80 validation invalid_handoff "$VALIDATION_REASON"
    record_disposition "$site" infra_error
    return
  fi
  if [ -z "$VALIDATED_ARCHIVE" ]; then
    echo "  $site: excluded by WPR validation."
    record_disposition "$site" excluded
    return
  fi
  ELIGIBLE_SITES=$((ELIGIBLE_SITES + 1))

  if ! start_wpr "$VALIDATED_ARCHIVE"; then
    set_runtime_failure 30 replay wpr_start_failed "WPR did not become ready"
    preserve_site_diagnostics "$site"
    stop_wpr || set_shared_failure cleanup unsafe_wpr_cleanup \
      "WPR failed to clean up after startup failure"
    record_disposition "$site" infra_error
    return
  fi

  for ((rep = 1; rep <= MEASURED_REPS; rep++)); do
    if ! process_is_alive "$WPR_PID"; then
      site_failed=1
      set_runtime_failure 80 replay wpr_exited "repetition=$rep"
      break
    fi
    if ! start_tsproxy; then
      site_failed=1
      set_runtime_failure 40 shaping tsproxy_start_failed "repetition=$rep"
      finish_tsproxy_log "$site" "$rep" 1
      [ "$SHARED_SERVICE_FAILURE" -eq 0 ] || break
      continue
    fi
    if ! start_app; then
      site_failed=1
      set_runtime_failure 20 automation app_start_failed "repetition=$rep"
      cleanup_failed=0
      if ! shutdown_app; then
        cleanup_failed=1
      fi
      stop_repetition_tsproxy "$rep" || true
      if ! process_is_alive "$WPR_PID"; then
        set_runtime_failure 80 replay wpr_exited "repetition=$rep; after app start failure"
      fi
      if [ "$cleanup_failed" -ne 0 ]; then
        set_shared_failure cleanup unsafe_app_cleanup "repetition=$rep"
      fi
      finish_repetition_logs "$site" "$rep" 1
      [ "$SHARED_SERVICE_FAILURE" -eq 0 ] || break
      continue
    fi

    before="$(tsproxy_line_count)"
    status_file="$(mktemp)"
    set +e
    output="$(
      AUTOMATION_TOKEN="$AUTOMATION_TOKEN_VALUE" \
        "$PYTHON_BIN" "$WATCHDOG_PY" \
          --timeout-seconds "$REPETITION_TIMEOUT_SECONDS" \
          --term-grace-seconds 2 \
          --status-file "$status_file" \
          -- "$PYTHON_BIN" "$DDG_AUTOMATION_PY" \
            "$AUTOMATION_PORT" measure "https://$site" \
            "$LCP_SETTLE_MS" "$LOAD_WINDOW_SECONDS" 2>&1
    )"
    command_status=$?
    set -e
    cleanup_failed=0
    if ! shutdown_app; then
      cleanup_failed=1
    fi

    # Stop the per-repetition shaper before accepting its route evidence.
    # This also guarantees that the next repetition starts with empty queues
    # and a fresh DNS cache.
    tsproxy_failed=0
    if ! stop_repetition_tsproxy "$rep"; then
      tsproxy_failed=1
      site_failed=1
    fi
    if ! process_is_alive "$WPR_PID"; then
      site_failed=1
      set_runtime_failure 80 replay wpr_exited "repetition=$rep"
    fi
    if [ "$cleanup_failed" -ne 0 ]; then
      site_failed=1
      set_shared_failure cleanup unsafe_app_cleanup "repetition=$rep"
    fi
    if [ "$SHARED_SERVICE_FAILURE" -ne 0 ] ||
        [ "$FAILURE_REASON" = wpr_exited ]; then
      rm -f "$status_file"
      finish_repetition_logs "$site" "$rep" 1
      break
    fi
    if [ "$tsproxy_failed" -ne 0 ]; then
      rm -f "$status_file"
      finish_repetition_logs "$site" "$rep" 1
      continue
    fi
    watchdog_lines="$(wc -l < "$status_file" 2>/dev/null || echo 0)"
    IFS=$'\t' read -r watchdog_state watchdog_code watchdog_cleanup watchdog_extra \
      < "$status_file" || true
    rm -f "$status_file"
    if [ "$watchdog_lines" -ne 1 ] ||
        [ -n "${watchdog_extra:-}" ] ||
        ! [[ "${watchdog_code:-}" =~ ^[0-9]+$ ]]; then
      site_failed=1
      set_shared_failure control watchdog_status_invalid \
        "repetition=$rep; lines=$watchdog_lines; state=${watchdog_state:--}; code=${watchdog_code:--}; cleanup=${watchdog_cleanup:--}; process_status=$command_status"
      finish_repetition_logs "$site" "$rep" 1
      break
    fi
    case "$watchdog_state:$watchdog_cleanup" in
      completed:not_needed) ;;
      timed_out:terminated|timed_out:killed|timed_out:already_exited)
        site_failed=1
        set_runtime_failure 40 automation watchdog_timeout "repetition=$rep"
        ;;
      interrupted:terminated|interrupted:killed|interrupted:already_exited)
        site_failed=1
        set_shared_failure control watchdog_interrupted \
          "repetition=$rep; exit_status=$watchdog_code"
        finish_repetition_logs "$site" "$rep" 1
        break
        ;;
      *)
        site_failed=1
        set_shared_failure control watchdog_cleanup_invalid \
          "repetition=$rep; state=$watchdog_state; cleanup=$watchdog_cleanup"
        finish_repetition_logs "$site" "$rep" 1
        break
        ;;
    esac

    field_count=0
    for field in detail landed_url landed_offsite lcp_ms; do
      field_count="$(printf '%s\n' "$output" | grep -c "^$field=" || true)"
      if [ "$field_count" -ne 1 ]; then
        site_failed=1
        set_runtime_failure 20 automation malformed_output \
          "repetition=$rep; field=$field; count=$field_count"
        break
      fi
    done
    if [ "$field_count" -ne 1 ]; then
      finish_repetition_logs "$site" "$rep" 1
      continue
    fi

    detail="$(printf '%s\n' "$output" | sed -n 's/^detail=//p')"
    landed_url="$(printf '%s\n' "$output" | sed -n 's/^landed_url=//p')"
    offsite="$(printf '%s\n' "$output" | sed -n 's/^landed_offsite=//p')"
    lcp="$(printf '%s\n' "$output" | sed -n 's/^lcp_ms=//p')"
    observed=$((observed + 1))

    if [ "$offsite" != 0 ] && [ "$offsite" != 1 ]; then
      site_failed=1
      no_metric=$((no_metric + 1))
      set_runtime_failure 30 automation invalid_offsite_flag "repetition=$rep"
      finish_repetition_logs "$site" "$rep" 1
      continue
    fi
    if ! [[ "$lcp" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
      site_failed=1
      no_metric=$((no_metric + 1))
      set_runtime_failure 30 automation invalid_lcp "repetition=$rep"
      finish_repetition_logs "$site" "$rep" 1
      continue
    fi
    if awk -v value="$lcp" 'BEGIN { exit !(value < -1) }'; then
      site_failed=1
      no_metric=$((no_metric + 1))
      set_runtime_failure 30 automation invalid_lcp \
        "repetition=$rep; lcp_ms=$lcp"
      finish_repetition_logs "$site" "$rep" 1
      continue
    fi
    if [ "$offsite" = 1 ] && [ -n "$landed_url" ]; then
      site_failed=1
      no_metric=$((no_metric + 1))
      set_runtime_failure 30 replay offsite_landing \
        "repetition=$rep; landed_url=$landed_url"
      finish_repetition_logs "$site" "$rep" 1
      continue
    fi
    if [ "$watchdog_code" -ne 0 ]; then
      site_failed=1
      no_metric=$((no_metric + 1))
      set_runtime_failure 30 automation command_failed \
        "repetition=$rep; exit_status=$watchdog_code"
      finish_repetition_logs "$site" "$rep" 1
      continue
    fi
    if ! tsproxy_saw_site "$before" "$site"; then
      site_failed=1
      no_metric=$((no_metric + 1))
      set_runtime_failure 30 replay missing_proxy_route "repetition=$rep"
      finish_repetition_logs "$site" "$rep" 1
      continue
    fi
    if awk -v value="$lcp" 'BEGIN { exit !(value <= 0) }'; then
      unfinalized=$((unfinalized + 1))
      finish_repetition_logs "$site" "$rep" 0
      continue
    fi
    recorded=$((recorded + 1))
    printf 'ddg\t%s\t%s\t%d\t%s\n' \
      "$BROWSER_VERSION" "$site" "$recorded" "$lcp" >> "$RESULTS_FILE"
    echo "  $site rep $rep: lcp_ms=$lcp; detail=$detail"
    finish_repetition_logs "$site" "$rep" 0
  done

  if [ "$observed" -ne $((recorded + unfinalized + no_metric)) ]; then
    site_failed=1
    set_shared_failure control repetition_accounting_invalid \
      "site=$site; observed=$observed; recorded=$recorded; unfinalized=$unfinalized; no_metric=$no_metric"
  fi
  LAST_OBSERVED="$observed"
  LAST_RECORDED="$recorded"
  LAST_UNFINALIZED="$unfinalized"
  LAST_NO_METRIC="$no_metric"
  TOTAL_RECORDED=$((TOTAL_RECORDED + recorded))
  if [ "$site_failed" -ne 0 ] || [ "$recorded" -lt "$MEASURED_REPS" ]; then
    preserve_site_diagnostics "$site"
  fi
  if ! stop_wpr; then
    site_failed=1
    set_shared_failure cleanup unsafe_wpr_cleanup "site=$site"
  fi
  if [ "$site_failed" -ne 0 ]; then
    record_disposition "$site" infra_error
  else
    record_disposition "$site" "$(classify_outcome)"
  fi
}

record_after_shared_failure() {
  local site="$1"
  reset_site_counters
  set_validation_result "$site"
  if [ "$VALIDATION_HANDOFF_ERROR" -eq 1 ]; then
    HANDOFF_FAILURES=$((HANDOFF_FAILURES + 1))
    set_runtime_failure 80 validation invalid_handoff "$VALIDATION_REASON"
    record_disposition "$site" infra_error
  elif [ -z "$VALIDATED_ARCHIVE" ]; then
    record_disposition "$site" excluded
  else
    ELIGIBLE_SITES=$((ELIGIBLE_SITES + 1))
    set_runtime_failure 100 "$SHARED_FAILURE_STAGE" \
      "$SHARED_FAILURE_REASON" "$SHARED_FAILURE_DETAIL"
    record_disposition "$site" infra_error
  fi
}

# Records what else the machine was doing, sampled between sites so the reading
# can never land inside a timed repetition. A run-long transient — another
# tenant on the runner, thermal throttling, memory pressure — raises every
# site's LCP together while leaving per-site spread normal, which is
# indistinguishable from a real regression unless the machine's own state is
# recorded next to the measurements. Best effort throughout: a missing sysctl
# or ps is not worth failing a measurement run over.
record_machine_load() {
  local label="$1" loadavg busiest pressure
  # Each assignment absorbs its own failure: the harness runs under
  # `set -euo pipefail`, where a missing sysctl or ps makes the whole pipeline
  # non-zero and would abort the run this line only exists to annotate.
  loadavg="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' \
    | awk '{printf "%s/%s/%s", $1, $2, $3}')" || loadavg=""
  busiest="$(ps -Ao %cpu=,ucomm= 2>/dev/null | sort -rn | head -3 \
    | awk '{printf "%s%%:%s ", $1, $2}')" || busiest=""
  pressure="$(memory_pressure -Q 2>/dev/null \
    | awk -F: '/percentage/ {gsub(/ /, "", $2); print $2; exit}')" || pressure=""
  printf 'machine: %s loadavg=%s free_mem=%s busiest=%s\n' \
    "$label" "${loadavg:-unknown}" "${pressure:-unknown}" "${busiest:-none}"
}

run_ddg() {
  local site
  log "DuckDuckGo LCP (mandatory WPR, ${WPR_US_BROADBAND_RTT_MS}ms RTT, ${WPR_US_BROADBAND_IN_KBPS}/${WPR_US_BROADBAND_OUT_KBPS} Kbps, window ${WPR_US_BROADBAND_WINDOW})"
  echo "ddg:     $BROWSER_VERSION"
  echo "route:   DDG WKWebView -> tsproxy:$TSPROXY_PORT -> per-site WPR"
  echo "results: $RESULTS_FILE"

  for site in "${SITES[@]}"; do
    log "site: $site"
    record_machine_load "before $site"
    if [ "$SHARED_SERVICE_FAILURE" -ne 0 ]; then
      record_after_shared_failure "$site"
    else
      measure_site "$site"
    fi
    record_machine_load "after $site"
  done
  if [ "$HANDOFF_FAILURES" -gt 0 ]; then
    RUN_FATAL=1
  fi
  if [ "$ELIGIBLE_SITES" -gt 0 ] && [ "$TOTAL_RECORDED" -eq 0 ]; then
    echo "ERROR: eligible sites produced no usable LCP samples." >&2
    RUN_FATAL=1
  fi
}

check_prerequisites
printf 'browser\tbrowser_version\tsite\trep\tlcp_ms\n' > "$RESULTS_FILE"
init_dispositions_file
run_ddg
report_dispositions
log "Done"
echo "results:      $RESULTS_FILE"
echo "rows:         $(($(wc -l < "$RESULTS_FILE") - 1))"
echo "dispositions: $DISPOSITIONS_FILE"
exit "$RUN_FATAL"
