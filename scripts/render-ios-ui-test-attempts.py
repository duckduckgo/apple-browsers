#!/usr/bin/env python3
"""Append failed XCUITest attempts from merged JUnit reports to the job summary."""
import html
import json
import os
import xml.etree.ElementTree as ET
from pathlib import Path

reports = Path("reports")
run_id = os.environ["RUN_ID"]


def clean(value):
    return html.escape(value, quote=False).replace("|", "&#124;").replace("\n", " ")


def evidence(stem):
    meta = reports / f"{stem}.meta.json"
    try:
        attempt = str(json.loads(meta.read_text()).get("workflow_attempt", ""))
    except (OSError, json.JSONDecodeError, AttributeError):
        attempt = ""
    repo = os.getenv("GITHUB_REPOSITORY", "duckduckgo/apple-browsers")
    run = f"https://github.com/{repo}/actions/runs/{run_id}"
    attempt_url = f"{run}?attempt={attempt}" if attempt else run
    artifact = (f"`ios-uitest-logs-{stem}-attempt{attempt}`" if attempt
                else "workflow attempt unknown; artifact name unavailable")
    links = f"[run]({attempt_url}) · [artifacts]({run}#artifacts) ({artifact})"
    return attempt, links


try:
    matrix = json.loads(os.environ.get("MATRIX", "") or "null")
except json.JSONDecodeError:
    matrix = None
incomplete = []
if not isinstance(matrix, list):
    expected = []
    incomplete.append(("setup-tests", "matrix unavailable; expected UI-test jobs could not be enumerated"))
else:
    expected = [
        f"{cell['test']}-{cell['device']}-{mode}"
        for cell in matrix
        for mode, enabled in (("production", os.getenv("RUN_PRODUCTION")),
                              ("internal", os.getenv("RUN_INTERNAL")))
        if enabled == "true"
    ]
    if not expected:
        incomplete.append(("setup-tests", "matrix yielded no selected UI-test jobs"))
rows = []
for stem in expected:
    path, invalid = reports / f"{stem}.xml", reports / f"{stem}.invalid"
    if not path.is_file():
        reason = "job marked report invalid; no JUnit report available" if invalid.exists() else "report missing"
        incomplete.append((stem, reason))
        continue
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError) as error:
        incomplete.append((stem, f"JUnit report could not be parsed: {error}"))
        continue
    attempt, links = evidence(stem)
    cases, occurrences = list(root.iter("testcase")), {}
    for index, case in enumerate(cases):
        key = (case.get("classname", ""), case.get("name", ""))
        occurrences[key] = occurrences.get(key, 0) + 1
        failure = case.find("failure")
        if failure is None:
            failure = case.find("error")
        if failure is None:
            continue
        later = [item for item in cases[index + 1:]
                 if (item.get("classname", ""), item.get("name", "")) == key]
        if any(item.find("failure") is None and item.find("error") is None and item.find("skipped") is None for item in later):
            outcome = "failed, then passed"
        elif any(item.find("failure") is not None or item.find("error") is not None for item in later):
            outcome = "failed, then failed again"
        else:
            outcome = "failed, then skipped" if later else "failed; no later attempt in report"
        message = failure.get("message", "") or (failure.text or "").strip()
        test = ".".join(part for part in key if part)
        rows.append(
            f"| `{clean(test)}` | {clean(root.get('name', stem))} | {occurrences[key]} | "
            f"{attempt or 'unknown'} | {outcome} | {clean(message)} | {links} |"
        )
    if not any(case.find("skipped") is None for case in cases):
        incomplete.append((stem, "JUnit report contains no executed testcases"))
    if invalid.exists():
        incomplete.append((stem, "job marked report invalid; partial test results shown above if available"))
with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
    summary.write("## Failed UI test executions\n\n")
    if rows:
        summary.write("Each row is one failed testcase occurrence in JUnit order; test and workflow attempts are separate.\n\n")
        summary.write("| Test | Device / mode | Test attempt | Workflow attempt | Outcome in this report | Failure location and message | Evidence |\n|---|---|---:|---:|---|---|---|\n")
        summary.write("\n".join(rows) + "\n\n")
    else:
        summary.write("No failed testcase occurrences were recorded in the available JUnit reports.\n\n")
    if incomplete:
        summary.write("### Jobs without a complete executed-test report\n\nThese jobs have incomplete JUnit evidence; no test failure is inferred from a missing report.\n\n")
        for stem, reason in incomplete:
            _, links = evidence(stem)
            summary.write(f"- `{stem}`: {clean(reason)} — {links}\n")
