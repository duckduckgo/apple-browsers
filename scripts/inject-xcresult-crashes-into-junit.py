#!/usr/bin/env python3
"""Inject crashed tests from an xcresult bundle into a JUnit XML file, and
write a crash details file describing each crash for later rendering.

xcbeautify doesn't emit <failure> entries for tests that crashed (SIGSEGV,
fatalError, etc.) because the test host dies before the failure is recorded.
This reads crashed tests from the xcresult's structured summary and adds them
as <failure> entries so downstream tooling (mikepenz/action-junit-report,
yq-based Asana reporter, render-test-report.py) sees accurate counts.

When --log is supplied, crashed-test messages are enriched with the fatal
error text extracted from the xcodebuild log. When --crash-reports-dir is
supplied, matching .ips stack traces are attached to each crash. All enriched
crash data is written to a JSON crash details file alongside the JUnit XML
(e.g. unittests.xml -> unittests-crash-details.json), which
render-test-report.py reads to produce the expandable Crashes section of
the step-summary report.
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
    args = parser.parse_args()

    summary = _xcresulttool_summary(args.xcresult)
    _, crashes = _extract_failures(summary)

    if not crashes:
        return 0

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

    _write_crash_details_file(args.junit, crashes)
    return 0


# ---------- xcresult ----------

def _xcresulttool_summary(xcresult: str) -> dict:
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary",
         "--path", xcresult, "--format", "json"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


CRASH_FAILURE_TEXT = re.compile(r"^(Test crashed\b|Crash:\s)")


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
        if CRASH_FAILURE_TEXT.match(f.get("failureText", "")):
            crashes.append(entry)
        else:
            failures.append(entry)
    return failures, crashes


# ---------- xcodebuild log ----------

def _extract_fatal_errors(log_path: str) -> list[str]:
    # Adjacent dedup only: GitHub Actions often repeats the same fatal-error line
    # once as stdout and once as ##[error]. Collapsing those preserves each
    # distinct crash's message so positional pairing with xcresult still works
    # when two different crashes happen to share an identical message.
    p = Path(log_path)
    if not p.is_file():
        return []
    results: list[str] = []
    with p.open("r", errors="replace") as f:
        for line in f:
            for pat in FATAL_ERROR_PATTERNS:
                m = pat.search(line)
                if not m:
                    continue
                msg = ": ".join(g for g in m.groups() if g).strip()
                if msg and (not results or results[-1] != msg):
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
        classname = suite.get("name", crash["class_name"])
        # Sync so the crash details file's class_name matches the JUnit's
        # (target-prefixed); otherwise render-test-report.py can't merge the
        # two views of this crash.
        crash["class_name"] = classname
        tc = ET.SubElement(suite, "testcase", {
            "classname": classname,
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


# ---------- crash details file ----------

def _write_crash_details_file(junit_path: str, crashes: list[dict]) -> None:
    path = _crash_details_path(junit_path)
    payload = [_serialize_crash(c) for c in crashes]
    with open(path, "w") as f:
        json.dump(payload, f, indent=2)
    print(f"Wrote {len(payload)} crash detail(s) to {path}")


def _crash_details_path(junit_path: str) -> Path:
    p = Path(junit_path)
    return p.with_name(f"{p.stem}-crash-details.json")


def _serialize_crash(crash: dict) -> dict:
    report = crash.get("report")
    return {
        "class_name": crash["class_name"],
        "test_name": crash["test_name"],
        "reason": crash["reason"],
        "report": None if report is None else {
            "process": report.get("process", ""),
            "signal": report.get("signal", ""),
            "exception_type": report.get("exception_type", ""),
            "source_location": report.get("source_location", ""),
            "top_frames": list(report.get("top_frames", [])),
        },
    }


if __name__ == "__main__":
    sys.exit(main())
