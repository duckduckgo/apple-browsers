#!/usr/bin/env python3

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).parents[1]))
from smartling_open_issues import Git, OpenIssue, adds_string, parse_time, string_commit, text_forms


class RepositoryGit(Git):

    def __init__(self, directory):
        self.directory = directory

    def _run(self, *args):
        return super()._run('-C', self.directory, *args)


class CatalogAttributionTests(unittest.TestCase):
    """Exercise real git history, including the diff context that a mocked Git cannot verify."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.git = RepositoryGit(self.directory.name)
        self.git._run('init', '-q')
        self.git._run('config', 'user.name', 'Test Author')
        self.git._run('config', 'user.email', 'test@example.com')
        self.path = Path(self.directory.name) / 'macOS' / 'Localizable.xcstrings'
        self.path.parent.mkdir()

    def commit(self):
        self.git._run('add', '.')
        with mock.patch.dict(os.environ, {
            'GIT_AUTHOR_DATE': '2026-11-01T00:00:00Z', 'GIT_COMMITTER_DATE': '2026-11-01T00:00:00Z',
        }):
            self.git._run('-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Update catalog')
        return self.git._run('rev-parse', 'HEAD').strip()

    def write_catalog(self, english, translation='Weiter', key='continue.button', plural=False):
        def unit(value):
            return {'stringUnit': {'state': 'translated', 'value': value}}

        source = {'variations': {'plural': {'one': unit(english), 'other': unit('Other items')}}} if plural else unit(english)
        catalog = {'sourceLanguage': 'en', 'strings': {key: {
            'comment': 'Button title', 'extractionState': 'manual',
            'localizations': {'de': unit(translation), 'en': source},
        }}}
        self.path.write_text(json.dumps(catalog, indent=2) + '\n')

    def testCatalogEditFindsTheEditorWhenTheKeyIsOutsideTheDiffHunk(self):
        self.write_catalog('Continue')
        original = self.commit()
        self.write_catalog('Continue now')
        editor = self.commit()
        self.write_catalog('Continue now', translation='Jetzt weiter')
        self.commit()
        github = SimpleNamespace(commit_pulls=lambda sha: [{
            'merge_commit_sha': sha, 'user': {'login': 'editor' if sha == editor else 'original-author'},
        }])
        timestamp = parse_time('2026-11-05')
        issue = OpenIssue(1, timestamp, timestamp, False, '', '', 'Continue now', 'continue.button', '', '')

        raw_diff = self.git._run('show', '-U6', '--format=', editor)
        self.assertNotIn('continue.button', raw_diff)
        found = string_commit(self.git, github, issue, 'macOS')

        self.assertEqual(found['user']['login'], 'editor')
        self.assertNotEqual(found['merge_commit_sha'], original)

    def testPluralEditKeepsItsOwningKey(self):
        self.write_catalog('One item', plural=True)
        self.commit()
        self.write_catalog('One selected item', plural=True)
        editor = self.commit()

        diff = self.git.diff(editor, ['macOS'])

        self.assertTrue(adds_string(diff, text_forms('One selected item'), ['continue.button']))
        self.assertFalse(adds_string(diff, text_forms('One selected item'), ['other.key']))

    def testTranslationChangesAndCatalogMovesDoNotAddEnglishStrings(self):
        self.write_catalog('Continue')
        self.commit()
        self.write_catalog('Continue', translation='Continue now')
        translation = self.commit()
        self.path.rename(self.path.with_name('Moved.xcstrings'))
        moved = self.commit()

        self.assertFalse(adds_string(self.git.diff(translation, ['macOS']), ['Continue now'], ['continue.button']))
        self.assertFalse(adds_string(self.git.diff(moved, ['macOS']), ['Continue'], ['continue.button']))
        self.assertFalse(adds_string(self.git.diff(moved, ['macOS']), [], ['continue.button']))


if __name__ == '__main__':
    unittest.main()
