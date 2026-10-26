#!/usr/bin/env python3
"""
Checks the translations a release translations import pull request changes against the release branch's English, and
writes the pull request comment for the release DRI: ready to merge, warnings to check first, or translations that need
a fix before merging.

Copyright © 2026 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import os
import re
import sys
import json
import plistlib
import argparse
import subprocess
from pathlib import Path
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Set, Tuple
from xml.parsers.expat import ExpatError

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'translation-pr-checks'))
from check_marker_consistency import marker_issues
from localization_utils import parse_strings_file

LOCALIZATION_EXTENSIONS = ('.strings', '.stringsdict', '.xcstrings')
SPECIFIER = re.compile(
    r"%arg|%(?:\d+\$)?#@(?P<variable>\w+)@|%%"
    r"|%(?:(?P<position>\d+)\$)?[-+#0']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?(?P<type>[@dDiuUxXoOfFeEgGcCsSaAp])"
)
SPECIFIER_TYPES = {
    **dict.fromkeys('dDiuUxXoOcC', 'integer'),
    **dict.fromkeys('fFeEgGaA', 'decimal'),
    '@': 'object',
    's': 'C string',
    'S': 'C string',
    'p': 'pointer',
}
PLURAL_CATEGORIES = {'zero', 'one', 'two', 'few', 'many', 'other'}
COMMENT_MARKER = '<!-- smartling-release-translations-check'
MAX_ROWS = 40

Path_ = Tuple[str, ...]
Reader = Callable[[str], Optional[str]]


@dataclass(frozen=True)
class Finding:
    needs_fix: bool
    problem: str
    file: str
    key: str
    locale: str
    translation: str = ''
    english: str = ''


def specifiers(value: str) -> Tuple[Dict[int, str], Set[str]]:
    """Return the format specifiers by argument position, and the stringsdict and xcstrings plural variables.
    Positional specifiers keep their position; the others are numbered in order among themselves, which is how a
    stringsdict plural's own %d refers to its count."""
    positions, variables, sequence = {}, set(), 0
    for match in SPECIFIER.finditer(value):
        if match[0] == '%%':
            continue
        if match[0] == '%arg':
            variables.add('arg')
        elif match['variable']:
            variables.add(match['variable'])
        else:
            if not match['position']:
                sequence += 1
            position = int(match['position']) if match['position'] else sequence
            positions[position] = SPECIFIER_TYPES.get(match['type'], match['type'])
    return positions, variables


def placeholder_problem(translation: str, english: str, plural: bool) -> Optional[str]:
    """Describe how the translation's format specifiers differ from English, or return None when they match. A plural
    variant may leave out a specifier, since languages word their plural categories differently. English without
    specifiers is never formatted, so a percent sign in its translation is just text."""
    english_positions, english_variables = specifiers(english)
    if not english_positions and not english_variables:
        return None
    positions, variables = specifiers(translation)
    unknown = variables - english_variables - {'arg'}
    if unknown:
        return f"Unknown plural variable {', '.join(sorted(unknown))}"
    for position, kind in sorted(positions.items()):
        if position not in english_positions:
            return f'Extra {kind} argument {position}'
        if english_positions[position] != kind:
            return f'Argument {position} is {kind}, English has {english_positions[position]}'
    missing = sorted(set(english_positions) - set(positions))
    if missing and not plural:
        return f"Missing argument {', '.join(str(position) for position in missing)}"
    if english_variables - {'arg'} - variables and not plural:
        return f"Missing plural variable {', '.join(sorted(english_variables - {'arg'} - variables))}"
    return None


def leaves(value, path: Path_ = ()) -> Dict[Path_, str]:
    """Flatten nested dictionaries to {path: string}."""
    if isinstance(value, str):
        return {path: value}
    if isinstance(value, dict):
        found = {}
        for key, child in value.items():
            found.update(leaves(child, path + (key,)))
        return found
    return {}


def is_plural(path: Path_) -> bool:
    return any(part in PLURAL_CATEGORIES for part in path)


def english_counterparts(path: Path_, english: Dict[Path_, str]) -> Tuple[str, str]:
    """Return the English to compare a translation's specifiers with and its markers with. A plural variant is
    compared with every English plural variant together, and its markers with the same or the 'other' variant."""
    plural_english = {other: value for other, value in english.items() if is_plural(other)}
    if is_plural(path) and plural_english:
        same = english.get(path) or next((value for other, value in plural_english.items() if 'other' in other), '')
        return ' '.join(plural_english.values()), same
    same = english.get(path) or english.get(('stringUnit', 'value')) or next(iter(english.values()), '')
    return same, same


