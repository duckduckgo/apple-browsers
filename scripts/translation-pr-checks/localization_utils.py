#!/usr/bin/env python3
"""
Localization Utilities

Shared utility functions for localization-related scripts.
Used by verify_string_extraction.py and check_new_string_translations.py.

Copyright © 2025 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import json
import os
import plistlib
import re
import subprocess
from typing import Dict, List, Optional, Set

# =============================================================================
# Git Utilities
# =============================================================================

_base_branch_cache: Optional[str] = None

def get_base_branch() -> str:
    """Get the base branch for comparison (usually main or the PR base)."""
    global _base_branch_cache
    if _base_branch_cache is not None:
        return _base_branch_cache

    base_ref = os.environ.get('GITHUB_BASE_REF')
    if base_ref:
        _base_branch_cache = f"origin/{base_ref}"
    else:
        _base_branch_cache = "origin/main"

    return _base_branch_cache

def get_files_content_at_base(file_paths: List[str]) -> Dict[str, str]:
    """
    Get content of multiple files at the base branch.

    Returns a dict mapping file_path -> content (empty string if file doesn't exist).
    """
    if not file_paths:
        return {}

    base = get_base_branch()
    contents: Dict[str, str] = {}

    for file_path in file_paths:
        try:
            result = subprocess.run(
                ['git', 'show', f'{base}:{file_path}'],
                capture_output=True, text=True, check=False
            )
            contents[file_path] = result.stdout if result.returncode == 0 else ""
        except Exception:
            contents[file_path] = ""

    return contents

def get_changed_files(extensions: List[str], paths: List[str]) -> List[str]:
    """
    Get list of changed files with given extensions in the specified paths.

    Args:
        extensions: List of file extensions (e.g., ['.swift', '.xcstrings'])
        paths: List of directory paths to search

    Returns:
        List of changed file paths
    """
    base = get_base_branch()
    cmd = ['git', 'diff', '--name-only', '--diff-filter=ACMR', base, '--']

    for path in paths:
        for ext in extensions:
            cmd.append(f':(glob){path}/**/*{ext}')

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, check=False
        )
    except Exception:
        return []

    return [f for f in result.stdout.strip().split('\n') if f]

# =============================================================================
# String File Parsing
# =============================================================================

def parse_xcstrings(content: str) -> Dict:
    """Parse .xcstrings JSON content."""
    if not content:
        return {"strings": {}}
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        return {"strings": {}}

def parse_strings_file(content: str) -> Dict[str, str]:
    """Parse .strings file content to dictionary."""
    if not content:
        return {}

    result = {}
    # Match "key" = "value"; pattern, handling escaped quotes
    pattern = r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;'

    for match in re.finditer(pattern, content):
        key = match.group(1)
        value = match.group(2)
        result[key] = value

    return result

def parse_stringsdict_file(content: str) -> Set[str]:
    """Parse .stringsdict file content and return the set of string keys."""
    if not content:
        return set()

    try:
        data = plistlib.loads(content.encode('utf-8'))
        if isinstance(data, dict):
            return set(data.keys())
    except (plistlib.InvalidFileException, ValueError, TypeError):
        pass
    return set()

def parse_stringsdict_file_full(content: str) -> Dict:
    """Parse .stringsdict file content and return the full dictionary."""
    if not content:
        return {}

    try:
        data = plistlib.loads(content.encode('utf-8'))
        if isinstance(data, dict):
            return data
    except (plistlib.InvalidFileException, ValueError, TypeError):
        pass
    return {}

# =============================================================================
# Platform Utilities
# =============================================================================

def get_search_paths(platform: str) -> List[str]:
    """Get the paths to search for source and string files."""
    if platform == "iOS":
        return ["iOS", "SharedPackages"]
    elif platform == "macOS":
        return ["macOS", "SharedPackages"]
    else:
        return [platform]

