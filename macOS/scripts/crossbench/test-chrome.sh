#!/usr/bin/env bash
#
# test-chrome.sh — run the crossbench page-load / LCP test for Chrome against
# RECORDED network (Web Page Replay), and write a results file.
#
# Chrome loads each site from a WPR archive through a traffic shaper; crossbench
# drives it and extracts LCP from a Perfetto trace (Chromium's
# PageLoadMetrics.NavigationToLargestContentfulPaint) via the navToLCP probe.
# Every site gets a disposition row saying whether it was measurable — see
# dispositions-lib.sh.
#
# WHY REPLAY: identical bytes on every load. On a live network the same page
# varies with CDN, geo and A/B changes, and several of these sites bot-block a
# CI runner outright, so a regression cannot be distinguished from weather.
#
# TRAFFIC SHAPING: US-broadband (28ms RTT, 50/10 Mbps), the same profile the
# Windows runner uses, so the two harnesses' numbers are comparable. Shaping is
# not optional decoration: replayed over unshaped loopback, apple.com measures
# ~204ms against ~745ms shaped on this runner, because loopback charges nothing
# for the round trips and slow start that dominate a real cold load. SHAPE=0
# replays unshaped for diagnosis.
#
# A site is measured only if its archive passes validation; otherwise it is
# recorded as excluded and skipped. There is no live-network fallback, because
# a live number is indistinguishable from a replayed one at read time while
# carrying all the variance replay exists to remove.
#
# Each site gets MEASURED_REPS loads, matching the Windows runner's 10. Every
# load is measured: replay makes the first load no colder than the rest, since
# there is no DNS or CDN edge to warm and a fresh Chrome profile per load leaves
# no cache to carry over.
#
# Prereqs: run provision-macos.sh first (crossbench + extras + Chrome + poetry +
# the wpr binary + tsproxy).
#
# Usage:
#   ./test-chrome.sh [--sites a.com,b.com] [--reps N] [--out FILE]
#
set -euo pipefail

# ---- config / args ---------------------------------------------------------
# The CI default matches the Windows runner's repetition count. --reps exists
# for a small local validation without changing the production default.
MEASURED_REPS="${MEASURED_REPS:-10}"
SITES_OVERRIDE=""
RESULTS_FILE=""
CROSSBENCH_DIR="${CROSSBENCH_DIR:-$HOME/Developer/crossbench-upstream}"

# ---- recorded network (WPR) + shaping --------------------------------------
WPR_DIR="${WPR_DIR:-$HOME/Developer/mac-perf-runner/wpr-archives}"
# CI sets this when archives came from the shared validation workflow.
WPR_ARCHIVES_PREPARED="${WPR_ARCHIVES_PREPARED:-0}"
WPR_MANIFEST="$WPR_DIR/manifest.tsv"
# Built by provision-macos.sh and handed to crossbench via --bin-override so
# crossbench never runs its own webpagereplay build (which needs CIPD Go).
WPR_BIN="${WPR_BIN:-$HOME/Developer/mac-perf-runner/bin/wpr}"
# Standalone Python-3 tsproxy, handed to crossbench via speed:{ts_proxy:...}.
# See wpr_network_arg for why crossbench's own DEPS-pinned copy cannot be used.
TSPROXY_PY="${TSPROXY_PY:-$HOME/Developer/mac-perf-runner/bin/tsproxy.py}"
# US-broadband, byte-for-byte the Windows runner's profile. Passed as explicit
# values rather than speed:"US-broadband" because that preset name exists only in
# the DDG crossbench fork, and we pin upstream.
SHAPE="${SHAPE:-1}"
SHAPE_RTT_MS="${SHAPE_RTT_MS:-28}"
SHAPE_IN_KBPS="${SHAPE_IN_KBPS:-50000}"
SHAPE_OUT_KBPS="${SHAPE_OUT_KBPS:-10000}"
SHAPE_WINDOW="${SHAPE_WINDOW:-10}"

