#!/usr/bin/env python3
"""Write verify.md, the one page an approver reads before a PR is opened.

Usage: verify_md.py <plan dir> <out dir>
Env: EVIDENCE_URL (this run's evidence), RETRY (0 for a new plan), PREV_URL (the retried run's
evidence), RUN_URL, TASK_GID

Combines the agent's result.json, pr.md, changes.patch and plan-notes.txt from plan dir with the build,
test and screen results that verify.sh wrote to results.md in out dir. Writes nothing to the log
"""

import json
import os
import subprocess
import sys


def read(path, limit=200000):
    try:
        with open(path, errors="replace") as f:
            return f.read(limit)
    except OSError:
        return ""


def money(v):
    return f"${v:.2f}"


def cost_rows(plan, cost):
    """Planner and earlier attempt rows when their stats exist, then a total of every cost shown"""
    def load(name):
        try:
            return json.loads(read(os.path.join(plan, name)))
        except ValueError:
            return None
    rows, costs = [], [cost]
    p = load("plan-stats.json")
    if isinstance(p, dict) and isinstance(p.get("total_cost_usd"), (int, float)):
        mins = (p.get("duration_ms") or 0) / 60000
        rows.append(f"| Planner | {money(p['total_cost_usd'])}, {p.get('num_turns', '-')} turns, {mins:.0f} min |")
        costs.append(p["total_cost_usd"])
    earlier = [a for a in load("attempts.json") or [] if isinstance(a, dict) and isinstance(a.get("cost"), (int, float))]
    if earlier:
        total = sum(a["cost"] for a in earlier)
        runs = "1 run" if len(earlier) == 1 else f"{len(earlier)} runs"
        rows.append(f"| Earlier attempts | {money(total)} over {runs} |")
        costs.append(total)
    if not rows or not all(isinstance(c, (int, float)) for c in costs):
        return rows
    return rows + [f"| **Total** | **{money(sum(costs))}** |"]


def main():
    plan, out = sys.argv[1:3]
    e = os.environ
    ev, run, attempt = e.get("EVIDENCE_URL", "").rstrip("/"), e.get("RUN_URL", ""), int(e.get("RETRY", "0"))
    try:
        r = json.loads(read(os.path.join(plan, "result.json")))
    except ValueError:
        r = {}

    pr = read(os.path.join(plan, "pr.md")).strip().splitlines()
    title = pr[0] if pr else ""
    body = "\n".join(pr[1:]).strip()

    md = [f"# {title or 'Agent change'}", ""]
    task = f"[Asana task](https://app.asana.com/0/0/{e['TASK_GID']}/f)" if e.get("TASK_GID") else "the task"
    md += [f"The agent's proposed fix for {task}, built and tested on a clean runner. Approving the publish step "
           f"in the [worker run]({run}) opens it as a PR with the title and description below.", ""]
    status = dict(l.split("=", 1) for l in read(os.path.join(out, "status")).split() if "=" in l)
    words = {"yes": "passed", "no": "failed"}
    parts = [f"build {words.get(status.get('build'), "didn't run")}"]
    parts += [f"{k} {status[k]}" for k in ("tests", "maestro") if k in status]
    md += [f"**Results:** {', '.join(parts).replace('maestro', 'Maestro flow')}.", ""]
    md += ["## Summary", "", (r.get("result") or "").strip() or "The agent left no summary.", ""]

    md += ["## Proposed pull request", ""]
    if title:
        md += [f"**Title:** {title}", "", "**Description:**", "", body or "(no description)", ""]
    else:
        md += ["The agent wrote no PR text, so the PR gets a default title and description.", ""]

    md += ["### Changes", ""]
    patch = os.path.join(plan, "changes.patch")
    if ev:
        md += [f"Full diff: [changes.patch]({ev}/changes.patch)", ""]
    stat = subprocess.run(["git", "apply", "--stat", patch], capture_output=True, text=True).stdout.rstrip()
    if stat:
        md += ["```", stat, "```", ""]

    results = read(os.path.join(out, "results.md")).strip()
    md += [results or "### Build and tests\n\nThe build didn't run. See the worker run for why.", ""]

    excluded = [l.partition(":") for l in read(os.path.join(plan, "excluded.txt")).splitlines() if ":" in l]
    if excluded:
        md += ["### Excluded tests", "",
               "The agent took these tests out of the run. They're tests it didn't add, for code the change doesn't touch. "
               "Check that its reason holds before approving.", ""]
        md += [f"- `{t.strip()}`: {r.strip()}" for t, _, r in excluded] + [""]

    # Everything about the agent workflow goes in this last section, so the page above reads as the change
    md += ["## Agent run", ""]
    if attempt:
        prev = e.get("PREV_URL", "").rstrip("/")
        md += [f"This is retry {attempt}. The agent started from the previous run's change and fixed what failed in "
               f"[its results]({prev}/verify/verify.md).", ""]
        fixed = read(os.path.join(plan, "retry.txt")).strip()
        if fixed:
            md += [f"What this retry fixed, in the agent's words: {fixed}", ""]
    notes = read(os.path.join(plan, "plan-notes.txt")).strip()
    if notes:
        md += [notes, ""]

    cost, secs = r.get("total_cost_usd"), (r.get("duration_ms") or 0) / 1000
    md += ["| | |", "|---|---|",
           f"| Outcome | {r.get('subtype', '-')}{' (error)' if r.get('is_error') else ''} |",
           f"| Model | {', '.join(sorted(r.get('modelUsage') or {})) or '-'} |",
           f"| Turns | {r.get('num_turns', '-')} |",
           f"| Cost | {'$%.2f' % cost if cost is not None else '-'} |",
           f"| Duration | {secs / 60:.0f} min |",
           f"| Denied tools | {', '.join(sorted({d.get('tool_name', '?') for d in r.get('permission_denials') or []})) or 'none'} |"]
    md += cost_rows(plan, cost) + [""]
    if ev:
        md += [f"Raw output: [result.json]({ev}/result.json)", ""]

    with open(os.path.join(out, "verify.md"), "w") as f:
        f.write("\n".join(md))


if __name__ == "__main__":
    main()
