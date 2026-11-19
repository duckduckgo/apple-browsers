#!/usr/bin/env python3
"""Print the agent's prompt from prompts/worker.md with the repository path and the plan. Without auto, the PR section
is prompts/pr-worker.md, since the worker opens the PR. With a worktrees dir, the prompt starts with prompts/auto.md,
which runs it through the auto plugin, and the PR section is prompts/pr-auto.md, since the agent opens its own PRs

Usage: prompt.py <repo dir> <plan.md> [<worktrees dir>]
Env: TASK_GID and DEFAULT_BRANCH, for the PR rules with auto
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
    pr = read(os.path.join(HERE, "pr-auto.md" if worktrees else "pr-worker.md")).rstrip()
    out = out.replace("{{PR}}", pr)
    if worktrees:
        out = read(os.path.join(HERE, "auto.md")).replace("{{WORKTREES}}", worktrees) + out
    for key in ("TASK_GID", "DEFAULT_BRANCH"):
        out = out.replace("{{" + key + "}}", os.environ.get(key, ""))
    out = out.replace("{{REPO_DIR}}", repo)
    sys.stdout.write(out.replace("{{PLAN}}", read(plan)))


if __name__ == "__main__":
    main()