PROBE_CONFIG="config/probe/perfetto/navToLCP.config.hjson"
SUITE="navToLCP"          # LCP focus; navToFCP exists in the ps1 as a sibling
LOAD_WINDOW="12s"         # matches runCrossbench.ps1 (--url=<site>,12s)
LOAD_WINDOW_MS=12000      # same value in ms, recorded so censoring counts from
                          # different runs are only compared at equal windows
CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Sourced before the cd into CROSSBENCH_DIR below, so the path is relative to
# this script rather than the working directory.
# shellcheck source=macOS/scripts/crossbench/dispositions-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dispositions-lib.sh"
# shellcheck source=macOS/scripts/crossbench/wpr-config.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wpr-config.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --reps)  MEASURED_REPS="$2"; shift 2 ;;
    --sites) SITES_OVERRIDE="$2"; shift 2 ;;
    --out)   RESULTS_FILE="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
if ! [[ "$MEASURED_REPS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --reps must be a positive integer." >&2
  exit 2
fi

log() { printf '\n=== %s ===\n' "$1"; }

# The default list is shared with archive validation.
SITES=()
while IFS= read -r site; do
  [ -z "$site" ] && continue
  [[ "$site" == \#* ]] && continue
  SITES+=("$site")
done < "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wpr-sites.txt"
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

# Default results file: ./crossbench-results/chrome-lcp-<utc-stamp>.tsv, relative
# to the invocation dir (CI uploads this directory as an artifact).
if [ -z "$RESULTS_FILE" ]; then
  RESULTS_DIR="${RESULTS_DIR:-$PWD/crossbench-results}"
  mkdir -p "$RESULTS_DIR"
  RESULTS_FILE="$RESULTS_DIR/chrome-lcp-$(date -u +%Y%m%dT%H%M%SZ).tsv"
fi

# `--version` prints "Google Chrome 150.0.7871.186 " — note the TRAILING SPACE,
# which without the second substitution ends up inside webview_version in
# ClickHouse and makes the column not compare equal to the same version typed by
# hand.
CHROME_VERSION="$("$CHROME_BIN" --version 2>/dev/null | sed -E 's/^Google Chrome //; s/[[:space:]]+$//' || echo unknown)"

# dispositions-lib.sh contract.
BROWSER_NAME=chrome
BROWSER_VERSION="$CHROME_VERSION"

# ---- prerequisites ---------------------------------------------------------
check_prerequisites() {
  if ! command -v poetry >/dev/null 2>&1; then
    echo "ERROR: poetry not found. Run provision-macos.sh first." >&2
    exit 1
  fi
  if [ ! -f "$CROSSBENCH_DIR/cb.py" ]; then
    echo "ERROR: crossbench not found at $CROSSBENCH_DIR (cb.py missing). Run provision-macos.sh first." >&2
    exit 1
  fi
  if [ ! -x "$WPR_BIN" ]; then
    echo "ERROR: wpr binary not found at $WPR_BIN. Run provision-macos.sh first." >&2
    exit 1
  fi
  if [ "$SHAPE" = "1" ] && [ ! -f "$TSPROXY_PY" ]; then
    echo "ERROR: tsproxy not found at $TSPROXY_PY. Run provision-macos.sh first." >&2
    exit 1
  fi
}

# ---- recorded network ------------------------------------------------------
# normalized story filename: 'navToLCP+youtube.com' -> 'navToLCP_youtube.com'
# ('+' -> '_', '/' -> '_'), matching Get-Normalized-Filename in the ps1.
normalize() { printf '%s' "$1" | tr '+/' '__'; }

# crossbench --network arg for a WPR archive. Notes:
# - No spaces: the arg is deliberately unquoted at the call site, so neither the
#   archive path nor TSPROXY_PY may contain spaces.
# - crossbench's own third_party/tsproxy is Python-2-only at the DEPS-pinned
#   revision: under a Python 3.11 venv its SOCKS handshake dies inside a bare
#   `except: pass`, leaving the browser pointed at a black-hole proxy where
#   nothing loads. speed:{ts_proxy:...} overrides the tool path with the
#   standalone Python-3 copy, which is also what the Safari and DDG runners use —
#   one shaper, one set of values, every browser.
wpr_network_arg() {
  local archive="$1" speed=""
  if [ "$SHAPE" = "1" ]; then
    speed=",speed:{ts_proxy:\"$TSPROXY_PY\",rtt_ms:$SHAPE_RTT_MS,in_kbps:$SHAPE_IN_KBPS,out_kbps:$SHAPE_OUT_KBPS,window:$SHAPE_WINDOW}"
  fi
  printf -- '--network={type:"wpr",path:"%s"%s}' "$archive" "$speed"
}

# Echo the crossbench --network arg for a story's archive, or nothing when no
# archive is available — the caller then skips the site.
fetch_network_arg() {
  local story="$1" normalized archive
  normalized="$(normalize "$story")"
  archive="$WPR_DIR/$normalized.wprgo"
  mkdir -p "$WPR_DIR"
  if [ "$WPR_ARCHIVES_PREPARED" = "1" ]; then
    if [ -f "$archive" ]; then
      wpr_network_arg "$archive"
    else
      printf ''
    fi
    return
  fi
  if curl -fLSs -o "$archive.tmp" "$WPR_BASE_URL/$normalized.wprgo" 2>/dev/null; then
    mv "$archive.tmp" "$archive"
    wpr_network_arg "$archive"
  else
    rm -f "$archive.tmp"
    # Reuse an already-downloaded archive when the fetch fails (offline runner).
    if [ -f "$archive" ]; then
      wpr_network_arg "$archive"
    else
      printf ''
    fi
  fi
}

# Populate the validation fields written beside this site's measurement
# counters. Prepared CI archives carry the shared validator's manifest; local
# replay without that handoff records only whether an archive was available.
set_validation_result() {
  local site="$1" archive_available="$2" verdict status_chain final_url failure reason

  VALIDATION_STATUS=error
  VALIDATION_REASON=archive_missing
  VALIDATION_HTTP_STATUS=-
  VALIDATION_DETAIL=-

  if [ "$WPR_ARCHIVES_PREPARED" != "1" ]; then
    if [ -n "$archive_available" ]; then
      VALIDATION_STATUS=ok
      VALIDATION_REASON=-
    fi
    return
  fi
  if [ ! -f "$WPR_MANIFEST" ]; then
    VALIDATION_REASON=validation_manifest_missing
    VALIDATION_DETAIL="validated archive handoff did not contain manifest.tsv"
    return
  fi

  verdict="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $5; exit }' "$WPR_MANIFEST")"
  if [ -z "$verdict" ]; then
    VALIDATION_REASON=validation_result_missing
    VALIDATION_DETAIL="site is absent from the WPR validation manifest"
    return
  fi

  status_chain="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $6; exit }' "$WPR_MANIFEST")"
  final_url="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $7; exit }' "$WPR_MANIFEST")"
  failure="$(awk -F'\t' -v site="$site" 'NR > 1 && $1 == site { print $10; exit }' "$WPR_MANIFEST")"
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

  reason="${failure%% | *}"
  reason="${reason%%: *}"
  VALIDATION_REASON="${reason:-unknown_validation_failure}"
  if [[ "$VALIDATION_REASON" =~ ^http_([0-9]{3})$ ]]; then
    VALIDATION_HTTP_STATUS="${BASH_REMATCH[1]}"
  fi
  VALIDATION_DETAIL="${failure:--}"
  if [ -n "$status_chain" ]; then
    VALIDATION_DETAIL="${VALIDATION_DETAIL}; status_chain=$status_chain"
  fi
  if [ -n "$final_url" ]; then
    VALIDATION_DETAIL="${VALIDATION_DETAIL}; final_url=$final_url"
  fi
}

# crossbench lays results out as
#   .../stories/<story>/<repetition>/<temperature>/...
# so the path itself carries the repetition index. Deriving it from the path
# rather than from a counter keeps the logged repetition number meaningful when
# some repetitions are discarded, and stable regardless of directory order.
rep_of_path() {
  awk -F/ '{for (i = 1; i <= NF; i++) if ($i == "stories") { print $(i + 2); exit }}' <<< "$1"
}

# Parse a crossbench RESULTS dir: for every per-iteration v2_metrics.textproto,
# pull the first `double_value:` — the LCP metric, which trace_processor emits in
# NANOSECONDS — and convert to ms. An iteration whose LCP never finalized is
# emitted as `double_value: -1`; count those separately. Appends one TSV row per
# valid value to RESULTS_FILE and prints a per-site summary to the console.
#
# Every individual attempt is logged with its disposition, so a site that lands
# fewer samples than expected can be read straight from the CI log instead of
# being inferred from a missing row. Attempt lines are prefixed `attempt` to be
# greppable inside crossbench's own --debug output.
summarize_lcp() {
  local results_path="$1" site="$2"
  # The caller reads these back for the disposition record, so every early
  # `return` below must leave them consistent — hence the reset here and the
  # single assignment point after the loop.
  reset_measurement_counters
  local -a vals=()
  local f v ms rep_idx unfinalized=0 no_metric=0 attempts=0 rep=0
  while IFS= read -r f; do
    attempts=$((attempts + 1))
    rep_idx="$(rep_of_path "$f")"
    # `|| true`: under set -e/pipefail a no-match grep would abort the script.
    v="$(grep -Eo 'double_value: -?[0-9]+(\.[0-9]+)?' "$f" | head -1 | awk '{print $2}' || true)"
    if [ -z "$v" ]; then
      # No metric at all. Because the page bytes come from the archive, this is
      # a browser/probe/trace_processor failure rather than a live-site block.
      echo "    attempt rep=$rep_idx: no double_value in metrics -> SKIPPED (no metric emitted)"
      no_metric=$((no_metric + 1))
      continue
    fi
    if awk -v v="$v" 'BEGIN{exit !(v < 0)}'; then
      echo "    attempt rep=$rep_idx: lcp_raw=$v -> SKIPPED (LCP never finalized within ${LOAD_WINDOW} window)"
      unfinalized=$((unfinalized + 1))
      continue
    fi
    ms="$(awk -v ns="$v" 'BEGIN{printf "%.1f", ns / 1000000}')"   # ns -> ms
    vals+=("$ms")
    rep=$((rep + 1))
    echo "    attempt rep=$rep_idx: lcp_ms=$ms -> recorded"
    printf 'chrome\t%s\t%s\t%d\t%s\n' "$CHROME_VERSION" "$site" "$rep" "$ms" >> "$RESULTS_FILE"
    # Only per-iteration files live under a trace_processor/ dir. crossbench also
    # writes story-level MERGED copies (identical dupes) which would inflate n.
    # Sorted so attempts are logged in repetition order.
  done < <(find "$results_path" -path '*/trace_processor/v2_metrics.textproto' 2>/dev/null | sort)

  # Single assignment point for the disposition counters: everything after this
  # only reports. observed counts repetitions that produced probe output at all,
  # so observed < MEASURED_REPS means the browser or harness stopped early, while
  # the dropped_* counters account for output that was unusable. LAST_HTTP_ERROR
  # stays 0 — the trace carries no HTTP status.
  LAST_OBSERVED="$attempts"
  LAST_RECORDED="${#vals[@]}"
  LAST_UNFINALIZED="$unfinalized"
  LAST_NO_METRIC="$no_metric"
  # Always print the tally, including the zero-attempt case — "expected 5, saw 0"
  # is a different failure from "saw 5, discarded 5" and the log should say which.
  echo "  $site: attempts=$attempts/$MEASURED_REPS recorded=${#vals[@]} unfinalized=$unfinalized no-metric=$no_metric"
  if [ "$unfinalized" -gt 0 ]; then
    echo "  WARNING: $site: $unfinalized iteration(s) with unfinalized LCP (-1)." >&2
  fi
  if [ "$attempts" -eq 0 ]; then
    echo "  $site: NO METRICS FILES FOUND under $results_path (probe or trace_processor did not run)"
    return
  fi
  if [ "${#vals[@]}" -eq 0 ]; then
    echo "  $site: NO LCP VALUES PARSED (check trace / probe)"
    return
  fi
  printf '  %s: lcp_ms=[%s] ' "$site" "$(IFS=,; echo "${vals[*]}")"
  printf '%s\n' "${vals[@]}" | awk '{s+=$1; n++} END{printf "mean=%.1f n=%d\n", s/n, n}'
}

# ---- run -------------------------------------------------------------------
run_chrome() {
  local shape_desc="unshaped"
  [ "$SHAPE" = "1" ] && shape_desc="${SHAPE_RTT_MS}ms RTT, ${SHAPE_IN_KBPS}/${SHAPE_OUT_KBPS} kbps"
  log "Chrome LCP run (WPR replay, $shape_desc) — $SUITE, ${#SITES[@]} sites, $MEASURED_REPS reps, ${LOAD_WINDOW} window"
  echo "chrome:  $CHROME_VERSION"
  echo "results: $RESULTS_FILE"
  cd "$CROSSBENCH_DIR"
  # .vpython3 is git-tracked and makes crossbench re-exec under Chromium vpython
  # instead of our poetry venv; removal belongs here (run step), not provisioning.
  rm -f .vpython3

  local site story network_arg out results_path outcome
  for site in "${SITES[@]}"; do
    story="${SUITE}+${site}"
    log "site: $site"
    reset_measurement_counters

    network_arg="$(fetch_network_arg "$story")"
    set_validation_result "$site" "$network_arg"
    if [ "$VALIDATION_STATUS" != "ok" ]; then
      network_arg=""
    fi
    if [ -z "$network_arg" ]; then
      if [ "$WPR_ARCHIVES_PREPARED" = "1" ]; then
        echo "  $site: excluded by WPR archive validation; SKIPPING." >&2
        echo "::warning title=Site excluded::$site did not pass WPR archive validation"
      else
        echo "  $site: no WPR archive available; SKIPPING (replay-only)." >&2
        echo "::warning title=Site skipped::$site: no WPR archive at $WPR_BASE_URL"
      fi
      # planned=0: the browser never ran, which is a different fact from "ran
      # $MEASURED_REPS times and recorded nothing".
      record_disposition "$site" excluded 0
      continue
    fi

    echo "  plan: $MEASURED_REPS measured loads, ${LOAD_WINDOW} window"
    out="$(mktemp)"
    # --about-blank-duration is REQUIRED: navigating to about:blank after each
    # page forces Chromium to finalize LCP; without it every value comes out -1.
    # shellcheck disable=SC2086  # network_arg must word-split into separate args
    poetry run python ./cb.py \
      loading \
      --browser=chrome-stable \
      --probe-config="$PROBE_CONFIG" \
      --repetitions="$MEASURED_REPS" \
      --url="$site,$LOAD_WINDOW" \
      --about-blank-duration=2s \
      --bin-override "wpr=$WPR_BIN" \
      $network_arg \
      --debug \
      --env-validation=skip 2>&1 | tee "$out" || echo "WARN: crossbench exited non-zero for $site" >&2

    # `|| true`: under set -e/pipefail a no-match grep would abort the script.
    results_path="$(grep -E '^RESULTS: ' "$out" | tail -1 | sed -E 's/^RESULTS: //' || true)"
    if [ -n "$results_path" ] && [ -d "$results_path" ]; then
      # Logged so a surprising per-attempt result can be traced back to the raw
      # trace and metrics on the runner.
      echo "  results dir: $results_path"
      summarize_lcp "$results_path" "$site"
      outcome="$(classify_outcome)"
      record_disposition "$site" "$outcome" "$MEASURED_REPS"
    else
      echo "  $site: no RESULTS path in crossbench output"
      # The archive was available, but the browser harness failed before it
      # produced a results directory.
      echo "::warning title=Harness failure::$site: crossbench produced no RESULTS path"
      record_disposition "$site" infra_error "$MEASURED_REPS"
    fi
    rm -f "$out"
  done
}

# ---- main ------------------------------------------------------------------
check_prerequisites
# TSV header. Columns: browser, browser_version, site, rep, lcp_ms.
printf 'browser\tbrowser_version\tsite\trep\tlcp_ms\n' > "$RESULTS_FILE"
init_dispositions_file
run_chrome
report_dispositions
log "Done"
echo "results:      $RESULTS_FILE"
echo "rows:         $(($(wc -l < "$RESULTS_FILE") - 1))"
echo "dispositions: $DISPOSITIONS_FILE"
