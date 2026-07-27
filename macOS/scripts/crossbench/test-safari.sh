#!/usr/bin/env bash
#
# test-safari.sh — run the crossbench page-load / LCP test for Safari against the
# LIVE network, and write a results file. Safari sibling of test-chrome.sh.
#
# WHY THIS DIFFERS FROM test-chrome.sh:
# Safari/WebKit does NOT produce Chromium Perfetto traces, so the Chrome path's
# perfetto + trace_processor LCP metric (PageLoadMetrics.NavigationToLargest-
# ContentfulPaint) cannot work here. Instead we read LCP directly in the page
# via the standard `largest-contentful-paint` PerformanceObserver entries (the
# Web Vitals LCP API), through crossbench's browser-agnostic `js` probe. See
# crossbench-extras/config/probe/js/navToLCP.safari.config.hjson for the probe.
#
# Three more Safari-specific differences from the Chrome flow:
#   1. NO --about-blank-duration. The `js` probe reads LCP AFTER the story's
#      core workload, with the browser still on the page. about:blank would
#      navigate away before the read and clear the performance timeline. Chrome
#      needs about:blank to finalize LCP into its trace; the JS read does not.
#   2. crossbench drives Safari via safaridriver (WebDriver), which requires
#      "Allow Remote Automation" (`sudo safaridriver --enable` or Safari's
#      Develop menu). Enable it before running — see provision / workflow.
#   3. Every site is pre-flighted with curl and skipped entirely if it is not
#      actually serving us the page. Chrome gets error rejection for free —
#      PageLoadMetrics emits no LCP slice for an error navigation — but the JS
#      LCP API times a bot-block page as readily as a real one, so a 403 would
#      be recorded as a very fast load (reddit's block page measured ~200ms and
#      reached ClickHouse). The status has to come from outside the browser:
#      WebKit implements no in-page API that exposes it. See preflight_site.
#
# NOTE: live network is NOISY — values vary run-to-run with network conditions
# and are NOT comparable to recorded-network (WPR) numbers, nor directly to the
# Chrome numbers (different engine + different LCP extraction path). This exists
# to stand up the pipeline (measure -> parse -> results file), not for
# trustworthy cross-browser comparison.
#
# Prereqs: run provision-macos.sh first (crossbench + extras + poetry), and
# enable safaridriver Remote Automation.
#
# Usage:
#   ./test-safari.sh [--sites a.com,b.com] [--out FILE]
#
# Each site gets one discarded warm-up load followed by MEASURED_REPS measured
# loads (same shape as test-chrome.sh). The warm-up primes OS-DNS + CDN edge so
# the measured reps don't carry first-load cold latency.
set -euo pipefail

# ---- config / args ---------------------------------------------------------
MEASURED_REPS=5
SITES_OVERRIDE=""
RESULTS_FILE=""
CROSSBENCH_DIR="${CROSSBENCH_DIR:-$HOME/Developer/crossbench-upstream}"
PROBE_CONFIG="config/probe/js/navToLCP.safari.config.hjson"
SUITE="navToLCP"
LOAD_WINDOW="12s"         # matches test-chrome.sh (--url=<site>,12s)
LOAD_WINDOW_MS=12000      # same value in ms, recorded so censoring counts from
                          # different runs are only compared at equal windows
SAFARI_APP="/Applications/Safari.app"

# Sourced before the cd into CROSSBENCH_DIR below, so the path is relative to
# this script rather than the working directory.
# shellcheck source=macOS/scripts/crossbench/preflight-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/preflight-lib.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --sites) SITES_OVERRIDE="$2"; shift 2 ;;
    --out)   RESULTS_FILE="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() { printf '\n=== %s ===\n' "$1"; }

# Site list, identical to test-chrome.sh.
SITES=(
  youtube.com wikipedia.org reddit.com amazon.com yelp.com
  weather.com yahoo.com apple.com fandom.com tripadvisor.com
  tiktok.com indeed.com spotify.com nih.gov espn.com
  walmart.com nytimes.com clevelandclinic.org ny.gov quora.com
  zillow.com mayoclinic.org
)
if [ -n "$SITES_OVERRIDE" ]; then
  IFS=',' read -r -a SITES <<< "$SITES_OVERRIDE"
fi

# Default results file: ./crossbench-results/safari-lcp-<utc-stamp>.tsv, relative
# to the invocation dir (CI uploads this directory as an artifact).
if [ -z "$RESULTS_FILE" ]; then
  RESULTS_DIR="${RESULTS_DIR:-$PWD/crossbench-results}"
  mkdir -p "$RESULTS_DIR"
  RESULTS_FILE="$RESULTS_DIR/safari-lcp-$(date -u +%Y%m%dT%H%M%SZ).tsv"
