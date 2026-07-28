#!/usr/bin/env python3
#
# aggregate-lcp.py — collapse the per-repetition TSV that test-chrome.sh emits
# into one upload-ready row per domain for the ClickHouse table
# native_apps.macos_browser_health_nav_to_lcp.
#
# Input TSV (with header): browser, browser_version, site, rep, lcp_ms
#
# Output TSV (no header). Column order matches the INSERT column list minus
# gh_run_conclusion, which the upload job appends itself — only it knows the
# benchmark job's conclusion:
#
#   run_id, start_time, domain, webview_type, webview_channel, webview_version,
#   samples, min_ms, max_ms, mean_ms, p25_ms, p50_ms, p75_ms, p95_ms,
#   gh_run_started_at
#
# start_time and gh_run_started_at are emitted as Unix epoch seconds (see
# to_epoch) so ClickHouse stores the exact instant regardless of server zone.
#
# Percentiles use ClickHouse's quantileExact formula so CI-computed values
# match what ClickHouse itself would compute:
#   quantileExact(level) = sorted[min(floor(level * n), n - 1)]
#
# stdlib only; runs on the system python3 of a hosted macOS runner.

import argparse
import calendar
import math
import sys
import time


def to_epoch(value: str) -> str:
    """'2026-07-24T13:10:51Z' or '2026-07-24 13:10:51' (UTC) -> Unix epoch seconds.

    GitHub timestamps are UTC. We insert the epoch rather than a wall-clock
    string so ClickHouse stores the exact instant: the DateTime columns carry no
    timezone, so a naive string would be parsed in the server's local zone and
    land hours off, whereas an epoch is unambiguous.
    """
    v = value.strip().replace("T", " ").removesuffix("Z")
    if len(v) != 19 or v[4] != "-" or v[7] != "-" or v[13] != ":" or v[16] != ":":
        sys.exit(f"ERROR: unrecognized datetime {value!r} (want YYYY-MM-DDThh:mm:ssZ)")
    return str(calendar.timegm(time.strptime(v, "%Y-%m-%d %H:%M:%S")))


def quantile_exact(sorted_vals: list[float], level: float) -> float:
    n = len(sorted_vals)
    return sorted_vals[min(math.floor(level * n), n - 1)]


def fmt(x: float) -> str:
    s = f"{x:.4f}".rstrip("0").rstrip(".")
    return s or "0"


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--input", required=True, help="per-repetition TSV from test-chrome.sh")
    p.add_argument("--output", required=True, help="upload-ready TSV to write")
    p.add_argument("--run-id", required=True, help="GitHub Actions run id")
    p.add_argument("--start-time", required=True,
                   help="run kickoff time (UTC), stable across re-run attempts")
    p.add_argument("--gh-run-started-at", required=True,
                   help="current ATTEMPT start time (UTC); ReplacingMergeTree version")
    p.add_argument("--webview-type", required=True)
    p.add_argument("--webview-channel", default="stable")
    args = p.parse_args()

    start_time = to_epoch(args.start_time)
    gh_run_started_at = to_epoch(args.gh_run_started_at)

    # site -> (browser_version, [lcp_ms, ...])
    domains: dict[str, tuple[str, list[float]]] = {}
    with open(args.input, encoding="utf-8") as f:
        header = f.readline().rstrip("\n").split("\t")
        expected = ["browser", "browser_version", "site", "rep", "lcp_ms"]
        if header != expected:
            sys.exit(f"ERROR: unexpected header {header!r} (want {expected!r})")
        for lineno, line in enumerate(f, start=2):
            line = line.rstrip("\n")
            if not line:
                continue
            fields = line.split("\t")
            if len(fields) != len(expected):
                sys.exit(f"ERROR: {args.input}:{lineno}: expected {len(expected)} fields, got {len(fields)}")
            _, version, site, _, lcp_ms = fields
            entry = domains.setdefault(site, (version, []))
            entry[1].append(float(lcp_ms))

    with open(args.output, "w", encoding="utf-8") as out:
        for site in sorted(domains):
            version, vals = domains[site]
            vals.sort()
            row = [
                args.run_id,
                start_time,
                site,
                args.webview_type,
                args.webview_channel,
                version,
                str(len(vals)),
                fmt(vals[0]),
                fmt(vals[-1]),
                fmt(sum(vals) / len(vals)),
                fmt(quantile_exact(vals, 0.25)),
                fmt(quantile_exact(vals, 0.50)),
                fmt(quantile_exact(vals, 0.75)),
                fmt(quantile_exact(vals, 0.95)),
                gh_run_started_at,
            ]
            out.write("\t".join(row) + "\n")

    print(f"wrote {len(domains)} row(s) to {args.output}")


if __name__ == "__main__":
    main()
