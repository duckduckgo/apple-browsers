#!/usr/bin/env python3
"""Inject crashed tests from an xcresult bundle into a JUnit XML file, and
append a test-results summary to $GITHUB_STEP_SUMMARY.

xcbeautify doesn't emit <failure> entries for tests that crashed (SIGSEGV,
fatalError, etc.) because the test host dies before the failure is recorded.
This reads crashed tests from the xcresult's structured summary and adds them
as <failure> entries so downstream tooling (mikepenz/action-junit-report,
yq-based Asana reporter) sees accurate counts.

When --log is supplied, crashed-test messages are enriched with the fatal
error text extracted from the xcodebuild log. When --crash-reports-dir is
supplied, matching .ips stack traces are included in the step summary.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


FATAL_ERROR_PATTERNS = [
    re.compile(r"Fatal error:\s*(.+?)(?:\s*:\s*file\s|\s*$)"),
    re.compile(r"precondition failed:\s*(.+?)(?:\s*:\s*file\s|\s*$)"),
    re.compile(r"\*\*\* Terminating app due to uncaught exception '([^']+)', reason: '([^']+)'"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xcresult", help="path to .xcresult bundle")
    parser.add_argument("junit", help="path to JUnit XML to patch")
    parser.add_argument("--log", help="xcodebuild log to mine for fatal error messages")
    parser.add_argument("--crash-reports-dir", help="directory of .ips crash reports")
    parser.add_argument("--summary-title", default="Tests",
                        help="context prefix for the $GITHUB_STEP_SUMMARY section heading")
    args = parser.parse_args()

    summary = _xcresulttool_summary(args.xcresult)
    failures, crashes = _extract_failures(summary)

    if crashes:
        fatal_errors = _extract_fatal_errors(args.log) if args.log else []
        start_time = summary.get("startTime")
        finish_time = summary.get("finishTime")
        crash_reports = (
            _scan_crash_reports(args.crash_reports_dir, start_time, finish_time)
            if args.crash_reports_dir else []
        )

        for i, crash in enumerate(crashes):
            if i < len(fatal_errors):
                crash["reason"] = fatal_errors[i]
            crash["report"] = _match_report(crash_reports, crash)

        added = _inject_into_junit(crashes, args.junit)
        print(f"Injected {added} crash(es) into {args.junit}")

    step_summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary_path and crashes:
        _append_step_summary(step_summary_path, args.summary_title, crashes)

    return 0


# ---------- xcresult ----------

def _xcresulttool_summary(xcresult: str) -> dict:
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary",
         "--path", xcresult, "--format", "json"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def _extract_failures(summary: dict) -> tuple[list[dict], list[dict]]:
    failures, crashes = [], []
    for f in summary.get("testFailures", []):
        class_name, _, test_name = f["testIdentifierString"].partition("/")
        entry = {
            "class_name": class_name,
            "test_name": test_name.rstrip("()"),
            "target": f["targetName"],
            "failure_text": f["failureText"],
            "reason": f["failureText"],
            "report": None,
        }
        if re.search(r"crash", f.get("failureText", ""), re.IGNORECASE):
            crashes.append(entry)
        else:
            failures.append(entry)
    return failures, crashes


# ---------- xcodebuild log ----------

def _extract_fatal_errors(log_path: str) -> list[str]:
    p = Path(log_path)
    if not p.is_file():
        return []
    seen, results = set(), []
    with p.open("r", errors="replace") as f:
        for line in f:
            for pat in FATAL_ERROR_PATTERNS:
                m = pat.search(line)
                if not m:
                    continue
                msg = ": ".join(g for g in m.groups() if g).strip()
                if msg and msg not in seen:
                    seen.add(msg)
                    results.append(msg)
                break
    return results


# ---------- crash reports ----------

def _scan_crash_reports(dir_path: str, start: float | None, finish: float | None) -> list[dict]:
    d = Path(os.path.expanduser(dir_path))
    if not d.is_dir():
        return []
    reports = []
    for ips in sorted(d.glob("*.ips"), key=lambda p: p.stat().st_mtime):
        parsed = _parse_ips(ips)
        if not parsed:
            continue
        # Skip .ips files that aren't from this test run (old system crashes etc).
        if start is not None and finish is not None:
            ts = parsed.get("epoch")
            if ts is None or ts < start - 60 or ts > finish + 60:
                continue
        reports.append(parsed)
    return reports


def _parse_ips(path: Path) -> dict | None:
    try:
        with path.open("r", errors="replace") as f:
            header = json.loads(f.readline())
            body = json.loads(f.read())
    except (OSError, json.JSONDecodeError):
        return None
    return {
        "path": path,
        "process": header.get("app_name") or body.get("procName", ""),
        "timestamp": header.get("timestamp", ""),
        "epoch": _parse_ips_timestamp(header.get("timestamp", "")),
        "signal": body.get("exception", {}).get("signal", ""),
        "exception_type": body.get("exception", {}).get("type", ""),
        "top_frames": _top_frames(body),
        "source_location": _first_source_location(body),
    }


def _parse_ips_timestamp(ts: str) -> float | None:
    # Example: "2026-04-21 00:27:15.00 +0000"
    m = re.match(r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?:\.\d+)? ([+-]\d{4})", ts)
    if not m:
        return None
    import datetime
    try:
        tz = datetime.timezone(datetime.timedelta(
            hours=int(m.group(2)[:3]), minutes=int(m.group(2)[0] + m.group(2)[3:])))
        return datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=tz).timestamp()
    except ValueError:
        return None


def _top_frames(body: dict, limit: int = 8) -> list[str]:
    fault = body.get("faultingThread", 0)
    threads = body.get("threads", [])
    images = body.get("usedImages", [])
    if fault >= len(threads):
        return []
    out = []
    for frame in threads[fault].get("frames", []):
        idx = frame.get("imageIndex")
        if idx is None or idx >= len(images):
            continue
        symbol = frame.get("symbol") or "?"
        if symbol == "<deduplicated_symbol>":
            continue
        img = images[idx].get("name", "?")
        src = frame.get("sourceFile", "")
        line = frame.get("sourceLine", "")
        src_part = f"  ({src}:{line})" if src else ""
        out.append(f"{img:40s} {symbol}{src_part}")
        if len(out) >= limit:
            break
    return out


def _first_source_location(body: dict) -> str:
    fault = body.get("faultingThread", 0)
    threads = body.get("threads", [])
    if fault >= len(threads):
        return ""
    for frame in threads[fault].get("frames", []):
        src = frame.get("sourceFile", "")
        line = frame.get("sourceLine", "")
        if src:
            return f"{src}:{line}"
    return ""


def _match_report(reports: list[dict], crash: dict) -> dict | None:
    if not reports:
        return None
    target = crash["target"].lower()
    for r in reports:
        if target and target in r["process"].lower():
            return r
    return reports[-1]  # fall back to most recent


# ---------- JUnit ----------

def _inject_into_junit(crashes: list[dict], junit_path: str) -> int:
    tree = ET.parse(junit_path)
    root = tree.getroot()
    added = 0
    for crash in crashes:
        suite = _find_or_create_suite(root, crash["class_name"], crash["target"])
        if suite.find(f"./testcase[@name='{crash['test_name']}']/failure") is not None:
            continue
        tc = ET.SubElement(suite, "testcase", {
            "classname": suite.get("name", crash["class_name"]),
            "name": crash["test_name"],
            "time": "0",
        })
        failure = ET.SubElement(tc, "failure", {"message": f"Crashed: {crash['reason']}"})
        failure.text = crash["reason"]
        suite.set("tests", str(int(suite.get("tests", "0")) + 1))
        suite.set("failures", str(int(suite.get("failures", "0")) + 1))
        added += 1

    if added > 0:
        root.set("tests", str(int(root.get("tests", "0")) + added))
        root.set("failures", str(int(root.get("failures", "0")) + added))
        tree.write(junit_path, encoding="UTF-8", xml_declaration=True)
    return added


def _find_or_create_suite(root: ET.Element, class_name: str, target: str) -> ET.Element:
    for ts in root.findall("testsuite"):
        name = ts.get("name", "")
        if name == class_name or name.endswith("." + class_name):
            return ts
    return ET.SubElement(root, "testsuite", {
        "name": f"{target}.{class_name}",
        "tests": "0",
        "failures": "0",
    })


# ---------- GitHub step summary ----------

def _append_step_summary(summary_path: str, title: str, crashes: list[dict]) -> None:
    n = len(crashes)
    lines = [
        f"### {title} — Crashes ({n})",
        "",
        "_Expand the entries below for more information._",
        "",
    ]
    for c in crashes:
        test_ref = f"{c['class_name']}.{c['test_name']}"
        summary_line = f"<b>{test_ref}</b> — {_md_escape(c['reason'])}"
        lines.append(f"<details><summary>{summary_line}</summary>")
        lines.append("")
        report = c.get("report")
        if report:
            lines.append(f"- **Process:** `{report['process']}`")
            if report["signal"]:
                lines.append(f"- **Signal:** `{report['signal']}` ({report['exception_type']})")
            if report["timestamp"]:
                lines.append(f"- **Timestamp:** `{report['timestamp']}`")
            if report["source_location"]:
                lines.append(f"- **Source location:** `{report['source_location']}`")
            lines.append(f"- **Crash report:** `{report['path'].name}`")
            if report["top_frames"]:
                lines += ["", "**Top frames (crashed thread):**", "", "```"]
                for i, frame in enumerate(report["top_frames"]):
                    lines.append(f"{i}  {frame}")
                lines.append("```")
        else:
            lines.append("_No matching crash report found in DiagnosticReports._")
        lines += ["", "</details>", ""]

    with open(summary_path, "a") as f:
        f.write("\n".join(lines) + "\n")


def _md_escape(s: str) -> str:
    return s.replace("|", "\\|").replace("\n", " ")


if __name__ == "__main__":
    sys.exit(main())
