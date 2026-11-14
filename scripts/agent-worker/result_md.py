#!/usr/bin/env python3
"""Print a short run summary to the log and write result.md, a readable copy of Claude's result.json.

Usage: result_md.py <result.json> <result.md> <claude exit code>

The log gets counts and tool names only. result.md, which holds the agent's final message, goes to
evidence behind SSO, never the log or job summary
"""

import json
import sys


def main():
    src, md, rc = sys.argv[1:4]
    try:
        with open(src) as f:
            r = json.load(f)
    except Exception:
        print("no parsable result")
        with open(md, "w") as f:
            f.write(f"# Agent result\n\nClaude exited with {rc} and wrote no parsable result. See result.json and claude.err.\n")
        return

    summary = {k: r.get(k) for k in ("subtype", "is_error", "num_turns", "total_cost_usd")}
    # Tool names only, never inputs, so blocked writes show up without leaking plan text
    summary["permission_denials"] = sorted({d.get("tool_name", "?") for d in r.get("permission_denials") or []})
    print(summary)

    cost, secs = r.get("total_cost_usd"), (r.get("duration_ms") or 0) / 1000
    # Rendered as Markdown; the artifacts viewer sanitizes the HTML it produces
    text = (r.get("result") or "").strip() or "(none)"
    lines = [
        "# Agent result", "",
        "| | |", "|---|---|",
        f"| Outcome | {r.get('subtype')}{' (error)' if r.get('is_error') else ''}, exit {rc} |",
        f"| Turns | {r.get('num_turns')} |",
        f"| Cost | {'$%.2f' % cost if cost is not None else '-'} |",
        f"| Duration | {secs:.0f}s |",
        f"| Denied tools | {', '.join(summary['permission_denials']) or 'none'} |",
        "", "## Final message", "", text, "",
    ]
    with open(md, "w") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
