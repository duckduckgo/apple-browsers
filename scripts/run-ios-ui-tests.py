#!/usr/bin/env python3
"""Run a UI-test class once, then retry only complete native failed methods once."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET


SELECTOR = re.compile(r"UI Tests/([A-Za-z_][A-Za-z_0-9]*)/(test[A-Za-z_0-9]+)\(\)")
CASE = re.compile(r"Test Case '-\[(?:UI_Tests\.)?([A-Za-z_][A-Za-z_0-9]*) (test[A-Za-z_0-9]+)\]' (started|passed|failed|skipped)(?: \(([0-9.]+) seconds\))?\.")
RUNNER_FAULT = re.compile(
    r"Restarting after unexpected|Early unexpected exit|Test runner.*(crash|exited|failed)|"
    r"Lost connection to|Failed to establish communication|Testing cancelled|"
    r"\bcrashed\b|\bCrash:|test runner.*crash|encountered an error.*launch|exceeded.*time allowance",
    re.IGNORECASE)


def save(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n")


def selectors(data, test_class):
    if data.get("errors") != [] or len(data.get("values", [])) != 1:
        raise ValueError("Native enumeration failed or returned multiple configurations")
    enabled = data["values"][0]["enabledTests"]
    result = [item["identifier"] for item in enabled]
    if not result or len(set(result)) != len(result):
        raise ValueError("Enumeration contains zero or duplicate enabled methods")
    for item in result:
        match = SELECTOR.fullmatch(item)
        if not match or match[1] != test_class:
            raise ValueError(f"Unexpected native selector: {item!r}")
    return result


def cases_from_tree(data):
    result = []

    def visit(node):
        if node.get("nodeType") == "Test Case":
            result.append(node)
        else:
            for child in node.get("children", []):
                visit(child)
    for node in data["testNodes"]:
        visit(node)
    return result


def messages(node):
    result = []
    if node.get("nodeType") == "Failure Message":
        location = node.get("sourceLocation", {})
        result.append(f"{location.get('filePath', '')}:{location.get('lineNumber', '')} {node['name']}".strip())
    for child in node.get("children", []):
        result.extend(messages(child))
    return result


def validate_attempt(summary, tree, log, expected, exit_code):
    """Reject partial/crashed runs before any retry can be selected."""
    cases = cases_from_tree(tree)
    actual = ["UI Tests/" + item["nodeIdentifier"] for item in cases]
    if len(set(actual)) != len(actual) or set(actual) != set(expected):
        raise ValueError("Native cases differ from the exact enumerated selection")
    counts = {status: sum(case.get("result") == status for case in cases)
              for status in ("Passed", "Failed", "Skipped")}
    if sum(counts.values()) != len(cases) or counts["Skipped"] == len(cases):
        raise ValueError("Native results are unknown or contain no executed methods")
    for key, status in (("passedTests", "Passed"), ("failedTests", "Failed"), ("skippedTests", "Skipped")):
        if summary.get(key) != counts[status]:
            raise ValueError("Native summary and test tree disagree")
    if summary.get("totalTestCount") != len(cases) or summary.get("expectedFailures", 0):
        raise ValueError("Unexpected native test count or expected-failure result")
    failed = [identifier for identifier, case in zip(actual, cases) if case["result"] == "Failed"]
    if exit_code != (65 if failed else 0) or summary.get("result") != ("Failed" if failed else "Passed"):
        raise ValueError("xcodebuild exit/native outcome disagree or indicate a runner fault")
    if RUNNER_FAULT.search(log) or any(RUNNER_FAULT.search(text) for case in cases for text in messages(case)):
        raise ValueError("Runner fault/timeout observed; no retry is permitted")
    events = {}
    for match in CASE.finditer(log):
        key = f"UI Tests/{match[1]}/{match[2]}()"
        events.setdefault(key, []).append(match[3])
    for identifier, case in zip(actual, cases):
        state = case["result"].lower()
        if events.get(identifier) != ["started", state]:
            raise ValueError("Missing/duplicate raw method start or terminal result")
        repetitions = [child for child in case.get("children", []) if child.get("nodeType") == "Repetition"]
        if len(repetitions) > 1 or any(rep.get("result") != case["result"] for rep in repetitions):
            raise ValueError("Unexpected built-in test repetition")
    if set(events) != set(expected):
        raise ValueError("Raw log contains methods outside the exact selection")
    return cases, failed


def write_report(path, test_id, attempts):
    """Keep native failures/skips even when xcbeautify omits a timed-out method."""
    root = ET.Element("testsuites")
    cases = [case for attempt in attempts for case in attempt.get("cases", [])]
    suite = ET.SubElement(root, "testsuite", name=test_id, tests=str(len(cases)),
                          failures=str(sum(c.get("result") == "Failed" for c in cases)),
                          errors=str(sum(c.get("result") not in ("Passed", "Failed", "Skipped") for c in cases)),
                          skipped=str(sum(c.get("result") == "Skipped" for c in cases)))
    for case in cases:
        identifier = case.get("nodeIdentifier", "")
        cls, _, name = identifier.partition("/")
        item = ET.SubElement(suite, "testcase", classname="UI_Tests." + cls, name=name.removesuffix("()"),
                             time=str(case.get("durationInSeconds", 0)))
        if case.get("result") == "Failed":
            text = "\n".join(messages(case)) or case.get("details") or "Native XCTest failure; see retained xcresult"
            ET.SubElement(item, "failure", message=text).text = text
        elif case.get("result") == "Skipped":
            ET.SubElement(item, "skipped", message=case.get("details", "Native XCTest skipped this method"))
        elif case.get("result") != "Passed":
            ET.SubElement(item, "error", message="Unknown/incomplete native result; shard marked invalid")
    ET.indent(root)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def capture(command, log_path):
    with log_path.open("w") as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        formatter = subprocess.Popen(["xcbeautify"], stdin=subprocess.PIPE, text=True)
        for line in process.stdout:
            log.write(line)
            log.flush()
            if formatter.stdin:
                try:
                    formatter.stdin.write(line)
                    formatter.stdin.flush()
                except BrokenPipeError:
                    formatter.stdin = None
        if formatter.stdin:
            formatter.stdin.close()
        code = process.wait()
        if formatter.wait() != 0:
            raise ValueError("xcbeautify failed")
    return code


def native(command, path):
    output = subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", command,
                                      "--path", str(path / "TestResults.xcresult"), "--compact"], text=True)
    data = json.loads(output)
    save(path / f"{command}.json", data)
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xctestrun", required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--test-class", required=True)
    parser.add_argument("--diagnostics-mode", choices=("default", "never"), default="never")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", args.test_class):
        parser.error("Invalid test class")
    output = Path("ui-test-attempts")
    output.mkdir()  # Never overwrite evidence from a prior invocation.
    reports = Path("reports")
    reports.mkdir(exist_ok=True)
    stem = f"{args.test_class}-{os.environ['DEVICE']}-{os.environ['USER_MODE']}"
    invalid = reports / f"{stem}.invalid"
    invalid.touch()
    metadata = {"workflow_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
                "run_id": os.environ["GITHUB_RUN_ID"], "checkout_sha": os.environ["GITHUB_SHA"],
                "device": os.environ["DEVICE"], "user_mode": os.environ["USER_MODE"],
                "destination": args.destination, "xctestrun": args.xctestrun,
                "attempts": [], "complete": False}
    base = ["xcodebuild", "test-without-building", "-xctestrun", args.xctestrun,
            "-destination", args.destination, "-parallel-testing-enabled", "NO"]
    attempts = metadata["attempts"]
    status = 1
    try:
        enumeration = output / "enumeration.json"
        command = base + [f"-only-testing:UI Tests/{args.test_class}", "-enumerate-tests",
                          "-test-enumeration-style", "flat", "-test-enumeration-format", "json",
                          "-test-enumeration-output-path", str(enumeration)]
        started = time.monotonic()
        with (output / "enumeration.log").open("w") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
        metadata["enumeration_seconds"] = time.monotonic() - started
        expected = selectors(json.loads(enumeration.read_text()), args.test_class)
        metadata["enumerated_selectors"] = expected
        selected = expected
        for name in ("initial", "retry"):
            path = output / name
            path.mkdir()
            command = base + ["-resultBundlePath", str(path / "TestResults.xcresult")]
            command += ["-only-testing:" + identifier.removesuffix("()") for identifier in selected]
            if args.diagnostics_mode == "never":
                command += ["-collect-test-diagnostics", "never"]
            record = {"name": name, "selected": selected, "command": command, "cases": []}
            attempts.append(record)
            save(path / "command.json", command)
            started = time.monotonic()
            code = capture(command, path / "ui-tests.log")
            record.update(exit_code=code, seconds=time.monotonic() - started)
            summary, tree = native("summary", path), native("tests", path)
            record["cases"] = cases_from_tree(tree)  # Preserve partial evidence even if validation rejects it.
            _, failed = validate_attempt(summary, tree, (path / "ui-tests.log").read_text(), selected, code)
            if name == "retry" and any(case["result"] == "Skipped" for case in record["cases"]):
                raise ValueError("A selected failed method was skipped on retry")
            record["validated"] = True
            if not failed:
                status = 0
                break
            selected = failed  # No class fallback; only first-attempt native failures.
        metadata["complete"] = True
        metadata["final_failed_selectors"] = selected if status else []
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        metadata["error"] = str(error)
        print(f"::error::{error}", file=sys.stderr)
    finally:
        try:
            write_report(reports / f"{stem}.xml", f"{args.test_class} ({args.destination}, {os.environ['USER_MODE']})", attempts)
            ET.parse(reports / f"{stem}.xml")
            with Path("ui-tests.log").open("w") as combined:
                for name in ("initial", "retry"):
                    path = output / name / "ui-tests.log"
                    if path.exists():
                        combined.write(path.read_text())
        except (OSError, ValueError, ET.ParseError) as error:
            metadata.update(complete=False, error=f"Report finalization failed: {error}")
            status = 1
            print(f"::error::{metadata['error']}", file=sys.stderr)
        metadata["exit_code"] = status
        save(reports / f"{stem}.meta.json", metadata)
        if metadata["complete"]:
            invalid.rename(reports / f"{stem}.valid")
    return status


if __name__ == "__main__":
    sys.exit(main())
