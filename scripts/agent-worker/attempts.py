#!/usr/bin/env python3
"""Carry earlier attempts' agent stats forward on a retry, for the cost table on the verify page.

Usage: attempts.py <previous run dir> <previous run id-attempt> <output attempts.json>

Writes the previous run's attempts.json plus the previous run itself, read from its result.json, as a
list of {"run", "turns", "cost", "duration_ms"}. A previous run with no result.json adds nothing
"""

import json
import os
import sys


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def main():
    prev, run, out = sys.argv[1], sys.argv[2], sys.argv[3]
    history = [a for a in load(os.path.join(prev, "attempts.json"), []) if isinstance(a, dict)]
    r = load(os.path.join(prev, "result.json"), None)
    if isinstance(r, dict):
        history.append({"run": run, "turns": r.get("num_turns"), "cost": r.get("total_cost_usd"),
                        "duration_ms": r.get("duration_ms")})
    if history:
        with open(out, "w") as f:
            json.dump(history, f)


if __name__ == "__main__":
    main()
