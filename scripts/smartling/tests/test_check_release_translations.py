#!/usr/bin/env python3

import importlib.util
import json
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location('check_release_translations', SCRIPTS_DIR / 'check_release_translations.py')
CHECK = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHECK
SPEC.loader.exec_module(CHECK)

ENGLISH_STRINGS = 'iOS/DuckDuckGo/en.lproj/Localizable.strings'
GERMAN_STRINGS = 'iOS/DuckDuckGo/de.lproj/Localizable.strings'
ENGLISH_STRINGSDICT = 'iOS/DuckDuckGo/en.lproj/Localizable.stringsdict'
CZECH_STRINGSDICT = 'iOS/DuckDuckGo/cs.lproj/Localizable.stringsdict'
XCSTRINGS = 'macOS/DuckDuckGo/Localization/Localizable.xcstrings'


def strings(values):
    return ''.join(f'"{key}" = "{value}";\n' for key, value in values.items())


def stringsdict(format_key, variants):
    plurals = ''.join(f'<key>{category}</key><string>{value}</string>' for category, value in variants.items())
    return ('<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>sites</key><dict>'
            f'<key>NSStringLocalizedFormatKey</key><string>{format_key}</string><key>count</key><dict>'
            '<key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>'
            f'<key>NSStringFormatValueTypeKey</key><string>d</string>{plurals}</dict></dict></dict></plist>')


def xcstrings(english, translations):
    localizations = {'en': {'stringUnit': {'state': 'translated', 'value': english}}}
    localizations.update({locale: {'stringUnit': {'state': 'translated', 'value': value}} for locale, value in translations.items()})
    return json.dumps({'sourceLanguage': 'en', 'strings': {'open.in': {'localizations': localizations}}})


def check(head, base=None):
    return CHECK.check(list(head), head.get, (base or {}).get)


class PlaceholderTests(unittest.TestCase):

    def testWhenTheSpecifiersMatchEnglishThenThereIsNoProblem(self):
        for translation, english in [
            ('Öffnen in %@', 'Open in %@'),
            ('%2$@ von %1$d', '%d of %@'),
            ('Usuń %#@items@.', 'Delete %#@items@.'),
            ('25 %', '25%'),
            ('Nur %d %% genutzt', 'Only %d%% used'),
        ]:
            with self.subTest(translation=translation):
                self.assertIsNone(CHECK.placeholder_problem(translation, [english], plural=False))

    def testWhenTheSpecifiersDifferFromEnglishThenTheProblemIsDescribed(self):
        for translation, english, problem in [
            ('Von % @', 'From %@', 'Missing argument 1'),
            ('@@ için şifre silindi', 'Password for %@ deleted', 'Missing argument 1'),
            ('%d Element', '%@ item', 'Argument 1 is integer, English has object'),
            ('%@ und %@', 'and %@', 'Extra object argument 2'),
            ('Usuń 1$#@items@.', 'Delete %#@items@.', 'Missing plural variable items'),
            ('%#@sites@', '%#@items@', 'Unknown plural variable sites'),
        ]:
            with self.subTest(translation=translation):
                self.assertEqual(CHECK.placeholder_problem(translation, [english], plural=False), problem)

    def testWhenAPluralVariantLeavesOutTheCountThenThereIsNoProblem(self):
        self.assertIsNone(CHECK.placeholder_problem('Eine Website', ['One site', '%d sites'], plural=True))

    def testWhenEnglishPluralVariantsNumberTheirSpecifiersDifferentlyThenEitherMatches(self):
        for translation in ['Jeden web v %@', '%d webů v %@']:
            with self.subTest(translation=translation):
                self.assertIsNone(CHECK.placeholder_problem(translation, ['One site in %@', '%d sites in %@'], plural=True))


