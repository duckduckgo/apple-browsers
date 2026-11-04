#!/usr/bin/env python3

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / 'smartling_changed_platforms.sh'
MACOS_CATALOG = 'macOS/DuckDuckGo/Localization/Localizable.xcstrings'
SHARED_CATALOG = 'SharedPackages/AIChat/Sources/AIChat/Resources/Localizable.xcstrings'


def catalog(**strings):
    """A string catalog whose strings map a key to (English value, comment, German value)."""
    return json.dumps({
        'sourceLanguage': 'en',
        'strings': {
            key: {
                'comment': comment,
                'localizations': {
                    'en': {'stringUnit': {'state': 'translated', 'value': english}},
                    'de': {'stringUnit': {'state': 'translated', 'value': german}},
                },
            }
            for key, (english, comment, german) in strings.items()
        },
        'version': '1.0',
    }, indent=2)


BASE_CATALOG = catalog(greeting=('Hello', 'A greeting', 'Hallo'))


class ChangedPlatformsTests(unittest.TestCase):

    def setUp(self):
        repo = tempfile.TemporaryDirectory()
        self.addCleanup(repo.cleanup)
        self.repo = Path(repo.name)
        self.git('init', '--quiet')
        self.base = self.commit({
            MACOS_CATALOG: BASE_CATALOG,
            SHARED_CATALOG: BASE_CATALOG,
            'iOS/DuckDuckGo/en.lproj/Localizable.strings': '"greeting" = "Hello";\n',
            'scripts/tool.sh': 'echo one\n',
        })

    def git(self, *args):
        return subprocess.run(
            ['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.com', *args],
            cwd=self.repo, check=True, capture_output=True, text=True
        ).stdout.strip()

    def commit(self, files, deleted=()):
        for path, content in files.items():
            (self.repo / path).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / path).write_text(content, encoding='utf-8')
        for path in deleted:
            (self.repo / path).unlink()
        self.git('add', '--all')
        self.git('commit', '--quiet', '--allow-empty', '--message', 'Change')
        return self.git('rev-parse', 'HEAD')

    def change(self, files, deleted=()):
        """Commit a change to the base commit."""
        self.git('reset', '--quiet', '--hard', self.base)
        return self.commit(files, deleted)

    def changed_platforms(self, head):
        return subprocess.run(
            [str(SCRIPT_PATH), self.base, head],
            cwd=self.repo, capture_output=True, text=True
        )

    def testWhenOnlyTranslationsChangeThenNoPlatformRuns(self):
        head = self.change({
            MACOS_CATALOG: catalog(greeting=('Hello', 'A greeting', 'Guten Tag')),
            SHARED_CATALOG: catalog(greeting=('Hello', 'A greeting', 'Guten Tag')),
            'iOS/DuckDuckGo/de.lproj/Localizable.strings': '"greeting" = "Hallo";\n',
            'scripts/tool.sh': 'echo two\n',
        })

        result = self.changed_platforms(head)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), [])

    def testWhenACatalogsEnglishChangesThenItsPlatformRuns(self):
        changes = {
            'English value': {MACOS_CATALOG: catalog(greeting=('Hi', 'A greeting', 'Hallo'))},
            'comment': {MACOS_CATALOG: catalog(greeting=('Hello', 'A short greeting', 'Hallo'))},
            'new key': {MACOS_CATALOG: catalog(greeting=('Hello', 'A greeting', 'Hallo'), bye=('Bye', 'A farewell', ''))},
            'new catalog': {'macOS/LocalPackages/Feature/Localizable.xcstrings': BASE_CATALOG},
        }
        for change, files in changes.items():
            with self.subTest(change):
                head = self.change(files)

                result = self.changed_platforms(head)

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), ['macOS'])

    def testWhenACatalogIsDeletedThenItsPlatformRuns(self):
        head = self.change({}, deleted=[MACOS_CATALOG])

        result = self.changed_platforms(head)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ['macOS'])

    def testWhenSharedEnglishStringsChangeThenBothPlatformsRun(self):
        head = self.change({SHARED_CATALOG: catalog(greeting=('Hi', 'A greeting', 'Hallo'))})

        result = self.changed_platforms(head)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ['iOS', 'macOS'])

    def testWhenAnEnglishStringsFileChangesThenItsPlatformRuns(self):
        head = self.change({'iOS/DuckDuckGo/en.lproj/Localizable.strings': '"greeting" = "Hi";\n'})

        result = self.changed_platforms(head)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ['iOS'])

    def testWhenACatalogCantBeReadThenTheScriptFails(self):
        head = self.change({MACOS_CATALOG: '{ not json'})

        result = self.changed_platforms(head)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')

    def testWhenACommitIsMissingThenTheScriptFails(self):
        head = '0123456789abcdef0123456789abcdef01234567'

        result = self.changed_platforms(head)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
