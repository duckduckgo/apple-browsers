#!/usr/bin/env python3

import asyncio
import contextlib
import importlib.util
import io
import json
import sys
import unittest
from unittest import mock
from urllib.error import URLError
from argparse import Namespace
from datetime import datetime, timezone
from pathlib import Path

import aiohttp


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
ADDING_DIFF = f'@@ -1,2 +1,3 @@\n context\n+"{KEY}" = "{ENGLISH}";\n context\n'
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

    def __init__(self, issues, jobs=None, key=KEY, missing_strings=()):
        self.issues = issues
        self.key = key
        self.missing_strings = set(missing_strings)
        self.jobs = jobs or {'nightly': {'translationJobUid': 'nightly', 'jobName': 'Nightly iOS - 2026-11-03', 'createdDate': '2026-11-03T03:20:00Z'}}
        self.creds = Namespace(project_id='ios-project')

    async def list_open_source_issues(self):
        return self.issues

    async def get_source_string(self, hashcode):
        if hashcode in self.missing_strings:
            raise RuntimeError('HTTP 500: Internal Server Error')
        return {'stringText': ENGLISH, 'keys': [{'key': self.key, 'fileUri': 'main/en.xliff'}]}

    async def get_job(self, job_uid):
        if job_uid == 'unavailable':
            raise RuntimeError('HTTP 503: Service Unavailable')
        if job_uid not in self.jobs:
            raise RuntimeError('HTTP 404: Not Found')
        return self.jobs[job_uid]


class FakeAsana:

    def __init__(self, tasks=None, rejected_assignees=(), failing_issues=()):
        self.tasks = tasks or []
        self.rejected_assignees = set(rejected_assignees)
        self.failing_issues = set(failing_issues)
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
        if any(f'#{number} ' in body['name'] for number in self.failing_issues):
            raise RuntimeError('Asana POST /tasks failed with HTTP 500: Server Error')
        self.created.append(body)
        return {'gid': str(len(self.created)), 'assignee': {'gid': body['assignee']} if body.get('assignee') else None}


class FakeGitHub:

    def __init__(self, runs=None, commit_pulls=None, branch_pulls=None, failing=False):
        self.runs = runs or []
        self.failing = failing
        self.pulls_by_commit = commit_pulls if commit_pulls is not None else {STRING_COMMIT: [pull('frosty')]}
        self.pulls_by_branch = branch_pulls or {}

    def workflow_runs(self, _workflow, _branch, _created_since):
        return [{'id': run['id']} for run in self.runs]

    def run_jobs(self, run_id):
        return next(run['jobs'] for run in self.runs if run['id'] == run_id)

    def commit_pulls(self, sha):
        if self.failing:
            raise RuntimeError('GitHub GET /commits/sha/pulls failed with HTTP 403: rate limit exceeded')
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


def run(smartling, asana, github=None, git=None, user_map=None, dry_run=False, since=None):
    """Run the job with the given clients, returning the summary rows, whether it failed, and the log."""
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        rows, failed = asyncio.run(OPEN_ISSUES.run(
            args(dry_run=dry_run, since=since), smartling, asana, github or FakeGitHub(runs=[nightly_run(1, 'success')]),
            git or FakeGit(), {'frosty': 'frosty-gid'} if user_map is None else user_map
        ))
    return rows, failed, output.getvalue()


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

    def testWhenSinceIsBeforeGoLiveThenOnlyADryRunStartsThere(self):
        for dry_run, expected in ((False, NOT_BEFORE), (True, '2026-10-01T00:00:00Z')):
            with self.subTest(dry_run=dry_run):
                run_args = args(dry_run=dry_run, since='2026-10-01T00:00:00Z')

                start = OPEN_ISSUES.window(run_args, FakeGitHub())

                self.assertEqual(start, utc(expected))


