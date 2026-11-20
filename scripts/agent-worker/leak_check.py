#!/usr/bin/env python3
"""Finds text the agent copied from its instructions (auto's skills and the worker prompts) into what gets published.

Used by pr_audit.py on what the agent published. Env: LEAK_CORPUS, colon-separated files or directories whose .md files
the agent was given

A line leaks when it shares a run of WORDS words with the corpus, so short common phrases don't count
"""

import os
import re

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
