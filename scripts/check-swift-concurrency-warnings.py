#!/usr/bin/env python3
"""Reject Swift 5 concurrency warnings that become errors in Swift 6.

Check explicit source directories or the SwiftPM targets that enable StrictConcurrency.
Other warnings, including concurrency advisories, retain their normal severity.
"""

import argparse
from functools import cache
import json
from pathlib import Path
import re
import subprocess
import sys


@cache
def strict_package_sources(package):
    command = ["swift", "package", "--package-path", str(package)]
    manifest = json.loads(subprocess.check_output([*command, "dump-package"]))
    enabled = {
        target["name"] for target in manifest["targets"]
        if any(setting["kind"].get("enableExperimentalFeature", {}).get("_0") == "StrictConcurrency"
               for setting in target.get("settings", []))
    }
    if not enabled:
        return set()

    # SwiftPM resolves custom target paths, explicit source lists and exclusions.
    description = json.loads(subprocess.check_output([*command, "describe", "--type", "json"]))
    return {
        (package / target["path"] / source).resolve()
        for target in description["targets"] if target["name"] in enabled
        for source in target["sources"]
    }


def belongs_to_strict_target(file, roots):
    # Resolve manifests only for packages that actually emitted a matching diagnostic.
    for root in roots:
        if file.is_relative_to(root):
            for directory in file.parents:
                if (directory / "Package.swift").is_file():
                    return file in strict_package_sources(directory)
                if directory == root:
                    break
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    scope = parser.add_mutually_exclusive_group(required=True)
    scope.add_argument("sources", type=Path, nargs="*", help="source directories to check")
    scope.add_argument("--package", type=Path, help="check targets opted in by this package")
    scope.add_argument("--package-roots", type=Path, nargs="+", default=[],
                       help="check opted-in targets in packages under these directories")
    args = parser.parse_args()
    sources = [path.resolve() for path in args.sources]
    roots = [path.resolve() for path in args.package_roots]
    if not args.log.is_file() or any(not path.is_dir() for path in sources + roots):
        parser.error("the compiler log and source directories must exist")
    if args.log.stat().st_size == 0:
        parser.error("the compiler log must not be empty")

    owned_files = strict_package_sources(args.package) if args.package else set()
    if args.package and not owned_files:
        print("No Swift sources opted in to StrictConcurrency.")
        return 0

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
        file = Path(path).resolve()
        if (file in owned_files
                or any(file.is_relative_to(source) for source in sources)
                or belongs_to_strict_target(file, roots)):
            failures.append(line)

    if failures:
        print("Swift 5 complete concurrency checking found Swift 6 errors:", file=sys.stderr)
        print("\n".join(dict.fromkeys(failures)), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
