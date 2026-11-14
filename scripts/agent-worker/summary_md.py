#!/usr/bin/env python3
"""Write summary.md, the readable record of the agent's run, from Claude's result.json.

Usage: summary_md.py <result.json> <evidence dir> <claude exit code>

summary.md starts with the agent's final message. Later steps add the pull request text and the
changes, and the run details (outcome, turns, cost) are appended last, from run-details.md. The log
gets counts and tool names only; summary.md goes to evidence behind SSO, never the log or job summary
"""

import json
import os
import sys


def main():
    src, evidence, rc = sys.argv[1:4]
    summary, details = os.path.join(evidence, "summary.md"), os.path.join(evidence, "run-details.md")
    try:
        with open(src) as f:
            r = json.load(f)
    except Exception:
        print("no parsable result")
        with open(summary, "w") as f:
            f.write("# Summary\n\nThe agent wrote no parsable result. See result.json and claude.err.\n")
        with open(details, "w") as f:
            f.write(f"\n## Agent run details\n\nClaude exited with {rc}.\n")
        return

    info = {k: r.get(k) for k in ("subtype", "is_error", "num_turns", "total_cost_usd")}
    # Tool names only, never inputs, so blocked writes show up without leaking plan text
    info["permission_denials"] = sorted({d.get("tool_name", "?") for d in r.get("permission_denials") or []})
    print(info)

    # Rendered as Markdown; the artifacts viewer sanitizes the HTML it produces
    text = (r.get("result") or "").strip() or "(none)"
    with open(summary, "w") as f:
        f.write(f"# Summary\n\n{text}\n")

    cost, secs = r.get("total_cost_usd"), (r.get("duration_ms") or 0) / 1000
    with open(details, "w") as f:
        f.write("\n".join([
            "", "## Agent run details", "",
            "| | |", "|---|---|",
            f"| Outcome | {r.get('subtype')}{' (error)' if r.get('is_error') else ''}, exit {rc} |",
            f"| Turns | {r.get('num_turns')} |",
            f"| Cost | {'$%.2f' % cost if cost is not None else '-'} |",
            f"| Duration | {secs:.0f}s |",
            f"| Denied tools | {', '.join(info['permission_denials']) or 'none'} |", "",
        ]))


if __name__ == "__main__":
    main()
