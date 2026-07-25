# shellcheck shell=bash
#
# preflight-lib.sh — shared load-quality machinery for test-chrome.sh and
# test-safari.sh. Sourced, not executed.
#
# WHAT THIS IS FOR
# Only real site loads belong in the benchmark. Two different things can stop a
# site from being measured, and they need to be told apart:
#
#   Stage 1 — pre-flight. Before any browser time is spent, curl asks whether the
#   site is actually serving us the page. If it isn't, the site is skipped
#   entirely and recorded as skipped. A whole-site decision.
#
#   Stage 2 — measurement. The site loaded, the browser ran it N times, and some
#   repetitions still produced no usable number. A per-repetition accounting,
#   kept by the caller's summarize_lcp and read back through the LAST_* globals.
#
# Both land in one row per site in the disposition record, which becomes the
# ClickHouse attempts table (see attempts-schema.sql). A domain missing from the
# metrics table is otherwise indistinguishable from a domain nobody tested.
#
# WHY THE PRE-FLIGHT IS OUT OF PROCESS
# Safari needs it for correctness: the JS LCP API times a bot-block page as
# readily as a real one, so a 403 gets recorded as a very fast load (reddit's
# block page measured ~200ms and reached ClickHouse), and WebKit implements no
# in-page API exposing the status — PerformanceNavigationTiming.responseStatus is
# unimplemented, not merely undocumented. Chrome already fails closed, because
# PageLoadMetrics emits no LCP slice for an error navigation. Chrome still runs
# the pre-flight for two other reasons: it stops the harness burning ~8 min per
# site to produce nothing, and it turns Chrome's ambiguous "no metric emitted"
# into a stated reason instead of a guess.
#
# CONTRACT — the caller must set these before sourcing is useful:
#   BROWSER_NAME      'chrome' | 'safari'
#   BROWSER_VERSION   version string recorded on every row
#   PREFLIGHT_UA      User-Agent sent on the pre-flight request
#   MEASURED_REPS     repetitions the run intends per site
#   LOAD_WINDOW       dwell per load, human form ('12s'), for log text
#   LOAD_WINDOW_MS    same value in ms, recorded per row
# and must call init_dispositions_file once before the site loop.

PREFLIGHT_TIMEOUT="${PREFLIGHT_TIMEOUT:-20}"   # seconds; a pre-flight normally takes <1s

# Runner identity, recorded per row. GitHub sets ImageOS/ImageVersion on hosted
# runners; the run log that would otherwise tell you which image ran is deleted
# after 90 days, while these rows live for a year.
RUNNER_IMAGE="${ImageOS:-$(uname -s)-$(uname -r)}${ImageVersion:+/$ImageVersion}"

# Bot-wall fingerprints, for the case a wall is served with a 2xx status — which
# happens: reddit returns 403 to a hosted runner but 200 plus a "Please wait for
# verification" wall to a residential IP, so status alone is not sufficient.
#
# Every entry is a phrase or code token that does not occur in ordinary page
# prose. Bare words like "captcha" or "access denied" are deliberately EXCLUDED:
# a false positive silently drops a whole domain from the benchmark, which is a
# worse outcome than one contaminated sample, so this list errs toward missing a
# wall rather than rejecting a real page. The matched marker is logged and
# recorded, so a false positive is diagnosable rather than mysterious.
WALL_MARKERS='blocked by network security|please wait for verification|checking if the site connection is secure|cf-browser-verification|cf_chl_opt|pardon our interruption|access to this page has been denied|request unsuccessful\. incapsula incident|unusual traffic from your computer network|enable javascript and cookies to continue'