def git_reader(revision: str) -> Reader:
    def read(path: str) -> Optional[str]:
        result = subprocess.run(['git', 'show', f'{revision}:{path}'], capture_output=True, text=True, check=False)
        return result.stdout if result.returncode == 0 else None
    return read


def changed_files(base: str) -> List[str]:
    result = subprocess.run(['git', 'diff', '--name-only', base, 'HEAD'], capture_output=True, text=True, check=True)
    return [path for path in result.stdout.split('\n') if path]


def locale_of(path: str) -> Optional[str]:
    match = re.search(r'/([^/]+)\.lproj/', path)
    return match[1] if match else None


def english_path(path: str, read: Reader) -> Optional[str]:
    locale = locale_of(path)
    for english_locale in ('en', 'Base'):
        candidate = path.replace(f'/{locale}.lproj/', f'/{english_locale}.lproj/')
        if read(candidate) is not None:
            return candidate
    return None


def parse_strings(content: Optional[str]) -> Dict[Path_, str]:
    return {(key,): value for key, value in parse_strings_file(content or '').items()}


def parse_stringsdict(content: Optional[str]) -> Dict[Path_, str]:
    if not content:
        return {}
    return leaves(plistlib.loads(content.encode('utf-8')))


def xcstrings_translations(data: Dict) -> Dict[Tuple[str, str], Dict[Path_, str]]:
    """Return {(key, locale): {path: value}} for every translated value, English included."""
    translations = {}
    for key, entry in (data.get('strings') or {}).items():
        for locale, localization in (entry.get('localizations') or {}).items():
            values = {path: value for path, value in leaves(localization).items() if path[-1] == 'value'}
            if values:
                translations[(key, locale)] = values
    return translations


def check_value(file: str, key: str, locale: str, path: Path_, translation: str, previous: Optional[str],
                english: Dict[Path_, str]) -> List[Finding]:
    english_specifiers, english_text = english_counterparts(path, english)
    if path[-1] == 'NSStringFormatSpecTypeKey':
        return []
    def finding(needs_fix: bool, problem: str) -> Finding:
        return Finding(needs_fix, problem, file, key, locale, translation, english_text)

    if path[-1] == 'NSStringFormatValueTypeKey':
        return [] if not english_text or translation == english_text else [finding(True, 'Plural value type differs from English')]
    if not translation.strip():
        return [finding(False, 'Empty translation')] if english_text.strip() else []

    findings = []
    problem = placeholder_problem(translation, english_specifiers, is_plural(path))
    if problem:
        findings.append(finding(True, problem))
    findings.extend(finding(False, f'Bold markers: {issue}') for issue in marker_issues(english_text, translation))
    if previous and previous != english_text and translation == english_text and len(re.findall(r'\w{2,}', translation)) >= 3:
        findings.append(finding(False, 'Translation replaced by the English text'))
    elif previous and len(translation.strip()) < len(previous.strip()) // 2:
        findings.append(Finding(False, 'Less than half its previous length', file, key, locale, translation, previous))
    return findings


def check_lproj_file(path: str, read_head: Reader, read_base: Reader) -> List[Finding]:
    locale = locale_of(path)
    if locale in (None, 'en', 'Base'):
        return []
    english_file = english_path(path, read_head)
    if not english_file:
        return []
    parse = parse_stringsdict if path.endswith('.stringsdict') else parse_strings
    try:
        current = parse(read_head(path))
    except (ValueError, ExpatError):
        return [Finding(True, "File doesn't parse", path, '', locale)]
    try:
        previous, english = parse(read_base(path)), parse(read_head(english_file))
    except (ValueError, ExpatError):
        previous, english = {}, {}

    findings = []
    for value_path, translation in current.items():
        if previous.get(value_path) == translation:
            continue
        key, sub_path = value_path[0], value_path[1:] or ('value',)
        english_values = {(other[1:] or ('value',)): value for other, value in english.items() if other[0] == key}
        findings.extend(check_value(path, key, locale, sub_path, translation, previous.get(value_path),
                                    english_values or {('value',): ''}))
    return findings


def check_xcstrings_file(path: str, read_head: Reader, read_base: Reader) -> List[Finding]:
    try:
        current = xcstrings_translations(json.loads(read_head(path) or '{}'))
    except ValueError:
        return [Finding(True, "File doesn't parse", path, '', '')]
    try:
        previous = xcstrings_translations(json.loads(read_base(path) or '{}'))
    except ValueError:
        previous = {}

    findings = []
    for (key, locale), values in current.items():
        if locale == 'en':
            continue
        english = current.get((key, 'en')) or {('stringUnit', 'value'): key}
        for value_path, translation in values.items():
            before = previous.get((key, locale), {}).get(value_path)
            if before != translation:
                findings.extend(check_value(path, key, locale, value_path, translation, before, english))
    return findings


