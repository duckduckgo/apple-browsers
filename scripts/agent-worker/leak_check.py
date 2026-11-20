#!/usr/bin/env python3
"""Finds text the agent copied from its instructions (auto's skills and the worker prompts) into what gets published.

Usage: leak_check.py patch <changes.patch> <out file>
Env: LEAK_CORPUS, colon-separated files or directories whose .md files the agent was given

A line leaks when it shares a run of WORDS words with the corpus, so short common phrases don't count. pr_audit.py
uses corpus() and leaks() on what the agent published. The patch command writes the added lines that leak to
<out file>, and the log only gets a count, since this repo's logs are public
"""

import os
import re
import sys

WORDS = 10
WORD = re.compile(r"[a-z0-9']+")


def words(text):
    return WORD.findall(text.lower())


def shingles(ws):
    return {" ".join(ws[i:i + WORDS]) for i in range(len(ws) - WORDS + 1)}


def corpus(paths=None):
    """Shingles of every .md file under the LEAK_CORPUS paths, one paragraph at a time"""
    paths = paths if paths is not None else [p for p in os.environ.get("LEAK_CORPUS", "").split(":") if p]
    files = []
    for p in paths:
        if os.path.isfile(p):
            files.append(p)
        for root, _, names in os.walk(p):
            files += [os.path.join(root, n) for n in names if n.endswith(".md")]
    found = set()
    for path in files:
        try:
            with open(path, errors="replace") as f:
                text = f.read(2_000_000)
        except OSError:
            continue
        # Paragraphs, so a run can't join the end of one paragraph to the start of the next
        for para in re.split(r"\n\s*\n", text):
            found |= shingles(words(para))
    return found


def leaks(line, known):
    return bool(known) and not shingles(words(line)).isdisjoint(known)


def patch(src, out):
    known = corpus()
    # Runs of added lines are checked together, so text split over several comment lines is still caught
    blocks, block = [], []
    with open(src, errors="replace") as f:
        for l in f:
            if l.startswith("+") and not l.startswith("+++"):
                block.append(l[1:].rstrip("\n"))
            elif block:
                blocks.append(block)
                block = []
    if block:
        blocks.append(block)
    hits = ["\n".join(b) for b in blocks if leaks(" ".join(b), known)]
    print(f"instruction text in patch: {len(hits)} block(s)")
    if hits:
        with open(out, "w") as f:
            f.write("\n\n---\n\n".join(hits) + "\n")
    return 1 if hits else 0


if __name__ == "__main__":
    if len(sys.argv) != 4 or sys.argv[1] != "patch":
        sys.exit(__doc__)
    sys.exit(patch(sys.argv[2], sys.argv[3]))