# ---- stage 1: out-of-browser pre-flight -------------------------------------
# Ask whether a site is actually serving us the page, before spending browser
# time on it.
#
# Known limitation: this is a DIFFERENT request from the browser's — different
# TLS fingerprint, no browser cookie jar — so a blocker fingerprinting the client
# could in principle treat the two differently. Measured 2026-07-25 from a
# blocked IP they agreed closely: curl received 190,240 bytes of reddit's wall,
# Safari 190,292 bytes of the same wall.
#
# Sets the PF_* globals. Never fails the script: an unreachable pre-flight yields
# verdict "preflight_error" and the site is measured anyway, so a transient
# network fault can never silently empty a domain.
preflight_site() {
  local site="$1" body hdrs stats
  PF_VERDICT=""; PF_FINAL_STATUS=""; PF_CHAIN=""; PF_REDIRECTS=""
  PF_BYTES=""; PF_FINAL_URL=""; PF_MARKER=""
  body="$(mktemp)"
  hdrs="$(mktemp)"
  # -L: the final response is what the browser would render; without it you only
  # ever see the apex -> www 301 and learn nothing. -D alongside -L records every
  # response's headers, so the whole status chain comes from one request.
  if stats="$(curl -sS -o "$body" -D "$hdrs" -L --max-time "$PREFLIGHT_TIMEOUT" \
      -A "$PREFLIGHT_UA" \
      -w '%{http_code}\t%{num_redirects}\t%{size_download}\t%{url_effective}' \
      "https://$site" 2>/dev/null)"; then
    IFS=$'\t' read -r PF_FINAL_STATUS PF_REDIRECTS PF_BYTES PF_FINAL_URL <<< "$stats"
    PF_CHAIN="$(awk 'toupper($1) ~ /^HTTP\// { print $2 }' "$hdrs" | paste -sd, - || true)"
    # `head -1`, not grep's -m1: -m1 stops after the first matching LINE, and -o
    # then prints every match ON that line. A minified Cloudflare wall carries
    # cf_chl_opt seven times in one <script>, which yielded a seven-LINE marker
    # and split the row into eight unparseable TSV lines.
    PF_MARKER="$(grep -ioE "$WALL_MARKERS" "$body" 2>/dev/null | head -1 || true)"
    if ! [[ "$PF_FINAL_STATUS" =~ ^[0-9]+$ ]] || [ "$PF_FINAL_STATUS" -lt 100 ]; then
      # curl reports 000 when it never got a response at all.
      PF_VERDICT="preflight_error"
    elif [ "$PF_FINAL_STATUS" -ge 400 ]; then
      PF_VERDICT="blocked_status"
    elif [ -n "$PF_MARKER" ]; then
      PF_VERDICT="blocked_marker"
    else
      PF_VERDICT="ok"
    fi
  else
    PF_VERDICT="preflight_error"
  fi
  rm -f "$body" "$hdrs"
}

# 1 when the pre-flight landed on a host that isn't the requested domain or a
# subdomain of it — a consent wall, a country variant or a login page. Computed
# here rather than at query time because only the harness knows which domain was
# REQUESTED; final_url alone can't be compared without re-deriving host matching
# in every query. "www." is stripped on both sides: apex -> www is the normal
# case, not a redirect worth flagging.
landed_offsite() {
  local site="$1" url="${2:-}" host
  [ -z "$url" ] && { echo 0; return; }
  host="${url#*://}"; host="${host%%/*}"; host="${host%%:*}"
  host="${host#www.}"; site="${site#www.}"
  if [ "$host" = "$site" ] || [ "$host" != "${host%".$site"}" ]; then
    echo 0
  else
    echo 1
  fi
}

# ---- stage 2: per-repetition counters --------------------------------------
# The caller's summarize_lcp owns these; reset before every site so a site that
# never reaches measurement reports zeros rather than inheriting the previous
# site's numbers.
#
# LAST_HTTP_ERROR stays 0 on both browsers today: neither harness can see the
# document's HTTP status from inside the page. The counter exists so the two
# browsers share one row shape and so it starts working if that changes.
reset_measurement_counters() {
  LAST_OBSERVED=0; LAST_RECORDED=0
  LAST_UNFINALIZED=0; LAST_NO_METRIC=0; LAST_HTTP_ERROR=0
}

# The overall verdict, from the stage-2 counters. Stage-1 skips and harness
# failures are passed explicitly by the caller instead.
classify_outcome() {
  if [ "$LAST_RECORDED" -eq 0 ]; then
    echo no_samples
  elif [ "$LAST_RECORDED" -lt "$MEASURED_REPS" ]; then
    echo partial
  else
    echo measured
  fi
}

