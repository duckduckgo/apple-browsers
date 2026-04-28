#!/usr/bin/env python3
"""Render a single HTML test report into $GITHUB_STEP_SUMMARY.

Reads a JUnit XML file (authoritative for counts and the failure list) and
an optional crash details JSON produced by inject-xcresult-crashes-into-junit.py
(provides expandable details for crashed tests).

Emits three HTML tables under an <h2> title:

  1. Counts    - total / passed / failed / skipped (always).
  2. Failures  - one row per non-crash failure (omitted when empty).
  3. Crashes   - one row per crash with an inline <details> containing
                 process, signal, source location, and top stack frames
                 (omitted when empty).

Designed to run every test job (success and failure) so the counts table is
always present. mikepenz/action-junit-report is configured with
`job_summary: false`, leaving this report as the sole Summary-tab output.
"""
import argparse
import html
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


CRASH_PREFIX = "Crashed: "
_PATH_LINE_PREFIX = re.compile(r"^/\S+\.swift:\d+\s*-\s*")
_FAILED_PREFIX = re.compile(r"^failed\s*-\s*")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--junit", required=True, help="path to JUnit XML")
    parser.add_argument("--title", required=True, help="heading shown above the report")
    parser.add_argument("--crash-details-json",
                        help="optional path to the JSON crash details file written by "
                             "inject-xcresult-crashes-into-junit.py")
    args = parser.parse_args()

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        print("GITHUB_STEP_SUMMARY is not set; nothing to do.", file=sys.stderr)
        return 0

    junit = Path(args.junit)
    if not junit.is_file():
        print(f"JUnit file {junit} not found; skipping report.", file=sys.stderr)
        return 0

    totals, failures, junit_crashes = _collect(junit)
    crashes = _merge_crashes(junit_crashes, _load_crash_details_file(args.crash_details_json))

    html_doc = _render(args.title, totals, failures, crashes)
    with open(summary_path, "a") as f:
        f.write(html_doc)
    return 0


# ---------- JUnit parsing ----------

def _collect(junit_path: Path) -> tuple[dict, list[dict], list[dict]]:
    # Group testcase attempts by (classname, name) so retries from
    # `-retry-tests-on-failure` / `-test-iterations` collapse to one row
    # per unique test. A test is considered passed if any attempt passed,
    # skipped if its sole attempt was marked skipped, and failed otherwise.
    root = ET.parse(junit_path).getroot()
    groups: dict[tuple[str, str], list[dict]] = {}
    for tc in root.iter("testcase"):
        key = (tc.get("classname", ""), tc.get("name", ""))
        failure_el = tc.find("failure")
        if failure_el is None:
            failure_el = tc.find("error")
        attempt = {
            "failure_message": (
                None if failure_el is None
                else (failure_el.get("message", "") or (failure_el.text or ""))
            ),
            "skipped": tc.find("skipped") is not None,
        }
        groups.setdefault(key, []).append(attempt)

    total = passed = failed = skipped_count = 0
    failures: list[dict] = []
    crashes: list[dict] = []
    for (class_name, test_name), attempts in groups.items():
        total += 1
        any_passed = any(a["failure_message"] is None and not a["skipped"] for a in attempts)
        only_skipped = all(a["skipped"] for a in attempts)
        if any_passed:
            passed += 1
            continue
        if only_skipped:
            skipped_count += 1
            continue
        failed += 1
        first_fail = next(
            (a for a in attempts if a["failure_message"] is not None),
            None,
        )
        msg = first_fail["failure_message"] if first_fail else ""
        row = {"class_name": class_name, "test_name": test_name}
        if msg.startswith(CRASH_PREFIX):
            row["reason"] = _clean_reason(msg[len(CRASH_PREFIX):])
            crashes.append(row)
        else:
            row["reason"] = _clean_reason(msg)
            failures.append(row)

    totals = {
        "total": total,
        "passed": passed,
        "failed": failed,
        "skipped": skipped_count,
    }
    return totals, failures, crashes


def _clean_reason(s: str) -> str:
    s = _PATH_LINE_PREFIX.sub("", s)
    s = _FAILED_PREFIX.sub("", s)
    return s.strip()


# ---------- crash details file ----------

def _load_crash_details_file(path: str | None) -> list[dict]:
    if not path:
        return []
    p = Path(path)
    if not p.is_file():
        return []
    try:
        with p.open() as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except (OSError, json.JSONDecodeError):
        return []