class OpenIssueTaskTests(unittest.TestCase):

    def testWhenARunStartsAfterThePendingWindowThenNeitherItNorTheNextNightSkipsTheIssue(self):
        override_started = '2026-11-04T03:00:00Z'
        first_asana = FakeAsana()

        first_rows, _, _ = run(FakeSmartling([smartling_issue()]), first_asana, since='2026-11-04T00:00:00Z')

        next_night = FakeGitHub(runs=[nightly_run(2, 'success', override_started), nightly_run(1, 'success')])
        second_asana = FakeAsana(tasks=[asana_task(3600, override_started)])
        second_rows, _, _ = run(FakeSmartling([smartling_issue()]), second_asana, github=next_night)

        self.assertEqual(first_rows, ['| #3600 | opened a task | @frosty (added the string) |'])
        self.assertEqual(len(first_asana.created) + len(second_asana.created), 1)
        self.assertEqual(second_rows, [])

    def testWhenARunStartsBeforeThePendingWindowThenItLooksFromThere(self):
        start = OPEN_ISSUES.window(args(since='2026-11-02T00:00:00Z'), FakeGitHub(runs=[nightly_run(1, 'success')]))

        self.assertEqual(start, utc('2026-11-02T00:00:00Z'))

    def testWhenAnIssueIsNewThenItsTaskGoesToWhoeverAddedTheString(self):
        asana = FakeAsana()

        rows, _, _ = run(FakeSmartling([smartling_issue()]), asana)

        self.assertEqual(len(asana.created), 1)
        self.assertEqual(asana.created[0]['name'], f'Smartling open issue #3600 (iOS): {KEY}')
        self.assertEqual(asana.created[0]['assignee'], 'frosty-gid')
        self.assertEqual(asana.created[0]['memberships'], [{'project': 'ios-app-development', 'section': 'incoming'}])
        self.assertIn(ISSUE_TEXT, asana.created[0]['html_notes'])
        self.assertEqual(rows, ['| #3600 | opened a task | @frosty (added the string) |'])

    def testWhenSmartlingListsAnIssueTwiceThenOneTaskIsOpened(self):
        asana = FakeAsana()

        rows, _, _ = run(FakeSmartling([smartling_issue(), smartling_issue()]), asana)

        self.assertEqual(len(asana.created), 1)
        self.assertEqual(rows, ['| #3600 | opened a task | @frosty (added the string) |'])

    def testWhenAnIssueWasOpenedBeforeTheLastSuccessfulNightThenNoTaskIsOpened(self):
        asana = FakeAsana()

        rows, _, _ = run(FakeSmartling([smartling_issue(created='2026-11-02T10:00:00Z')]), asana)

        self.assertEqual(asana.created, [])
        self.assertEqual(rows, [])

    def testWhenARerunFindsTheIssuesTaskThenNoSecondTaskIsOpened(self):
        asana = FakeAsana(tasks=[asana_task(3600, '2026-11-04T03:21:00Z')])

        rows, _, _ = run(FakeSmartling([smartling_issue()]), asana)

        self.assertEqual(asana.created, [])
        self.assertEqual(rows, ['| #3600 | already has a task | |'])

    def testWhenAnIssueIsReopenedAfterItsTaskThenANewTaskIsOpened(self):
        asana = FakeAsana(tasks=[asana_task(3600, '2026-11-03T12:00:00Z')])
        reopened = smartling_issue(created='2026-10-20T10:00:00Z', reopened_date='2026-11-03T15:00:00Z')

        run(FakeSmartling([reopened]), asana)

        self.assertEqual(len(asana.created), 1)

    def testWhenTheStringsAuthorIsABotOrUnmappedThenTheTriageDRIGetsTheTask(self):
        translate_job = {'label': {'translationJobUid': 'label', 'jobName': 'anya/sync-restore', 'createdDate': '2026-11-03T09:00:00Z'}}
        cases = {
            'bot': (FakeSmartling([smartling_issue()]), FakeGitHub(runs=[nightly_run(1, 'success')], commit_pulls={STRING_COMMIT: [pull('daxmobile')]}), None),
            'unmapped': (FakeSmartling([smartling_issue()]), None, {}),
            'unmapped before a mapped author': (
                FakeSmartling([smartling_issue(job_uid='label')], jobs=translate_job),
                FakeGitHub(runs=[nightly_run(1, 'success')], branch_pulls={'anya/sync-restore': [pull('anya', 7100)]}),
                None,
            ),
        }
        for case, (smartling, github, user_map) in cases.items():
            with self.subTest(case):
                asana = FakeAsana()

                run(smartling, asana, github=github, user_map=user_map)

                self.assertEqual(asana.created[0]['assignee'], 'dri')

    def testWhenAsanaRejectsTheAuthorThenTheTriageDRIGetsTheTask(self):
        asana = FakeAsana(rejected_assignees={'frosty-gid'})

        rows, _, _ = run(FakeSmartling([smartling_issue()]), asana)

        self.assertEqual([task['assignee'] for task in asana.created], ['dri'])
        self.assertEqual(rows, ['| #3600 | opened a task | the triage DRI |'])

    def testWhenOneIssueFailsThenTheOthersStillGetTasksAndTheRunFails(self):
        issues = [
            smartling_issue(3600), smartling_issue(3601, job_uid='unavailable'), smartling_issue(3602), smartling_issue(3603, job_uid='deleted'),
        ]
        smartling = FakeSmartling(issues, missing_strings={'hash-3600'})
        asana = FakeAsana(failing_issues={3602})

        rows, failed, _ = run(smartling, asana)

        self.assertTrue(failed)
        self.assertEqual([task['name'] for task in asana.created], [f'Smartling open issue #3603 (iOS): {KEY}'])
        self.assertEqual(rows, [
            '| #3600 | failed, retried next night | |',
            '| #3601 | failed, retried next night | |',
            '| #3602 | failed, retried next night | @frosty (added the string) |',
            '| #3603 | opened a task | @frosty (added the string) |',
        ])

    def testWhenGitHubFailsThenTheIssueIsRetriedInsteadOfGoingToTheTriageDRI(self):
        asana = FakeAsana()
        github = FakeGitHub(runs=[nightly_run(1, 'success')], failing=True)

        rows, failed, _ = run(FakeSmartling([smartling_issue()]), asana, github=github)

        self.assertTrue(failed)
        self.assertEqual(asana.created, [])
        self.assertEqual(rows, ['| #3600 | failed, retried next night | |'])

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

        rows, _, _ = run(FakeSmartling([smartling_issue()]), asana, dry_run=True)

        self.assertEqual(asana.created, [])
        self.assertEqual(rows, ['| #3600 | would open a task | @frosty (added the string) |'])

    def testWhenTheKeyIsTheEnglishTextThenTheLogAndSummaryStillDontShowIt(self):
        smartling = FakeSmartling([smartling_issue()], key=ENGLISH)

        rows, _, log = run(smartling, FakeAsana(), git=FakeGit(diffs={STRING_COMMIT: f'@@ -1 +1 @@\n+Text("{ENGLISH}")\n'}))

        self.assertNotIn(ISSUE_TEXT, log)
        self.assertNotIn(ENGLISH, log + '\n'.join(rows))

    def testWhenGitFailsThenItsErrorDoesntShowTheSearchedText(self):
        with self.assertRaises(RuntimeError) as failure:
            OPEN_ISSUES.Git()._run('log', '-S', ENGLISH, 'no-such-ref')  # pylint: disable=protected-access

        self.assertNotIn(ENGLISH, str(failure.exception))


