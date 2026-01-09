#!/usr/bin/env python3
"""
Translation Check Script

Validates that changed strings (new or modified) have translations for all required locales.
Supports .xcstrings (String Catalogs), .strings files, and .stringsdict files.

Usage:
    python3 check_new_string_translations.py --platform iOS
    python3 check_new_string_translations.py --platform macOS

Copyright © 2025 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import argparse
import os
import re
import subprocess
import sys
from typing import Dict, List, Optional, Set, Tuple

# Import shared utilities
from localization_utils import (
    get_base_branch,
    get_changed_files,
    get_files_content_at_base,
    get_search_paths,
    parse_strings_file,
    parse_stringsdict_file,
    parse_stringsdict_file_full,
    parse_xcstrings,
)

ISSUE_TYPE_MISSING = "missing"
ISSUE_TYPE_NEEDS_REVIEW = "needs_review"

TranslationIssue = Tuple[str, str, Set[str], str]

# =============================================================================
# Platform-specific Required Locales
# =============================================================================

MACOS_LOCALES = frozenset([
    "de",  # German
    "es",  # Spanish
    "fr",  # French
    "it",  # Italian
    "nl",  # Dutch
    "pl",  # Polish
    "pt",  # Portuguese
    "ru",  # Russian
])

IOS_LOCALES = frozenset([
    "bg",  # Bulgarian
    "cs",  # Czech
    "da",  # Danish
    "de",  # German
    "el",  # Greek
    "es",  # Spanish
    "et",  # Estonian
    "fi",  # Finnish
    "fr",  # French
    "hr",  # Croatian
    "hu",  # Hungarian
    "it",  # Italian
    "lt",  # Lithuanian
    "lv",  # Latvian
    "nb",  # Norwegian Bokmål
    "nl",  # Dutch
    "pl",  # Polish
    "pt",  # Portuguese
    "ro",  # Romanian
    "ru",  # Russian
    "sk",  # Slovak
    "sl",  # Slovenian
    "sv",  # Swedish
    "tr",  # Turkish
])

def get_required_locales(platform: str) -> Set[str]:
    """Get the required locales for a platform."""
    if platform == "iOS":
        return set(IOS_LOCALES)
    elif platform == "macOS":
        return set(MACOS_LOCALES)
    else:
        return set()

# =============================================================================
# .xcstrings (String Catalog) Handling
# =============================================================================

def get_string_unit_value(string_entry: Dict) -> str:
    """Extract source string value from a .xcstrings string entry."""
    if not isinstance(string_entry, dict):
        return ""
    # The source string is stored in localizations['en']['stringUnit']['value']
    localizations = string_entry.get("localizations", {})
    if isinstance(localizations, dict):
        en_localization = localizations.get("en", {})
        if isinstance(en_localization, dict):
            string_unit = en_localization.get("stringUnit", {})
            if isinstance(string_unit, dict):
                return string_unit.get("value", "")
    return ""

def get_string_unit_state(localization_entry: Dict) -> Optional[str]:
    """Extract state from a .xcstrings localization entry."""
    if not isinstance(localization_entry, dict):
        return None
    string_unit = localization_entry.get("stringUnit", {})
    if isinstance(string_unit, dict):
        return string_unit.get("state")
    return None

def get_changed_string_keys(old_data: Dict, new_data: Dict) -> Set[str]:
    """Get keys that have changed in new_data compared to old_data."""
    old_strings = old_data.get("strings", {})
    new_strings = new_data.get("strings", {})

    changed_keys = set()
    old_keys = set(old_strings.keys())
    new_keys = set(new_strings.keys())
    changed_keys.update(new_keys - old_keys)

    # Get keys with changed source values
    for key in old_keys & new_keys:
        old_value = old_strings.get(key, {})
        new_value = new_strings.get(key, {})

        if not isinstance(old_value, dict) or not isinstance(new_value, dict):
            continue

        old_source = get_string_unit_value(old_value)
        new_source = get_string_unit_value(new_value)

        if old_source != new_source:
            changed_keys.add(key)

    return changed_keys

def check_xcstrings_strings_missing_translations(
    file_path: str,
    current_data: Dict,
    required_locales: Set[str],
    changed_keys: Set[str]
) -> List[TranslationIssue]:
    """
    Check a .xcstrings file for changed strings missing translations.

    Args:
        file_path: Path to the .xcstrings file
        current_data: Parsed current file content
        required_locales: Set of required locale codes
        changed_keys: Pre-computed set of changed string keys

    Returns list of (file_path, string_key, missing_locales, "new") tuples.
    """
    issues: List[TranslationIssue] = []

    if not changed_keys:
        return issues

    # Check each changed key for translations
    strings = current_data.get("strings", {})
    for key in changed_keys:
        value = strings.get(key, {})

        # Skip if key is not a dictionary or shouldTranslate is False
        if not isinstance(value, dict) or value.get("shouldTranslate") is False:
            continue

        # Check translations
        localizations = value.get("localizations", {})
        missing_locales = set()

        for locale in required_locales:
            loc_data = localizations.get(locale, {})
            if not isinstance(loc_data, dict):
                missing_locales.add(locale)
                continue

            state = get_string_unit_state(loc_data)
            # Only mark as missing if not translated AND not needs_review
            # (needs_review is handled separately)
            if state != "translated" and state != "needs_review":
                missing_locales.add(locale)

        if missing_locales:
            issues.append((file_path, key, missing_locales, ISSUE_TYPE_MISSING))

    return issues

def check_xcstrings_needs_review(
    file_path: str,
    current_data: Dict,
    base_data: Dict,
    required_locales: Set[str],
    changed_keys: Set[str]
) -> List[TranslationIssue]:
    """
    Check a .xcstrings file for strings with needs_review state.

    Args:
        file_path: Path to the .xcstrings file
        current_data: Parsed current file content
        base_data: Parsed base branch file content
        required_locales: Set of required locale codes
        changed_keys: Pre-computed set of changed string keys

    Returns list of (file_path, string_key, needs_review_locales, "updated") tuples.
    """
    issues: List[TranslationIssue] = []

    if not changed_keys:
        return issues

    current_strings = current_data.get("strings", {})
    base_strings = base_data.get("strings", {})

    for key in changed_keys:
        value = current_strings.get(key, {})
        if not isinstance(value, dict):
            continue

        # Skip if shouldTranslate is False
        if value.get("shouldTranslate") is False:
            continue

        # Check translations
        localizations = value.get("localizations", {})
        needs_review_locales = set()

        for locale in required_locales:
            loc_data = localizations.get(locale, {})
            if not isinstance(loc_data, dict):
                continue

            current_state = get_string_unit_state(loc_data)
            if current_state == "needs_review":
                base_value = base_strings.get(key, {})
                if isinstance(base_value, dict):
                    base_localizations = base_value.get("localizations", {})
                    base_loc_data = base_localizations.get(locale, {})
                    base_state = get_string_unit_state(base_loc_data)
                    if base_state == "needs_review":
                        continue

                needs_review_locales.add(locale)

        if needs_review_locales:
            issues.append((file_path, key, needs_review_locales, ISSUE_TYPE_NEEDS_REVIEW))

    return issues

# =============================================================================
# .strings (Legacy) File Handling
# =============================================================================

def find_strings_file_locations(paths: List[str]) -> Set[Tuple[str, str]]:
    """
    Find .strings files in locale directories.

    Returns set of (parent_dir, filename) tuples where parent_dir contains
    locale .lproj directories.
    """
    locations = set()

    for search_path in paths:
        if not os.path.exists(search_path):
            continue

        for root, _, files in os.walk(search_path):
            for file in files:
                if not file.endswith('.strings'):
                    continue

                parent = os.path.basename(root)
                if parent.endswith('.lproj'):
                    grandparent = os.path.dirname(root)
                    locations.add((grandparent, file))

    return locations

def check_strings_translations(
    en_file_path: str,
    base_content: str,
    required_locales: Set[str]
) -> List[TranslationIssue]:
    """
    Check a .strings file for changed strings missing translations.

    Args:
        en_file_path: Path to the English .strings file
        base_content: Content of the file at base branch (pre-fetched)
        required_locales: Set of required locale codes

    Returns list of (file_path, string_key, missing_locales, "new") tuples.
    """
    issues: List[TranslationIssue] = []

    try:
        with open(en_file_path, 'r', encoding='utf-8') as f:
            current_content = f.read()
    except FileNotFoundError:
        return issues

    current_strings = parse_strings_file(current_content)
    base_strings = parse_strings_file(base_content)

    # Find changed keys (new or modified)
    current_keys = set(current_strings.keys())
    base_keys = set(base_strings.keys())

    # New keys
    changed_keys = current_keys - base_keys

    # Modified keys (value changed)
    for key in current_keys & base_keys:
        if current_strings[key] != base_strings[key]:
            changed_keys.add(key)

    if not changed_keys:
        return issues

    parent_dir = os.path.dirname(os.path.dirname(en_file_path))
    filename = os.path.basename(en_file_path)

    # Cache locale strings for faster lookup
    locale_strings_cache: Dict[str, Dict[str, str]] = {}
    for locale in required_locales:
        locale_file = os.path.join(parent_dir, f"{locale}.lproj", filename)
        try:
            with open(locale_file, 'r', encoding='utf-8') as f:
                locale_strings_cache[locale] = parse_strings_file(f.read())
        except FileNotFoundError:
            locale_strings_cache[locale] = {}

    # Check each changed key for translations in all locales
    for key in changed_keys:
        missing_locales = set()

        for locale in required_locales:
            locale_strings = locale_strings_cache.get(locale, {})
            if key not in locale_strings:
                missing_locales.add(locale)

        if missing_locales:
            issues.append((en_file_path, key, missing_locales, ISSUE_TYPE_MISSING))

    return issues

# =============================================================================
# .stringsdict (Pluralization) File Handling
# =============================================================================

def find_stringsdict_file_locations(paths: List[str]) -> Set[Tuple[str, str]]:
    """
    Find .stringsdict files in locale directories.

    Returns set of (parent_dir, filename) tuples where parent_dir contains
    locale .lproj directories.
    """
    locations = set()

    for search_path in paths:
        if not os.path.exists(search_path):
            continue

        for root, _, files in os.walk(search_path):
            for file in files:
                if not file.endswith('.stringsdict'):
                    continue

                parent = os.path.basename(root)
                if parent.endswith('.lproj'):
                    grandparent = os.path.dirname(root)
                    locations.add((grandparent, file))

    return locations

def check_stringsdict_translations(
    en_file_path: str,
    base_content: str,
    required_locales: Set[str]
) -> List[TranslationIssue]:
    """
    Check a .stringsdict file for changed strings missing translations.

    Args:
        en_file_path: Path to the English .stringsdict file
        base_content: Content of the file at base branch (pre-fetched)
        required_locales: Set of required locale codes

    Returns list of (file_path, string_key, missing_locales, "new") tuples.
    """
    issues: List[TranslationIssue] = []

    try:
        with open(en_file_path, 'r', encoding='utf-8') as f:
            current_content = f.read()
    except FileNotFoundError:
        return issues

    current_data = parse_stringsdict_file_full(current_content)
    base_data = parse_stringsdict_file_full(base_content)

    current_keys = set(current_data.keys())
    base_keys = set(base_data.keys())
    changed_keys = current_keys - base_keys

    for key in current_keys & base_keys:
        if current_data.get(key) != base_data.get(key):
            changed_keys.add(key)

    if not changed_keys:
        return issues

    parent_dir = os.path.dirname(os.path.dirname(en_file_path))
    filename = os.path.basename(en_file_path)

    locale_keys_cache: Dict[str, Set[str]] = {}
    for locale in required_locales:
        locale_file = os.path.join(parent_dir, f"{locale}.lproj", filename)
        try:
            with open(locale_file, 'r', encoding='utf-8') as f:
                locale_keys_cache[locale] = parse_stringsdict_file(f.read())
        except FileNotFoundError:
            locale_keys_cache[locale] = set()

    for key in changed_keys:
        missing_locales = set()

        for locale in required_locales:
            locale_keys = locale_keys_cache.get(locale, set())
            if key not in locale_keys:
                missing_locales.add(locale)

        if missing_locales:
            issues.append((en_file_path, key, missing_locales, ISSUE_TYPE_MISSING))

    return issues

# =============================================================================
# Main Logic
# =============================================================================

def check_locale_based_files(
    extension: str,
    changed_files_cache: List[str],
    paths: List[str],
    required_locales: Set[str],
    find_locations_func,
    check_translations_func
) -> List[TranslationIssue]:
    """
    Generic helper for checking locale-based files (.strings, .stringsdict).

    Args:
        extension: File extension to filter (e.g., '.strings', '.stringsdict')
        changed_files_cache: List of all changed files
        paths: Search paths for finding locale files
        required_locales: Set of required locale codes
        find_locations_func: Function to find file locations (e.g., find_strings_file_locations)
        check_translations_func: Function to check translations (e.g., check_strings_translations)

    Returns list of translation issues.
    """
    all_issues: List[TranslationIssue] = []

    changed_files = {f for f in changed_files_cache if f.endswith(extension)}
    if not changed_files:
        return all_issues

    locations = find_locations_func(paths)

    en_files_to_check = []
    for parent_dir, filename in locations:
        en_file_path = os.path.join(parent_dir, "en.lproj", filename)
        if en_file_path in changed_files and os.path.exists(en_file_path):
            en_files_to_check.append(en_file_path)

    if not en_files_to_check:
        return all_issues

    base_contents = get_files_content_at_base(en_files_to_check)

    for en_file_path in en_files_to_check:
        issues = check_translations_func(
            en_file_path, base_contents.get(en_file_path, ""), required_locales
        )
        all_issues.extend(issues)

    return all_issues

def check_xcstrings_files(required_locales: Set[str], changed_files_cache: List[str]) -> List[TranslationIssue]:
    """Check all changed .xcstrings files for translation issues."""
    all_issues: List[TranslationIssue] = []

    changed_files = [f for f in changed_files_cache if f.endswith('.xcstrings')]
    existing_files = [f for f in changed_files if os.path.exists(f)]

    if not existing_files:
        return all_issues

    base_contents = get_files_content_at_base(existing_files)

    for file_path in existing_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                current_content = f.read()
        except FileNotFoundError:
            continue

        current_data = parse_xcstrings(current_content)
        base_data = parse_xcstrings(base_contents.get(file_path, ""))

        changed_keys = get_changed_string_keys(base_data, current_data)

        if changed_keys:
            missing_issues = check_xcstrings_strings_missing_translations(file_path, current_data, required_locales, changed_keys)
            all_issues.extend(missing_issues)

            review_issues = check_xcstrings_needs_review(file_path, current_data, base_data, required_locales, changed_keys)
            all_issues.extend(review_issues)

    return all_issues

def check_strings_files(paths: List[str], required_locales: Set[str], changed_files_cache: List[str]) -> List[TranslationIssue]:
    """Check all changed .strings files for translation issues."""
    return check_locale_based_files(
        '.strings',
        changed_files_cache,
        paths,
        required_locales,
        find_strings_file_locations,
        check_strings_translations
    )

def check_stringsdict_files(paths: List[str], required_locales: Set[str], changed_files_cache: List[str]) -> List[TranslationIssue]:
    """Check all changed .stringsdict files for translation issues."""
    return check_locale_based_files(
        '.stringsdict',
        changed_files_cache,
        paths,
        required_locales,
        find_stringsdict_file_locations,
        check_stringsdict_translations
    )

def format_issues(issues: List[TranslationIssue], required_locales: Set[str]) -> str:
    """Format issues for output."""
    if not issues:
        return ""

    by_file: Dict[str, List[Tuple[str, Set[str], str]]] = {}
    for file_path, key, locales, issue_type in issues:
        if file_path not in by_file:
            by_file[file_path] = []
        by_file[file_path].append((key, locales, issue_type))

    lines = ["❌ Untranslated strings found:"]

    for file_path, file_issues in sorted(by_file.items()):
        lines.append(f"\nFile: {file_path}")
        for key, locales, issue_type in sorted(file_issues, key=lambda x: x[0]):
            display_key = key if len(key) <= 50 else key[:47] + "..."

            if locales == required_locales:
                locale_count = len(required_locales)
                locale_display = f"All {locale_count} languages"
            else:
                locales_sorted = sorted(locales)
                locale_display = ', '.join(locales_sorted)

            status_label = "Missing translations" if issue_type == ISSUE_TYPE_MISSING else "Needs review"

            lines.append(f"   • Key: {display_key}")
            lines.append(f"     {status_label}: {locale_display}")

    return "\n".join(lines)

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Check new strings for missing translations'
    )
    parser.add_argument(
        '--platform',
        required=True,
        choices=['iOS', 'macOS'],
        help='Platform to check (iOS or macOS)'
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Show verbose output'
    )

    args = parser.parse_args()

    print(f"🔍 Checking translations for {args.platform}...")

    paths = get_search_paths(args.platform)
    required_locales = get_required_locales(args.platform)

    if args.verbose:
        print(f"   Searching in: {', '.join(paths)}")
        print(f"   Required locales: {', '.join(sorted(required_locales))}")

    all_extensions = ['.xcstrings', '.strings', '.stringsdict']
    all_changed = get_changed_files(all_extensions, paths)
    if not all_changed:
        print("✅ No localization files changed")
        sys.exit(0)

    xcstrings_issues = check_xcstrings_files(required_locales, all_changed)
    strings_issues = check_strings_files(paths, required_locales, all_changed)
    stringsdict_issues = check_stringsdict_files(paths, required_locales, all_changed)

    all_issues = xcstrings_issues + strings_issues + stringsdict_issues

    if all_issues:
        print(format_issues(all_issues, required_locales))
        sys.exit(1)
    else:
        print("✅ All strings have translations")
        sys.exit(0)

if __name__ == '__main__':
    main()