def _merge_crashes(junit_crashes: list[dict], crash_details: list[dict]) -> list[dict]:
    # The crash details file's class_name may be bare (e.g.
    # "StringExtensionTests") while the JUnit is target-prefixed (e.g.
    # "UnitTests.StringExtensionTests"); match by exact key first, then by
    # classname-suffix as a fallback.
    crash_details_remaining = list(crash_details)
    merged: list[dict] = []
    for jc in junit_crashes:
        detail = _pop_matching_crash_detail(crash_details_remaining, jc)
        merged.append({
            "class_name": jc["class_name"],
            "test_name": jc["test_name"],
            "reason": (detail or jc)["reason"],
            "report": (detail or {}).get("report"),
        })
    # Any crash details entry we couldn't match to a JUnit crash (e.g. JUnit
    # injection was skipped) still gets rendered with its own data.
    for c in crash_details_remaining:
        merged.append({
            "class_name": c["class_name"],
            "test_name": c["test_name"],
            "reason": c.get("reason", ""),
            "report": c.get("report"),
        })
    return merged


def _pop_matching_crash_detail(crash_details: list[dict], jc: dict) -> dict | None:
    for i, c in enumerate(crash_details):
        if c["test_name"] != jc["test_name"]:
            continue
        junit_class = jc["class_name"]
        detail_class = c["class_name"]
        if (detail_class == junit_class
                or junit_class.endswith("." + detail_class)
                or detail_class.endswith("." + junit_class)):
            return crash_details.pop(i)
    return None


# ---------- HTML ----------

def _render(title: str, totals: dict, failures: list[dict], crashes: list[dict]) -> str:
    parts = [f"<h2>{html.escape(title)}</h2>", ""]
    parts.append(_counts_table(totals))
    parts.append("")
    if failures:
        parts.append(_failures_table(failures))
        parts.append("")
    if crashes:
        parts.append(_crashes_table(crashes))
        parts.append("")
    return "\n".join(parts) + "\n"


def _counts_table(t: dict) -> str:
    return (
        "<table>\n"
        "  <tr><th>📊 Total</th><th>✅ Passed</th><th>❌ Failed</th><th>⏭️ Skipped</th></tr>\n"
        f"  <tr><td>{t['total']}</td><td>{t['passed']}</td><td>{t['failed']}</td>"
        f"<td>{t['skipped']}</td></tr>\n"
        "</table>"
    )


def _failures_table(failures: list[dict]) -> str:
    rows = ["<table>",
            f"  <tr><th>Failed tests ({len(failures)})</th><th>Reason</th></tr>"]
    for f in failures:
        test_ref = f"{f['class_name']}.{f['test_name']}"
        rows.append(
            f"  <tr><td><code>{html.escape(test_ref)}</code></td>"
            f"<td>{html.escape(f['reason'])}</td></tr>"
        )
    rows.append("</table>")
    return "\n".join(rows)


def _crashes_table(crashes: list[dict]) -> str:
    rows = ["<table>",
            f"  <tr><th>Crashed tests ({len(crashes)})</th><th>Reason</th><th>Details</th></tr>"]
    for c in crashes:
        test_ref = f"{c['class_name']}.{c['test_name']}"
        rows.append(
            "  <tr>"
            f"<td><code>{html.escape(test_ref)}</code></td>"
            f"<td>{html.escape(c['reason'])}</td>"
            f"<td>{_crash_details(c.get('report'))}</td>"
            "</tr>"
        )
    rows.append("</table>")
    return "\n".join(rows)


def _crash_details(report: dict | None) -> str:
    if not report:
        return "<em>No matching crash report.</em>"
    parts: list[str] = ["<details><summary>View</summary>"]
    if report.get("process"):
        parts.append(f"<b>Process:</b> <code>{html.escape(report['process'])}</code><br>")
    if report.get("signal"):
        ex = html.escape(report.get("exception_type", "")) if report.get("exception_type") else ""
        signal = html.escape(report["signal"])
        parts.append(f"<b>Signal:</b> <code>{signal}</code>"
                     + (f" ({ex})" if ex else "") + "<br>")
    if report.get("source_location"):
        parts.append(f"<b>Source:</b> <code>{html.escape(report['source_location'])}</code>")
    frames = report.get("top_frames") or []
    if frames:
        body = "\n".join(f"{i}  {html.escape(frame)}" for i, frame in enumerate(frames))
        parts.append(f"<pre>{body}</pre>")
    parts.append("</details>")
    return "".join(parts)


if __name__ == "__main__":
    sys.exit(main())
