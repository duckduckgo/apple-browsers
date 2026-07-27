#!/usr/bin/env python3
#
# aggregate-dispositions.py — turn the per-site disposition TSV that
# test-safari.sh / test-chrome.sh emit into upload-ready rows for
# native_apps.macos_browser_health_nav_to_lcp_attempts (see attempts-schema.sql).
#
# Input TSV (with header), one row per site the run considered. Columns are
# grouped by identity, outcome, WPR validation, repetition accounting, and
# runner context.
# Absent values are written by the shell as "-".
#
# Output TSV (no header). Column order matches the INSERT column list minus
# gh_run_conclusion, which the upload job appends itself — only it knows the
# benchmark job's conclusion.
#
# Unlike aggregate-lcp.py this emits a row for EVERY site, including ones that
# produced no samples — that is the entire point. A domain missing from the
# metrics table is indistinguishable from a domain that was never tested; a row
# here says which it was, and which stage it failed at.
#
# stdlib only; runs on the system python3 of a hosted macOS runner.

import argparse
import calendar
import sys
import time

EXPECTED_HEADER = [
    "browser", "browser_version", "site", "outcome",
    "validation_status", "validation_reason", "validation_http_status",
    "validation_detail",
    "planned_repetitions", "observed_repetitions", "recorded_samples",
    "dropped_unfinalized", "dropped_no_metric",
    "load_window_ms", "runner_image",
]

# Enumerations the shell is allowed to emit. Validated rather than passed through
# so a typo in the shell can't quietly create a new LowCardinality value that
# then has to be cleaned out of the table.
VALID_OUTCOMES = {
    "measured", "partial", "no_samples", "excluded", "infra_error",
}
VALID_VALIDATION_STATUSES = {"ok", "error"}


def to_epoch(value: str) -> str:
    """'2026-07-24T13:10:51Z' or '2026-07-24 13:10:51' (UTC) -> Unix epoch seconds.

    Duplicated from aggregate-lcp.py rather than imported: the sibling's filename
    is hyphenated and so not importable as a module, and importlib gymnastics for
    ten lines would be worse than the copy. Keep the two in sync.
    """
    v = value.strip().replace("T", " ").removesuffix("Z")
    if len(v) != 19 or v[4] != "-" or v[7] != "-" or v[13] != ":" or v[16] != ":":
        sys.exit(f"ERROR: unrecognized datetime {value!r} (want YYYY-MM-DDThh:mm:ssZ)")
    return str(calendar.timegm(time.strptime(v, "%Y-%m-%d %H:%M:%S")))


def as_int(value: str, default: int = -1) -> int:
    """Numeric field, tolerating the shell's '-' placeholder."""
    try:
        return int(value)
    except ValueError:
        return default


def as_str(value: str) -> str:
    """String field: '-' is the shell's placeholder for absent, not a value."""
    return "" if value == "-" else value


def as_nullable_http_status(value: str) -> str:
    """HTTP status for ClickHouse Nullable(UInt16), or TSV NULL."""
    if value in {"", "-"}:
        return r"\N"
    status = as_int(value)
    if not 100 <= status <= 599:
        sys.exit(f"ERROR: invalid HTTP status {value!r}")
    return str(status)


def clean(value: str) -> str:
    """Strip tab/newline so one diagnostic can never become two columns."""
    return value.replace("\t", " ").replace("\r", " ").replace("\n", " ")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", required=True, help="disposition TSV from the test script")
    p.add_argument("--output", required=True, help="upload-ready TSV to write")
    p.add_argument("--run-id", required=True, help="GitHub Actions run id")
    p.add_argument("--start-time", required=True,
                   help="run kickoff time (UTC), stable across re-run attempts")
    p.add_argument("--gh-run-started-at", required=True,
                   help="current ATTEMPT start time (UTC); ReplacingMergeTree version")
    p.add_argument("--webview-type", default="sfr")
    p.add_argument("--webview-channel", default="stable")
    args = p.parse_args()

    start_time = to_epoch(args.start_time)
    gh_run_started_at = to_epoch(args.gh_run_started_at)

    rows = []
    with open(args.input, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        if header != EXPECTED_HEADER:
            sys.exit(f"ERROR: unexpected header {header!r} (want {EXPECTED_HEADER!r})")
        for lineno, line in enumerate(f, start=2):
            line = line.rstrip("\n")
            if not line:
                continue
            fields = line.split("\t")
            if len(fields) != len(EXPECTED_HEADER):
                sys.exit(f"ERROR: {args.input}:{lineno}: expected "
                         f"{len(EXPECTED_HEADER)} fields, got {len(fields)}")
            (_browser, version, site, outcome,
             validation_status, validation_reason, validation_http_status,
             validation_detail,
             planned, observed, recorded, dropped_unfinalized,
             dropped_no_metric,
             load_window_ms, runner_image) = fields
            if outcome not in VALID_OUTCOMES:
                sys.exit(f"ERROR: {args.input}:{lineno}: unknown outcome {outcome!r} "
                         f"(known: {sorted(VALID_OUTCOMES)})")
            if validation_status not in VALID_VALIDATION_STATUSES:
                sys.exit(f"ERROR: {args.input}:{lineno}: unknown validation_status "
                         f"{validation_status!r} "
                         f"(known: {sorted(VALID_VALIDATION_STATUSES)})")
            reason = as_str(validation_reason)
            if validation_status == "ok" and reason:
                sys.exit(f"ERROR: {args.input}:{lineno}: validation_status ok "
                         "must not have validation_reason")
            if validation_status == "error" and not reason:
                sys.exit(f"ERROR: {args.input}:{lineno}: validation_status error "
                         "requires validation_reason")
            rows.append([
                args.run_id,
                start_time,
                site,
                args.webview_type,
                args.webview_channel,
                version,
                outcome,
                validation_status,
                clean(reason),
                as_nullable_http_status(validation_http_status),
                clean(as_str(validation_detail)),
                str(as_int(planned, 0)),
                str(as_int(observed, 0)),
                str(as_int(recorded, 0)),
                str(as_int(dropped_unfinalized, 0)),
                str(as_int(dropped_no_metric, 0)),
                str(as_int(load_window_ms, 0)),
                clean(as_str(runner_image)),
                gh_run_started_at,
            ])

    with open(args.output, "w", encoding="utf-8") as out:
        for row in rows:
            out.write("\t".join(row) + "\n")

    # Counted by outcome, so the step log states the shape of the run without
    # anyone having to open the artifact. Index 6 is `outcome` in the emitted row
    # order: run_id, start_time, domain, webview_type, webview_channel,
    # webview_version, outcome, ...
    tally = {}
    for r in rows:
        tally[r[6]] = tally.get(r[6], 0) + 1
    summary = ", ".join(f"{n} {k}" for k, n in sorted(tally.items()))
    print(f"wrote {len(rows)} row(s) to {args.output} ({summary})")


if __name__ == "__main__":
    main()
