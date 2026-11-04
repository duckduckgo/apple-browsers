#!/usr/bin/env python3

import asyncio
import contextlib
import importlib.util
import io
import sys
import unittest
from argparse import Namespace
from datetime import datetime, timezone
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))
SPEC = importlib.util.spec_from_file_location('smartling_open_issues', SCRIPTS_DIR / 'smartling_open_issues.py')
OPEN_ISSUES = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = OPEN_ISSUES
SPEC.loader.exec_module(OPEN_ISSUES)

NOT_BEFORE = '2026-11-01T00:00:00Z'
LAST_NIGHT = '2026-11-03T03:20:00Z'
ISSUE_TEXT = 'Is this a button or a title?'
ENGLISH = 'Entry Pill'
KEY = 'duckplayer.entry.pill'
ADDING_DIFF = f'@@ -1,2 +1,3 @@\n context\n+        "{KEY}": "{ENGLISH}",\n context\n'
STRING_COMMIT = 'a' * 40
TRIAGE_DRI = {'gid': 'dri', 'name': 'Triage DRI'}


def utc(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(timezone.utc)


def smartling_issue(number=3600, created='2026-11-03T10:00:00Z', reopened_date=None, job_uid='nightly'):
    return {
        'issueNumber': number,
        'createdDate': created,
        'reopened': bool(reopened_date),
        'reopenedDate': reopened_date,
        'issueSubTypeCode': 'CLARIFICATION',
        'issueText': ISSUE_TEXT,
        'string': {'hashcode': f'hash-{number}'},
        'jobUids': [job_uid],
    }


def pull(login, number=7000, user_type='User', merge_commit_sha=STRING_COMMIT):
    return {
        'number': number,
        'user': {'login': login, 'type': user_type},
        'merge_commit_sha': merge_commit_sha,
        'html_url': f'https://github.com/duckduckgo/apple-browsers/pull/{number}',
    }


def nightly_run(run_id, conclusion, started_at=LAST_NIGHT, name='iOS open issues'):
    return {'id': run_id, 'jobs': [{'name': name, 'conclusion': conclusion, 'started_at': started_at}]}


def asana_task(number, created_at):
    return {'name': f'Smartling open issue #{number} (iOS): {KEY}', 'created_at': created_at}


class FakeSmartling:

    def __init__(self, issues, jobs=None):
        self.issues = issues
        self.jobs = jobs or {'nightly': {'translationJobUid': 'nightly', 'jobName': 'Nightly iOS - 2026-11-03', 'createdDate': '2026-11-03T03:20:00Z'}}
        self.creds = Namespace(project_id='ios-project')

    async def list_open_source_issues(self):
        return self.issues

    async def get_source_string(self, _hashcode):
        return {'stringText': ENGLISH, 'keys': [{'key': KEY, 'fileUri': 'main/en.xliff'}]}

    async def get_job(self, job_uid):
        return self.jobs[job_uid]


class FakeAsana:

    def __init__(self, tasks=None, rejected_assignees=()):
        self.tasks = tasks or []
        self.rejected_assignees = set(rejected_assignees)
        self.created = []

    def project_tasks(self, _project_id, _since):
        return self.tasks

    def sections(self, _project_id):
        return [{'gid': 'incoming', 'name': 'Incoming'}]

    def rotation_tasks(self, _section_id, _since):
        return [{'assignee': TRIAGE_DRI, 'start_on': '2000-01-01', 'due_on': '2100-12-31'}]

    def create_task(self, body):
        if body.get('assignee') in self.rejected_assignees:
            raise RuntimeError('Asana POST /tasks failed with HTTP 400: assignee: Not a recognized ID')
        self.created.append(body)
        return {'gid': str(len(self.created))}


class FakeGitHub:

    def __init__(self, runs=None, commit_pulls=None, branch_pulls=None):
        self.runs = runs or []
        self.pulls_by_commit = commit_pulls if commit_pulls is not None else {STRING_COMMIT: [pull('frosty')]}
        self.pulls_by_branch = branch_pulls or {}

    def workflow_runs(self, _workflow, _branch):
        return [{'id': run['id']} for run in self.runs]

    def run_jobs(self, run_id):
        return next(run['jobs'] for run in self.runs if run['id'] == run_id)

    def commit_pulls(self, sha):
        return self.pulls_by_commit.get(sha, [])

    def branch_pulls(self, branch):
        return self.pulls_by_branch.get(branch, [])


class FakeGit:

    def __init__(self, diffs=None):
        self.diffs = diffs if diffs is not None else {STRING_COMMIT: ADDING_DIFF}

    def ensure_history(self):
        pass

    def shallow_commits(self):
        return set()

    def commits_changing(self, _text, _paths, _before):
        return list(self.diffs)

    def diff(self, sha, _paths):
        return self.diffs[sha]

    def full_sha(self, _short_sha):
        return None


def args(dry_run=False, since=None):
    return Namespace(
        platform='iOS',
        asana_project='ios-app-development',
        section_name='Incoming',
        rotation_section='ios-triage',
        workflow='smartling_nightly.yml',
        job_name='iOS open issues',
        not_before=NOT_BEFORE,
        since=since,
        workflow_url='https://github.com/duckduckgo/apple-browsers/actions/runs/1',
        dry_run=dry_run,
    )


def run(smartling, asana, github=None, git=None, user_map=None, dry_run=False):
    """Run the job with the given clients, returning the summary rows and the log."""
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        rows = asyncio.run(OPEN_ISSUES.run(
            args(dry_run=dry_run), smartling, asana, github or FakeGitHub(runs=[nightly_run(1, 'success')]),
            git or FakeGit(), {'frosty': 'frosty-gid'} if user_map is None else user_map
        ))
    return rows, output.getvalue()


class WindowStartTests(unittest.TestCase):

    def testWhenANightSucceededThenTheWindowStartsWhenItsJobStarted(self):
        github = FakeGitHub(runs=[nightly_run(2, 'failure', '2026-11-04T03:20:00Z'), nightly_run(1, 'success')])

        start = OPEN_ISSUES.window_start(github, 'smartling_nightly.yml', 'iOS open issues', utc(NOT_BEFORE))

        self.assertEqual(start, utc(LAST_NIGHT))

    def testWhenOnlyDryRunsSucceededThenTheWindowStartsAtGoLive(self):
        github = FakeGitHub(runs=[nightly_run(1, 'success', name='iOS open issues (dry run)')])

        start = OPEN_ISSUES.window_start(github, 'smartling_nightly.yml', 'iOS open issues', utc(NOT_BEFORE))

        self.assertEqual(start, utc(NOT_BEFORE))

    def testWhenTheLastSuccessIsBeforeGoLiveThenTheWindowStartsAtGoLive(self):
        github = FakeGitHub(runs=[nightly_run(1, 'success', '2026-10-01T03:20:00Z')])

        start = OPEN_ISSUES.window_start(github, 'smartling_nightly.yml', 'iOS open issues', utc(NOT_BEFORE))

        self.assertEqual(start, utc(NOT_BEFORE))


class OpenIssueTaskTests(unittest.TestCase):

    def testWhenAnIssueIsNewThenItsTaskGoesToWhoeverAddedTheString(self):
        asana = FakeAsana()

        rows, _ = run(FakeSmartling([smartling_issue()]), asana)

        self.assertEqual(len(asana.created), 1)
        self.assertEqual(asana.created[0]['name'], f'Smartling open issue #3600 (iOS): {KEY}')
        self.assertEqual(asana.created[0]['assignee'], 'frosty-gid')
        self.assertEqual(asana.created[0]['memberships'], [{'project': 'ios-app-development', 'section': 'incoming'}])
        self.assertIn(ISSUE_TEXT, asana.created[0]['html_notes'])
        self.assertEqual(rows, ['| #3600 | opened a task | @frosty (added the string) |'])

    def testWhenAnIssueWasOpenedBeforeTheLastSuccessfulNightThenNoTaskIsOpened(self):
        asana = FakeAsana()

        rows, _ = run(FakeSmartling([smartling_issue(created='2026-11-02T10:00:00Z')]), asana)

        self.assertEqual(asana.created, [])
        self.assertEqual(rows, [])

    def testWhenARerunFindsTheIssuesTaskThenNoSecondTaskIsOpened(self):
        asana = FakeAsana(tasks=[asana_task(3600, '2026-11-04T03:21:00Z')])

        rows, _ = run(FakeSmartling([smartling_issue()]), asana)

        self.assertEqual(asana.created, [])
        self.assertEqual(rows, ['| #3600 | already has a task | |'])

    def testWhenAnIssueIsReopenedAfterItsTaskThenANewTaskIsOpened(self):
        asana = FakeAsana(tasks=[asana_task(3600, '2026-11-03T12:00:00Z')])
        reopened = smartling_issue(created='2026-10-20T10:00:00Z', reopened_date='2026-11-03T15:00:00Z')

        run(FakeSmartling([reopened]), asana)

        self.assertEqual(len(asana.created), 1)

    def testWhenTheStringsAuthorIsABotOrUnmappedThenTheTriageDRIGetsTheTask(self):
        cases = {
            'bot': (FakeGitHub(runs=[nightly_run(1, 'success')], commit_pulls={STRING_COMMIT: [pull('daxmobile')]}), None),
            'unmapped': (None, {}),
        }
        for case, (github, user_map) in cases.items():
            with self.subTest(case):
                asana = FakeAsana()

                run(FakeSmartling([smartling_issue()]), asana, github=github, user_map=user_map)

                self.assertEqual(asana.created[0]['assignee'], 'dri')

    def testWhenAsanaRejectsTheAuthorThenTheTriageDRIGetsTheTask(self):
        asana = FakeAsana(rejected_assignees={'frosty-gid'})

        run(FakeSmartling([smartling_issue()]), asana)

        self.assertEqual([task['assignee'] for task in asana.created], ['dri'])

    def testWhenTheIssueWasRaisedInATranslateJobThenItsPullRequestsAuthorGetsTheTask(self):
        smartling = FakeSmartling([smartling_issue(job_uid='label')], jobs={
            'label': {'translationJobUid': 'label', 'jobName': 'anya/sync-restore-2026-11-03', 'createdDate': '2026-11-03T09:00:00Z'},
        })
        github = FakeGitHub(runs=[nightly_run(1, 'success')], branch_pulls={'anya/sync-restore': [pull('anya', 7100)]})
        asana = FakeAsana()

        run(smartling, asana, github=github, user_map={'anya': 'anya-gid'})

        self.assertEqual(asana.created[0]['assignee'], 'anya-gid')

    def testWhenItIsADryRunThenNoTaskIsOpened(self):
        asana = FakeAsana()

        rows, _ = run(FakeSmartling([smartling_issue()]), asana, dry_run=True)

        self.assertEqual(asana.created, [])
        self.assertEqual(rows, ['| #3600 | would open a task | @frosty (added the string) |'])

    def testWhenTasksAreOpenedThenTheLogHasNoIssueOrEnglishText(self):
        smartling = FakeSmartling([smartling_issue()])

        _, log = run(smartling, FakeAsana())

        self.assertNotIn(ISSUE_TEXT, log)
        self.assertNotIn(ENGLISH, log)


class StringAttributionTests(unittest.TestCase):

    def testWhenTheTextIsAddedUnderTheKeyThenTheCommitAddedTheString(self):
        added = OPEN_ISSUES.adds_string(ADDING_DIFF, [ENGLISH], [KEY])

        self.assertTrue(added)

    def testWhenTheSameTextIsAddedUnderAnotherKeyThenTheCommitDidntAddTheString(self):
        diff = f'@@ -1,2 +1,3 @@\n context\n+        "other.key": "{ENGLISH}",\n context\n'

        added = OPEN_ISSUES.adds_string(diff, [ENGLISH], [KEY])

        self.assertFalse(added)

    def testWhenTheNewestCommitIsATranslationImportThenTheOlderAuthorGetsIt(self):
        import_commit = 'b' * 40
        git = FakeGit(diffs={import_commit: ADDING_DIFF, STRING_COMMIT: ADDING_DIFF})
        github = FakeGitHub(commit_pulls={import_commit: [pull('daxmobile', 7200, merge_commit_sha=import_commit)], STRING_COMMIT: [pull('frosty')]})
        issue = OPEN_ISSUES.OpenIssue(3600, utc(LAST_NIGHT), utc(LAST_NIGHT), False, '', '', ENGLISH, KEY, '', '')

        found = OPEN_ISSUES.string_commit(git, github, issue, 'iOS')

        self.assertEqual(found['user']['login'], 'frosty')

    def testWhenTheKeyIsAPluralVariantThenItsBaseKeyIsSearched(self):
        forms = OPEN_ISSUES.key_forms('/tab.switcher.close-tabs.button.withCount:dict/tabs:dict/one:dict/:string')

        self.assertEqual(forms, ['tab.switcher.close-tabs.button.withCount'])

    def testWhenTheStringIsInSeveralJobsThenTheIssueBelongsToTheNewestOneBeforeIt(self):
        jobs = [
            {'translationJobUid': 'label', 'createdDate': '2025-12-08T10:00:00Z'},
            {'translationJobUid': 'nightly', 'createdDate': '2026-10-22T03:20:00Z'},
            {'translationJobUid': 'merge', 'createdDate': '2026-10-30T12:00:00Z'},
        ]

        job = OPEN_ISSUES.issue_job(jobs, utc('2026-10-22T08:53:39Z'))

        self.assertEqual(job['translationJobUid'], 'nightly')


if __name__ == '__main__':
    unittest.main()
