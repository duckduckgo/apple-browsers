#!/usr/bin/env python3
"""Reject Swift 5 concurrency warnings that become errors in Swift 6.

Read a raw compiler log and limit validation to the supplied source directories.
Other warnings, including concurrency advisories, retain their normal severity.
"""

import argparse
from pathlib import Path
import re
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("sources", type=Path, nargs="+")
    args = parser.parse_args()
    sources = [path.resolve() for path in args.sources]
    if not args.log.is_file() or any(not path.is_dir() for path in sources):
        parser.error("the compiler log and source directories must exist")
    if args.log.stat().st_size == 0:
        parser.error("the compiler log must not be empty")

    diagnostic = re.compile(r"^(.*\.swift):\d+:\d+: warning: (.*)$")
    swift6_error = re.compile(r"this is an error in (?:the )?Swift 6 language mode")
    concurrency = re.compile(r"actor|sendab|isolat|concurren|data race|sending|async", re.IGNORECASE)
    failures = []
    for line in args.log.read_text(encoding="utf-8", errors="replace").splitlines():
        match = diagnostic.match(line)
        if not match:
            continue
        path, message = match.groups()
        if not swift6_error.search(message) or not concurrency.search(message):
            continue
        if any(Path(path).resolve().is_relative_to(source) for source in sources):
            failures.append(line)

    if failures:
        print("Swift 5 complete concurrency checking found Swift 6 errors:", file=sys.stderr)
        print("\n".join(dict.fromkeys(failures)), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
