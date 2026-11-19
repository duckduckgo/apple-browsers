#!/usr/bin/env python3
"""The PR's title and description, written by the agent and checked before anyone can publish them.

Usage:
  pr_text.py extract <repo dir> <evidence dir>   Move the agent's .agent-pr.md out of the checkout into
                                                 evidence as pr.md, cleaned, and add it to summary.md
  pr_text.py render <pr.md> <out dir> [<template>]
                                                 Write title.txt and body.md for gh pr create, in the
                                                 shape of the repo's PR template (env: TASK_GID, RUN_URL, RUN_ID)

The PR is public and opens without an approval step, so lines with links are dropped from the agent's
text and the title is one plain line. Only the template sections below are kept, in the template's order
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


# The agent's sections from the PR template, in template order. Text before the first heading counts as Description
SECTIONS = ["### Description", "### Testing Steps", "### Impact", "#### What could go wrong?", "### Quality Considerations"]


def sections(body):
    """{heading: text} for the template sections in the agent's body"""
    keys = {h.lstrip("#").strip().lower(): h for h in SECTIONS}
    found, current = {}, SECTIONS[0]
    for line in body:
        key = keys.get(line.lstrip("#").strip().rstrip(":").lower()) if line.startswith("#") else None
        if key:
            current = key
            continue
        found.setdefault(current, []).append(line)
    return {h: "\n".join(found[h]).strip() for h in SECTIONS if "\n".join(found.get(h, [])).strip()}


def footer(template):
    """The template's closing references, from its last --- line, or nothing"""
    try:
        with open(template, errors="replace") as f:
            lines = f.read(20000).rstrip().splitlines()
    except (OSError, TypeError):
        return ""
    idx = max((i for i, l in enumerate(lines) if l.strip() == "---"), default=None)
    return "\n".join(lines[idx:]) if idx is not None else ""


def render(pr_md, out, template=None):
    e = os.environ
    title, body = None, []
    if os.path.isfile(pr_md):
        with open(pr_md, errors="replace") as f:
            title, body = clean(f.read())
    title = title or f"Agent worker run {e['RUN_ID']}"
    found = sections(body)
    found.setdefault(SECTIONS[0], "Change from the agent worker, for a person to review.")
    parts = [f"Task/Issue URL: https://app.asana.com/0/0/{e['TASK_GID']}/f"]
    parts += [f"{h}\n{found[h]}" for h in SECTIONS if h in found]
    parts.append(f"Opened by the agent worker after its build and tests passed. Run: {e['RUN_URL']}")
    end = footer(template)
    if end:
        parts.append(end)
    with open(os.path.join(out, "title.txt"), "w") as f:
        f.write(title)
    with open(os.path.join(out, "body.md"), "w") as f:
        f.write("\n\n".join(parts) + "\n")


def main():
    if sys.argv[1] == "extract":
        extract(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "render":
        render(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
