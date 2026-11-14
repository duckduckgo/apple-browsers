#!/usr/bin/env python3
"""Print the agent's prompt from prompts/worker.md, adding prompts/fix.md on a fix attempt.

Usage: prompt.py <repo dir> <plan.md> <previous results.md>
Env: ROUND (0 for the first attempt)

On a fix attempt the previous attempt's build, test and flow results go into the prompt with their
links removed, since the agent mustn't copy links into code
"""

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
    repo, plan, results = sys.argv[1:4]
    attempt = int(os.environ.get("ROUND", "0"))
    fix = ""
    if attempt > 0:
        text = read(results)
        text = re.sub(r"^\[?!\[.*$", "", text, flags=re.M)            # screenshots and recordings
        text = re.sub(r"\s*\(\[[^\]]*\]\([^)]*\)(, \[[^\]]*\]\([^)]*\))*\)", "", text)  # (log links)
        text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)           # any other link, keeping its text
        fix = read(os.path.join(HERE, "fix.md")).replace("{{RESULTS}}", text.strip() or "(no results)")
    out = read(os.path.join(HERE, "worker.md"))
    out = out.replace("{{REPO_DIR}}", repo).replace("{{FIX}}", fix.replace("{{ATTEMPT}}", str(attempt)))
    sys.stdout.write(out.replace("{{PLAN}}", read(plan)))


if __name__ == "__main__":
    main()