fi

# Safari's user-facing version (e.g. "26.5.2"). CFBundleShortVersionString is the
# marketing version; matches what users see in Safari > About.
SAFARI_VERSION="$(defaults read "$SAFARI_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"

# preflight-lib.sh contract.
BROWSER_NAME=safari
BROWSER_VERSION="$SAFARI_VERSION"
# Sent on the pre-flight request so we're asking the question as the browser we
# are about to measure with. The block we care about is IP-based (measured: the
# runner gets 403 with a Safari UA, a Chrome UA, and no UA alike), but matching
# the UA keeps the pre-flight as close to the real navigation as curl can get.
PREFLIGHT_UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/${SAFARI_VERSION%%.*}.0 Safari/605.1.15"

# ---- preflight -------------------------------------------------------------
preflight() {
  if ! command -v poetry >/dev/null 2>&1; then
    echo "ERROR: poetry not found. Run provision-macos.sh first." >&2
    exit 1
  fi
  if [ ! -f "$CROSSBENCH_DIR/cb.py" ]; then
    echo "ERROR: crossbench not found at $CROSSBENCH_DIR (cb.py missing). Run provision-macos.sh first." >&2
    exit 1
  fi
  if [ ! -f "$CROSSBENCH_DIR/$PROBE_CONFIG" ]; then
    echo "ERROR: probe config missing at $CROSSBENCH_DIR/$PROBE_CONFIG. provision-macos.sh copies the extras in." >&2
    exit 1
  fi
  if [ ! -d "$SAFARI_APP" ]; then
    echo "ERROR: Safari not found at $SAFARI_APP." >&2
    exit 1
  fi
}

# The curl pre-flight, the disposition record and the per-site reporting live in
# preflight-lib.sh, shared with test-chrome.sh. Safari is the browser that needs
# it for CORRECTNESS rather than economy: WebKit implements no in-page API that
# exposes the document's HTTP status (PerformanceNavigationTiming.responseStatus
# is unimplemented — mdn/browser-compat-data records version_added:false, and it
# measured undefined on Safari 26.4), safaridriver's WebDriver-classic protocol
# has no network surface either, and the JS LCP API happily times a bot-block
# page. curl also returns the redirect chain, which Safari withholds too: a
# cross-origin redirect zeroes its navigation-timing internals.

# Parse a crossbench RESULTS dir: for every per-repetition js.json the `js` probe
# wrote, pull `lcp_ms`. Per-repetition files live at
#   .../stories/<story>/<rep>/<temperature>/js.json
# so the 3-segment glob after /stories/ isolates them from the shallower MERGED
# story-level / browser-level js.json that crossbench also writes (those would
# inflate n). A repetition whose LCP never fired is emitted by the probe as
# lcp_ms == -1; count those separately, matching test-chrome.sh's handling of
# unfinalized (-1) Chrome iterations. Repetitions whose navigation returned an
# HTTP error are discarded too — see the http_status comment below. Appends
# one TSV row per valid value to RESULTS_FILE and prints a per-site summary.
# crossbench lays results out as
#   .../stories/<story>/<repetition>/<temperature>/...
# so the path itself carries the repetition index. Deriving it from the path
# rather than from a counter keeps the logged repetition number meaningful when
# some repetitions are discarded, and stable regardless of directory order.
rep_of_path() {
  awk -F/ '{for (i = 1; i <= NF; i++) if ($i == "stories") { print $(i + 2); exit }}' <<< "$1"
}

