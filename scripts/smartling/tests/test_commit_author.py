#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPTS_DIR = Path(__file__).parents[1]
SPEC = importlib.util.spec_from_file_location('commit_author', SCRIPTS_DIR / 'commit_author.py')
COMMIT_AUTHOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = COMMIT_AUTHOR
SPEC.loader.exec_module(COMMIT_AUTHOR)

MERGE_COMMIT = 'c' * 40


def pull(login, user_type='User', merge_commit_sha=MERGE_COMMIT):
    return {'user': {'login': login, 'type': user_type}, 'merge_commit_sha': merge_commit_sha}


class FakeGitHub:

    def __init__(self, pulls):
        self.pulls = pulls

    def commit_pulls(self, _sha):
        return self.pulls


class PullRequestAuthorTests(unittest.TestCase):

    def testWhenACommitWasSquashMergedThenItsPullRequestsAuthorIsReturned(self):
        github = FakeGitHub([pull('frosty', merge_commit_sha='d' * 40), pull('brindy')])

        login = COMMIT_AUTHOR.pull_request_author(github, MERGE_COMMIT)

        self.assertEqual(login, 'brindy')

    def testWhenTheAuthorIsABotOrThereIsNoPullRequestThenNoOneIsReturned(self):
        cases = {
            'daxmobile': [pull('daxmobile')],
            'app bot': [pull('dependabot[bot]', user_type='Bot')],
            'no pull request': [],
        }
        for case, pulls in cases.items():
            with self.subTest(case):
                login = COMMIT_AUTHOR.pull_request_author(FakeGitHub(pulls), MERGE_COMMIT)

                self.assertIsNone(login)


class UserMapTests(unittest.TestCase):

    def testWhenTheMapIsParsedThenLoginsMatchWhateverTheirCase(self):
        user_map = COMMIT_AUTHOR.parse_user_map('# iOS\nBrindy: "1201"\nfrosty: 1202  # comment\n\nnot a mapping\n')

        found = [COMMIT_AUTHOR.asana_user(user_map, login) for login in ('brindy', 'Frosty', 'unknown', None)]

        self.assertEqual(found, ['1201', '1202', None, None])


if __name__ == '__main__':
    unittest.main()
