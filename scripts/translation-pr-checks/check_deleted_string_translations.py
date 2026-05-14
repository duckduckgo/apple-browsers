#!/usr/bin/env python3
"""
Deleted String Translation Check Script

Detects English string keys that were removed in the PR but whose translations
still exist in locale files. This catches the case where a developer deletes
a string but forgets to run a Smartling translation job to propagate the deletion.

Note: This only applies to legacy .strings and .stringsdict files.
For .xcstrings (String Catalogs), keys and translations live in the same JSON file,
so deletions are automatically consistent.

Usage:
    python3 check_deleted_string_translations.py --platform iOS
    python3 check_deleted_string_translations.py --platform macOS

Copyright © 2025 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import argparse
import os
import sys
from typing import Dict, List, Optional, Set, Tuple

from localization_utils import (
    get_changed_files,
    get_files_content_at_base,
    get_required_locales,
    get_search_paths,
    parse_strings_file,
    parse_stringsdict_file,
)


# =============================================================================
# Core Logic
# =============================================================================

OrphanIssue = Tuple[str, str, Set[str]]  # (file_path, key, locales_with_orphan)


def find_en_lproj_files(changed_files: List[str], extension: str) -> List[str]:
    """Filter changed files to only English locale files with the given extension."""
    return [
        f for f in changed_files
        if f.endswith(extension) and "/en.lproj/" in f
    ]


def get_deleted_keys_strings(en_file_path: str, base_content: str) -> Set[str]:
    """Find keys that were deleted from an English .strings file."""
    try:
        with open(en_file_path, 'r', encoding='utf-8') as f:
            current_content = f.read()
    except FileNotFoundError:
        return set()

    base_keys = set(parse_strings_file(base_content).keys())
    current_keys = set(parse_strings_file(current_content).keys())

    return base_keys - current_keys


def get_deleted_keys_stringsdict(en_file_path: str, base_content: str) -> Set[str]:
    """Find keys that were deleted from an English .stringsdict file."""
    try:
        with open(en_file_path, 'r', encoding='utf-8') as f:
            current_content = f.read()
    except FileNotFoundError:
        return set()

    base_keys = parse_stringsdict_file(base_content)
    current_keys = parse_stringsdict_file(current_content)

    return base_keys - current_keys


def check_orphaned_translations(
    en_file_path: str,
    deleted_keys: Set[str],
    required_locales: Set[str],
    parse_func,
) -> List[OrphanIssue]:
    """Check if deleted English keys still have translations in locale files."""
    if not deleted_keys:
        return []

    issues: List[OrphanIssue] = []

    parent_dir = os.path.dirname(os.path.dirname(en_file_path))
    filename = os.path.basename(en_file_path)

    # Read all locale files once
    locale_keys_cache: Dict[str, Set[str]] = {}
    for locale in required_locales:
        locale_file = os.path.join(parent_dir, f"{locale}.lproj", filename)
        try:
            with open(locale_file, 'r', encoding='utf-8') as f:
                content = f.read()
            parsed = parse_func(content)
            # parse_strings_file returns a dict, parse_stringsdict_file returns a set
            locale_keys_cache[locale] = set(parsed.keys()) if isinstance(parsed, dict) else parsed
        except FileNotFoundError:
            locale_keys_cache[locale] = set()

    for key in deleted_keys:
        orphan_locales = set()
        for locale in required_locales:
            if key in locale_keys_cache.get(locale, set()):
                orphan_locales.add(locale)

        if orphan_locales:
            issues.append((en_file_path, key, orphan_locales))

    return issues


def format_issues(issues: List[OrphanIssue], required_locales: Set[str]) -> str:
    """Format orphan issues for output."""
    if not issues:
        return ""

    by_file: Dict[str, List[Tuple[str, Set[str]]]] = {}
    for file_path, key, locales in issues:
        if file_path not in by_file:
            by_file[file_path] = []
        by_file[file_path].append((key, locales))

    lines = [
        "⚠️  Deleted strings with orphaned translations found:",
        "",
        "The following English strings were removed, but translations still exist in locale files.",
        "Run a Smartling translation job to clean up the orphaned translations.",
    ]

    for file_path, file_issues in sorted(by_file.items()):
        lines.append(f"\nFile: {file_path}")
        for key, locales in sorted(file_issues, key=lambda x: x[0]):
            display_key = key if len(key) <= 50 else key[:47] + "..."

            if locales == required_locales:
                locale_display = f"All {len(required_locales)} languages"
            else:
                locale_display = ', '.join(sorted(locales))

            lines.append(f"   • Key: {display_key}")
            lines.append(f"     Orphaned translations: {locale_display}")

    return "\n".join(lines)


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='Check for deleted strings with orphaned translations'
    )
    parser.add_argument(
        '--platform',
        required=True,
        choices=['iOS', 'macOS'],
        help='Platform to check (iOS or macOS)'
    )

    args = parser.parse_args()

    print(f"🔍 Checking for orphaned translations ({args.platform})...")

    paths = get_search_paths(args.platform)
    required_locales = get_required_locales(args.platform)

    all_extensions = ['.strings', '.stringsdict']
    all_changed = get_changed_files(all_extensions, paths)
    if not all_changed:
        print("✅ No localization files changed")
        sys.exit(0)

    all_issues: List[OrphanIssue] = []

    # Check .strings files
    en_strings_files = find_en_lproj_files(all_changed, '.strings')
    if en_strings_files:
        base_contents = get_files_content_at_base(en_strings_files)
        for en_file in en_strings_files:
            deleted_keys = get_deleted_keys_strings(en_file, base_contents.get(en_file, ""))
            issues = check_orphaned_translations(en_file, deleted_keys, required_locales, parse_strings_file)
            all_issues.extend(issues)

    # Check .stringsdict files
    en_stringsdict_files = find_en_lproj_files(all_changed, '.stringsdict')
    if en_stringsdict_files:
        base_contents = get_files_content_at_base(en_stringsdict_files)
        for en_file in en_stringsdict_files:
            deleted_keys = get_deleted_keys_stringsdict(en_file, base_contents.get(en_file, ""))
            issues = check_orphaned_translations(en_file, deleted_keys, required_locales, parse_stringsdict_file)
            all_issues.extend(issues)

    if all_issues:
        output = format_issues(all_issues, required_locales)
        print(output)

        # Emit GitHub Actions warning annotation so it surfaces on the PR
        if os.environ.get("GITHUB_ACTIONS"):
            total = len(all_issues)
            print(f"::warning::Found {total} deleted string(s) with orphaned translations. "
                  "Run a Smartling translation job to clean them up.")

        sys.exit(0)
    else:
        print("✅ No orphaned translations found")
        sys.exit(0)


if __name__ == '__main__':
    main()
