#!/usr/bin/env python3
#
# aggregate-dispositions.py — turn the per-site disposition TSV that
# test-safari.sh / test-chrome.sh emit into upload-ready rows for
# native_apps.macos_browser_health_nav_to_lcp_attempts (see attempts-schema.sql).
#
# Input TSV (with header), one row per site the run considered. Columns are
# grouped by identity, outcome, WPR validation, runtime failure, repetition
# accounting, and runner context.
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
import csv
import re
import sys
import time
from typing import List, Optional

EXPECTED_HEADER = [
    "browser", "browser_version", "site", "outcome",
    "validation_status", "validation_reason", "validation_http_status",
    "validation_detail", "archive_sha256",
    "failure_stage", "failure_reason", "failure_detail",
    "requested_repetitions", "observed_repetitions", "recorded_samples",
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
VALID_HANDOFF_FAILURE_REASONS = {
    "validation_manifest_missing",
    "validation_manifest_schema_mismatch",
    "validation_result_missing",
    "validation_result_ambiguous",
    "validation_verdict_invalid",
    "validation_http_status_invalid",
    "validated_archive_name_invalid",
    "validated_archive_missing",
    "validated_archive_hash_invalid",
    "validated_archive_hash_mismatch",
}


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


UINT32_MAX = 2**32 - 1
UINT64_MAX = 2**64 - 1
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def as_uint32(value: str, field: str, location: str) -> int:
    """Parse a required ClickHouse UInt32 without silently repairing bad data."""
    try:
        parsed = int(value)
    except ValueError:
        sys.exit(f"ERROR: {location}: {field} must be an integer, got {value!r}")
    if not 0 <= parsed <= UINT32_MAX:
        sys.exit(f"ERROR: {location}: {field} must be in 0..{UINT32_MAX}, got {value!r}")
    return parsed


def as_uint64(value: str, field: str, location: str) -> int:
    try:
        parsed = int(value)
    except ValueError:
        sys.exit(f"ERROR: {location}: {field} must be an integer, got {value!r}")
    if not 0 <= parsed <= UINT64_MAX:
        sys.exit(f"ERROR: {location}: {field} must be in 0..{UINT64_MAX}, got {value!r}")
    return parsed


def as_str(value: str) -> str:
    """String field: '-' is the shell's placeholder for absent, not a value."""
    return "" if value == "-" else value


def as_nullable_http_status(value: str, location: str) -> Optional[str]:
    """HTTP status for ClickHouse Nullable(UInt16), or TSV NULL."""
    if value in {"", "-"}:
        return None
    status = as_uint32(value, "validation_http_status", location)
    if not 100 <= status <= 599:
        sys.exit(f"ERROR: invalid HTTP status {value!r}")
    return str(status)


def encode_tsv(value: Optional[str]) -> str:
    """Encode ClickHouse TSV text; only None becomes the SQL NULL token."""
    if value is None:
        return r"\N"
    return (value.replace("\\", r"\\")
                 .replace("\t", r"\t")
                 .replace("\n", r"\n")
                 .replace("\r", r"\r"))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", required=True, help="disposition TSV from the test script")
    p.add_argument("--output", required=True, help="upload-ready TSV to write")
    p.add_argument("--run-id", required=True, help="GitHub Actions run id")
    p.add_argument("--start-time", required=True,
                   help="run kickoff time (UTC), stable across re-run attempts")
    p.add_argument("--gh-run-started-at", required=True,
                   help="current ATTEMPT start time (UTC); ReplacingMergeTree version")
    p.add_argument("--webview-type", required=True)
    p.add_argument("--webview-channel", default="stable")
    args = p.parse_args()

    run_id = str(as_uint64(args.run_id, "run_id", "arguments"))
    start_time = to_epoch(args.start_time)
    gh_run_started_at = to_epoch(args.gh_run_started_at)

    rows: List[List[Optional[str]]] = []
    with open(args.input, encoding="utf-8", newline="") as f:
        # The producer emits plain TSV, not CSV-style quoted fields. Disable
        # quote handling so diagnostics beginning with `"` remain unchanged.
        reader = csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE, strict=True)
        header = next(reader, [])
        if header != EXPECTED_HEADER:
            sys.exit(f"ERROR: unexpected header {header!r} (want {EXPECTED_HEADER!r})")
        for lineno, fields in enumerate(reader, start=2):
            location = f"{args.input}:{lineno}"
            if not fields or all(not field for field in fields):
                sys.exit(f"ERROR: {location}: empty disposition row")
            if len(fields) != len(EXPECTED_HEADER):
                sys.exit(f"ERROR: {location}: expected "
                         f"{len(EXPECTED_HEADER)} fields, got {len(fields)}")
            (_browser, version, site, outcome,
             validation_status, validation_reason, validation_http_status,
             validation_detail, archive_sha256,
             failure_stage, failure_reason, failure_detail,
             requested, observed, recorded, dropped_unfinalized,
             dropped_no_metric,
             load_window_ms, runner_image) = fields
            if not site or not version:
                sys.exit(f"ERROR: {location}: site and browser_version are required")
            if outcome not in VALID_OUTCOMES:
                sys.exit(f"ERROR: {location}: unknown outcome {outcome!r} "
                         f"(known: {sorted(VALID_OUTCOMES)})")
            if validation_status not in VALID_VALIDATION_STATUSES:
                sys.exit(f"ERROR: {location}: unknown validation_status "
                         f"{validation_status!r} "
                         f"(known: {sorted(VALID_VALIDATION_STATUSES)})")
            reason = as_str(validation_reason)
            detail = as_str(validation_detail)
            runtime_stage = as_str(failure_stage)
            runtime_reason = as_str(failure_reason)
            runtime_detail = as_str(failure_detail)
            sha = None if archive_sha256 in {"", "-"} else archive_sha256
            if sha is not None and not SHA256_PATTERN.fullmatch(sha):
                sys.exit(f"ERROR: {location}: archive_sha256 must be 64 lowercase hex characters")
            http_status = as_nullable_http_status(validation_http_status, location)
            counters = {
                name: as_uint32(value, name, location)
                for name, value in (
                    ("requested_repetitions", requested),
                    ("observed_repetitions", observed),
                    ("recorded_samples", recorded),
                    ("dropped_unfinalized", dropped_unfinalized),
                    ("dropped_no_metric", dropped_no_metric),
                    ("load_window_ms", load_window_ms),
                )
            }
            requested_n = counters["requested_repetitions"]
            observed_n = counters["observed_repetitions"]
            recorded_n = counters["recorded_samples"]
            dropped_n = counters["dropped_unfinalized"] + counters["dropped_no_metric"]
            if requested_n == 0 or counters["load_window_ms"] == 0:
                sys.exit(f"ERROR: {location}: requested_repetitions and load_window_ms must be positive")
            if observed_n > requested_n or recorded_n + dropped_n != observed_n:
                sys.exit(f"ERROR: {location}: repetition counters are inconsistent")
            if validation_status == "ok" and reason:
                sys.exit(f"ERROR: {location}: validation_status ok "
                         "must not have validation_reason")
            if validation_status == "error" and not reason:
                sys.exit(f"ERROR: {location}: validation_status error "
                         "requires validation_reason")
            if bool(runtime_stage) != bool(runtime_reason):
                sys.exit(
                    f"ERROR: {location}: failure_stage and failure_reason "
                    "must either both be set or both be absent"
                )
            if outcome != "infra_error" and (runtime_stage or runtime_reason):
                sys.exit(
                    f"ERROR: {location}: runtime failure fields require "
                    "outcome infra_error"
                )
            if validation_status == "ok" and (sha is None or http_status is not None or outcome == "excluded"):
                sys.exit(f"ERROR: {location}: validated sites require a hash, no HTTP error, and a non-excluded outcome")
            if validation_status == "error":
                valid_validation_outcome = outcome == "excluded"
                valid_handoff_outcome = (
                    outcome == "infra_error"
                    and reason in VALID_HANDOFF_FAILURE_REASONS
                )
                if not (valid_validation_outcome or valid_handoff_outcome):
                    sys.exit(
                        f"ERROR: {location}: validation errors must be excluded; "
                        "validated-archive handoff failures must be infra_error"
                    )
            if outcome == "excluded" and (observed_n or recorded_n or dropped_n):
                sys.exit(f"ERROR: {location}: excluded sites cannot have measurement counters")
            if outcome == "measured" and not (recorded_n == observed_n == requested_n):
                sys.exit(f"ERROR: {location}: measured requires every requested repetition to be recorded")
            if outcome == "partial" and not (0 < recorded_n < requested_n):
                sys.exit(f"ERROR: {location}: partial requires some but not all requested samples")
            if outcome == "no_samples" and recorded_n != 0:
                sys.exit(f"ERROR: {location}: no_samples requires recorded_samples=0")
            rows.append([
                run_id,
                start_time,
                site,
                args.webview_type,
                args.webview_channel,
                version,
                outcome,
                validation_status,
                reason,
                http_status,
                detail,
                sha,
                runtime_stage,
                runtime_reason,
                runtime_detail,
                str(requested_n),
                str(observed_n),
                str(recorded_n),
                str(counters["dropped_unfinalized"]),
                str(counters["dropped_no_metric"]),
                str(counters["load_window_ms"]),
                as_str(runner_image),
                gh_run_started_at,
            ])
    if not rows:
        sys.exit(f"ERROR: {args.input}: no disposition rows")

    with open(args.output, "w", encoding="utf-8") as out:
        for row in rows:
            out.write("\t".join(encode_tsv(value) for value in row) + "\n")

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
