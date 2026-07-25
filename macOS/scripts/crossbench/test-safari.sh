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
#   3. Repetitions whose navigation returned HTTP >= 400 are discarded here.
#      Chrome gets this for free — PageLoadMetrics emits no LCP slice for an
#      error navigation — but the JS LCP API times a bot-block page as readily
#      as a real one, so without this filter a 403 shows up as a fast load.
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
SAFARI_APP="/Applications/Safari.app"

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
summarize_lcp() {
  local results_path="$1" site="$2"
  local -a vals=()
  local f info v http_status unfinalized=0 blocked=0 rep=0
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
    [ -z "$info" ] && continue
    v="${info%% *}"
    http_status="${info##* }"
    # Discard error navigations. The LCP API measures whatever painted, so a
    # bot-block or error page yields a small, plausible-looking value — which is
    # worse than no value at all, because nothing downstream can tell it apart
    # from a genuinely fast page (a 403 Reddit block page measured ~200ms).
    #
    # Deliberately >= 400 rather than "not 2xx": per spec responseStatus is the
    # status of the FINAL response, but WebKit's support for the field is
    # unverified, and a UA reporting the FIRST response would make a not-2xx
    # test throw away every site that redirects (reddit.com -> www.reddit.com is
    # a 301). Erring toward keeping data is right here — a stray 3xx costs one
    # noisy sample, whereas over-filtering silently empties whole domains. The
    # -1 "UA didn't expose it" case falls open through the same comparison.
    if [ "$http_status" -ge 400 ]; then
      blocked=$((blocked + 1))
      continue
    fi
    if awk -v v="$v" 'BEGIN{exit !(v < 0)}'; then
      unfinalized=$((unfinalized + 1))
      continue
    fi
    vals+=("$v")
    rep=$((rep + 1))
    printf 'safari\t%s\t%s\t%d\t%s\n' "$SAFARI_VERSION" "$site" "$rep" "$v" >> "$RESULTS_FILE"
  done < <(find "$results_path" -path '*/stories/*/*/*/js.json' 2>/dev/null | sort)

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

  local site out results_path
  for site in "${SITES[@]}"; do
    log "site: $site"
    # Warm-up load (discarded): primes OS-DNS + CDN edge. Output ignored.
    poetry run python ./cb.py \
      loading \
      --browser=safari \
      --probe-config="$PROBE_CONFIG" \
      --repetitions=1 \
      --url="$site,$LOAD_WINDOW" \
      --env-validation=skip >/dev/null 2>&1 || true

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
      summarize_lcp "$results_path" "$site"
    else
      echo "  $site: no RESULTS path in crossbench output"
    fi
    rm -f "$out"
  done
}

# ---- main ------------------------------------------------------------------
preflight
# TSV header. Columns match test-chrome.sh: browser, browser_version, site, rep, lcp_ms.
printf 'browser\tbrowser_version\tsite\trep\tlcp_ms\n' > "$RESULTS_FILE"
run_safari
log "Done"
echo "results: $RESULTS_FILE"
echo "rows:    $(($(wc -l < "$RESULTS_FILE") - 1))"
