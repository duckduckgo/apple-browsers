#!/usr/bin/env python3
"""Create a concise report for site-level browser measurement problems."""

import argparse
import csv
from pathlib import Path


REPORTABLE_OUTCOMES = {"partial", "no_samples", "infra_error"}
REQUIRED_COLUMNS = {
    "browser",
    "site",
    "outcome",
    "failure_stage",
    "failure_reason",
    "failure_detail",
    "requested_repetitions",
    "observed_repetitions",
    "recorded_samples",
    "dropped_unfinalized",
    "dropped_no_metric",
}


def build_report(
    input_path: Path,
    job_result: str = "success",
    browser_label: str = "Browser",
) -> tuple[str, int]:
    with input_path.open(newline="", encoding="utf-8") as source:
        reader = csv.DictReader(source, delimiter="\t")
        columns = set(reader.fieldnames or ())
        missing = REQUIRED_COLUMNS - columns
        if missing:
            raise ValueError(
                f"disposition file is missing columns: {', '.join(sorted(missing))}"
            )
        issues = [row for row in reader if row["outcome"] in REPORTABLE_OUTCOMES]

    if not issues and job_result not in {"success", "skipped"}:
        return (
            f"[RUN ERROR] {browser_label} LCP job did not complete successfully\n"
            f"Result: {job_result}\n"
            "Action: inspect the failed workflow step and preserved diagnostics\n",
            1,
        )
    if not issues:
        return "", 0

    browser = issues[0]["browser"]
    lines = [
        f"Browser measurement problems: {len(issues)}",
        f"Browser: {browser}",
        "",
    ]
    for row in issues:
        lines.extend((
            f"[SITE ERROR] {row['site']}",
            f"Outcome: {row['outcome']}",
        ))
        if row["failure_stage"] or row["failure_reason"]:
            lines.append(
                f"Failure: {row['failure_stage'] or '-'} / "
                f"{row['failure_reason'] or '-'}"
            )
        if row["failure_detail"]:
            lines.append(f"Detail: {row['failure_detail']}")
        lines.extend(
            (
                "Samples: "
                f"{row['recorded_samples']}/{row['requested_repetitions']} "
                f"(observed {row['observed_repetitions']}, "
                f"unfinalized {row['dropped_unfinalized']}, "
                f"no metric {row['dropped_no_metric']})",
                "Action: inspect the workflow warnings and preserved diagnostics",
                "",
            )
        )
    return "\n".join(lines).rstrip() + "\n", len(issues)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--job-result", default="success")
    parser.add_argument("--browser-label", default="Browser")
    args = parser.parse_args()

    report, issue_count = build_report(
        args.input,
        job_result=args.job_result,
        browser_label=args.browser_label,
    )
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(report, encoding="utf-8")

    outputs = (
        f"has-errors={'true' if issue_count else 'false'}\n"
        f"issue-count={issue_count}\n"
    )
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as output:
            output.write(outputs)
    else:
        print(outputs, end="")


if __name__ == "__main__":
    main()
