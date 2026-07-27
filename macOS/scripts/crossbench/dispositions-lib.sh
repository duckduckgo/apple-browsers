# shellcheck shell=bash
#
# dispositions-lib.sh — shared load-accounting machinery for the browser
# runners. Sourced, not executed.
#
# WHAT THIS IS FOR
# A domain missing from the metrics table is indistinguishable from a domain
# nobody tested. This library writes one row per site saying what happened to it,
# whether or not it produced samples: the disposition record, which becomes the
# ClickHouse attempts table (see attempts-schema.sql).
#
# The accounting is per repetition. A site is replayed N times and some of those
# repetitions still produce no usable number — because LCP never finalized inside
# the load window, or because the probe wrote nothing at all. The caller's
# summarize_lcp keeps the counts and hands them back through the LAST_* globals;
# classify_outcome turns them into the one-column summary that is `outcome`.
#
# THE LANDING COLUMNS
# final_url, landed_offsite, final_status and their neighbours describe WHERE a
# load actually ended up, which is not always the requested site: an
# interstitial, a consent wall or a country variant all still paint, and still
# produce a plausible LCP number. A runner that can observe the landed URL sets
# the PF_* globals before calling record_disposition; one that cannot leaves them
# unset, and they are written as "-".
#
# CONTRACT — the caller must set these before sourcing is useful:
#   BROWSER_NAME      'chrome' | 'safari'
#   BROWSER_VERSION   version string recorded on every row
#   MEASURED_REPS     repetitions the run intends per site
#   LOAD_WINDOW       dwell per load, human form ('12s'), for log text
#   LOAD_WINDOW_MS    same value in ms, recorded per row
# and must call init_dispositions_file once before the site loop.

# Runner identity, recorded per row. GitHub sets ImageOS/ImageVersion on hosted
# runners; the run log that would otherwise tell you which image ran is deleted
# after 90 days, while these rows live for a year.
RUNNER_IMAGE="${ImageOS:-$(uname -s)-$(uname -r)}${ImageVersion:+/$ImageVersion}"

# ---- landing --------------------------------------------------------------
# 1 when the load landed on a host that isn't the requested domain or a
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

# ---- per-repetition counters ------------------------------------------------
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

# The overall verdict, from the counters above. Skips and harness failures are
# passed explicitly by the caller instead.
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
# Columns are grouped by what they describe — where the load landed, then how
# many repetitions survived — because conflating the two is what makes the record
# unreadable. `outcome` is the one-column summary. aggregate-dispositions.py
# asserts this exact header, so the two move together.
init_dispositions_file() {
  DISPOSITIONS_DIR="${DISPOSITIONS_DIR:-$PWD/crossbench-dispositions}"
  mkdir -p "$DISPOSITIONS_DIR"
  DISPOSITIONS_FILE="$DISPOSITIONS_DIR/${BROWSER_NAME}-dispositions-$(date -u +%Y%m%dT%H%M%SZ).tsv"
  {
    printf 'browser\tbrowser_version\tsite\toutcome\t'
    printf 'preflight_verdict\tfinal_status\tstatus_chain\tredirects\tbytes\tfinal_url\tlanded_offsite\tblocked_marker\t'
    printf 'attempted\tobserved\trecorded\tdropped_unfinalized\tdropped_no_metric\tdropped_http_error\t'
    printf 'load_window_ms\trunner_image\n'
  } > "$DISPOSITIONS_FILE"
}

# Collapse tab/CR/LF to a space so one value can never become two columns — or,
# worse, two rows. status_chain, final_url and blocked_marker are all derived from
# a network response and so are attacker-influenced; a single stray newline in one
# of them corrupts the whole file, and the aggregator then rejects every row
# rather than just the bad one.
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
