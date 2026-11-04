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


class UserMapTests(unittest.TestCase):

    def testWhenTheMapIsParsedThenLoginsMatchWhateverTheirCase(self):
        user_map = COMMIT_AUTHOR.parse_user_map('# iOS\nBrindy: "1201"\nfrosty: 1202  # comment\n\nnot a mapping\n')

        found = [COMMIT_AUTHOR.asana_user(user_map, login) for login in ('brindy', 'Frosty', 'unknown', None)]

        self.assertEqual(found, ['1201', '1202', None, None])


if __name__ == '__main__':
    unittest.main()
