"""
Finds who to ask about a commit on main: the author of the pull request it was squash-merged from, and their Asana user.

Copyright © 2026 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import re
import json
from typing import Dict, List, Optional
from urllib.parse import urlencode
from urllib.error import HTTPError
from urllib.request import Request, urlopen

GITHUB_API = "https://api.github.com"
REPOSITORY = "duckduckgo/apple-browsers"

# Accounts that merge on someone's behalf, such as translation imports. They can't answer for the strings.
BOT_LOGINS = {'daxmobile'}


class GitHubClient:
    """Minimal GitHub REST API client."""

    def __init__(self, token: str, repository: str = REPOSITORY):
        self.token = token
        self.repository = repository

    def _get(self, path: str, params: Optional[Dict] = None):
        url = f"{GITHUB_API}/repos/{self.repository}{path}"
        if params:
            url += f"?{urlencode(params)}"
        request = Request(url, headers={
            'Authorization': f'Bearer {self.token}',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
        })
        try:
            with urlopen(request, timeout=30) as response:
                return json.loads(response.read())
        except HTTPError as error:
            raise RuntimeError(f"GitHub GET {path} failed with HTTP {error.code}: {error.reason}") from error

    def commit_pulls(self, sha: str) -> List[Dict]:
        return self._get(f'/commits/{sha}/pulls')

    def branch_pulls(self, branch: str) -> List[Dict]:
        owner = self.repository.split('/')[0]
        return self._get('/pulls', {'head': f'{owner}:{branch}', 'state': 'all', 'per_page': 10})

    def workflow_runs(self, workflow: str, branch: str) -> List[Dict]:
        return self._get(f'/actions/workflows/{workflow}/runs', {
            'branch': branch, 'status': 'completed', 'per_page': 30
        })['workflow_runs']

    def run_jobs(self, run_id: int) -> List[Dict]:
        return self._get(f'/actions/runs/{run_id}/jobs', {'per_page': 100})['jobs']


def is_bot(user: Dict) -> bool:
    return user.get('type') == 'Bot' or user.get('login') in BOT_LOGINS


def pull_request(github: GitHubClient, sha: str) -> Optional[Dict]:
    """The pull request a commit was merged from, preferring the one whose merge commit it is."""
    pulls = github.commit_pulls(sha)
    return next((pull for pull in pulls if pull.get('merge_commit_sha') == sha), pulls[0] if pulls else None)


def parse_user_map(text: str) -> Dict[str, str]:
    """GitHub login → Asana user GID, from internal-github-asana-utils' flat user_map.yml."""
    user_map = {}
    for line in text.splitlines():
        match = re.match(r'''^\s*["']?([A-Za-z0-9-]+)["']?\s*:\s*["']?(\d+)["']?\s*(#.*)?$''', line)
        if match:
            user_map[match[1].lower()] = match[2]
    return user_map


def asana_user(user_map: Dict[str, str], login: Optional[str]) -> Optional[str]:
    return user_map.get(login.lower()) if login else None