summarize_lcp() {
  local results_path="$1" site="$2"
  # The caller reads these back for the disposition record, so every early
  # `return` below must leave them consistent — hence the reset here and the
  # single assignment point after the loop.
  reset_measurement_counters
  local -a vals=()
  local f info v http_status rep_idx unfinalized=0 blocked=0 no_metric=0 attempts=0 rep=0
  # Every status seen this site, reported in the summary below. Without this the
  # log can't distinguish "the UA doesn't expose responseStatus" (all -1, guard
  # inert) from "the navigation really did return 2xx" (guard working, the page
  # is just genuinely fast) — the two look identical in the lcp_ms line.
  local -a statuses=()
  while IFS= read -r f; do
    # stdlib python: read lcp_ms and http_status out of the flattened js.json as
    # "<lcp_ms> <http_status>". Prints nothing if lcp_ms is absent so the `-z`
    # guard below skips the file.
    info="$(/usr/bin/python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
v = d.get("lcp_ms")
if isinstance(v, (int, float)):
    s = d.get("http_status")
    print(f"{v:.1f}", int(s) if isinstance(s, (int, float)) else -1)
' "$f" || true)"
    attempts=$((attempts + 1))
    rep_idx="$(rep_of_path "$f")"
    if [ -z "$info" ]; then
      echo "    attempt rep=$rep_idx: no lcp_ms in js.json -> SKIPPED (probe wrote no metric)"
      no_metric=$((no_metric + 1))
      continue
    fi
    v="${info%% *}"
    http_status="${info##* }"
    statuses+=("$http_status")
    # Discard error navigations. The LCP API measures whatever painted, so a
    # bot-block or error page yields a small, plausible-looking value — which is
    # worse than no value at all, because nothing downstream can tell it apart
    # from a genuinely fast page (a 403 Reddit block page measured ~200ms).
    #
    # MEASURED 2026-07-25, Safari 26.4 (21624.1.16.11.4): WebKit does not
    # implement PerformanceNavigationTiming.responseStatus at all — MDN's
    # browser-compat-data records Safari as version_added:false, not merely
    # undocumented — so http_status is -1 for every repetition and this filter
    # never fires. Blocked sites are handled by preflight_site instead, which
    # reads the real status from outside the browser and skips the site before it
    # is ever measured. This filter is kept only because it costs nothing and
    # starts working the day WebKit ships the field; it is NOT the protection.
    # The http_status=[...] line in the summary is how you confirm it is inert.
    #
    # Deliberately >= 400 rather than "not 2xx": per spec responseStatus is the
    # status of the FINAL response, but a UA reporting the FIRST response would
    # make a not-2xx test throw away every site that redirects (reddit.com ->
    # www.reddit.com is a 301). Erring toward keeping data is right here — a
    # stray 3xx costs one noisy sample, whereas over-filtering silently empties
    # whole domains. The -1 case falls open through the same comparison.
    if [ "$http_status" -ge 400 ]; then
      echo "    attempt rep=$rep_idx: lcp_ms=$v http_status=$http_status -> SKIPPED (HTTP error / bot-block page)"
      blocked=$((blocked + 1))
      continue
    fi
    if awk -v v="$v" 'BEGIN{exit !(v < 0)}'; then
      echo "    attempt rep=$rep_idx: lcp_ms=-1 http_status=$http_status -> SKIPPED (no LCP entry within ${LOAD_WINDOW} window)"
      unfinalized=$((unfinalized + 1))
      continue
    fi
    vals+=("$v")
    rep=$((rep + 1))
    echo "    attempt rep=$rep_idx: lcp_ms=$v http_status=$http_status -> recorded"
    printf 'safari\t%s\t%s\t%d\t%s\n' "$SAFARI_VERSION" "$site" "$rep" "$v" >> "$RESULTS_FILE"
  done < <(find "$results_path" -path '*/stories/*/*/*/js.json' 2>/dev/null | sort)

  # Single assignment point for the disposition counters: everything after this
  # only reports. observed counts repetitions that produced probe output at all,
  # so observed < MEASURED_REPS means the browser or harness stopped early, while
  # the dropped_* counters account for output that was unusable.
  LAST_OBSERVED="$attempts"
  LAST_RECORDED="${#vals[@]}"
  LAST_UNFINALIZED="$unfinalized"
  LAST_NO_METRIC="$no_metric"
  LAST_HTTP_ERROR="$blocked"
  # Always print the tally, including the zero-attempt case — "expected 5, saw 0"
  # is a different failure from "saw 5, discarded 5" and the log should say which.
  echo "  $site: attempts=$attempts/$MEASURED_REPS recorded=${#vals[@]} unfinalized=$unfinalized http-error=$blocked no-metric=$no_metric"
  # Distinct statuses, sorted. "http_status=[-1]" means this Safari doesn't
  # expose responseStatus, so the HTTP >= 400 filter above is inert and cannot
  # be relied on to reject bot-block pages.
  if [ "${#statuses[@]}" -gt 0 ]; then
    echo "  $site: http_status=[$(printf '%s\n' "${statuses[@]}" | sort -un | paste -sd, -)]"
  fi
  if [ "$attempts" -eq 0 ]; then
    echo "  $site: NO js.json FILES FOUND under $results_path (probe did not run)"
    return
  fi
  if [ "$unfinalized" -gt 0 ]; then
    echo "  WARNING: $site: $unfinalized repetition(s) with no LCP entry (-1)." >&2
  fi
  if [ "$blocked" -gt 0 ]; then
    echo "  WARNING: $site: $blocked repetition(s) discarded — HTTP >= 400 (error or bot-block page)." >&2
  fi
  if [ "${#vals[@]}" -eq 0 ]; then
    if [ "$blocked" -gt 0 ]; then
      echo "  $site: NO VALID LCP — every repetition returned an HTTP error."
    else
      echo "  $site: NO LCP VALUES PARSED (check that Safari exposes largest-contentful-paint entries)"
    fi
    return
  fi
  printf '  %s: lcp_ms=[%s] ' "$site" "$(IFS=,; echo "${vals[*]}")"
  printf '%s\n' "${vals[@]}" | awk '{s+=$1; n++} END{printf "mean=%.1f n=%d\n", s/n, n}'
}

