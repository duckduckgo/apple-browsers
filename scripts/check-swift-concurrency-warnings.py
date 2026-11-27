#!/usr/bin/env python3
"""Reject Swift 5 concurrency warnings that become errors in Swift 6.

Check explicit source directories or the SwiftPM targets that enable StrictConcurrency.
Other warnings, including concurrency advisories, retain their normal severity.
"""

import argparse
from functools import cache
import json
import os
from pathlib import Path
import re
import subprocess
import sys


@cache
def strict_target_names(package):
    command = ["swift", "package", "--package-path", str(package)]
    manifest = json.loads(subprocess.check_output([*command, "dump-package"]))
    return {
        target["name"] for target in manifest["targets"]
        if any(setting["kind"].get("enableExperimentalFeature", {}).get("_0") == "StrictConcurrency"
               for setting in target.get("settings", []))
    }


@cache
def package_targets(package):
    command = ["swift", "package", "--package-path", str(package), "describe", "--type", "json"]
    description = json.loads(subprocess.check_output(command))
    return {target["c99name"]: target for target in description["targets"] if target.get("c99name")}


def target_sources(package, target):
    # SwiftPM resolves custom target paths, explicit source lists and exclusions.
    return ((package / target["path"] / source).resolve() for source in target.get("sources", []))


@cache
def strict_package_sources(package):
    enabled = strict_target_names(package)
    if not enabled:
        return set()
    return {
        file for target in package_targets(package).values() if target["name"] in enabled
        for file in target_sources(package, target)
    }


def packages_under(roots):
    for root in roots:
        for directory, children, files in os.walk(root):
            children[:] = [child for child in children if not child.startswith(".") and child != "DerivedData"]
            if "Package.swift" in files:
                yield Path(directory)


def xcode_module_packages(log):
    # Xcode prints the resolved packages and the project that emits each module.
    # Join those records so parallel build output does not affect attribution.
    resolved = re.search(r"^Resolved source packages:\n((?:  .+\n)+)", log, re.MULTILINE)
    if not resolved:
        return {}
    packages = {}
    for entry in resolved[1].splitlines():
        project, _, location = entry.strip().partition(": ")
        path = Path(location.split(" @ ", 1)[0])
        packages[project] = path.resolve() if path.is_absolute() else None
    modules = re.findall(r"^SwiftEmitModule .*? for\\ (\w+) \(in target '[^']+' from project '([^']+)'\)$",
                         log, re.MULTILINE)
    return {module: packages[project] for module, project in modules if project in packages}


@cache
def macro_in_scope(module, package, roots, sources):
    if sources:
        packages = {
            directory for source in sources for directory in (source, *source.parents)
            if (directory / "Package.swift").is_file()
        }
    else:
        packages = [package] if package else packages_under(roots)

    for directory in packages:
        if not sources and not strict_target_names(directory):
            continue
        target = package_targets(directory).get(module)
        if not target or not target.get("sources"):
            continue
        if sources:
            files = target_sources(directory, target)
            if all(any(file.is_relative_to(source) for source in sources) for file in files):
                return True
        elif target["name"] in strict_target_names(directory):
            return True
    return False


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


def warning_locations(log):
    diagnostic = re.compile(r"^(.*\.swift|macro expansion @\S+):\d+:\d+: warning: (.*)$")
    origin = re.compile(r"^`- (.*\.swift):\d+:\d+: note: expanded code originates here$")
    lines = log.splitlines()
    for index, line in enumerate(lines):
        match = diagnostic.match(line)
        if not match:
            continue
        path, message = match.groups()
        if path.startswith("macro expansion @"):
            # Swift's formatted diagnostic gives the original source on the next line.
            location = origin.match(lines[index + 1]) if index + 1 < len(lines) else None
            if not location:
                continue
            path = location[1]
            line += "\n" + lines[index + 1]
        yield line, path, message


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    scope = parser.add_mutually_exclusive_group(required=True)
    scope.add_argument("sources", type=Path, nargs="*", default=[], help="source directories to check")
    scope.add_argument("--package", type=Path, help="check targets opted in by this package")
    scope.add_argument("--package-roots", type=Path, nargs="+", default=[],
                       help="check opted-in targets in packages under these directories")
    args = parser.parse_args()
    sources = tuple(path.resolve() for path in args.sources)
    roots = tuple(path.resolve() for path in args.package_roots)
    if not args.log.is_file() or any(not path.is_dir() for path in sources + roots):
        parser.error("the compiler log and source directories must exist")
    if args.log.stat().st_size == 0:
        parser.error("the compiler log must not be empty")

    owned_files = strict_package_sources(args.package) if args.package else set()
    if args.package and not owned_files:
        print("No Swift sources opted in to StrictConcurrency.")
        return 0

    swift6_error = re.compile(r"this is an error in (?:the )?Swift 6 language mode")
    concurrency = re.compile(r"actor|sendab|isolat|concurren|data race|sending|async", re.IGNORECASE)
    failures = []
    log = args.log.read_text(encoding="utf-8", errors="replace")
    module_packages = None
    for line, path, message in warning_locations(log):
        if not swift6_error.search(message) or not concurrency.search(message):
            continue
        file = Path(path).resolve()
        if (file in owned_files
                or any(file.is_relative_to(source) for source in sources)
                or belongs_to_strict_target(file, roots)):
            failures.append(line)
            continue

        # Macro filenames start with the length-prefixed name of the compiling module.
        macro = re.match(r"@__swiftmacro_(\d+)(.*)", file.name)
        if macro:
            module = macro[2][:int(macro[1])]
            package = args.package
            if roots:
                if module_packages is None:
                    module_packages = xcode_module_packages(log)
                if module in module_packages:
                    package = module_packages[module]
                    if package is None or not any(package.is_relative_to(root) for root in roots):
                        continue
            if macro_in_scope(module, package, roots, sources):
                failures.append(line)

    if failures:
        print("Swift 5 complete concurrency checking found Swift 6 errors:", file=sys.stderr)
        print("\n".join(dict.fromkeys(failures)), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
