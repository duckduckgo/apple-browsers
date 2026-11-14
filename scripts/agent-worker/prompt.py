#!/usr/bin/env python3
"""Print the agent's prompt from prompts/worker.md, adding a retry section on a retry.

Usage: prompt.py <repo dir> <plan.md> <previous run dir>
Env: RETRY (0 for a new plan)

On a retry that has the previous run's patch, prompts/fix.md goes in with that run's build, test and
flow results, links removed since the agent mustn't copy links into code. When the previous run made
no change, prompts/retry.md goes in with how its agent run ended
"""

import json

import os
import re
import sys

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prompts")


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def main():
    repo, plan, prev = sys.argv[1:4]
    attempt = int(os.environ.get("RETRY", "0"))
    fix = ""
    has_patch = bool(read(os.path.join(prev, "changes.patch")).strip())
    if attempt > 0 and not has_patch:
        try:
            r = json.loads(read(os.path.join(prev, "result.json")))
        except ValueError:
            r = {}
        ended = r.get("subtype") or "no result"
        fix = read(os.path.join(HERE, "retry.md")).replace("{{ENDED}}", f"{ended}{' (error)' if r.get('is_error') else ''}")
    elif attempt > 0:
        text = read(os.path.join(prev, "results.md"))
        text = re.sub(r"^\[?!\[.*$", "", text, flags=re.M)            # screenshots and recordings
        text = re.sub(r"\s*\(\[[^\]]*\]\([^)]*\)(, \[[^\]]*\]\([^)]*\))*\)", "", text)  # (log links)
        text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)           # any other link, keeping its text
        fix = read(os.path.join(HERE, "fix.md")).replace("{{RESULTS}}", text.strip() or "(no results)")
    out = read(os.path.join(HERE, "worker.md"))
    out = out.replace("{{REPO_DIR}}", repo).replace("{{FIX}}", fix.replace("{{ATTEMPT}}", str(attempt)))
    sys.stdout.write(out.replace("{{PLAN}}", read(plan)))


if __name__ == "__main__":
    main()
