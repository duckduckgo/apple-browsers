#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
SPEC = importlib.util.spec_from_file_location('commit_author', SCRIPTS_DIR / 'commit_author.py')
COMMIT_AUTHOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = COMMIT_AUTHOR
SPEC.loader.exec_module(COMMIT_AUTHOR)

MERGE_COMMIT = 'c' * 40


def pull(login, user_type='User', merge_commit_sha=MERGE_COMMIT):
    return {
        'user': {'login': login, 'type': user_type},
        'merge_commit_sha': merge_commit_sha,
        'html_url': f'https://github.com/duckduckgo/apple-browsers/pull/{len(login)}',
    }


class FakeGitHub:

    def __init__(self, pulls):
        self.pulls = pulls

    def commit_pulls(self, _sha):
        return self.pulls


class PullRequestTests(unittest.TestCase):

    def testWhenACommitWasSquashMergedThenThePullRequestItWasMergedFromIsReturned(self):
        github = FakeGitHub([pull('frosty', merge_commit_sha='d' * 40), pull('brindy')])

        found = COMMIT_AUTHOR.pull_request(github, MERGE_COMMIT)

        self.assertEqual(found['user']['login'], 'brindy')

    def testWhenThereIsNoPullRequestThenNoneIsReturned(self):
        found = COMMIT_AUTHOR.pull_request(FakeGitHub([]), MERGE_COMMIT)

        self.assertIsNone(found)

    def testAppBotsAndDaxmobileAreBots(self):
        users = [{'login': 'dependabot[bot]', 'type': 'Bot'}, {'login': 'daxmobile', 'type': 'User'}, {'login': 'brindy', 'type': 'User'}]

        bots = [COMMIT_AUTHOR.is_bot(user) for user in users]

        self.assertEqual(bots, [True, True, False])


class PagedGitHubClient(COMMIT_AUTHOR.GitHubClient):

    def __init__(self, pages):
        super().__init__('token')
        self.pages = pages
        self.requests = []

    def _get(self, path, params=None):
        self.requests.append((path, params))
        return {'workflow_runs': self.pages[params['page'] - 1]}


class WorkflowRunsTests(unittest.TestCase):

    def testWhenThereAreMoreRunsThanAPageThenEveryPageSinceGoLiveIsRead(self):
        github = PagedGitHubClient([[{'id': run_id} for run_id in range(100)], [{'id': 100}]])

        runs = list(github.workflow_runs('smartling_nightly.yml', 'main', datetime(2026, 11, 5, tzinfo=timezone.utc)))

        self.assertEqual(len(runs), 101)
        self.assertEqual([params['page'] for _, params in github.requests], [1, 2])
        self.assertEqual(github.requests[0][1]['created'], '>=2026-11-05T00:00:00Z')
        self.assertEqual(github.requests[0][1]['branch'], 'main')


class UserMapTests(unittest.TestCase):

    def testWhenTheMapIsParsedThenLoginsMatchWhateverTheirCase(self):
        user_map = COMMIT_AUTHOR.parse_user_map('# iOS\nBrindy: "1201"\nfrosty: 1202  # comment\n\nnot a mapping\n')

        found = [COMMIT_AUTHOR.asana_user(user_map, login) for login in ('brindy', 'Frosty', 'unknown', None)]

        self.assertEqual(found, ['1201', '1202', None, None])


class MergeAuthorTests(unittest.TestCase):

    def testWhenTheAuthorIsAPersonThenTheirAsanaUserAndPullRequestAreReturned(self):
        github = FakeGitHub([pull('Brindy')])

        found = [COMMIT_AUTHOR.merge_author(github, user_map, MERGE_COMMIT) for user_map in ({'brindy': '1201'}, {})]

        self.assertEqual(found, [
            COMMIT_AUTHOR.Author('Brindy', '1201', 'https://github.com/duckduckgo/apple-browsers/pull/6'),
            COMMIT_AUTHOR.Author('Brindy', None, 'https://github.com/duckduckgo/apple-browsers/pull/6'),
        ])

    def testWhenTheCommitHasNoPullRequestByAPersonThenNoAuthorIsReturned(self):
        githubs = [FakeGitHub([]), FakeGitHub([pull('daxmobile')])]

        found = [COMMIT_AUTHOR.merge_author(github, {'daxmobile': '1201'}, MERGE_COMMIT) for github in githubs]

        self.assertEqual(found, [None, None])


if __name__ == '__main__':
    unittest.main()
