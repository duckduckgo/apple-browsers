#!/usr/bin/env python3
"""Print the agent's prompt from prompts/worker.md with the repository path and the plan. With a
worktrees dir, the prompt starts with prompts/auto.md, which runs it through the auto plugin

Usage: prompt.py <repo dir> <plan.md> [<worktrees dir>]
"""

import os
import sys

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prompts")


def read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def main():
    repo, plan = sys.argv[1:3]
    worktrees = sys.argv[3] if len(sys.argv) > 3 else ""
    out = read(os.path.join(HERE, "worker.md"))
    if worktrees:
        out = read(os.path.join(HERE, "auto.md")).replace("{{WORKTREES}}", worktrees) + out
    out = out.replace("{{REPO_DIR}}", repo)
    sys.stdout.write(out.replace("{{PLAN}}", read(plan)))


if __name__ == "__main__":
    main()
