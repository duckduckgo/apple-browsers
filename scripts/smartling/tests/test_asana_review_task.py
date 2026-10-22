#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import sys
import unittest
from argparse import Namespace
from datetime import date
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / 'asana_review_task.py'
SPEC = importlib.util.spec_from_file_location('asana_review_task', MODULE_PATH)
ASANA_REVIEW_TASK = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = ASANA_REVIEW_TASK
SPEC.loader.exec_module(ASANA_REVIEW_TASK)

ROTATION = [
    {'assignee': {'gid': 'anya', 'name': 'Anya'}, 'start_on': '2026-10-12', 'due_on': '2026-10-16'},
    {'assignee': {'gid': 'elle', 'name': 'Elle'}, 'start_on': '2026-10-19', 'due_on': '2026-10-23'},
    {'assignee': {'gid': 'bartek', 'name': 'Bartek'}, 'start_on': '2026-10-26', 'due_on': '2026-10-30'},
]


def review_task_args():
    return Namespace(
        project='ios-app-development',
        section_name='Incoming: Dev Related Issues',
        rotation_section='apple-ios-triage',
        name='Smartling job needs review: Nightly iOS - 2026-10-21',
        notes='Details',
        assignee=None
    )


class FakeAsanaClient:

    def __init__(self, sections=None, rotation=None, failing=False):
        self.project_sections = sections or []
        self.rotation = rotation or []
        self.failing = failing

    def sections(self, _project_id):
        if self.failing:
            raise RuntimeError('HTTP 500')
        return self.project_sections

    def rotation_tasks(self, _section_id, _since):
        if self.failing:
            raise RuntimeError('HTTP 500')
        return self.rotation


class PickDRITests(unittest.TestCase):

    def testWhenARotationCoversTodayThenItsAssigneeIsTheDRI(self):
        dri = ASANA_REVIEW_TASK.pick_dri(ROTATION, date(2026, 10, 21))

        self.assertEqual(dri['gid'], 'elle')

    def testWhenTodayFallsOnAWeekendThenTheNextRotationsAssigneeIsTheDRI(self):
        dri = ASANA_REVIEW_TASK.pick_dri(ROTATION, date(2026, 10, 24))

        self.assertEqual(dri['gid'], 'bartek')

    def testWhenNoRotationIsScheduledThenThereIsNoDRI(self):
        dri = ASANA_REVIEW_TASK.pick_dri(ROTATION, date(2026, 11, 2))

        self.assertIsNone(dri)


class PagedAsanaClient(ASANA_REVIEW_TASK.AsanaClient):
    """Serves a section's rotation over two pages, like Asana's paginated collections."""

    def __init__(self):
        super().__init__('token')
        self.requested_offsets = []

    def _send(self, method, path, params=None, body=None):  # pylint: disable=unused-argument
        self.requested_offsets.append(params.get('offset'))
        if params.get('offset') is None:
            return {'data': ROTATION[:2], 'next_page': {'offset': 'page-2'}}
        return {'data': ROTATION[2:], 'next_page': None}


class AsanaClientTests(unittest.TestCase):

    def testRotationTasksFollowEveryPage(self):
        client = PagedAsanaClient()

        tasks = client.rotation_tasks('apple-ios-triage', date(2026, 10, 7))

        self.assertEqual(tasks, ROTATION)
        self.assertEqual(client.requested_offsets, [None, 'page-2'])


class NotesHTMLTests(unittest.TestCase):

    def testLabelsAreBoldURLsAreLinksAndTextIsEscaped(self):
        notes = (
            "🌍 Couldn't authorize the job.\n"
            "\n"
            "🔗 Job: https://dashboard.smartling.com/app/projects/p/account-jobs/p:j\n"
            "✋ Reason: HTTP 400: <bad> & worse"
        )

        html_notes = ASANA_REVIEW_TASK.notes_html(notes)

        self.assertEqual(html_notes, (
            "<body>🌍 Couldn&#x27;t authorize the job.\n"
            "\n"
            "<strong>🔗 Job:</strong> <a href=\"https://dashboard.smartling.com/app/projects/p/account-jobs/p:j\">"
            "https://dashboard.smartling.com/app/projects/p/account-jobs/p:j</a>\n"
            "<strong>✋ Reason:</strong> HTTP 400: &lt;bad&gt; &amp; worse</body>"
        ))


class ReviewTaskTests(unittest.TestCase):

    def review_task(self, client):
        with contextlib.redirect_stdout(io.StringIO()):
            return ASANA_REVIEW_TASK.review_task(client, review_task_args(), date(2026, 10, 21))

    def testTaskIsDueTodayInTheIncomingSectionAndAssignedToTheDRI(self):
        client = FakeAsanaClient(
            sections=[{'gid': 'triaged', 'name': 'Triaged'}, {'gid': 'incoming', 'name': 'Incoming: Dev Related Issues'}],
            rotation=ROTATION
        )

        task = self.review_task(client)

        self.assertEqual(task, {
            'name': 'Smartling job needs review: Nightly iOS - 2026-10-21',
            'html_notes': '<body>Details</body>',
            'projects': ['ios-app-development'],
            'due_on': '2026-10-21',
            'memberships': [{'project': 'ios-app-development', 'section': 'incoming'}],
            'assignee': 'elle',
        })

    def testWhenLookupsFailThenTaskIsStillCreatedUnassignedInTheProject(self):
        client = FakeAsanaClient(failing=True)

        task = self.review_task(client)

        self.assertEqual(task, {
            'name': 'Smartling job needs review: Nightly iOS - 2026-10-21',
            'html_notes': '<body>Details</body>',
            'projects': ['ios-app-development'],
            'due_on': '2026-10-21',
        })


if __name__ == '__main__':
    unittest.main()
