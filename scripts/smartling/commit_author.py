"""
Finds who to ask about a commit on main: the author of the pull request it was squash-merged from, and their Asana user.
Run on its own, it writes that author of a merge job's commit to GITHUB_OUTPUT, for the job's review task.

Copyright © 2026 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import os
import re
import sys
import json
import argparse
from dataclasses import dataclass
from pathlib import Path
from datetime import datetime, timezone
from typing import Dict, Iterator, List, Optional
from urllib.parse import urlencode
from http.client import HTTPException
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

GITHUB_API = "https://api.github.com"
REPOSITORY = "duckduckgo/apple-browsers"

# Accounts that merge on someone's behalf, such as translation imports. They can't answer for the strings.
BOT_LOGINS = {'daxmobile'}


@dataclass(frozen=True)
class Author:
    login: str
    asana_gid: Optional[str]
    pull_url: str


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
        except (URLError, TimeoutError, ConnectionError, HTTPException, ValueError) as error:
            raise RuntimeError(f"GitHub GET {path} failed: {type(error).__name__}") from error

    def commit_pulls(self, sha: str) -> List[Dict]:
        return self._get(f'/commits/{sha}/pulls')

    def branch_pulls(self, branch: str) -> List[Dict]:
        owner = self.repository.split('/')[0]
        return self._get('/pulls', {'head': f'{owner}:{branch}', 'state': 'all', 'per_page': 10})

    def workflow_runs(self, workflow: str, branch: str, created_since: datetime) -> Iterator[Dict]:
        created = created_since.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        page = 1
        while True:
            runs = self._get(f'/actions/workflows/{workflow}/runs', {
                'branch': branch, 'status': 'completed', 'created': f'>={created}', 'per_page': 100, 'page': page
            })['workflow_runs']
            yield from runs
            if len(runs) < 100:
                return
            page += 1

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


def merge_author(github: GitHubClient, user_map: Dict[str, str], sha: str) -> Optional[Author]:
    """The person behind a commit on main: the author of its pull request, unless that's a bot."""
    pull = pull_request(github, sha)
    user = (pull or {}).get('user') or {}
    if not user.get('login') or is_bot(user):
        return None
    return Author(login=user['login'], asana_gid=asana_user(user_map, user['login']), pull_url=pull.get('html_url', ''))


def main():
    parser = argparse.ArgumentParser(description="Write the Asana user of a commit's pull request author to GITHUB_OUTPUT")
    parser.add_argument('--sha', required=True)
    parser.add_argument('--user-map', required=True, help='Path to the GitHub to Asana user_map.yml')
    args = parser.parse_args()
    token = os.environ.get('GITHUB_TOKEN')
    if not token:
        print("❌ Missing GITHUB_TOKEN", file=sys.stderr)
        sys.exit(1)
    user_map_path = Path(args.user_map)
    user_map = parse_user_map(user_map_path.read_text(encoding='utf-8') if user_map_path.exists() else '')
    try:
        author = merge_author(GitHubClient(token), user_map, args.sha)
    except RuntimeError as error:
        print(f"❌ {error}", file=sys.stderr)
        sys.exit(1)
    if not author:
        print(f"⚠️ {args.sha[:7]} has no pull request by a person")
    elif not author.asana_gid:
        print(f"⚠️ @{author.login} isn't in the GitHub to Asana user map")
    else:
        print(f"👤 @{author.login} ({author.pull_url})")
    if os.environ.get('GITHUB_OUTPUT') and author:
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write(f"login={author.login}\nasana_gid={author.asana_gid or ''}\npull_url={author.pull_url}\n")


if __name__ == '__main__':
    main()
