#!/usr/bin/env python3
"""Render a single HTML test report into $GITHUB_STEP_SUMMARY.

Reads a JUnit XML file (authoritative for counts and the failure list) and
an optional sidecar JSON produced by inject-xcresult-crashes-into-junit.py
(provides expandable details for crashed tests).

Emits three HTML tables under an <h2> title:

  1. Counts    - total / passed / failed / skipped / duration (always).
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
    parser.add_argument("--crashes-json",
                        help="optional path to the sidecar crash-details JSON")
    args = parser.parse_args()

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        print("GITHUB_STEP_SUMMARY is not set; nothing to do.", file=sys.stderr)
        return 0

    junit = Path(args.junit)
    if not junit.is_file():
        print(f"JUnit file {junit} not found; skipping report.", file=sys.stderr)
        return 0

    totals = _totals(junit)
    failures, junit_crashes = _failures_and_crashes(junit)
    crashes = _merge_crashes(junit_crashes, _load_sidecar(args.crashes_json))

    html_doc = _render(args.title, totals, failures, crashes)
    with open(summary_path, "a") as f:
        f.write(html_doc)
    return 0


# ---------- JUnit parsing ----------

def _totals(junit_path: Path) -> dict:
    root = ET.parse(junit_path).getroot()
    # Root can be <testsuites> or a single <testsuite>. When the
    # aggregate attributes are missing, sum across <testsuite> children.
    tests = _int_attr(root, "tests")
    failures = _int_attr(root, "failures")
    errors = _int_attr(root, "errors")
    skipped = _int_attr(root, "skipped")
    time = _float_attr(root, "time")

    suites = root.findall("testsuite") if root.tag == "testsuites" else [root]
    if tests == 0 and suites:
        tests = sum(_int_attr(s, "tests") for s in suites)
        failures = sum(_int_attr(s, "failures") for s in suites)
        errors = sum(_int_attr(s, "errors") for s in suites)
        skipped = sum(_int_attr(s, "skipped") for s in suites)
        time = sum(_float_attr(s, "time") for s in suites)

    passed = max(tests - failures - errors - skipped, 0)
    return {
        "total": tests,
        "passed": passed,
        "failed": failures + errors,
        "skipped": skipped,
        "duration": _format_duration(time),
    }


def _failures_and_crashes(junit_path: Path) -> tuple[list[dict], list[dict]]:
    root = ET.parse(junit_path).getroot()
    failures: list[dict] = []
    crashes: list[dict] = []
    for tc in root.iter("testcase"):
        failure = tc.find("failure")
        if failure is None:
            failure = tc.find("error")
        if failure is None:
            continue
        message = failure.get("message", "") or (failure.text or "")
        row = {
            "class_name": tc.get("classname", ""),
            "test_name": tc.get("name", ""),
            "reason": _clean_reason(message),
        }
        if message.startswith(CRASH_PREFIX):
            row["reason"] = _clean_reason(message[len(CRASH_PREFIX):])
            crashes.append(row)
        else:
            failures.append(row)
    return failures, crashes


def _int_attr(el: ET.Element, name: str) -> int:
    try:
        return int(el.get(name, "0"))
    except ValueError:
        return 0


def _float_attr(el: ET.Element, name: str) -> float:
    try:
        return float(el.get(name, "0"))
    except ValueError:
        return 0.0


def _format_duration(seconds: float) -> str:
    if seconds <= 0:
        return "—"
    if seconds < 60:
        return f"{seconds:.1f}s"
    m, s = divmod(int(round(seconds)), 60)
    if m < 60:
        return f"{m}m {s:02d}s"
    h, m = divmod(m, 60)
    return f"{h}h {m:02d}m {s:02d}s"


def _clean_reason(s: str) -> str:
    s = _PATH_LINE_PREFIX.sub("", s)
    s = _FAILED_PREFIX.sub("", s)
    return s.strip()


# ---------- sidecar ----------

def _load_sidecar(path: str | None) -> list[dict]:
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


def _merge_crashes(junit_crashes: list[dict], sidecar: list[dict]) -> list[dict]:
    # Key the sidecar by class.test so rendering is independent of ordering.
    by_key = {f"{c['class_name']}.{c['test_name']}": c for c in sidecar}
    merged: list[dict] = []
    seen: set[str] = set()
    for jc in junit_crashes:
        key = f"{jc['class_name']}.{jc['test_name']}"
        side = by_key.get(key)
        merged.append({
            "class_name": jc["class_name"],
            "test_name": jc["test_name"],
            "reason": (side or jc)["reason"],
            "report": (side or {}).get("report"),
        })
        seen.add(key)
    # Include any sidecar-only entries (e.g. if JUnit injection was skipped).
    for key, c in by_key.items():
        if key in seen:
            continue
        merged.append({
            "class_name": c["class_name"],
            "test_name": c["test_name"],
            "reason": c.get("reason", ""),
            "report": c.get("report"),
        })
    return merged


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
        "  <tr><th>Total</th><th>Passed</th><th>Failed</th><th>Skipped</th><th>Duration</th></tr>\n"
        f"  <tr><td>{t['total']}</td><td>{t['passed']}</td><td>{t['failed']}</td>"
        f"<td>{t['skipped']}</td><td>{html.escape(t['duration'])}</td></tr>\n"
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
