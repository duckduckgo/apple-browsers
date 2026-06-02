#!/usr/bin/env python3
"""
Markdown Marker Consistency Check

Verifies that markdown bold markers (`**`) in localized strings match the
English source. Smartling occasionally returns translations where the `**`
markers are dropped, unpaired, or have a stray space next to a delimiter;
because our SwiftUI rendering uses `Text(LocalizedStringKey(...))`, any of these
makes the affected words render literal asterisks or lose the bold styling.

For each key, a locale's value is flagged when:
  - its `**` count differs from the English source count, or
  - its `**` count is odd (an unpaired marker), or
  - a bold span has whitespace adjacent to a `**` delimiter (e.g. `**text **`),
    which markdown won't render as bold even though the count is balanced.

Modes:
  - Default (PR check): only inspects keys whose value changed vs the base
    branch, so it flags regressions introduced by the PR without choking on the
    pre-existing backlog.
  - --all (audit): scans every string in the platform for a full sweep.

Supports .strings (English from en.lproj) and .xcstrings (String Catalogs).

Usage:
    python3 check_marker_consistency.py --platform iOS
    python3 check_marker_consistency.py --platform macOS --all

Exit code is 1 when any issue is found, 0 otherwise.

Copyright © 2025 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import argparse
import os
import sys
from typing import Dict, List, Tuple

from localization_utils import (
    get_changed_files,
    get_files_content_at_base,
    get_search_paths,
    parse_strings_file,
    parse_xcstrings,
)

MARKER = "**"

# (display_key, file, locale, issues) where issues is a list of descriptions
Finding = Tuple[str, str, str, List[str]]


def count_markers(value: str) -> int:
    """Count non-overlapping `**` occurrences in a string value."""
    return value.count(MARKER) if value else 0


def read_file(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()
    except OSError:
        return ""


def flatten_localization(entry: Dict, prefix: str = "") -> Dict[str, str]:
    """Flatten one .xcstrings localization entry to {subpath: value}.

    Recurses through stringUnit, variations (plural/device), and substitutions
    (named plural arguments, which themselves nest variations), so every
    translatable leaf is captured.
    """
    leaves: Dict[str, str] = {}
    if not isinstance(entry, dict):
        return leaves
    string_unit = entry.get("stringUnit")
    if isinstance(string_unit, dict) and isinstance(string_unit.get("value"), str):
        leaves[prefix] = string_unit["value"]
    variations = entry.get("variations")
    if isinstance(variations, dict):
        for kind, cases in variations.items():
            if not isinstance(cases, dict):
                continue
            for case_name, case_entry in cases.items():
                key = f"{prefix}.{kind}.{case_name}" if prefix else f"{kind}.{case_name}"
                leaves.update(flatten_localization(case_entry, key))
    substitutions = entry.get("substitutions")
    if isinstance(substitutions, dict):
        for name, sub_entry in substitutions.items():
            key = f"{prefix}.sub:{name}" if prefix else f"sub:{name}"
            leaves.update(flatten_localization(sub_entry, key))
    return leaves


_WS_ESCAPES = (("\\n", "\n"), ("\\t", "\t"), ("\\r", "\r"))


def _edge_whitespace(segment: str) -> bool:
    """True if a bold-content segment starts/ends with whitespace.

    Counts literal .strings escapes (\\n, \\t, \\r) as whitespace: the regex
    .strings parser keeps them escaped, but they decode to real whitespace at
    runtime, so `**Text\\n**` renders broken just like `**Text **`.
    """
    probe = segment
    for escape, real in _WS_ESCAPES:
        probe = probe.replace(escape, real)
    return bool(probe) and probe != probe.strip()


def marker_issues(source_value: str, loc_value: str) -> List[str]:
    """Return a list of problem descriptions for a translation. Empty == fine.

    Detects three classes:
      - count mismatch / unpaired markers (vs the English source), and
      - whitespace adjacent to a `**` delimiter (won't render as bold).
    """
    en = count_markers(source_value)
    loc = count_markers(loc_value)
    issues: List[str] = []

    if loc != en or loc % 2 != 0:
        if loc % 2 != 0:
            category = "UNPAIRED"
        elif en == 0 and loc > 0:
            category = "ADDED"
        elif loc > en:
            category = "EXTRA"
        else:
            category = "DROPPED"
        issues.append(f"{loc} marker(s) vs {en} in source [{category}]")

    # Whitespace next to a delimiter: split into segments; odd-index segments are
    # the bold content. Any leading/trailing whitespace there means a `**` sits
    # next to a space and won't render. Only meaningful when markers are paired.
    if loc % 2 == 0 and loc > 0:
        segments = loc_value.split(MARKER)
        bad = [segments[i] for i in range(1, len(segments), 2)
               if _edge_whitespace(segments[i])]
        if bad:
            rendered = ", ".join(repr(b) for b in bad)
            issues.append(f"space inside bold delimiter: {rendered} [WHITESPACE]")

    return issues


def en_sibling_path(strings_path: str) -> str:
    """en.lproj sibling of a <locale>.lproj/<name>.strings path."""
    parent = os.path.dirname(os.path.dirname(strings_path))
    return os.path.join(parent, "en.lproj", os.path.basename(strings_path))


# =============================================================================
# .strings
# =============================================================================

def check_strings_file(path: str, only_changed_keys=None) -> List[Finding]:
    locale_dir = os.path.basename(os.path.dirname(path))
    if locale_dir in ("en.lproj", "Base.lproj"):
        return []
    en_path = en_sibling_path(path)
    if not os.path.exists(en_path):
        return []
    english = parse_strings_file(read_file(en_path))
    translated = parse_strings_file(read_file(path))
    locale = locale_dir[: -len(".lproj")]
    findings: List[Finding] = []
    for key, value in translated.items():
        if only_changed_keys is not None and key not in only_changed_keys:
            continue
        if key not in english:
            continue
        issues = marker_issues(english[key], value)
        if issues:
            findings.append((key, path, locale, issues))
    return findings


# =============================================================================
# .xcstrings
# =============================================================================

def check_xcstrings_data(new_data: Dict, path: str, old_data: Dict = None) -> List[Finding]:
    source_lang = new_data.get("sourceLanguage", "en")
    findings: List[Finding] = []
    old_strings = (old_data or {}).get("strings", {})
    for key, entry in new_data.get("strings", {}).items():
        localizations = entry.get("localizations", {})
        if not isinstance(localizations, dict):
            continue
        if source_lang in localizations:
            source_leaves = flatten_localization(localizations[source_lang])
        else:
            source_leaves = {"": key}
        old_locs = old_strings.get(key, {}).get("localizations", {}) if old_data is not None else {}
        # If the English source for this key changed, every locale leaf must be
        # re-checked — not just leaves that themselves changed — because a
        # source-only marker edit now mismatches the untouched translations.
        old_source_leaves = (flatten_localization(old_locs.get(source_lang, {}))
                             if source_lang in old_locs else {"": key})
        source_changed = old_data is not None and old_source_leaves != source_leaves
        for locale, loc_entry in localizations.items():
            if locale == source_lang:
                continue
            new_leaves = flatten_localization(loc_entry)
            old_leaves = flatten_localization(old_locs.get(locale, {})) if old_data is not None else {}
            for sub_path, loc_value in new_leaves.items():
                if old_data is not None and not source_changed and old_leaves.get(sub_path) == loc_value:
                    continue
                source_value = source_leaves.get(sub_path, source_leaves.get(""))
                if source_value is None:
                    continue
                issues = marker_issues(source_value, loc_value)
                if issues:
                    display_key = f"{key} [{sub_path}]" if sub_path else key
                    findings.append((display_key, path, locale, issues))
    return findings


# =============================================================================
# Modes
# =============================================================================

def check_changed(platform: str) -> List[Finding]:
    """PR mode: keys changed vs the base branch, plus every locale of any key
    whose English source changed — a source-only marker edit must re-check the
    existing (unchanged) translations against the new source."""
    paths = get_search_paths(platform)
    findings: List[Finding] = []

    # ---- .strings ----
    # A "unit" is one (lproj-parent, filename) the PR touched via en.lproj or any
    # locale. For each, check every sibling locale for the union of
    # (source-changed keys) and (that locale's own changed keys).
    units = set()
    for path in get_changed_files([".strings"], paths):
        if os.path.basename(os.path.dirname(path)) == "Base.lproj":
            continue
        units.add((os.path.dirname(os.path.dirname(path)), os.path.basename(path)))

    for parent, filename in sorted(units):
        en_path = os.path.join(parent, "en.lproj", filename)
        if not os.path.exists(en_path):
            continue
        locale_paths = [os.path.join(parent, d, filename)
                        for d in sorted(os.listdir(parent))
                        if d.endswith(".lproj") and d not in ("en.lproj", "Base.lproj")
                        and os.path.exists(os.path.join(parent, d, filename))]
        base = get_files_content_at_base([en_path] + locale_paths)
        en_old = parse_strings_file(base.get(en_path, ""))
        en_new = parse_strings_file(read_file(en_path))
        source_changed = {k for k in set(en_old) | set(en_new) if en_old.get(k) != en_new.get(k)}
        for loc_path in locale_paths:
            loc_old = parse_strings_file(base.get(loc_path, ""))
            loc_new = parse_strings_file(read_file(loc_path))
            loc_changed = {k for k, v in loc_new.items() if loc_old.get(k) != v}
            keys = source_changed | loc_changed
            if keys:
                findings.extend(check_strings_file(loc_path, only_changed_keys=keys))

    # ---- .xcstrings ----
    xcstrings_files = get_changed_files([".xcstrings"], paths)
    base_xc = get_files_content_at_base(xcstrings_files)
    for path in xcstrings_files:
        new_data = parse_xcstrings(read_file(path))
        old_data = parse_xcstrings(base_xc.get(path, ""))
        findings.extend(check_xcstrings_data(new_data, path, old_data=old_data))

    return findings


def check_all(platform: str) -> List[Finding]:
    """Audit mode: every string in the platform."""
    findings: List[Finding] = []
    for root_path in get_search_paths(platform):
        for dirpath, _dirs, filenames in os.walk(root_path):
            if any(skip in dirpath for skip in (".build", "DerivedData", "node_modules")):
                continue
            for filename in filenames:
                full = os.path.join(dirpath, filename)
                if filename.endswith(".strings"):
                    findings.extend(check_strings_file(full))
                elif filename.endswith(".xcstrings"):
                    findings.extend(check_xcstrings_data(parse_xcstrings(read_file(full)), full))
    return findings


def report(findings: List[Finding], mode_label: str) -> int:
    if not findings:
        print("✅ No markdown marker issues found.")
        return 0

    by_key: Dict[Tuple[str, str], List[Tuple[str, List[str]]]] = {}
    for key, path, locale, issues in findings:
        by_key.setdefault((key, path), []).append((locale, issues))

    print(f"⚠️  Found {len(findings)} markdown marker issue(s) {mode_label} "
          f"across {len(by_key)} key(s):\n")
    for (key, path), locales in sorted(by_key.items()):
        print(f"  {key}  ({path})")
        for locale, issues in sorted(locales):
            for issue in issues:
                print(f"      {locale}: {issue}")
        print()
    print("Each translation's ** bold markers must match the English source. "
          "Fix the affected translations at the Smartling source.")
    print("Legend: UNPAIRED = odd marker count; DROPPED = fewer markers than "
          "source (missing); EXTRA = more markers than source; ADDED = source has "
          "none but translation does (often wrong content); WHITESPACE = a space "
          "sits next to a ** delimiter so it won't render as bold.")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Check markdown bold marker consistency.")
    parser.add_argument("--platform", required=True, choices=["iOS", "macOS"])
    parser.add_argument("--all", action="store_true",
                        help="Audit every string instead of only PR changes.")
    args = parser.parse_args()

    if args.all:
        return report(check_all(args.platform), mode_label="in the tree")
    return report(check_changed(args.platform), mode_label="introduced by this PR")


if __name__ == "__main__":
    sys.exit(main())
