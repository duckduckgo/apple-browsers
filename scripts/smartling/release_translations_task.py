#!/usr/bin/env python3
"""
Finds the Translations subtask of a release's Asana task and writes its URL to the step's task_url output for the
release translations pull request.

Copyright © 2026 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import os
import re
import sys
import argparse
from datetime import date, timedelta
from typing import Dict, List, Optional

from asana_review_task import AsanaClient, log

RELEASE_SECTIONS = {
    'iOS': '1209802997613372',
    'macOS': '1209802997613373',
}
TEST_BRANCH_TASK_ID = '1219536424657556'
SUBTASK_NAME = 'Translations'


def task_url(task_id: str) -> str:
    return f'https://app.asana.com/0/0/{task_id}/f'


def release_version(platform: str, branch: str) -> Optional[str]:
    """Return the version of a release/<platform>/<version> branch, or None for any other branch."""
    match = re.fullmatch(r'release/([^/]+)/([^/]+)', branch)
    return match[2] if match and match[1] == platform.lower() else None


def find_task(tasks: List[Dict], name: str) -> Optional[str]:
    """Return the GID of the task with this name, ignoring case and surrounding spaces."""
    return next((task['gid'] for task in tasks if task.get('name', '').strip().lower() == name.lower()), None)


def translations_task_url(client: AsanaClient, platform: str, branch: str, today: date) -> str:
    """Return the URL of the release task's Translations subtask; a test branch has no release task and gets a fixed task."""
    version = release_version(platform, branch)
    if not version:
        log(f"🧪 {branch} isn't a {platform} release branch, linking the test task")
        return task_url(TEST_BRANCH_TASK_ID)

    release_task_name = f'{platform} App Release {version}'
    release_task_id = find_task(client.section_tasks(RELEASE_SECTIONS[platform], today - timedelta(days=30)), release_task_name)
    if not release_task_id:
        raise RuntimeError(f"No release task named '{release_task_name}'")
    log(f"📋 Release task: {task_url(release_task_id)}")

    subtask_id = find_task(client.subtasks(release_task_id), SUBTASK_NAME)
    if not subtask_id:
        raise RuntimeError(f"The release task has no {SUBTASK_NAME} subtask")
    return task_url(subtask_id)


def main():
    parser = argparse.ArgumentParser(description="Find the release task's Translations subtask for the release translations pull request")
    parser.add_argument('--platform', required=True, choices=sorted(RELEASE_SECTIONS))
    parser.add_argument('--release-branch', required=True)
    args = parser.parse_args()

    token = os.environ.get('ASANA_ACCESS_TOKEN')
    if not token:
        print("❌ Missing ASANA_ACCESS_TOKEN")
        sys.exit(1)

    try:
        url = translations_task_url(AsanaClient(token), args.platform, args.release_branch, date.today())
    except RuntimeError as error:
        log(f"❌ {error}")
        sys.exit(1)

    log(f"✅ {SUBTASK_NAME} task: {url}")
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write(f'task_url={url}\n')


if __name__ == '__main__':
    main()
