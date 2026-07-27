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
# THE VALIDATION COLUMNS
# The shared WPR validator decides whether a site's archive is eligible before
# the browser starts. The caller sets VALIDATION_STATUS, VALIDATION_REASON,
# VALIDATION_HTTP_STATUS, VALIDATION_DETAIL, and ARCHIVE_SHA256 for each site.
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

# ---- per-repetition counters ------------------------------------------------
# The caller's summarize_lcp owns these; reset before every site so a site that
# never reaches measurement reports zeros rather than inheriting the previous
# site's numbers.
reset_measurement_counters() {
  LAST_OBSERVED=0; LAST_RECORDED=0
  LAST_UNFINALIZED=0; LAST_NO_METRIC=0
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
# aggregate-dispositions.py asserts this exact header, so the two move together.
init_dispositions_file() {
  DISPOSITIONS_DIR="${DISPOSITIONS_DIR:-$PWD/crossbench-dispositions}"
  mkdir -p "$DISPOSITIONS_DIR"
  DISPOSITIONS_FILE="$DISPOSITIONS_DIR/${BROWSER_NAME}-dispositions-$(date -u +%Y%m%dT%H%M%SZ).tsv"
  {
    printf 'browser\tbrowser_version\tsite\toutcome\t'
    printf 'validation_status\tvalidation_reason\tvalidation_http_status\tvalidation_detail\tarchive_sha256\t'
    printf 'requested_repetitions\tobserved_repetitions\trecorded_samples\t'
    printf 'dropped_unfinalized\tdropped_no_metric\t'
    printf 'load_window_ms\trunner_image\n'
  } > "$DISPOSITIONS_FILE"
}

# Collapse tab/CR/LF so diagnostic text cannot corrupt the TSV shape.
tsv_clean() {
  local v="$1"
  v="${v//$'\t'/ }"; v="${v//$'\r'/ }"; v="${v//$'\n'/ }"
  printf '%s' "$v"
}

# One row per site, whether or not it produced samples. Empty fields are written
# as "-" so the column count is fixed and the file stays parseable by column/awk.
#
# browser/browser_version are repeated on every row so the artifact is
# self-contained: when every site is excluded the results TSV has no data rows
# at all, and the version would otherwise be unavailable to the attempts insert.
record_disposition() {
  local site="$1" outcome="$2"
  printf '%s\t' \
    "$BROWSER_NAME" "$BROWSER_VERSION" "$site" "$outcome" \
    "$VALIDATION_STATUS" "${VALIDATION_REASON:--}" "${VALIDATION_HTTP_STATUS:--}" \
    "$(tsv_clean "${VALIDATION_DETAIL:--}")" "${ARCHIVE_SHA256:--}" \
    "$MEASURED_REPS" "$LAST_OBSERVED" "$LAST_RECORDED" \
    "$LAST_UNFINALIZED" "$LAST_NO_METRIC" \
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
  # Columns: identity(1-3), outcome(4), validation(5-8),
  # archive identity(9), repetition accounting(10-14), context(15-16).
  awk -F'\t' 'BEGIN { OFS = "\t" }
    { print $3, $4, $5, $6, $7, $12 "/" $10, $13 "/" $14 }' \
    "$DISPOSITIONS_FILE" \
    | sed '1s/.*/site\toutcome\tvalidation\treason\thttp\trecorded\tu\/n/' \
    | { column -t -s "$(printf '\t')" 2>/dev/null || cat; }
  echo
  awk -F'\t' 'NR > 1 { n[$4]++ } END { for (v in n) printf "  %s: %d site(s)\n", v, n[v] }' \
    "$DISPOSITIONS_FILE"

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      printf '### %s LCP — per-site outcomes\n\n' "$BROWSER_NAME"
      printf 'Dropped repetitions: unfinalized = no LCP within the %s window ' "$LOAD_WINDOW"
      printf '(page slower than the window), no-metric = probe wrote nothing.\n\n'
      printf '| site | outcome | validation | reason | HTTP | recorded | unfinalized | no-metric |\n'
      printf '|---|---|---|---|---|---|---|---|\n'
      awk -F'\t' 'NR > 1 {
        printf "| %s | %s | %s | %s | %s | %s/%s | %s | %s |\n",
          $3, $4, $5, $6, $7, $12, $10, $13, $14
      }' "$DISPOSITIONS_FILE"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}
