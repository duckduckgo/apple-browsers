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
# replay needs no DNS/CDN warm-up. A missing archive is an infrastructure error,
# never a reason to fall back to the live network.
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
SAFARI_APP="/Applications/Safari.app"
SUITE="navToLCP"
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
normalize() { printf '%s' "$1" | tr '+/' '__'; }

SITES=()
while IFS= read -r site; do
  [ -z "$site" ] && continue
  [[ "$site" == \#* ]] && continue
  SITES+=("$site")
done < "$SCRIPT_DIR/wpr-sites.txt"
if [ -n "$SITES_OVERRIDE" ]; then
  IFS=',' read -r -a SITES <<< "$SITES_OVERRIDE"
fi
NORMALIZED_SITES=()
for site in "${SITES[@]}"; do
  site="$(normalize_wpr_site "$site")"
  if ! [[ "$site" =~ ^[a-z0-9.-]+$ ]]; then
    echo "ERROR: invalid site hostname: $site" >&2
    exit 2
  fi
  for previous in "${NORMALIZED_SITES[@]}"; do
    if [ "$site" = "$previous" ]; then
      echo "ERROR: duplicate site hostname: $site" >&2
      exit 2
    fi
  done
  NORMALIZED_SITES+=("$site")
done
SITES=("${NORMALIZED_SITES[@]}")

if [ -z "$RESULTS_FILE" ]; then
  RESULTS_DIR="${RESULTS_DIR:-$PWD/crossbench-results}"
  mkdir -p "$RESULTS_DIR"
  RESULTS_FILE="$RESULTS_DIR/safari-lcp-$(date -u +%Y%m%dT%H%M%SZ).tsv"
fi

SAFARI_VERSION="$(defaults read "$SAFARI_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
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

kill_pid() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6; do
      if ! kill -0 "$pid" 2>/dev/null; then
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
    defaults write "$SAFARI_DOMAIN" "$key" -string "$value"
  else
    defaults delete "$SAFARI_DOMAIN" "$key" 2>/dev/null || true
  fi
}

apply_proxy_state() {
  capture_proxy_state
  # Mark before the first write so a failure during either write still restores
  # both keys from the snapshot.
  PROXY_APPLIED=1
  defaults write "$SAFARI_DOMAIN" "$SAFARI_HTTP_PROXY_KEY" \
    -string "http://127.0.0.1:$HTTPPROXY_PORT"
  defaults write "$SAFARI_DOMAIN" "$SAFARI_HTTPS_PROXY_KEY" \
    -string "http://127.0.0.1:$HTTPPROXY_PORT"
}

restore_proxy_state() {
  [ -n "$PROXY_STATE_CAPTURED" ] || return 0
  restore_proxy_key "$SAFARI_HTTP_PROXY_KEY" "$HTTP_PROXY_WAS_SET" "$HTTP_PROXY_VALUE"
  restore_proxy_key "$SAFARI_HTTPS_PROXY_KEY" "$HTTPS_PROXY_WAS_SET" "$HTTPS_PROXY_VALUE"
  PROXY_APPLIED=""
  PROXY_STATE_CAPTURED=""
}

cleanup() {
  local exit_code=$?
  trap - EXIT HUP INT TERM
  kill_pid "$SAFARIDRIVER_PID"
  kill_pid "$HTTPPROXY_PID"
  kill_pid "$TSPROXY_PID"
  kill_pid "$WPR_PID"
  if [ -n "$PROXY_APPLIED" ]; then
    restore_proxy_state || {
      echo "ERROR: failed to restore Safari proxy preferences." >&2
      exit_code=1
    }
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

fetch_archive() {
  local story="$1" normalized archive
  normalized="$(normalize "$story")"
  archive="$WPR_DIR/$normalized.wprgo"
  mkdir -p "$WPR_DIR"
  if [ "$WPR_ARCHIVES_PREPARED" = "1" ]; then
    [ ! -f "$archive" ] || printf '%s' "$archive"
    return
  fi
  if curl -fLSs -o "$archive.tmp" "$WPR_BASE_URL/$normalized.wprgo" 2>/dev/null; then
    mv "$archive.tmp" "$archive"
    printf '%s' "$archive"
  else
    rm -f "$archive.tmp"
    [ ! -f "$archive" ] || printf '%s' "$archive"
  fi
}

set_validation_result() {
  local site="$1" archive_available="$2"
  local verdict reason status_chain final_url detail header

  VALIDATION_STATUS=error
  VALIDATION_REASON=archive_missing
  VALIDATION_HTTP_STATUS=-
  VALIDATION_DETAIL=-
  ARCHIVE_SHA256=-

  if [ "$WPR_ARCHIVES_PREPARED" != "1" ]; then
    if [ -n "$archive_available" ]; then
      VALIDATION_STATUS=ok
      VALIDATION_REASON=-
      ARCHIVE_SHA256="$(shasum -a 256 "$archive_available" | awk '{print $1}')"
    fi
    return
  fi
  if [ ! -f "$WPR_MANIFEST" ]; then
    VALIDATION_REASON=validation_manifest_missing
    VALIDATION_DETAIL="validated archive handoff did not contain manifest.tsv"
    return
  fi

  header="$(head -1 "$WPR_MANIFEST")"
  if [ "$header" != $'site\tarchive\tsha256\tarchive_bytes\tverdict\treason_code\thttp_status\tdetail\tstatus_chain\tfinal_url\tcontent_type\tblocked_marker' ]; then
    VALIDATION_REASON=validation_manifest_schema_mismatch
    VALIDATION_DETAIL="validated archive manifest has an unsupported schema"
    return
  fi
  verdict="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $5; exit }' "$WPR_MANIFEST")"
  if [ -z "$verdict" ]; then
    VALIDATION_REASON=validation_result_missing
    VALIDATION_DETAIL="site is absent from the WPR validation manifest"
    return
  fi

  ARCHIVE_SHA256="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $3; exit }' "$WPR_MANIFEST")"
  ARCHIVE_SHA256="${ARCHIVE_SHA256:--}"
  reason="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $6; exit }' "$WPR_MANIFEST")"
  VALIDATION_HTTP_STATUS="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $7; exit }' "$WPR_MANIFEST")"
  VALIDATION_HTTP_STATUS="${VALIDATION_HTTP_STATUS:--}"
  detail="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $8; exit }' "$WPR_MANIFEST")"
  status_chain="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $9; exit }' "$WPR_MANIFEST")"
  final_url="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $10; exit }' "$WPR_MANIFEST")"
  if [ "$verdict" = "ok" ] && [ -n "$archive_available" ]; then
    VALIDATION_STATUS=ok
    VALIDATION_REASON=-
    return
  fi
  if [ "$verdict" = "ok" ]; then
    VALIDATION_REASON=validated_archive_missing
    VALIDATION_DETAIL="validator marked the site eligible but its archive was not staged"
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

proxy_line_count() {
  wc -l < "$HTTPPROXY_LOG" 2>/dev/null || echo 0
}

measure_site() {
  local site="$1" archive rep before output lcp detail landed_url offsite
  local automation_status site_harness_failed=0
  local unfinalized=0 no_metric=0 observed=0 recorded=0
  local -a values=()
  reset_measurement_counters

  archive="$(fetch_archive "$SUITE+$site")"
  set_validation_result "$site" "$archive"
  if [ "$VALIDATION_STATUS" != "ok" ]; then
    archive=""
  fi
  if [ -z "$archive" ]; then
    if [ "$WPR_ARCHIVES_PREPARED" = "1" ]; then
      echo "  $site: excluded by WPR archive validation; SKIPPING." >&2
      echo "::warning title=Site excluded::$site did not pass WPR archive validation"
    else
      echo "  $site: no WPR archive available; SKIPPING (replay-only)." >&2
      echo "::warning title=Site skipped::$site: no WPR archive at $WPR_BASE_URL"
    fi
    record_disposition "$site" excluded
    return
  fi
  ELIGIBLE_SITES=$((ELIGIBLE_SITES + 1))

  if ! start_wpr "$archive"; then
    echo "::warning title=Harness failure::$site: WPR could not start"
    HARNESS_FAILURES=$((HARNESS_FAILURES + 1))
    record_disposition "$site" infra_error
    return
  fi

  for ((rep = 1; rep <= MEASURED_REPS; rep++)); do
    before="$(proxy_line_count)"
    set +e
    output="$("$PYTHON_BIN" "$SAFARI_AUTOMATION_PY" \
      "$SAFARIDRIVER_PORT" measure "https://$site" \
      "$LCP_SETTLE_MS" "$LOAD_WINDOW_SECONDS" 2>&1)"
    automation_status=$?
    set -e
    observed=$((observed + 1))
    if [ "$automation_status" -ne 0 ]; then
      echo "::warning title=Harness failure::$site: Safari automation exited $automation_status on repetition $rep"
      site_harness_failed=1
    fi
    lcp="$(printf '%s\n' "$output" | sed -n 's/^lcp_ms=//p' | tail -1)"
    detail="$(printf '%s\n' "$output" | sed -n 's/^detail=//p' | tail -1)"
    landed_url="$(printf '%s\n' "$output" | sed -n 's/^landed_url=//p' | tail -1)"
    offsite="$(printf '%s\n' "$output" | sed -n 's/^landed_offsite=//p' | tail -1)"

    if [ "$(proxy_line_count)" -le "$before" ]; then
      echo "    attempt rep=$rep: no Safari proxy traffic -> SKIPPED" >&2
      no_metric=$((no_metric + 1))
      continue
    fi
    if [ -z "$lcp" ]; then
      echo "    attempt rep=$rep: automation produced no metric -> SKIPPED" >&2
      no_metric=$((no_metric + 1))
      continue
    fi
    if [ "$offsite" = "1" ]; then
      echo "    attempt rep=$rep: landed off-site at $landed_url -> SKIPPED" >&2
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

  if ! kill -0 "$WPR_PID" 2>/dev/null; then
    echo "  ERROR: WPR exited during $site replay. Log:" >&2
    cat "$WPR_LOG" >&2
    stop_wpr
    site_harness_failed=1
  else
    stop_wpr
  fi

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
    echo "ERROR: $HARNESS_FAILURES eligible site(s) had browser harness failures." >&2
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
