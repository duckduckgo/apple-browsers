#!/usr/bin/env python3
"""Print the agent's prompt: prompts/auto.md, which runs it through the auto plugin, then prompts/worker.md with
prompts/pr-auto.md as its PR section, the repository path and the plan

Usage: prompt.py <repo dir> <plan.md> <worktrees dir>
Env: TASK_GID and DEFAULT_BRANCH, for the PR rules, and SCRATCH, the agent's scratch dir
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
    repo, plan, worktrees = sys.argv[1:4]
    out = read(os.path.join(HERE, "worker.md")).replace("{{PR}}", read(os.path.join(HERE, "pr-auto.md")).rstrip())
    out = read(os.path.join(HERE, "auto.md")).replace("{{WORKTREES}}", worktrees) + out
    for key in ("TASK_GID", "DEFAULT_BRANCH", "SCRATCH"):
        out = out.replace("{{" + key + "}}", os.environ.get(key, ""))
    out = out.replace("{{REPO_DIR}}", repo)
    sys.stdout.write(out.replace("{{PLAN}}", read(plan)))


if __name__ == "__main__":
    main()