def check(files: List[str], read_head: Reader, read_base: Reader) -> List[Finding]:
    findings = [Finding(True, 'Not a localization file', path, '', '') for path in files
                if not path.endswith(LOCALIZATION_EXTENSIONS)]
    for path in files:
        if read_head(path) is None:
            continue
        if path.endswith('.xcstrings'):
            findings.extend(check_xcstrings_file(path, read_head, read_base))
        elif path.endswith(('.strings', '.stringsdict')):
            findings.extend(check_lproj_file(path, read_head, read_base))
    return findings


def verdict(findings: List[Finding]) -> str:
    if any(finding.needs_fix for finding in findings):
        return 'fix'
    return 'warning' if findings else 'ready'


def cell(text: str, limit: int = 120) -> str:
    text = text.replace('\n', '⏎').replace('|', '\\|').replace('`', "'")
    text = text if len(text) <= limit else text[:limit - 1] + '…'
    return f'`{text}`' if text else ''


def table(findings: List[Finding]) -> List[str]:
    rows = ['| Problem | Locale | Key | Translation | English or previous |', '| --- | --- | --- | --- | --- |']
    for finding in findings[:MAX_ROWS]:
        key = cell(finding.key, 60) or cell(finding.file.rsplit('/', 1)[-1], 60)
        rows.append(f'| {finding.problem} | {finding.locale} | {key} | {cell(finding.translation)} | {cell(finding.english)} |')
    if len(findings) > MAX_ROWS:
        rows.append(f'\n…and {len(findings) - MAX_ROWS} more. The workflow log lists them all.')
    return rows


def comment(findings: List[Finding], run_url: str) -> str:
    result = verdict(findings)
    to_fix = [finding for finding in findings if finding.needs_fix]
    warnings = [finding for finding in findings if not finding.needs_fix]
    lines = [f'{COMMENT_MARKER} verdict={result} -->']
    if result == 'ready':
        lines += ['## ✅ Translations ready to merge', '',
                  "Every check passed. Merge this pull request once its required checks are green: the push to the "
                  "release branch starts the internal build as usual."]
    elif result == 'warning':
        lines += [f'## ⚠️ Translations ready to merge after checking {len(warnings)} warning(s)', '',
                  "Nothing below should crash the app or break the build. Check each warning, then merge once the "
                  "required checks are green. To change a translation, fix it in Smartling and run **Smartling - "
                  "Release Import** with **reimport** checked: a fix made only in this pull request is overwritten by "
                  "the next import."]
    else:
        lines += [f'## ❌ {len(to_fix)} translation problem(s) to fix before merging', '',
                  "Don't merge yet: these can crash the app, show the wrong text or bring code changes into the "
                  "release. Fix the translations in Smartling and run **Smartling - Release Import** with **reimport** "
                  "checked, which updates this pull request and checks it again. If the release can't wait, fix them "
                  "in this pull request too, since the next import overwrites a fix made only here."]
    if to_fix:
        lines += ['', '### Needs a fix', ''] + table(to_fix)
    if warnings:
        lines += ['', '### Warnings', ''] + table(warnings)
    lines += ['', '<details><summary>What this checks</summary>', '',
              'Each translation this pull request changes is compared with the release branch\'s English:',
              '- **Needs a fix:** format specifiers (`%@`, `%d`, `%1$@`, plural variables) that are missing, extra or '
              'of another type, files that don\'t parse, and files other than `.strings`, `.stringsdict` and '
              '`.xcstrings`.',
              '- **Warnings:** bold `**` markers that differ from English, empty translations, translations replaced '
              'by the English text, and translations less than half their previous length.',
              '',
              "Translation quality isn't checked: Smartling's translators own it.",
              '</details>']
    if run_url:
        lines += ['', f'⚙️ [Workflow run]({run_url})']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description='Check a release translations import pull request and write its comment')
    parser.add_argument('--base', required=True, help='Revision the pull request is compared with, e.g. origin/release/ios/7.200.0')
    parser.add_argument('--comment-file', required=True, help='Where to write the pull request comment')
    parser.add_argument('--run-url', default='')
    args = parser.parse_args()

    merge_base = subprocess.run(['git', 'merge-base', args.base, 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()
    findings = check(changed_files(merge_base), git_reader('HEAD'), git_reader(merge_base))
    for finding in findings:
        print(f"{'❌' if finding.needs_fix else '⚠️'} {finding.problem}: {finding.file} {finding.key} "
              f"[{finding.locale}] {finding.translation!r} vs {finding.english!r}")
    result = verdict(findings)
    print(f'Verdict: {result}')

    Path(args.comment_file).write_text(comment(findings, args.run_url), encoding='utf-8')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write(f'verdict={result}\n')


if __name__ == '__main__':
    main()