class CheckTests(unittest.TestCase):

    def testWhenAChangedTranslationDropsASpecifierThenItNeedsAFix(self):
        findings = check(
            {ENGLISH_STRINGS: strings({'open.in': 'Open in %@'}), GERMAN_STRINGS: strings({'open.in': 'Öffnen in'})},
            {GERMAN_STRINGS: strings({'open.in': 'Öffnen in %@'})},
        )

        self.assertEqual([(f.needs_fix, f.problem, f.locale, f.key) for f in findings], [(True, 'Missing argument 1', 'de', 'open.in')])
        self.assertEqual(CHECK.verdict(findings), 'fix')

    def testWhenATranslationIsUnchangedThenItIsNotChecked(self):
        findings = check(
            {ENGLISH_STRINGS: strings({'open.in': 'Open in %@'}), GERMAN_STRINGS: strings({'open.in': 'Öffnen in'})},
            {GERMAN_STRINGS: strings({'open.in': 'Öffnen in'})},
        )

        self.assertEqual(findings, [])
        self.assertEqual(CHECK.verdict(findings), 'ready')

    def testWhenTheEnglishIsInBaseLprojThenItIsUsed(self):
        base_english = ENGLISH_STRINGS.replace('/en.lproj/', '/Base.lproj/')

        findings = check({base_english: strings({'open.in': 'Open in %@'}), GERMAN_STRINGS: strings({'open.in': 'Öffnen in'})})

        self.assertEqual([f.problem for f in findings], ['Missing argument 1'])

    def testWhenATranslationIsEmptyOrBecomesEnglishOrShrinksThenItIsAWarning(self):
        english = {'empty': 'Close', 'english': 'Reject optional cookies', 'short': 'Manage cookie pop-ups automatically'}
        previous = {'empty': 'Schließen', 'english': 'Optionale Cookies ablehnen', 'short': 'Cookie-Pop-ups automatisch verwalten'}
        current = {'empty': '', 'english': 'Reject optional cookies', 'short': 'Cookies'}

        findings = check({ENGLISH_STRINGS: strings(english), GERMAN_STRINGS: strings(current)}, {GERMAN_STRINGS: strings(previous)})

        self.assertEqual(sorted((f.key, f.problem) for f in findings), [
            ('empty', 'Empty translation'),
            ('english', 'Translation replaced by the English text'),
            ('short', 'Less than half its previous length'),
        ])
        self.assertTrue(all(not f.needs_fix for f in findings))
        self.assertEqual(CHECK.verdict(findings), 'warning')

    def testWhenAShortTranslationMatchesEnglishThenItIsNotAWarning(self):
        findings = check({ENGLISH_STRINGS: strings({'tab': 'Tab'}), GERMAN_STRINGS: strings({'tab': 'Tab'})},
                         {GERMAN_STRINGS: strings({'tab': 'Reiter'})})

        self.assertEqual(findings, [])

    def testWhenBoldMarkersAreDroppedThenItIsAWarning(self):
        findings = check({ENGLISH_STRINGS: strings({'promo': 'Get **more** today'}), GERMAN_STRINGS: strings({'promo': 'Hol dir heute mehr'})})

        self.assertEqual([(f.needs_fix, f.problem.split(':')[0]) for f in findings], [(False, 'Bold markers')])

    def testWhenAStringsdictPluralVariableIsBrokenThenItNeedsAFix(self):
        findings = check({
            ENGLISH_STRINGSDICT: stringsdict('%#@count@', {'one': '%d site', 'other': '%d sites'}),
            CZECH_STRINGSDICT: stringsdict('%# @count @', {'one': 'Jeden web', 'few': '%d weby', 'other': '%d webů'}),
        })

        self.assertEqual([(f.needs_fix, f.key) for f in findings], [(True, 'sites')])

    def testWhenOnlyTheEnglishOtherVariantHasTheCountThenACorrectPluralIsNotFlagged(self):
        findings = check({
            ENGLISH_STRINGSDICT: stringsdict('%#@count@', {'one': 'One site in %@', 'other': '%d sites in %@'}),
            CZECH_STRINGSDICT: stringsdict('%#@count@', {'one': 'Jeden web v %@', 'few': '%d weby v %@', 'other': '%d webů v %@'}),
        })

        self.assertEqual(findings, [])

    def testWhenAStringsFileIsMalformedThenItNeedsAFix(self):
        for content in ['"open.in" = "Öffnen "in" %@";\n', '"open.in" = "Öffnen in %@"\n']:
            with self.subTest(content=content):
                findings = check({ENGLISH_STRINGS: strings({'open.in': 'Open in %@'}), GERMAN_STRINGS: content})

                self.assertEqual([(f.needs_fix, f.problem) for f in findings], [(True, "File doesn't parse")])

    def testWhenAStringsFileHasCommentsAndEscapesThenItParses(self):
        content = '\ufeff/* Link */\n"open.in" = "Öffnen in %@ – \\"https://duckduckgo.com\\"";\n// End\n'

        findings = check({ENGLISH_STRINGS: strings({'open.in': 'Open in %@'}), GERMAN_STRINGS: content})

        self.assertEqual(findings, [])

    def testWhenThePreviousFileDoesNotParseThenTheChangesAreStillChecked(self):
        findings = check(
            {ENGLISH_STRINGS: strings({'open.in': 'Open in %@'}), GERMAN_STRINGS: strings({'open.in': 'Öffnen in'})},
            {GERMAN_STRINGS: '"open.in" = "broken'},
        )

        self.assertEqual([f.problem for f in findings], ['Missing argument 1'])

    def testWhenALocalizationFileIsDeletedThenItNeedsAFix(self):
        findings = check({ENGLISH_STRINGS: strings({'open.in': 'Open in %@'}), GERMAN_STRINGS: None},
                         {GERMAN_STRINGS: strings({'open.in': 'Öffnen in %@'})})

        self.assertEqual([(f.needs_fix, f.problem, f.locale) for f in findings], [(True, 'File deleted', 'de')])

    def testWhenATranslationIsRemovedWhileItsEnglishRemainsThenItIsAWarning(self):
        findings = check(
            {ENGLISH_STRINGS: strings({'open.in': 'Open in %@', 'close': 'Close'}), GERMAN_STRINGS: strings({'close': 'Schließen'})},
            {GERMAN_STRINGS: strings({'open.in': 'Öffnen in %@', 'close': 'Schließen', 'gone': 'Weg'})},
        )

        self.assertEqual([(f.needs_fix, f.problem, f.key) for f in findings], [(False, 'Translation removed', 'open.in')])

    def testWhenAnXcstringsLocaleIsRemovedThenItIsAWarning(self):
        findings = check({XCSTRINGS: xcstrings('Open in %@', {'de': 'Öffnen in %@'})},
                         {XCSTRINGS: xcstrings('Open in %@', {'de': 'Öffnen in %@', 'es': 'Abrir en %@'})})

        self.assertEqual([(f.needs_fix, f.problem, f.locale) for f in findings], [(False, 'Translation removed', 'es')])

    def testWhenAnXcstringsFileIsNotAStringCatalogThenItNeedsAFix(self):
        for content in ['[]', '{"strings": []}', '{"strings": {"open.in": "Open in %@"}}']:
            with self.subTest(content=content):
                self.assertEqual([f.problem for f in check({XCSTRINGS: content})], ["File doesn't parse"])

    def testWhenAnXcstringsTranslationHasTheWrongSpecifierThenItNeedsAFix(self):
        findings = check({XCSTRINGS: xcstrings('Open in %@', {'de': 'Öffnen in %@', 'es': 'Abrir en %d'})},
                         {XCSTRINGS: xcstrings('Open in %@', {'de': 'Öffnen in %@'})})

        self.assertEqual([(f.locale, f.problem) for f in findings], [('es', 'Argument 1 is integer, English has object')])

    def testWhenAFileDoesNotParseOrIsNotALocalizationFileThenItNeedsAFix(self):
        findings = check({XCSTRINGS: '{ not json', 'iOS/DuckDuckGo/AppDelegate.swift': 'import UIKit'})

        self.assertEqual(sorted(f.problem for f in findings), ["File doesn't parse", 'Not a localization file'])
        self.assertTrue(all(f.needs_fix for f in findings))


