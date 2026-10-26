#!/usr/bin/env python3
"""
Finds the Translations subtask of a release's Asana task for the release translations pull request, and keeps it in
line with the release import: assigned to the release DRI, open while the translations are on their way, completed
when the release branch needs no pull request, and commented on when the translations aren't ready.

Copyright © 2026 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import os
import re
import sys
import argparse
from datetime import date, timedelta
from typing import Dict, List, Optional

from asana_review_task import AsanaClient, log, notes_html

RELEASE_SECTIONS = {
    'iOS': '1209802997613372',
    'macOS': '1209802997613373',
}
TEST_BRANCH_TASK_ID = '1219893285200023'
SUBTASK_NAME = 'Translations'
PR_OUTCOMES = {'pr_opened', 'pr_updated'}
NO_PR_COMMENTS = {
    'no_changes': '✅ The release branch already has every translation, so no translations pull request is needed.',
    'pr_closed': '✅ The release branch already has every translation, so the open translations pull request was closed.',
}


def task_url(task_id: str) -> str:
    return f'https://app.asana.com/0/0/{task_id}/f'


def release_version(platform: str, branch: str) -> Optional[str]:
    """Return the version of a release/<platform>/<version> branch, or None for any other branch."""
    match = re.fullmatch(r'release/([^/]+)/([^/]+)', branch)
    return match[2] if match and match[1] == platform.lower() else None


def find_task(tasks: List[Dict], name: str) -> Optional[str]:
    """Return the GID of the task with this name, ignoring case and surrounding spaces."""
    return next((task['gid'] for task in tasks if task.get('name', '').strip().lower() == name.lower()), None)


def translations_task_id(client: AsanaClient, platform: str, branch: str, today: date) -> str:
    """Return the GID of the release task's Translations subtask; a test branch has no release task and gets a fixed task."""
    version = release_version(platform, branch)
    if not version:
        log(f"🧪 {branch} isn't a {platform} release branch, linking the test task")
        return TEST_BRANCH_TASK_ID

    release_task_name = f'{platform} App Release {version}'
    release_task_id = find_task(client.section_tasks(RELEASE_SECTIONS[platform], today - timedelta(days=30)), release_task_name)
    if not release_task_id:
        raise RuntimeError(f"No release task named '{release_task_name}'")
    log(f"📋 Release task: {task_url(release_task_id)}")

    subtask_id = find_task(client.subtasks(release_task_id), SUBTASK_NAME)
    if not subtask_id:
        raise RuntimeError(f"The release task has no {SUBTASK_NAME} subtask")
    return subtask_id


def update_translations_task(client: AsanaClient, task_id: str, outcome: str, notes: str) -> bool:
    """Bring the Translations subtask in line with the import outcome and return whether it was commented on.
    A completed subtask is left alone when no pull request is needed, so the nightly import doesn't comment again."""
    task = client.task(task_id)
    changes = {}
    release_assignee = ((task.get('parent') or {}).get('assignee') or {}).get('gid')
    if not task.get('assignee') and release_assignee:
        changes['assignee'] = release_assignee

    comment = None
    if outcome in PR_OUTCOMES:
        if task.get('completed'):
            changes['completed'] = False
    elif outcome in NO_PR_COMMENTS:
        if task.get('completed'):
            log(f"✅ The {SUBTASK_NAME} task is already completed")
            return False
        changes['completed'] = True
        comment = NO_PR_COMMENTS[outcome]
    elif notes:
        comment = notes

    if comment:
        client.add_comment(task_id, notes_html(comment))
        log(f"💬 Commented on the {SUBTASK_NAME} task")
    if changes:
        client.update_task(task_id, changes)
        log(f"✏️ Updated the {SUBTASK_NAME} task: {', '.join(sorted(changes))}")
    return bool(comment)


def write_outputs(**outputs: str):
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.writelines(f'{key}={value}\n' for key, value in outputs.items())


def main():
    parser = argparse.ArgumentParser(description="Find and update the release task's Translations subtask for the release translations pull request")
    commands = parser.add_subparsers(dest='command', required=True)
    find = commands.add_parser('find', help='Write the URL and GID of the Translations subtask to the task_url and task_id outputs')
    find.add_argument('--platform', required=True, choices=sorted(RELEASE_SECTIONS))
    find.add_argument('--release-branch', required=True)
    update = commands.add_parser('update', help='Assign, reopen, complete or comment on the Translations subtask after an import')
    update.add_argument('--task-id', required=True)
    update.add_argument('--outcome', required=True, help='Outcome of smartling_release_import.sh')
    update.add_argument('--notes', default='', help='Plain text to comment for any other outcome, e.g. the not-ready details')
    args = parser.parse_args()

    token = os.environ.get('ASANA_ACCESS_TOKEN')
    if not token:
        print("❌ Missing ASANA_ACCESS_TOKEN")
        sys.exit(1)

    client = AsanaClient(token)
    try:
        if args.command == 'find':
            task_id = translations_task_id(client, args.platform, args.release_branch, date.today())
            log(f"✅ {SUBTASK_NAME} task: {task_url(task_id)}")
            write_outputs(task_url=task_url(task_id), task_id=task_id)
        else:
            commented = update_translations_task(client, args.task_id, args.outcome, args.notes)
            write_outputs(commented=str(commented).lower())
    except RuntimeError as error:
        log(f"❌ {error}")
        sys.exit(1)


if __name__ == '__main__':
    main()
