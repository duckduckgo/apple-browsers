#!/usr/bin/env bash
#
# test-chrome.sh — run the crossbench page-load / LCP test for Chrome against the
# LIVE network, and write a results file.
#
# WPR-free variant: no recorded network, no traffic shaping, no proxy. Chrome
# loads real public sites over the live internet; crossbench drives it and
# extracts LCP from a Perfetto trace (Chromium's
# PageLoadMetrics.NavigationToLargestContentfulPaint) via the navToLCP probe.
#
# NOTE: live network is NOISY — values vary run-to-run with network conditions
# and are NOT comparable to recorded-network (WPR) numbers. This exists to stand
# up the pipeline (measure -> parse -> results file), not for trustworthy
# cross-browser comparison. That needs WPR + a dedicated runner (later).
#
# Prereqs: run provision-macos.sh first (crossbench + extras + Chrome + poetry).
#
# Usage:
#   ./test-chrome.sh [--sites a.com,b.com] [--out FILE]
#
# Each site gets one discarded warm-up load followed by MEASURED_REPS measured
# loads. The first load of a domain pays cold OS-DNS + cold CDN-edge latency the
# later loads don't; a fresh Chrome profile per load means no browser-cache
# carry-over, so only that DNS/edge warmth persists — and it persists across
# crossbench invocations, so the throwaway warm-up primes it for the measured run.
#
set -euo pipefail

# ---- config / args ---------------------------------------------------------
MEASURED_REPS=5
SITES_OVERRIDE=""
RESULTS_FILE=""
CROSSBENCH_DIR="${CROSSBENCH_DIR:-$HOME/Developer/crossbench-upstream}"
PROBE_CONFIG="config/probe/perfetto/navToLCP.config.hjson"
SUITE="navToLCP"          # LCP focus; navToFCP exists in the ps1 as a sibling
LOAD_WINDOW="12s"         # matches runCrossbench.ps1 (--url=<site>,12s)
CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

while [ $# -gt 0 ]; do
  case "$1" in
    --sites) SITES_OVERRIDE="$2"; shift 2 ;;
    --out)   RESULTS_FILE="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

log() { printf '\n=== %s ===\n' "$1"; }

# Site list, copied verbatim from runCrossbench.ps1 $navToSites.
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

# Default results file: ./crossbench-results/chrome-lcp-<utc-stamp>.tsv, relative
# to the invocation dir (CI uploads this directory as an artifact).
if [ -z "$RESULTS_FILE" ]; then
  RESULTS_DIR="${RESULTS_DIR:-$PWD/crossbench-results}"
  mkdir -p "$RESULTS_DIR"
  RESULTS_FILE="$RESULTS_DIR/chrome-lcp-$(date -u +%Y%m%dT%H%M%SZ).tsv"
fi

CHROME_VERSION="$("$CHROME_BIN" --version 2>/dev/null | sed -E 's/^Google Chrome //' || echo unknown)"

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
  local -a vals=()
  local f v ms rep_idx unfinalized=0 no_metric=0 attempts=0 rep=0
  while IFS= read -r f; do
    attempts=$((attempts + 1))
    rep_idx="$(rep_of_path "$f")"
    # `|| true`: under set -e/pipefail a no-match grep would abort the script.
    v="$(grep -Eo 'double_value: -?[0-9]+(\.[0-9]+)?' "$f" | head -1 | awk '{print $2}' || true)"
    if [ -z "$v" ]; then
      # No metric at all. Chrome's PageLoadMetrics emits no LCP slice for an
      # error navigation, so this is what a bot-block or HTTP error looks like
      # from here — indistinguishable, without a NetLog, from a probe failure.
      echo "    attempt rep=$rep_idx: no double_value in metrics -> SKIPPED (no metric emitted; error navigation or probe failure)"
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
  log "Chrome LCP run (LIVE network) — $SUITE, ${#SITES[@]} sites, 1 warm-up + $MEASURED_REPS reps, ${LOAD_WINDOW} window"
  echo "chrome:  $CHROME_VERSION"
  echo "results: $RESULTS_FILE"
  cd "$CROSSBENCH_DIR"
  # .vpython3 is git-tracked and makes crossbench re-exec under Chromium vpython
  # instead of our poetry venv; removal belongs here (run step), not provisioning.
  rm -f .vpython3

  local site out results_path
  for site in "${SITES[@]}"; do
    log "site: $site"
    echo "  plan: 1 warm-up load (discarded) + $MEASURED_REPS measured, ${LOAD_WINDOW} window"
    # Warm-up load (discarded): primes OS-DNS + CDN edge so the measured reps
    # below don't carry first-load cold latency. Output is intentionally ignored,
    # but its exit status is reported — a warm-up that always fails is a signal
    # the site is unreachable rather than slow.
    if poetry run python ./cb.py \
      loading \
      --browser=chrome-stable \
      --probe-config="$PROBE_CONFIG" \
      --repetitions=1 \
      --url="$site,$LOAD_WINDOW" \
      --about-blank-duration=2s \
      --env-validation=skip >/dev/null 2>&1; then
      echo "  warm-up: ok"
    else
      echo "  warm-up: crossbench exited non-zero (ignored, warm-up is discarded)"
    fi

    out="$(mktemp)"
    # --about-blank-duration is REQUIRED: navigating to about:blank after each
    # page forces Chromium to finalize LCP; without it every value comes out -1.
    # No --network arg => live network.
    poetry run python ./cb.py \
      loading \
      --browser=chrome-stable \
      --probe-config="$PROBE_CONFIG" \
      --repetitions="$MEASURED_REPS" \
      --url="$site,$LOAD_WINDOW" \
      --about-blank-duration=2s \
      --debug \
      --env-validation=skip 2>&1 | tee "$out" || echo "WARN: crossbench exited non-zero for $site" >&2

    # `|| true`: under set -e/pipefail a no-match grep would abort the script.
    results_path="$(grep -E '^RESULTS: ' "$out" | tail -1 | sed -E 's/^RESULTS: //' || true)"
    if [ -n "$results_path" ] && [ -d "$results_path" ]; then
      # Logged so a surprising per-attempt result can be traced back to the raw
      # trace and metrics on the runner.
      echo "  results dir: $results_path"
      summarize_lcp "$results_path" "$site"
    else
      echo "  $site: no RESULTS path in crossbench output"
    fi
    rm -f "$out"
  done
}

# ---- main ------------------------------------------------------------------
preflight
# TSV header. Columns: browser, browser_version, site, rep, lcp_ms.
printf 'browser\tbrowser_version\tsite\trep\tlcp_ms\n' > "$RESULTS_FILE"
run_chrome
log "Done"
echo "results: $RESULTS_FILE"
echo "rows:    $(($(wc -l < "$RESULTS_FILE") - 1))"
