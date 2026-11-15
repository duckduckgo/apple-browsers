#!/usr/bin/env python3
"""Print the agent's prompt from prompts/worker.md with the repository path and the plan.

Usage: prompt.py <repo dir> <plan.md>
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
    out = read(os.path.join(HERE, "worker.md")).replace("{{REPO_DIR}}", repo)
    sys.stdout.write(out.replace("{{PLAN}}", read(plan)))


if __name__ == "__main__":
    main()
