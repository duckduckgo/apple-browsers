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


def translations_task_id(client, branch='release/ios/7.244.0', platform='iOS'):
    with contextlib.redirect_stdout(io.StringIO()):
        return RELEASE_TRANSLATIONS_TASK.translations_task_id(client, platform, branch, TODAY)


class FakeTaskClient:

    def __init__(self, completed=False, assignee=None, release_assignee='100'):
        self.translations_task = {
            'completed': completed,
            'assignee': {'gid': assignee} if assignee else None,
            'parent': {'gid': '2', 'assignee': {'gid': release_assignee} if release_assignee else None},
        }
        self.updates = []
        self.comments = []
        self.calls = []

    def task(self, task_id):
        return self.translations_task

    def update_task(self, task_id, body):
        self.updates.append((task_id, body))
        self.calls.append('update_task')

    def add_comment(self, task_id, html_text):
        self.comments.append((task_id, html_text))
        self.calls.append('add_comment')


def update_translations_task(client, outcome, notes='', pr_url=''):
    with contextlib.redirect_stdout(io.StringIO()):
        return RELEASE_TRANSLATIONS_TASK.update_translations_task(client, '21', outcome, notes, pr_url)


class TranslationsTaskIDTests(unittest.TestCase):

    def testWhenTheReleaseTaskHasATranslationsSubtaskThenItIsLinked(self):
        client = FakeAsanaClient(subtasks=[{'gid': '20', 'name': 'Automation'}, {'gid': '21', 'name': 'Translations '}])

        task_id = translations_task_id(client)

        self.assertEqual(task_id, '21')
        self.assertEqual(client.section_requests, [('1209802997613372', date(2026, 9, 26))])

    def testWhenTheReleaseTaskHasNoTranslationsSubtaskThenItIsAnError(self):
        client = FakeAsanaClient(subtasks=[{'gid': '20', 'name': 'Automation'}])

        with self.assertRaisesRegex(RuntimeError, 'no Translations subtask'):
            translations_task_id(client)

    def testWhenTheBranchIsNotAReleaseBranchThenTheTestTaskIsLinkedWithoutLookingUpAsana(self):
        client = FakeAsanaClient()

        task_id = translations_task_id(client, branch='test/smartling-release-0.1.0')

        self.assertEqual(task_id, '1219893285200023')
        self.assertEqual(client.section_requests, [])

    def testWhenTheBranchIsAReleaseBranchForTheOtherPlatformThenTheTestTaskIsLinked(self):
        task_id = translations_task_id(FakeAsanaClient(), branch='release/macos/1.214.0')

        self.assertEqual(task_id, '1219893285200023')

    def testWhenAMacOSReleaseBranchIsGivenThenTheMacOSReleaseTaskIsLookedUp(self):
        client = FakeAsanaClient(release_tasks=[{'gid': '2', 'name': 'macOS App Release 1.214.0'}], subtasks=[{'gid': '21', 'name': 'Translations'}])

        task_id = translations_task_id(client, branch='release/macos/1.214.0', platform='macOS')

        self.assertEqual(task_id, '21')
        self.assertEqual(client.section_requests[0][0], '1209802997613373')

    def testWhenThereIsNoReleaseTaskThenItIsAnError(self):
        client = FakeAsanaClient(release_tasks=[{'gid': '1', 'name': 'iOS App Release 7.243.0'}])

        with self.assertRaisesRegex(RuntimeError, 'iOS App Release 7.244.0'):
            translations_task_id(client)


class UpdateTranslationsTaskTests(unittest.TestCase):

    def testWhenAPullRequestIsOpenedThenTheUnassignedTaskIsAssignedToTheReleaseDRI(self):
        client = FakeTaskClient()

        commented = update_translations_task(client, 'pr_opened')

        self.assertEqual(client.updates, [('21', {'assignee': '100'})])
        self.assertEqual(client.comments, [])
        self.assertFalse(commented)

    def testWhenAPullRequestIsOpenedThenItIsCommentedAfterTheTaskIsAssigned(self):
        client = FakeTaskClient()

        commented = update_translations_task(client, 'pr_opened', pr_url='https://github.com/duckduckgo/apple-browsers/pull/1')

        self.assertEqual(client.calls, ['update_task', 'add_comment'])
        self.assertEqual(len(client.comments), 1)
        self.assertIn('https://github.com/duckduckgo/apple-browsers/pull/1', client.comments[0][1])
        self.assertTrue(commented)

    def testWhenAReimportUpdatesThePullRequestOfAnOpenTaskThenNothingIsCommented(self):
        client = FakeTaskClient(assignee='100')

        commented = update_translations_task(client, 'pr_updated', pr_url='https://github.com/duckduckgo/apple-browsers/pull/1')

        self.assertEqual(client.updates, [])
        self.assertEqual(client.comments, [])
        self.assertFalse(commented)

    def testWhenTheTaskIsAlreadyAssignedThenItKeepsItsAssignee(self):
        client = FakeTaskClient(assignee='200')

        update_translations_task(client, 'pr_opened')

        self.assertEqual(client.updates, [])

    def testWhenTheReleaseTaskIsUnassignedThenTheTaskStaysUnassigned(self):
        client = FakeTaskClient(release_assignee=None)

        update_translations_task(client, 'pr_opened')

        self.assertEqual(client.updates, [])

    def testWhenAReimportUpdatesThePullRequestThenTheCompletedTaskIsReopenedWithThePullRequest(self):
        client = FakeTaskClient(completed=True, assignee='100')

        update_translations_task(client, 'pr_updated', pr_url='https://github.com/duckduckgo/apple-browsers/pull/1')

        self.assertEqual(client.updates, [('21', {'completed': False})])
        self.assertEqual(len(client.comments), 1)
        self.assertIn('https://github.com/duckduckgo/apple-browsers/pull/1', client.comments[0][1])

    def testWhenNoPullRequestIsNeededThenTheTaskIsCompletedWithAComment(self):
        for outcome in ('no_changes', 'pr_closed'):
            with self.subTest(outcome=outcome):
                client = FakeTaskClient()

                commented = update_translations_task(client, outcome)

                self.assertEqual(client.updates, [('21', {'assignee': '100', 'completed': True})])
                self.assertEqual(client.calls, ['update_task', 'add_comment'])
                self.assertEqual(len(client.comments), 1)
                self.assertIn('already has every translation', client.comments[0][1])
                self.assertTrue(commented)

    def testWhenNoPullRequestIsNeededAndTheTaskIsCompletedThenItIsLeftAlone(self):
        client = FakeTaskClient(completed=True)

        commented = update_translations_task(client, 'no_changes')

        self.assertEqual(client.updates, [])
        self.assertEqual(client.comments, [])
        self.assertFalse(commented)

    def testWhenTheTranslationsAreNotReadyThenTheDetailsAreCommentedAndTheTaskStaysOpen(self):
        client = FakeTaskClient()

        commented = update_translations_task(client, 'not_ready', 'Job: https://example.com/job')

        self.assertEqual(client.calls, ['update_task', 'add_comment'])
        self.assertEqual(client.updates, [('21', {'assignee': '100'})])
        self.assertEqual(client.comments, [('21', '<body><strong>Job:</strong> <a href="https://example.com/job">https://example.com/job</a></body>')])
        self.assertTrue(commented)

    def testWhenThereAreNoNotesForAnotherOutcomeThenNothingIsCommented(self):
        client = FakeTaskClient(assignee='100')

        commented = update_translations_task(client, 'skipped_existing_pr')

        self.assertEqual(client.comments, [])
        self.assertFalse(commented)


if __name__ == '__main__':
    unittest.main()
