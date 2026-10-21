#!/usr/bin/env python3
"""
Opens the Asana task for a Smartling job that needs review, assigned to the platform's triage DRI.

Copyright © 2026 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import os
import re
import sys
import html
import json
import argparse
from datetime import date, timedelta
from typing import Dict, List, Optional
from urllib.parse import urlencode
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ASANA_API = "https://app.asana.com/api/1.0"


def pick_dri(rotation_tasks: List[Dict], today: date) -> Optional[Dict]:
    """Return the assignee of the rotation covering today, or of the next one (weekends fall between rotations)."""
    scheduled = [
        task for task in rotation_tasks
        if task.get('assignee') and task.get('start_on') and task.get('due_on')
    ]
    today_iso = today.isoformat()
    covering = [task for task in scheduled if task['start_on'] <= today_iso <= task['due_on']]
    if covering:
        return covering[0]['assignee']
    upcoming = sorted(
        (task for task in scheduled if task['start_on'] > today_iso),
        key=lambda task: task['start_on']
    )
    return upcoming[0]['assignee'] if upcoming else None


def notes_html(notes: str) -> str:
    """Asana rich text for plain notes: "Label: value" lines get a bold label, and URLs become links."""
    lines = []
    for line in notes.strip().split('\n'):
        line = html.escape(line, quote=True)
        line = re.sub(r'(https?://\S+)', r'<a href="\1">\1</a>', line)
        line = re.sub(r'^([^:<]{1,60}):(\s)', r'<strong>\1:</strong>\2', line)
        lines.append(line)
    return '<body>' + '\n'.join(lines) + '</body>'


def find_section(sections: List[Dict], name: str) -> Optional[str]:
    """Return the GID of the section with this name."""
    return next((section['gid'] for section in sections if section.get('name') == name), None)


class AsanaClient:
    """Minimal Asana API client."""

    def __init__(self, token: str):
        self.token = token

    def _request(self, method: str, path: str, params: Optional[Dict] = None, body: Optional[Dict] = None):
        url = f"{ASANA_API}{path}"
        if params:
            url += f"?{urlencode(params)}"
        data = json.dumps({'data': body}).encode('utf-8') if body is not None else None
        request = Request(url, data=data, method=method, headers={
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
        })
        try:
            with urlopen(request, timeout=30) as response:
                return json.loads(response.read())['data']
        except HTTPError as error:
            try:
                messages = [item.get('message', '') for item in json.loads(error.read()).get('errors', [])]
            except ValueError:
                messages = []
            raise RuntimeError(f"Asana {method} {path} failed with HTTP {error.code}: {'; '.join(messages) or error.reason}") from error

    def rotation_tasks(self, section_id: str, since: date) -> List[Dict]:
        return self._request('GET', f'/sections/{section_id}/tasks', {
            'completed_since': f'{since.isoformat()}T00:00:00Z',
            'opt_fields': 'assignee.name,start_on,due_on',
            'limit': 100,
        })

    def sections(self, project_id: str) -> List[Dict]:
        return self._request('GET', f'/projects/{project_id}/sections', {'opt_fields': 'name'})

    def create_task(self, body: Dict) -> Dict:
        return self._request('POST', '/tasks', {'opt_fields': 'permalink_url'}, body)


def log(message: str):
    print(f"[smartling] {message}", flush=True)


def review_task(client: AsanaClient, args, today: date) -> Dict:
    """Build the review task. Failing to look up the DRI or the section never stops the task from being created."""
    body = {
        'name': args.name,
        'html_notes': notes_html(args.notes),
        'projects': [args.project],
        'due_on': today.isoformat(),
    }

    try:
        section_id = find_section(client.sections(args.project), args.section_name)
        if section_id:
            body['memberships'] = [{'project': args.project, 'section': section_id}]
        else:
            log(f"⚠️ No section named '{args.section_name}', creating the task in the project's default section")
    except Exception as error:  # pylint: disable=broad-except
        log(f"⚠️ Couldn't look up the sections: {error}")

    try:
        dri = pick_dri(client.rotation_tasks(args.rotation_section, today - timedelta(days=14)), today)
        if dri:
            body['assignee'] = dri['gid']
            log(f"👤 Assigning to {dri.get('name', dri['gid'])}, the triage DRI for {today.isoformat()}")
        else:
            log(f"⚠️ No triage DRI scheduled for {today.isoformat()}, leaving the task unassigned")
    except Exception as error:  # pylint: disable=broad-except
        log(f"⚠️ Couldn't look up the triage DRI: {error}")

    if args.assignee:
        body['assignee'] = args.assignee
        log(f"👤 Assigning to {args.assignee} instead (--assignee)")

    return body


def main():
    parser = argparse.ArgumentParser(description='Open the Asana task for a Smartling job that needs review')
    parser.add_argument('--project', required=True, help='Asana project to create the task in')
    parser.add_argument('--section-name', required=True, help='Section to create the task in, e.g. "Incoming: Dev Related Issues"')
    parser.add_argument('--rotation-section', required=True, help='Asana section listing the weekly triage DRI rotation')
    parser.add_argument('--name', required=True)
    parser.add_argument('--notes', required=True, help='Plain text; "Label: value" lines get a bold label, URLs become links')
    parser.add_argument('--assignee', help='Assign to this user (GID, email or "me") instead of the triage DRI')
    parser.add_argument('--dry-run', action='store_true', help='Look everything up and print the task instead of creating it')
    args = parser.parse_args()

    token = os.environ.get('ASANA_ACCESS_TOKEN')
    if not token:
        print("❌ Missing ASANA_ACCESS_TOKEN")
        sys.exit(1)

    client = AsanaClient(token)
    body = review_task(client, args, date.today())
    if args.dry_run:
        log("Dry run, not creating the task:")
        print(json.dumps(body, indent=2, ensure_ascii=False))
        return
    try:
        task = client.create_task(body)
    except RuntimeError as error:
        log(f"❌ {error}")
        sys.exit(1)
    log(f"✅ Created review task: {task.get('permalink_url', task.get('gid'))}")


if __name__ == '__main__':
    main()