class TransportFailureTests(unittest.TestCase):
    """Use the real client boundaries so transport errors are not hidden by RuntimeError-only fakes."""

    def testSmartlingTimeoutOrDisconnectLeavesOtherIssuesProcessable(self):
        for stage in ('string', 'job'):
            for error in (asyncio.TimeoutError(), aiohttp.ServerDisconnectedError('private response detail')):
                with self.subTest(stage=stage, error=type(error).__name__):
                    client = OPEN_ISSUES.SmartlingClient(OPEN_ISSUES.Credentials('user', 'secret', 'project'))
                    client.token = 'token'
                    client.token_expiry = datetime.max
                    client.session = mock.Mock()
                    response = mock.MagicMock()
                    response.__aenter__.side_effect = error
                    client.session.request.return_value = response
                    smartling = FakeSmartling([smartling_issue(3600, job_uid='broken'), smartling_issue(3601)])
                    if stage == 'string':
                        normal_lookup = smartling.get_source_string

                        async def get_string(hashcode):
                            if hashcode == 'hash-3600':
                                return await client.get_source_string(hashcode)
                            return await normal_lookup(hashcode)

                        smartling.get_source_string = get_string
                    else:
                        normal_lookup = smartling.get_job

                        async def get_job(uid):
                            if uid == 'broken':
                                return await client.get_job(uid)
                            return await normal_lookup(uid)

                        smartling.get_job = get_job
                    asana = FakeAsana()

                    rows, failed, log = run(smartling, asana)

                    self.assertTrue(failed)
                    self.assertEqual(len(asana.created), 1)
                    self.assertIn('#3601 ', asana.created[0]['name'])
                    self.assertIn('| #3600 | failed, retried next night | |', rows)
                    self.assertNotIn('private response detail', log)

    def testSmartlingNonJSONErrorLeavesOtherIssuesProcessable(self):
        client = OPEN_ISSUES.SmartlingClient(OPEN_ISSUES.Credentials('user', 'secret', 'project'))
        client.token = 'token'
        client.token_expiry = datetime.max
        client.session = mock.Mock()
        html = mock.MagicMock(status=503, reason='Service Unavailable')
        html.text = mock.AsyncMock(return_value='<html>private response detail</html>')
        response = mock.MagicMock()
        response.__aenter__.return_value = html
        client.session.request.return_value = response
        smartling = FakeSmartling([smartling_issue(3600), smartling_issue(3601)])
        normal_lookup = smartling.get_source_string

        async def get_string(hashcode):
            if hashcode == 'hash-3600':
                return await client.get_source_string(hashcode)
            return await normal_lookup(hashcode)

        smartling.get_source_string = get_string
        asana = FakeAsana()

        rows, failed, log = run(smartling, asana)

        self.assertTrue(failed)
        self.assertEqual(len(asana.created), 1)
        self.assertIn('#3601 ', asana.created[0]['name'])
        self.assertIn('| #3600 | failed, retried next night | |', rows)
        self.assertIn('HTTP 503: Service Unavailable', log)
        self.assertNotIn('private response detail', log)

    def testNonJSONSuccessResponsesBecomeSanitizedRuntimeErrors(self):
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b'<html>private response detail</html>'
        github = OPEN_ISSUES.GitHubClient('token')
        asana = OPEN_ISSUES.AsanaClient('token')

        for call, module_globals in ((lambda: github.commit_pulls('sha'), github._get.__globals__),
                                     (lambda: asana.create_task({}), asana._send.__globals__)):
            with self.subTest(client=call), mock.patch.dict(module_globals, urlopen=mock.Mock(return_value=response)):
                with self.assertRaises(RuntimeError) as failure:
                    call()
                self.assertNotIn('private response detail', str(failure.exception))

    def testGitHubTransportFailureDoesNotAssignAFallbackOrStopOtherIssues(self):
        for error in (TimeoutError(), URLError('private request detail')):
            with self.subTest(error=type(error).__name__):
                github = FakeGitHub(runs=[nightly_run(1, 'success')])
                client = OPEN_ISSUES.GitHubClient('token')
                github.commit_pulls = client.commit_pulls
                response = mock.MagicMock()
                response.__enter__.return_value.read.return_value = json.dumps([pull('frosty')]).encode()
                opener = mock.Mock(side_effect=[error, response])
                asana = FakeAsana()

                with mock.patch.dict(client._get.__globals__, urlopen=opener):
                    rows, failed, log = run(FakeSmartling([smartling_issue(3600), smartling_issue(3601)]), asana, github=github)

                self.assertTrue(failed)
                self.assertEqual([task['assignee'] for task in asana.created], ['frosty-gid'])
                self.assertIn('| #3600 | failed, retried next night | |', rows)
                self.assertIn('#3601 ', asana.created[0]['name'])
                self.assertNotIn('private request detail', log)

    def testAsanaTransportFailureDoesNotRetryThePostWithAFallbackAssignee(self):
        for error in (TimeoutError(), URLError('private request detail')):
            with self.subTest(error=type(error).__name__):
                client = OPEN_ISSUES.AsanaClient('token')
                asana = FakeAsana()
                asana.create_task = client.create_task
                response = mock.MagicMock()
                response.__enter__.return_value.read.return_value = json.dumps({
                    'data': {'gid': 'task', 'assignee': {'gid': 'frosty-gid'}},
                }).encode()
                opener = mock.Mock(side_effect=[error, response])

                with mock.patch.dict(client._send.__globals__, urlopen=opener):
                    rows, failed, log = run(FakeSmartling([smartling_issue(3600), smartling_issue(3601)]), asana)

                self.assertTrue(failed)
                self.assertEqual(opener.call_count, 2)
                self.assertIn('| #3600 | failed, retried next night | @frosty (added the string) |', rows)
                self.assertIn('| #3601 | opened a task | @frosty (added the string) |', rows)
                self.assertNotIn('private request detail', log)