class CommentTests(unittest.TestCase):

    FIX = CHECK.Finding(True, 'Missing argument 1', GERMAN_STRINGS, 'open.in', 'de', 'Öffnen in', 'Open in %@')
    WARNING = CHECK.Finding(False, 'Empty translation', GERMAN_STRINGS, 'close', 'de', '', 'Close')

    def testWhenEveryCheckPassesThenTheCommentSaysItIsReadyToMerge(self):
        body = CHECK.comment([], 'https://example.com/run')

        self.assertTrue(body.startswith('<!-- smartling-release-translations-check verdict=ready -->'))
        self.assertIn('## ✅ Translations ready to merge', body)
        self.assertIn('https://example.com/run', body)

    def testWhenThereAreOnlyWarningsThenTheCommentAsksToCheckThem(self):
        body = CHECK.comment([self.WARNING], '')

        self.assertIn('verdict=warning', body)
        self.assertIn('ready to merge after checking 1 warning(s)', body)
        self.assertNotIn('### Needs a fix', body)

    def testWhenSomethingNeedsAFixThenTheCommentSaysNotToMergeAndListsIt(self):
        body = CHECK.comment([self.FIX, self.WARNING], '')

        self.assertIn('verdict=fix', body)
        self.assertIn("Don't merge yet", body)
        self.assertIn("| Missing argument 1 | de | `open.in` | `Öffnen in` | `Open in %@` |", body)
        self.assertIn('### Warnings', body)

    def testWhenThereAreManyFindingsThenTheTableIsCapped(self):
        body = CHECK.comment([self.WARNING] * (CHECK.MAX_ROWS + 5), '')

        self.assertEqual(body.count('| Empty translation |'), CHECK.MAX_ROWS)
        self.assertIn('…and 5 more', body)

    def testCellsEscapePipesAndNewlines(self):
        self.assertEqual(CHECK.cell('a|b\nc'), '`a\\|b⏎c`')


if __name__ == '__main__':
    unittest.main()