# ---- disposition record ----------------------------------------------------
# Per-site disposition file. Deliberately NOT in crossbench-results/ — the CI
# aggregate step globs that directory for *.tsv and feeds the first match to
# aggregate-lcp.py, so a second .tsv alongside the results would sort first and
# be aggregated as if it were the measurements.
#
# Columns are grouped by the STAGE they describe, because conflating them is what
# makes the record unreadable: preflight_verdict=ok next to recorded=0 reads as
# "fine" unless the two are visibly separate concerns. `outcome` is the
# one-column summary of both. aggregate-dispositions.py asserts this exact
# header, so the two move together.
init_dispositions_file() {
  DISPOSITIONS_DIR="${DISPOSITIONS_DIR:-$PWD/crossbench-dispositions}"
  mkdir -p "$DISPOSITIONS_DIR"
  DISPOSITIONS_FILE="$DISPOSITIONS_DIR/${BROWSER_NAME}-dispositions-$(date -u +%Y%m%dT%H%M%SZ).tsv"
  printf 'browser\tbrowser_version\tsite\toutcome\t'                        > "$DISPOSITIONS_FILE"
  printf 'preflight_verdict\tfinal_status\tstatus_chain\tredirects\tbytes\tfinal_url\tlanded_offsite\tblocked_marker\t' >> "$DISPOSITIONS_FILE"
  printf 'attempted\tobserved\trecorded\tdropped_unfinalized\tdropped_no_metric\tdropped_http_error\t' >> "$DISPOSITIONS_FILE"
  printf 'load_window_ms\trunner_image\n'                                   >> "$DISPOSITIONS_FILE"
}

# Collapse tab/CR/LF to a space so one value can never become two columns — or,
# worse, two rows. status_chain, final_url and blocked_marker are all derived from
# a network response and so are attacker-influenced; a single stray newline in one
# of them corrupts the whole file, and the aggregator then rejects every row
# rather than just the bad one. Belt to the marker fix's braces.
tsv_clean() {
  local v="$1"
  v="${v//$'\t'/ }"; v="${v//$'\r'/ }"; v="${v//$'\n'/ }"
  printf '%s' "$v"
}

# One row per site, whether or not it produced samples. Empty fields are written
# as "-" so the column count is fixed and the file stays parseable by column/awk.
#
# browser/browser_version are repeated on every row so the artifact is
# self-contained: when every site is blocked the results TSV has no data rows at
# all, and the version would otherwise be unrecoverable for the attempts insert.
record_disposition() {
  local site="$1" outcome="$2" verdict="$3" attempted="$4"
  printf '%s\t' \
    "$BROWSER_NAME" "$BROWSER_VERSION" "$site" "$outcome" \
    "$verdict" "${PF_FINAL_STATUS:--}" "$(tsv_clean "${PF_CHAIN:--}")" "${PF_REDIRECTS:--}" \
    "${PF_BYTES:--}" "$(tsv_clean "${PF_FINAL_URL:--}")" "$(landed_offsite "$site" "${PF_FINAL_URL:-}")" \
    "$(tsv_clean "${PF_MARKER:--}")" \
    "$attempted" "$LAST_OBSERVED" "$LAST_RECORDED" "$LAST_UNFINALIZED" \
    "$LAST_NO_METRIC" "$LAST_HTTP_ERROR" \
    "$LOAD_WINDOW_MS" >> "$DISPOSITIONS_FILE"
  printf '%s\n' "$RUNNER_IMAGE" >> "$DISPOSITIONS_FILE"
}

