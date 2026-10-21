#!/usr/bin/env python3
"""
String Extraction Verification Script

Verifies that NSLocalizedString calls in source code have been extracted to
string files (.xcstrings, .strings).

Usage:
    python3 verify_string_extraction.py --platform iOS
    python3 verify_string_extraction.py --platform macOS

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
    parse_xcstrings,
)

# =============================================================================
# Git Utilities
# =============================================================================

def get_file_diff(file_path: str) -> str:
    """Get the diff for a specific file."""
    base = get_base_branch()
    try:
        result = subprocess.run(
            ['git', 'diff', base, '--', file_path],
            capture_output=True, text=True, check=False
        )
        return result.stdout
    except Exception:
        return ""

def get_file_contents(file_path: str) -> Tuple[str, str]:
    """
    Get both current and base branch contents for a file.

    Returns:
        Tuple of (current_content, base_content)
    """
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            current_content = f.read()
    except FileNotFoundError:
        return "", ""

    base = get_base_branch()
    try:
        result = subprocess.run(
            ['git', 'show', f'{base}:{file_path}'],
            capture_output=True, text=True, check=False
        )
        base_content = result.stdout if result.returncode == 0 else ""
    except Exception:
        base_content = ""

    return current_content, base_content

# =============================================================================
# NSLocalizedString Extraction
# =============================================================================

def extract_nslocalized_string_keys(content: str) -> Set[str]:
    """
    Extract NSLocalizedString keys from Swift code.

    Handles various formats:
    - NSLocalizedString("key", ...)
    - NSLocalizedString("key", bundle: ..., ...)
    - NSLocalizedString("key", value: "...", ...)
    """
    keys = set()
    pattern = r'NSLocalizedString\s*\(\s*"([^"]+)"'

    for match in re.finditer(pattern, content):
        key = match.group(1)
        keys.add(key)

    return keys

def has_nslocalized_string_changes(file_path: str) -> bool:
    """
    Quickly check if a file has any NSLocalizedString changes.

    Returns True if there are any new or modified NSLocalizedString calls.
    """
    diff = get_file_diff(file_path)
    if not diff:
        return False

    current_content, base_content = get_file_contents(file_path)
    if not current_content:
        return False

    current_keys = extract_nslocalized_string_keys(current_content)
    base_keys = extract_nslocalized_string_keys(base_content)

    if current_keys - base_keys:
        return True

    for key in base_keys & current_keys:
        current_value = extract_string_value_for_key(current_content, key)
        base_value = extract_string_value_for_key(base_content, key)
        if current_value and base_value and current_value != base_value:
            return True

    return False

def get_changed_nslocalized_string_keys(file_path: str) -> Tuple[Set[str], Set[str]]:
    """
    Get NSLocalizedString keys that were added or modified in a file.

    Returns:
        Tuple of (new_keys, modified_keys)
    """
    diff = get_file_diff(file_path)
    if not diff:
        return set(), set()

    current_content, base_content = get_file_contents(file_path)
    if not current_content:
        return set(), set()

    current_keys = extract_nslocalized_string_keys(current_content)
    base_keys = extract_nslocalized_string_keys(base_content)

    new_keys = current_keys - base_keys

    modified_keys = set()
    for key in base_keys & current_keys:
        current_value = extract_string_value_for_key(current_content, key)
        base_value = extract_string_value_for_key(base_content, key)
        if current_value and base_value and current_value != base_value:
            modified_keys.add(key)

    return new_keys, modified_keys

def extract_string_value_for_key(content: str, key: str) -> Optional[str]:
    """Extract the value parameter for a specific NSLocalizedString key."""
    pattern = rf'NSLocalizedString\s*\(\s*"{re.escape(key)}"[\s\S]*?value:\s*"((?:[^"\\]|\\.)*)"'
    match = re.search(pattern, content, re.MULTILINE | re.DOTALL)
    if match:
        return match.group(1)
    return None

# =============================================================================
# String File Parsing
# =============================================================================

def find_string_files(paths: List[str]) -> Dict[str, List[str]]:
    """
    Find English string files in the specified paths.

    For .xcstrings files: includes all (keys are language-agnostic)
    For .strings files: only includes files in en.lproj directories

    Returns:
        Dict mapping file type (xcstrings, strings) to list of file paths
    """
    files = {
        'xcstrings': [],
        'strings': []
    }

    for search_path in paths:
        if not os.path.exists(search_path):
            continue

        for root, _, filenames in os.walk(search_path):
            for filename in filenames:
                file_path = os.path.join(root, filename)
                if filename.endswith('.xcstrings'):
                    # .xcstrings files contain all locales, keys are language-agnostic
                    files['xcstrings'].append(file_path)
                elif filename.endswith('.strings'):
                    # Only check English .strings files
                    parent_dir = os.path.basename(root)
                    if parent_dir == 'en.lproj':
                        files['strings'].append(file_path)

    return files

def check_key_in_xcstrings(key: str, file_path: str) -> bool:
    """Check if a key exists in an .xcstrings file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except (FileNotFoundError, UnicodeDecodeError):
        return False

    data = parse_xcstrings(content)
    strings = data.get("strings", {})
    return key in strings

