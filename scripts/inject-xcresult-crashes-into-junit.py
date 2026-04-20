#!/usr/bin/env python3
"""Inject crashed tests from an xcresult bundle into a JUnit XML file.

xcbeautify doesn't emit <failure> entries for tests that crashed (SIGSEGV,
fatalError, etc.) because the test host dies before the failure is recorded.
This reads crashed tests from the xcresult's structured summary and adds them
as <failure> entries so downstream tooling (mikepenz/action-junit-report,
yq-based Asana reporter) sees accurate counts.

Usage: inject-xcresult-crashes-into-junit.py <xcresult> <junit-xml>
"""
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <xcresult> <junit-xml>", file=sys.stderr)
        return 2

    xcresult, junit_path = sys.argv[1], sys.argv[2]

    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "summary",
         "--path", xcresult, "--format", "json"],
        capture_output=True, text=True, check=True,
    )
    summary = json.loads(result.stdout)

    crashes = [
        f for f in summary.get("testFailures", [])
        if re.search(r"crash", f.get("failureText", ""), re.IGNORECASE)
    ]

    if not crashes:
        return 0

    tree = ET.parse(junit_path)
    root = tree.getroot()

    added = 0
    for crash in crashes:
        test_id = crash["testIdentifierString"]
        class_name, _, test_name = test_id.partition("/")
        test_name = test_name.rstrip("()")
        target = crash["targetName"]
        failure_text = crash["failureText"]

        suite = find_or_create_suite(root, class_name, target)

        if suite.find(f"./testcase[@name='{test_name}']/failure") is not None:
            continue

        tc = ET.SubElement(suite, "testcase", {
            "classname": suite.get("name", class_name),
            "name": test_name,
            "time": "0",
        })
        failure = ET.SubElement(tc, "failure", {
            "message": f"Crashed: {failure_text}",
        })
        failure.text = failure_text

        suite.set("tests", str(int(suite.get("tests", "0")) + 1))
        suite.set("failures", str(int(suite.get("failures", "0")) + 1))
        added += 1

    if added > 0:
        root.set("tests", str(int(root.get("tests", "0")) + added))
        root.set("failures", str(int(root.get("failures", "0")) + added))
        tree.write(junit_path, encoding="UTF-8", xml_declaration=True)

    print(f"Injected {added} crash(es) into {junit_path}")
    return 0


def find_or_create_suite(root, class_name: str, target: str) -> ET.Element:
    for ts in root.findall("testsuite"):
        name = ts.get("name", "")
        if name == class_name or name.endswith("." + class_name):
            return ts
    return ET.SubElement(root, "testsuite", {
        "name": f"{target}.{class_name}",
        "tests": "0",
        "failures": "0",
    })


if __name__ == "__main__":
    sys.exit(main())
