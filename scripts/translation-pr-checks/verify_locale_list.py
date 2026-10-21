#!/usr/bin/env python3
"""
Locale List Verification Script

Ensures that the locale lists in localization_utils.py stay in sync with the
knownRegions defined in the Xcode project files. Fails if any locale is missing
from the script or present in the script but not in the project.

Usage:
    python3 verify_locale_list.py --platform iOS
    python3 verify_locale_list.py --platform macOS

Copyright © 2026 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import argparse
import re
import sys
from typing import Set

from localization_utils import get_required_locales

XCODE_PROJECT_PATHS = {
    "iOS": "iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj",
    "macOS": "macOS/DuckDuckGo-macOS.xcodeproj/project.pbxproj",
}

# Locales to exclude from comparison (always present in knownRegions but not translation targets)
EXCLUDED_REGIONS = {"en", "Base"}


def parse_known_regions(project_path: str) -> Set[str]:
    """Extract knownRegions from a .pbxproj file."""
    with open(project_path, 'r', encoding='utf-8') as f:
        content = f.read()

    match = re.search(r'knownRegions\s*=\s*\((.*?)\)', content, re.DOTALL)
    if not match:
        print(f"❌ Could not find knownRegions in {project_path}")
        sys.exit(1)

    raw = match.group(1)
    regions = set(re.findall(r'(\w[\w-]*)', raw))
    return regions - EXCLUDED_REGIONS


def main():
    parser = argparse.ArgumentParser(
        description='Verify locale lists match Xcode project knownRegions'
    )
    parser.add_argument(
        '--platform',
        required=True,
        choices=['iOS', 'macOS'],
        help='Platform to check (iOS or macOS)'
    )

    args = parser.parse_args()

    print(f"🔍 Verifying locale list for {args.platform}...")

    project_path = XCODE_PROJECT_PATHS[args.platform]
    project_locales = parse_known_regions(project_path)
    script_locales = get_required_locales(args.platform)

    missing_from_script = project_locales - script_locales
    not_in_project = script_locales - project_locales

    if missing_from_script or not_in_project:
        print(f"❌ Locale list mismatch for {args.platform}:")
        if missing_from_script:
            print(f"   Missing from script: {', '.join(sorted(missing_from_script))}")
        if not_in_project:
            print(f"   In script but not in project: {', '.join(sorted(not_in_project))}")
        print(f"   Update localization_utils.py to match {project_path}")
        sys.exit(1)
    else:
        print(f"✅ Locale list matches Xcode project ({len(script_locales)} locales)")
        sys.exit(0)


if __name__ == '__main__':
    main()