def check_key_in_strings(key: str, file_path: str) -> bool:
    """Check if a key exists in a .strings file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        return False
    except FileNotFoundError:
        return False

    strings = parse_strings_file(content)
    return key in strings

def find_key_in_string_files(key: str, string_files: Dict[str, List[str]]) -> Optional[str]:
    """
    Find which string file contains the given key.

    Returns:
        Path to the file containing the key, or None if not found
    """
    for file_path in string_files.get('xcstrings', []):
        if check_key_in_xcstrings(key, file_path):
            return file_path

    for file_path in string_files.get('strings', []):
        if check_key_in_strings(key, file_path):
            return file_path

    return None

def is_file_changed(file_path: str) -> bool:
    """Check if a file was changed in the PR."""
    base = get_base_branch()
    try:
        result = subprocess.run(
            ['git', 'diff', '--name-only', base, '--', file_path],
            capture_output=True, text=True, check=False
        )
        return bool(result.stdout.strip())
    except Exception:
        return False

# =============================================================================
# Main Verification Logic
# =============================================================================

def has_any_nslocalized_string_changes(platform: str) -> bool:
    """
    Check if there are any NSLocalizedString changes in the PR.

    Returns True if any changed Swift files contain NSLocalizedString changes.
    """
    paths = get_search_paths(platform)
    changed_swift_files = get_changed_files(['.swift'], paths)

    if not changed_swift_files:
        return False

    for swift_file in changed_swift_files:
        if os.path.exists(swift_file) and has_nslocalized_string_changes(swift_file):
            return True

    return False

def verify_string_changes(platform: str) -> Tuple[List[str], List[str]]:
    """
    Verify that NSLocalizedString calls have been extracted to string files.

    Returns:
        Tuple of (missing_new_keys, missing_modified_keys)
        Each is a list of strings in format "file_path::key"
    """
    paths = get_search_paths(platform)
    changed_swift_files = get_changed_files(['.swift'], paths)

    if not changed_swift_files:
        return [], []

    has_changes = False
    files_with_changes = []
    for swift_file in changed_swift_files:
        if os.path.exists(swift_file) and has_nslocalized_string_changes(swift_file):
            has_changes = True
            files_with_changes.append(swift_file)

    if not has_changes:
        return [], []

    print(f"   Found {len(files_with_changes)} file(s) with NSLocalizedString changes:")
    for swift_file in files_with_changes:
        print(f"     • {swift_file}")

    string_files = find_string_files(paths)

    missing_new_keys = []
    missing_modified_keys = []

    changed_string_files_cache: Dict[str, bool] = {}
    for swift_file in files_with_changes:
        print(f"\n   Verifying {swift_file}...")
        new_keys, modified_keys = get_changed_nslocalized_string_keys(swift_file)

        for key in new_keys:
            string_file = find_key_in_string_files(key, string_files)
            if not string_file:
                missing_new_keys.append(f"{swift_file}::{key}")
            else:
                print(f"     ✓ Key '{key}' found")

        for key in modified_keys:
            string_file = find_key_in_string_files(key, string_files)
            if not string_file:
                missing_modified_keys.append(f"{swift_file}::{key}")
            else:
                if string_file not in changed_string_files_cache:
                    changed_string_files_cache[string_file] = is_file_changed(string_file)
                if changed_string_files_cache[string_file]:
                    print(f"     ✓ Key '{key}' found with updated value")
                else:
                    missing_modified_keys.append(f"{swift_file}::{key}")

    return missing_new_keys, missing_modified_keys

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Verify NSLocalizedString calls have been extracted to string files'
    )
    parser.add_argument(
        '--platform',
        required=True,
        choices=['iOS', 'macOS'],
        help='Platform to check (iOS or macOS)'
    )

    args = parser.parse_args()

    print(f"🔍 Verifying string extraction for {args.platform}...")

    # Check if there are any NSLocalizedString changes first
    if not has_any_nslocalized_string_changes(args.platform):
        print("\n✅ No NSLocalizedString changes detected")
        sys.exit(0)

    print()

    missing_new_keys, missing_modified_keys = verify_string_changes(args.platform)

    if not missing_new_keys and not missing_modified_keys:
        print("\n✅ All NSLocalizedString calls have been extracted to string files")
        sys.exit(0)

    # Report issues
    lines = []

    if missing_new_keys:
        lines.append("\n❌ New strings missing from string files:")
        # Group keys by file_path
        keys_by_file: Dict[str, List[str]] = {}
        for item in missing_new_keys:
            file_path, key = item.rsplit('::', 1)
            if file_path not in keys_by_file:
                keys_by_file[file_path] = []
            keys_by_file[file_path].append(key)

        # Sort files and keys for consistent output
        for file_path in sorted(keys_by_file.keys()):
            lines.append(f"   • {file_path}")
            for key in sorted(keys_by_file[file_path]):
                lines.append(f"     Key: {key}")

    if missing_modified_keys:
        lines.append("\n❌ Modified strings not updated in string files:")
        # Group keys by file_path
        keys_by_file: Dict[str, List[str]] = {}
        for item in missing_modified_keys:
            file_path, key = item.rsplit('::', 1)
            if file_path not in keys_by_file:
                keys_by_file[file_path] = []
            keys_by_file[file_path].append(key)

        # Sort files and keys for consistent output
        for file_path in sorted(keys_by_file.keys()):
            lines.append(f"   • {file_path}")
            for key in sorted(keys_by_file[file_path]):
                lines.append(f"     Key: {key}")

    lines.append("\n💡 Please build the app and commit the corresponding string files.")

    print("\n".join(lines))
    sys.exit(1)

if __name__ == '__main__':
    main()

