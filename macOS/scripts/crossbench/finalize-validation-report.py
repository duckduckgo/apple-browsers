#!/usr/bin/env python3
"""Finalize a WPR report after the validation job and emit workflow outputs."""

import argparse
import re
from pathlib import Path
from typing import Optional, Tuple


def infrastructure_failure(reason: str) -> Tuple[str, bool, bool]:
    text = f"""WPR archive validation: INFRASTRUCTURE FAILURE
Package status: FAILED
Eligible sites: 0/0
Site errors: 0
Detected issues: 1

[PACKAGE ERROR] validation infrastructure
Failure: {reason}
Action: inspect the failed validation job

Browser jobs were blocked because archive validation did not complete.
"""
    return text, True, True


def replace_count(report: str, count: int) -> str:
    return re.sub(r"(?m)^Detected issues: \d+$", f"Detected issues: {count}", report)


def finalize(report: Optional[str], job_result: str) -> Tuple[str, bool, bool]:
    if not report:
        return infrastructure_failure("validation did not produce a report")

    status = re.search(r"(?m)^Package status: (READY|FAILED)$", report)
    detected = re.search(r"(?m)^Detected issues: (\d+)$", report)
    site_errors = re.search(r"(?m)^Site errors: (\d+)$", report)
    if not status or not detected or not site_errors:
        return infrastructure_failure("validation produced a malformed report")
    if int(detected.group(1)) != int(site_errors.group(1)):
        return infrastructure_failure("validation report contains inconsistent issue counts")

    # FAILED is the validator's intentional zero-eligible-sites result, not an
    # artifact handoff failure. Preserve its report and reason.
    if status.group(1) == "FAILED":
        return report, True, True
    if job_result != "success":
        issue_count = int(detected.group(1)) + 1
        report = report.replace("Package status: READY", "Package status: FAILED", 1)
        report = replace_count(report, issue_count).rstrip() + f"""

[PACKAGE ERROR] validation handoff
Failure: validation job concluded {job_result}
Action: inspect archive staging and artifact upload in the validation job

Browser jobs were blocked because the validation package was not delivered.
"""
        return report, True, True
    return report, int(detected.group(1)) > 0, False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True)
    parser.add_argument("--validation-result", required=True)
    parser.add_argument("--github-output")
    args = parser.parse_args()

    path = Path(args.report)
    text, has_errors, package_failed = finalize(
        path.read_text() if path.is_file() and path.stat().st_size else None,
        args.validation_result,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    outputs = (
        f"has-errors={'true' if has_errors else 'false'}\n"
        f"package-failed={'true' if package_failed else 'false'}\n"
    )
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as output:
            output.write(outputs)
    else:
        print(outputs, end="")


if __name__ == "__main__":
    main()