# Log the pre-flight result, and decide whether to measure. Returns 1 when the
# caller should skip the site (the disposition row is already written).
handle_preflight() {
  local site="$1" reason
  preflight_site "$site"
  echo "  pre-flight: verdict=$PF_VERDICT status=[${PF_CHAIN:--}] final=${PF_FINAL_STATUS:--} redirects=${PF_REDIRECTS:--} bytes=${PF_BYTES:--}"
  if [ -n "$PF_FINAL_URL" ] && [ "$PF_FINAL_URL" != "https://$site/" ]; then
    # Recorded because the measured page may not be the requested one: a consent
    # wall, a country variant or a login page all land here.
    echo "  pre-flight: requested https://$site -> landed $PF_FINAL_URL"
  fi
  case "$PF_VERDICT" in
    blocked_status|blocked_marker)
      if [ "$PF_VERDICT" = "blocked_status" ]; then
        reason="HTTP $PF_FINAL_STATUS (chain [$PF_CHAIN])"
      else
        reason="bot-wall marker \"$PF_MARKER\" on HTTP $PF_FINAL_STATUS"
      fi
      echo "  $site: SKIPPED — $reason. Site not measured; 0 samples recorded."
      # A GitHub annotation surfaces this on the run page instead of leaving it
      # buried in crossbench's --debug output.
      echo "::warning title=Site skipped::$site: $reason"
      # attempted=0: the browser never ran, which is a different fact from "ran
      # 5 times and recorded nothing".
      record_disposition "$site" skipped_blocked "$PF_VERDICT" 0
      return 1
      ;;
    preflight_error)
      # Fail open: never let a flaky pre-flight be the reason a domain has no
      # data. Measure, and let the disposition record show the pre-flight could
      # not be trusted for this run.
      echo "  pre-flight: could not reach $site — measuring anyway (fail open)"
      ;;
  esac
  return 0
}

# ---- reporting -------------------------------------------------------------
# The disposition record is the answer to "why does this domain have no data?".
# Printed to the log for a human, written as a TSV artifact for the ClickHouse
# attempts insert, and summarised on the run page via GITHUB_STEP_SUMMARY.
report_dispositions() {
  printf '\n=== Per-site dispositions ===\n'
  if [ ! -s "$DISPOSITIONS_FILE" ]; then
    echo "(none recorded)"
    return
  fi
  # Columns: browser(1) browser_version(2) site(3) outcome(4)
  # preflight_verdict(5) final_status(6) status_chain(7) redirects(8) bytes(9)
  # final_url(10) landed_offsite(11) blocked_marker(12)
  # attempted(13) observed(14) recorded(15) dropped_unfinalized(16)
  # dropped_no_metric(17) dropped_http_error(18)
  # load_window_ms(19) runner_image(20)
  #
  # A projection rather than the whole file: 20 columns of column -t wraps and
  # becomes unreadable in a CI log. The full row set is in the uploaded artifact.
  # The dropped counters are shown as u/n/h (unfinalized / no-metric / http) —
  # unfinalized is the one that matters, it means the page is SLOWER than the
  # load window, not that anything went wrong.
  awk -F'\t' 'BEGIN { OFS = "\t" }
    { print $3, $4, $5, $7, $15 "/" $13, $16 "/" $17 "/" $18, ($11 == 1 ? $10 : "") }' \
    "$DISPOSITIONS_FILE" \
    | sed '1s/.*/site\toutcome\tpreflight\tstatus_chain\trecorded\tu\/n\/h\toffsite_url/' \
    | { column -t -s "$(printf '\t')" 2>/dev/null || cat; }
  echo
  awk -F'\t' 'NR > 1 { n[$4]++ } END { for (v in n) printf "  %s: %d site(s)\n", v, n[v] }' \
    "$DISPOSITIONS_FILE"

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      printf '### %s LCP — per-site outcomes\n\n' "$BROWSER_NAME"
      printf 'Dropped repetitions: unfinalized = no LCP within the %s window ' "$LOAD_WINDOW"
      printf '(page slower than the window), no-metric = probe wrote nothing.\n\n'
      printf '| site | outcome | pre-flight | status chain | recorded | unfinalized | no-metric | landed |\n'
      printf '|---|---|---|---|---|---|---|---|\n'
      awk -F'\t' 'NR > 1 {
        printf "| %s | %s | %s | %s | %s/%s | %s | %s | %s |\n",
          $3, $4, $5, $7, $15, $13, $16, $17, ($11 == 1 ? $10 : "-")
      }' "$DISPOSITIONS_FILE"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}
