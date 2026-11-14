#!/usr/bin/env python3
"""The draft PR's title and description, written by the agent and checked before anyone can publish them.

Usage:
  pr_text.py extract <repo dir> <evidence dir>   Move the agent's .agent-pr.md out of the checkout into
                                                 evidence as pr.md, cleaned, and add it to summary.md
  pr_text.py render <pr.md> <out dir>            Write title.txt and body.md for gh pr create
                                                 (env: TASK_GID, RUN_URL, RUN_ID)

The PR is public, so lines with links are dropped and the title is one plain line. The person who
approves agent-publish sees the text in summary.md before it's used
"""

import os
import re
import sys

AGENT_FILE = ".agent-pr.md"
MAX_TITLE = 100


def clean(text):
    """(title, body lines) with links dropped, or (None, []) when there's no usable title"""
    lines = [line.rstrip() for line in text.splitlines() if "://" not in line and "www." not in line]
    while lines and not lines[0].strip():
        lines.pop(0)
    if not lines:
        return None, []
    title = re.sub(r"\s+", " ", lines[0].lstrip("#").strip())[:MAX_TITLE]
    body = lines[1:]
    while body and not body[0].strip():
        body.pop(0)
    return title or None, body


def extract(repo, evidence):
    src = os.path.join(repo, AGENT_FILE)
    if not os.path.isfile(src):
        print("the agent wrote no PR text")
        return
    with open(src, errors="replace") as f:
        title, body = clean(f.read(20000))
    os.remove(src)
    if not title:
        print("the agent's PR text had no title")
        return
    text = "\n".join([title, ""] + body).rstrip() + "\n"
    with open(os.path.join(evidence, "pr.md"), "w") as f:
        f.write(text)
    with open(os.path.join(evidence, "summary.md"), "a") as f:
        f.write(f"\n## Pull request\n\n**Title:** {title}\n\n" + "\n".join(body).strip() + "\n")
    print("PR text saved to evidence")


def render(pr_md, out):
    e = os.environ
    title, body = None, []
    if os.path.isfile(pr_md):
        with open(pr_md, errors="replace") as f:
            title, body = clean(f.read())
    title = title or f"Agent worker run {e['RUN_ID']}"
    description = "\n".join(body).strip() or "Draft change from the agent worker, for a person to review and finish."
    with open(os.path.join(out, "title.txt"), "w") as f:
        f.write(title)
    with open(os.path.join(out, "body.md"), "w") as f:
        f.write(f"Task/Issue URL: https://app.asana.com/0/0/{e['TASK_GID']}/f\n\n### Description\n{description}\n\n"
                f"Opened by the agent worker as a draft for a person to review and finish. Run: {e['RUN_URL']}\n")


def main():
    if sys.argv[1] == "extract":
        extract(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "render":
        render(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