# ---- run -------------------------------------------------------------------
run_safari() {
  log "Safari LCP run (LIVE network) — $SUITE, ${#SITES[@]} sites, 1 warm-up + $MEASURED_REPS reps, ${LOAD_WINDOW} window"
  echo "safari:  $SAFARI_VERSION"
  echo "results: $RESULTS_FILE"
  cd "$CROSSBENCH_DIR"
  # .vpython3 is git-tracked and makes crossbench re-exec under Chromium vpython
  # instead of our poetry venv; removal belongs here (run step), not provisioning.
  rm -f .vpython3

  local site out results_path outcome
  for site in "${SITES[@]}"; do
    log "site: $site"
    reset_measurement_counters
    # Pre-flight before spending any browser time on this site. Writes the
    # disposition row itself when it says skip.
    handle_preflight "$site" || continue

    echo "  plan: 1 warm-up load (discarded) + $MEASURED_REPS measured, ${LOAD_WINDOW} window"
    # Warm-up load (discarded): primes OS-DNS + CDN edge. Output ignored, but the
    # exit status is reported — a warm-up that always fails is a signal the site
    # is unreachable rather than slow.
    if poetry run python ./cb.py \
      loading \
      --browser=safari \
      --probe-config="$PROBE_CONFIG" \
      --repetitions=1 \
      --url="$site,$LOAD_WINDOW" \
      --env-validation=skip >/dev/null 2>&1; then
      echo "  warm-up: ok"
    else
      echo "  warm-up: crossbench exited non-zero (ignored, warm-up is discarded)"
    fi

    out="$(mktemp)"
    # NO --about-blank-duration on purpose (see header). No --network => live.
    poetry run python ./cb.py \
      loading \
      --browser=safari \
      --probe-config="$PROBE_CONFIG" \
      --repetitions="$MEASURED_REPS" \
      --url="$site,$LOAD_WINDOW" \
      --debug \
      --env-validation=skip 2>&1 | tee "$out" || echo "WARN: crossbench exited non-zero for $site" >&2

    # `|| true`: under set -e/pipefail a no-match grep would abort the script.
    results_path="$(grep -E '^RESULTS: ' "$out" | tail -1 | sed -E 's/^RESULTS: //' || true)"
    if [ -n "$results_path" ] && [ -d "$results_path" ]; then
      # Logged so a surprising per-attempt result can be traced back to the raw
      # probe output on the runner.
      echo "  results dir: $results_path"
      summarize_lcp "$results_path" "$site"
      outcome="$(classify_outcome)"
      record_disposition "$site" "$outcome" "$PF_VERDICT" "$MEASURED_REPS"
    else
      echo "  $site: no RESULTS path in crossbench output"
      # Distinct from "blocked": the site was reachable, the harness failed. The
      # two must not be conflated or fail-open can't be audited. preflight_verdict
      # is kept as-is so a fail-open pre-flight followed by a harness failure is
      # still visible as two separate facts.
      echo "::warning title=Harness failure::$site: crossbench produced no RESULTS path"
      record_disposition "$site" infra_error "$PF_VERDICT" "$MEASURED_REPS"
    fi
    rm -f "$out"
  done
}

# ---- main ------------------------------------------------------------------
preflight
# TSV header. Columns match test-chrome.sh: browser, browser_version, site, rep, lcp_ms.
printf 'browser\tbrowser_version\tsite\trep\tlcp_ms\n' > "$RESULTS_FILE"
init_dispositions_file
run_safari
report_dispositions
log "Done"
echo "results:      $RESULTS_FILE"
echo "rows:         $(($(wc -l < "$RESULTS_FILE") - 1))"
echo "dispositions: $DISPOSITIONS_FILE"
