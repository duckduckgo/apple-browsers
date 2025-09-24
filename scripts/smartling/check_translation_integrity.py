#!/usr/bin/env python3
"""
Translation Integrity Checker

Analyzes .strings and .stringsdict files for deleted keys and problematic replacements.
Designed for Smartling translation import safety checks.

Copyright © 2025 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import json
import subprocess
import sys

def get_changed_files():
    """Get list of changed .strings and .stringsdict files.

    Returns:
        List of file paths that have been modified.

    Example:
        >>> get_changed_files()
        ['iOS/DuckDuckGo/en.lproj/Localizable.strings',
         'iOS/DuckDuckGo/en.lproj/Localizable.stringsdict']
    """
    result = subprocess.run(
        ['git', 'diff', '--name-only', '--', '*.strings', '*.stringsdict'],
        capture_output=True, text=True, check=False
    )
    return [f for f in result.stdout.strip().split('\n') if f]


def parse_strings_file(content):
    """Parse .strings file content to dictionary using plutil.

    Args:
        content: Raw .strings file content as string.

    Returns:
        Dictionary mapping keys to values.

    Example:
        >>> content = '"some.key" = "Some value";\\n"some.other.key" = "Other value";'
        >>> parse_strings_file(content)
        {'some.key': 'Some value', 'some.other.key': 'Other value'}
    """
    if not content:
        return {}
    try:
        # Convert to JSON using plutil
        result = subprocess.run(
            ['plutil', '-convert', 'json', '-o', '-', '-'],
            input=content, capture_output=True, text=True, check=False
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception:  # pylint: disable=broad-except
        pass
    return {}


def parse_stringsdict_file(content):
    """Parse .stringsdict file and extract all string values recursively.

    Args:
        content: Raw .stringsdict file content as XML string.

    Returns:
        Dictionary mapping hierarchical keys to string values.

    Example:
        For a .stringsdict with plural forms:
        >>> parse_stringsdict_file(stringsdict_xml)
        {
            'items_count.NSStringLocalizedFormatKey': '%#@items@',
            'items_count.items.one': '%d item',
            'items_count.items.other': '%d items'
        }
    """
    if not content:
        return {}

    def collect_string_leaves(obj, prefix=""):
        """Recursively collect all string values from nested dict/list.

        Args:
            obj: Dictionary, list, or primitive value to traverse.
            prefix: Current path prefix for building hierarchical keys.

        Returns:
            Dictionary mapping full paths to string values.

        Example:
            >>> data = {'key1': {'subkey': 'value1', 'list': ['item1', 'item2']}}
            >>> collect_string_leaves(data)
            {'key1.subkey': 'value1', 'key1.list[0]': 'item1', 'key1.list[1]': 'item2'}
        """
        strings = {}
        if isinstance(obj, dict):
            for key, value in obj.items():
                new_prefix = f"{prefix}.{key}" if prefix else key
                if isinstance(value, str):
                    strings[new_prefix] = value
                elif isinstance(value, (dict, list)):
                    strings.update(collect_string_leaves(value, new_prefix))
        elif isinstance(obj, list):
            for i, value in enumerate(obj):
                new_prefix = f"{prefix}[{i}]"
                if isinstance(value, str):
                    strings[new_prefix] = value
                elif isinstance(value, (dict, list)):
                    strings.update(collect_string_leaves(value, new_prefix))
        return strings

    try:
        # Convert to JSON using plutil
        result = subprocess.run(
            ['plutil', '-convert', 'json', '-o', '-', '-'],
            input=content, capture_output=True, text=True, check=False
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return collect_string_leaves(data)
    except Exception:  # pylint: disable=broad-except
        pass
    return {}


def get_file_content(file_path, revision='HEAD'):
    """Get file content at specific revision.

    Args:
        file_path: Path to the file to read.
        revision: Git revision ('HEAD' for committed version, 'WORKING' for current).

    Returns:
        File content as string, empty string if file doesn't exist.

    Example:
        >>> get_file_content('iOS/en.strings', 'HEAD')
        '"menu.save" = "Save File";'
        >>> get_file_content('iOS/en.strings', 'WORKING')
        '"menu.save" = "Save Document";'
    """
    try:
        if revision == 'HEAD':
            result = subprocess.run(
                ['git', 'show', f'HEAD:{file_path}'],
                capture_output=True, text=True, check=False
            )
            return result.stdout if result.returncode == 0 else ""
        # Current working copy
        with open(file_path, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception:  # pylint: disable=broad-except
        return ""


def analyze_translation_changes():
    """Main check function.

    Returns:
        Integer indicating if the check failed (1) or passed (0).
    """
    for file_path in get_changed_files():
        current_content = get_file_content(file_path, 'WORKING')
        original_content = get_file_content(file_path, 'HEAD')

        if file_path.endswith('.strings'):
            current = parse_strings_file(current_content)
            original = parse_strings_file(original_content)
        elif file_path.endswith('.stringsdict'):
            current = parse_stringsdict_file(current_content)
            original = parse_stringsdict_file(original_content)
        else:
            continue

        # If there are deleted keys, fail immediately
        if set(original.keys()) - set(current.keys()):
            return 1

        # Find problematic replacements
        for key in set(original.keys()) & set(current.keys()):
            old_val = str(original[key]).strip()
            new_val = str(current[key]).strip()

            # Check for empty or significantly shortened values (after trimming)
            if not new_val or len(new_val) < len(old_val) // 2:
                return 1

    return 0


def main():
    """Main entry point.

    Runs the integrity check and exits with its return code:
    - 0 when no issues detected
    - 1 when deletions or suspicious replacements are found
    """
    try:
        exit_code = analyze_translation_changes()
        sys.exit(exit_code)
    except Exception as e:  # pylint: disable=broad-except
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
