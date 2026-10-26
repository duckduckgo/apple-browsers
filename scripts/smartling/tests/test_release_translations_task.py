#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import sys
import unittest
from datetime import date
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location('release_translations_task', SCRIPTS_DIR / 'release_translations_task.py')
RELEASE_TRANSLATIONS_TASK = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = RELEASE_TRANSLATIONS_TASK
SPEC.loader.exec_module(RELEASE_TRANSLATIONS_TASK)

TODAY = date(2026, 10, 26)
RELEASE_TASKS = [
    {'gid': '1', 'name': 'iOS App Release 7.243.0'},
    {'gid': '2', 'name': 'iOS App Release 7.244.0'},
    {'gid': '3', 'name': 'macOS App Release 1.214.0'},
]


class FakeAsanaClient:

    def __init__(self, release_tasks=None, subtasks=None):
        self.release_tasks = RELEASE_TASKS if release_tasks is None else release_tasks
        self.release_subtasks = subtasks or []
        self.section_requests = []

    def section_tasks(self, section_id, since):
        self.section_requests.append((section_id, since))
        return self.release_tasks

    def subtasks(self, task_id):
        return self.release_subtasks if task_id == '2' else []


def translations_task_url(client, branch='release/ios/7.244.0', platform='iOS'):
    with contextlib.redirect_stdout(io.StringIO()):
        return RELEASE_TRANSLATIONS_TASK.translations_task_url(client, platform, branch, TODAY)


class TranslationsTaskURLTests(unittest.TestCase):

    def testWhenTheReleaseTaskHasATranslationsSubtaskThenItIsLinked(self):
        client = FakeAsanaClient(subtasks=[{'gid': '20', 'name': 'Automation'}, {'gid': '21', 'name': 'Translations '}])

        url = translations_task_url(client)

        self.assertEqual(url, 'https://app.asana.com/0/0/21/f')
        self.assertEqual(client.section_requests, [('1209802997613372', date(2026, 9, 26))])

    def testWhenTheReleaseTaskHasNoTranslationsSubtaskThenItIsAnError(self):
        client = FakeAsanaClient(subtasks=[{'gid': '20', 'name': 'Automation'}])

        with self.assertRaisesRegex(RuntimeError, 'no Translations subtask'):
            translations_task_url(client)

    def testWhenTheBranchIsNotAReleaseBranchThenTheTestTaskIsLinkedWithoutLookingUpAsana(self):
        client = FakeAsanaClient()

        url = translations_task_url(client, branch='test/smartling-release-0.1.0')

        self.assertEqual(url, 'https://app.asana.com/0/0/1219536424657556/f')
        self.assertEqual(client.section_requests, [])

    def testWhenTheBranchIsAReleaseBranchForTheOtherPlatformThenTheTestTaskIsLinked(self):
        url = translations_task_url(FakeAsanaClient(), branch='release/macos/1.214.0')

        self.assertEqual(url, 'https://app.asana.com/0/0/1219536424657556/f')

    def testWhenAMacOSReleaseBranchIsGivenThenTheMacOSReleaseTaskIsLookedUp(self):
        client = FakeAsanaClient(release_tasks=[{'gid': '2', 'name': 'macOS App Release 1.214.0'}], subtasks=[{'gid': '21', 'name': 'Translations'}])

        url = translations_task_url(client, branch='release/macos/1.214.0', platform='macOS')

        self.assertEqual(url, 'https://app.asana.com/0/0/21/f')
        self.assertEqual(client.section_requests[0][0], '1209802997613373')

    def testWhenThereIsNoReleaseTaskThenItIsAnError(self):
        client = FakeAsanaClient(release_tasks=[{'gid': '1', 'name': 'iOS App Release 7.243.0'}])

        with self.assertRaisesRegex(RuntimeError, 'iOS App Release 7.244.0'):
            translations_task_url(client)


if __name__ == '__main__':
    unittest.main()
