#!/usr/bin/env python3

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / 'check_translation_integrity.py'
XCSTRINGS_PATH = 'macOS/App/Localizable.xcstrings'


def xcstrings(translations, state='translated'):
    return json.dumps({
        'sourceLanguage': 'en',
        'strings': {
            key: {'localizations': {
                locale: {'stringUnit': {'state': state, 'value': value}}
                for locale, value in locales.items()
            }}
            for key, locales in translations.items()
        },
        'version': '1.0'
    })


class XcstringsIntegrityTests(unittest.TestCase):

    def setUp(self):
        repo = tempfile.TemporaryDirectory()
        self.addCleanup(repo.cleanup)
        self.repo = Path(repo.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.com')
        self.write(xcstrings({'menu.save': {'en': 'Save', 'de': 'Speichern'}}))
        self.git('add', '.')
        self.git('commit', '-q', '-m', 'Initial')

    def git(self, *args):
        subprocess.run(['git', *args], cwd=self.repo, check=True)

    def write(self, content):
        path = self.repo / XCSTRINGS_PATH
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8')

    def check(self):
        return subprocess.run([sys.executable, str(SCRIPT_PATH)], cwd=self.repo, check=False).returncode

    def testWhenAnXcstringsTranslationIsDeletedThenTheCheckFails(self):
        self.write(xcstrings({'menu.save': {'en': 'Save'}}))

        self.assertEqual(self.check(), 1)

    def testWhenAnXcstringsTranslationIsMuchShorterThenTheCheckFails(self):
        self.write(xcstrings({'menu.save': {'en': 'Save', 'de': 'S'}}))

        self.assertEqual(self.check(), 1)

    def testWhenOnlyAnXcstringsStateChangesThenTheCheckPasses(self):
        self.write(xcstrings({'menu.save': {'en': 'Save', 'de': 'Speichern'}}, state='new'))

        self.assertEqual(self.check(), 0)

    def testWhenAnXcstringsTranslationIsAddedThenTheCheckPasses(self):
        self.write(xcstrings({'menu.save': {'en': 'Save', 'de': 'Speichern', 'fr': 'Enregistrer'}}))

        self.assertEqual(self.check(), 0)


if __name__ == '__main__':
    unittest.main()