class StringAttributionTests(unittest.TestCase):

    def testWhenTheTextIsAddedInTheKeysEntryThenTheCommitAddedTheString(self):
        diffs = {
            'strings file': f'@@ -1 +1,2 @@\n "other.key" = "Other";\n+"{KEY}" = "{ENGLISH}";\n',
            'swift': f'@@ -1 +1,3 @@\n context\n+    NSLocalizedString("{KEY}",\n+                      value: "{ENGLISH}",\n',
            'string catalog': (
                f'@@ -1 +1,6 @@\n+    "{KEY}" : {{\n+      "localizations" : {{\n+        "en" : {{\n'
                f'+          "stringUnit" : {{\n+            "state" : "translated",\n+            "value" : "{ENGLISH}"\n'
            ),
        }
        for case, diff in diffs.items():
            with self.subTest(case):
                added = OPEN_ISSUES.adds_string(diff, [ENGLISH], [KEY])

                self.assertTrue(added)

    def testWhenTheTextIsShortenedThenTheCommitAddedTheString(self):
        diff = f'@@ -1 +1 @@\n-"{KEY}" = "{ENGLISH} now";\n+"{KEY}" = "{ENGLISH}";\n'

        added = OPEN_ISSUES.adds_string(diff, [ENGLISH], [KEY])

        self.assertTrue(added)

    def testWhenTheSameTextIsAddedUnderAnotherKeyNextToTheKeyThenTheCommitDidntAddTheString(self):
        diffs = {
            'another key': f'@@ -1 +1,2 @@\n "{KEY}" = "{ENGLISH}";\n+"other.key" = "{ENGLISH}";\n',
            'a longer key': f'@@ -1 +1,2 @@\n "{KEY}" = "{ENGLISH}";\n+"{KEY}.tooltip" = "{ENGLISH}";\n',
            'a key like a catalog field': f'@@ -1 +1,2 @@\n "{KEY}" = "{ENGLISH}";\n+"value" = "{ENGLISH}";\n',
            'a catalog key that starts with the key': f'@@ -1 +1,2 @@\n+    "{KEY}, longer" : {{\n+      "value" : "{ENGLISH}"\n',
            'an entry moved to another file': (
                f'@@ -1,2 +1 @@\n context\n-"{KEY}" = "{ENGLISH}";\n@@ -1 +1,2 @@\n context\n+"{KEY}" = "{ENGLISH}";\n'
            ),
        }
        for case, diff in diffs.items():
            with self.subTest(case):
                added = OPEN_ISSUES.adds_string(diff, [ENGLISH], [KEY])

                self.assertFalse(added)

    def testWhenOnlyTheKeyIsSearchedThenALongerKeyDoesntCount(self):
        diffs = {f'"{KEY}" = "Other text";': True, f'"{KEY}.tooltip" = "Other text";': False}
        for line, expected in diffs.items():
            with self.subTest(line):
                added = OPEN_ISSUES.adds_string(f'@@ -1 +1,2 @@\n context\n+{line}\n', [], [KEY])

                self.assertEqual(added, expected)

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

    def testWhenNoJobExistedByTheIssueThenItHasNoJob(self):
        jobs = [{'translationJobUid': 'label', 'createdDate': '2026-10-30T12:00:00Z'}]

        job = OPEN_ISSUES.issue_job(jobs, utc('2026-10-22T08:53:39Z'))

        self.assertEqual(job, {})


if __name__ == '__main__':
    unittest.main()
