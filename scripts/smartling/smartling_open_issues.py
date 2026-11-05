#!/usr/bin/env python3
"""
Opens one Asana task for each new Smartling issue on an English string, such as a translator's question, assigned to
the author of the pull request that added the string. The person replies in Smartling; nothing is tracked after that.

Runs nightly. It only looks at issues opened or reopened since this job last succeeded, so an issue gets its task
once and later nights leave it alone. It also skips an issue that already has a task opened since, for reruns.

The repository is public, so the log and the job summary never carry an issue's text, the English text or the key,
which can be the English text: only issue numbers and GitHub logins. The rest goes into the Asana task.

Copyright © 2026 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import os
import re
import sys
import json
import asyncio
import argparse
import subprocess
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).parent))

from asana_review_task import AsanaClient, create_task, find_section, notes_html, pick_dri  # noqa: E402
from commit_author import GitHubClient, asana_user, is_bot, parse_user_map, pull_request  # noqa: E402
from localization_tool import Credentials, SmartlingClient, job_url  # noqa: E402

TASK_NAME_PREFIX = "Smartling open issue"
TASK_NUMBER = re.compile(rf'^{TASK_NAME_PREFIX} #(\d+) ')
# "Merge iOS - 2026-11-04 12:28 01b1c7e": the commit main was at when the merge job was submitted.
MERGE_JOB_COMMIT = re.compile(r'^Merge \S+ - \S+ \S+ ([0-9a-f]{7,40})$')
# "pikor/project-11/ump-translations-2026-08-19": a pull request's /translate job, named after its branch. Its strings
# are submitted before they're merged. Older jobs were named by hand, often after the branch without a date.
LABEL_JOB_BRANCH = re.compile(r'^(\S+?)(?:-\d{4}-\d{2}-\d{2})?$')
# Storyboard and XIB keys are "<object id>.<property>", and the file has the id on the text's line.
INTERFACE_BUILDER_KEY = re.compile(r'^([A-Za-z0-9]{3}-[A-Za-z0-9]{2}-[A-Za-z0-9]{3})\.')
# Plural variants are "/<key>:dict/<rule>:dict/…".
PLURAL_KEY = re.compile(r'^/(.+?):dict/')
# Where an entry starts: `"key" = "…"` in a strings file, `"key" : {` in a string catalog, or NSLocalizedString("key".
# In a catalog, its own fields and its locales also look like `"name" :`, so they don't count there.
KEY_DECLARATION = re.compile(r'^.\s*"([^"]+)"\s*([:=])|NSLocalizedString\(\s*"([^"]+)"')
CATALOG_FIELDS = {
    'comment', 'extractionState', 'localizations', 'stringUnit', 'state', 'value', 'variations', 'plural', 'device',
    'substitutions', 'argNum', 'formatSpecifier', 'zero', 'one', 'two', 'few', 'many', 'other', 'sourceLanguage',
    'strings', 'version', 'shouldTranslate',
}
LOCALE = re.compile(r'^[a-z]{2,3}(?:[-_][A-Za-z0-9]+)*$')
PLATFORM_PATHS = {'iOS': ['iOS', 'SharedPackages'], 'macOS': ['macOS', 'SharedPackages']}
MAX_CANDIDATE_COMMITS = 30


@dataclass
class OpenIssue:
    number: int
    created_at: datetime
    opened_at: datetime  # When it was created, or reopened
    reopened: bool
    subtype: str
    text: str
    english: str
    key: str
    job_uid: str  # The job the issue was raised in, empty if unknown
    job_name: str


@dataclass
class Person:
    login: str
    asana_gid: str
    pull_url: str
    source: str  # How they were found, for the log


def log(message: str):
    print(f"[smartling] {message}", flush=True)


def parse_time(value: str) -> datetime:
    """An ISO time or date, in UTC unless it says otherwise."""
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def opened_at(issue: Dict) -> datetime:
    """When the issue started waiting for an answer: when it was reopened, or else created."""
    if issue.get('reopened') and issue.get('reopenedDate'):
        return parse_time(issue['reopenedDate'])
    return parse_time(issue['createdDate'])


def window_start(github: GitHubClient, workflow: str, job_name: str, not_before: datetime) -> datetime:
    """When this platform's job last succeeded on main, so this run picks up where it left off. A failed or skipped
    night widens the window instead of losing issues. Dry runs have another job name, so they never count."""
    for run in github.workflow_runs(workflow, 'main'):
        job = next((job for job in github.run_jobs(run['id']) if job.get('name') == job_name), None)
        if job and job.get('conclusion') == 'success' and job.get('started_at'):
            return max(parse_time(job['started_at']), not_before)
    return not_before


def main_key(source_string: Dict) -> str:
    """The string's key in main's file. Smartling keeps the string under every file URI it was ever uploaded with."""
    keys = source_string.get('keys') or []
    main = next((key for key in keys if (key.get('fileUri') or '').startswith('main/')), None)
    return ((main or (keys[0] if keys else {})).get('key')) or ''


def issue_job(jobs: List[Dict], created_at: datetime) -> Dict:
    """The job the issue was raised in: the newest of the string's jobs that existed by then, or none if Smartling no
    longer has it. The string may have been in older jobs, such as a pull request's /translate job, and in newer ones
    since, which never count: a later /translate job would send the task to the wrong person."""
    existing = [job for job in jobs if job.get('createdDate') and parse_time(job['createdDate']) <= created_at]
    return max(existing, key=lambda job: job['createdDate'], default={})


async def issue_jobs(smartling: SmartlingClient, issue: Dict) -> List[Dict]:
    """The string's jobs that Smartling still has. A deleted job is skipped for good, so it can't fail every night;
    any other error is raised, so that a transient one doesn't send the task to the wrong person."""
    jobs = []
    for job_uid in issue.get('jobUids') or []:
        try:
            jobs.append(await smartling.get_job(job_uid))
        except RuntimeError as error:
            if not str(error).startswith('HTTP 404'):
                raise
            log(f"⚠️ #{issue['issueNumber']}: one of its jobs no longer exists, leaving it out")
    return jobs


async def load_issues(smartling: SmartlingClient, since: datetime) -> Tuple[List[OpenIssue], List[int]]:
    """The open issues on English strings that were opened or reopened since then, oldest first, and the numbers of
    those whose string or jobs couldn't be loaded."""
    issues, failed = [], []
    for issue in await smartling.list_open_source_issues():
        if opened_at(issue) < since:
            continue
        try:
            source_string = await smartling.get_source_string(issue['string']['hashcode']) or {}
            jobs = await issue_jobs(smartling, issue)
        except RuntimeError as error:
            log(f"❌ #{issue['issueNumber']}: couldn't load its string or jobs: {error}")
            failed.append(issue['issueNumber'])
            continue
        job = issue_job(jobs, parse_time(issue['createdDate']))
        issues.append(OpenIssue(
            number=issue['issueNumber'],
            created_at=parse_time(issue['createdDate']),
            opened_at=opened_at(issue),
            reopened=bool(issue.get('reopened')),
            subtype=issue.get('issueSubTypeCode') or '',
            text=issue.get('issueText') or '',
            english=source_string.get('stringText') or source_string.get('parsedStringText') or '',
            key=main_key(source_string),
            job_uid=job.get('translationJobUid', ''),
            job_name=job.get('jobName', ''),
        ))
    return sorted(issues, key=lambda issue: issue.opened_at), failed


def has_task(tasks: List[Dict], issue: OpenIssue) -> bool:
    """Whether the issue already has a task opened since it was opened or reopened."""
    for task in tasks:
        match = TASK_NUMBER.match(task.get('name') or '')
        if match and int(match[1]) == issue.number and parse_time(task['created_at']) >= issue.opened_at:
            return True
    return False


class Git:
    """The git history of the checkout, for finding the commit that added a string."""

    def _run(self, *args: str) -> str:
        """Run git. A failure names only the subcommand: the arguments can hold the English text."""
        result = subprocess.run(['git', *args], check=False, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"git {args[0]} failed with exit code {result.returncode}")
        return result.stdout

    def ensure_history(self):
        """Fetch main's whole history once, if the checkout is shallow, so that the search reaches older commits."""
        if self._run('rev-parse', '--is-shallow-repository').strip() == 'true':
            log("⏳ Fetching main's history to find who added each string")
            self._run('fetch', '--quiet', '--unshallow', 'origin', 'main')

    def shallow_commits(self) -> set:
        shallow = Path(self._run('rev-parse', '--git-path', 'shallow').strip())
        return set(shallow.read_text().split()) if shallow.exists() else set()

    def commits_changing(self, text: str, paths: List[str], before: datetime) -> List[str]:
        """Commits on HEAD before then that change how often the text appears, newest first. Renames don't count."""
        return self._run(
            'log', '-M', '--format=%H', f'--before={before.isoformat()}', '-S', text, 'HEAD', '--', *paths
        ).split()

    def diff(self, sha: str, paths: List[str]) -> str:
        return self._run('show', '-M', '-U6', '--format=', sha, '--', *paths)

    def full_sha(self, short_sha: str) -> Optional[str]:
        try:
            return self._run('rev-parse', '--verify', '--quiet', f'{short_sha}^{{commit}}').strip() or None
        except RuntimeError:
            return None


def text_forms(text: str) -> List[str]:
    """How the English text can be written in the sources: as is, and escaped in a string catalog or a Swift literal."""
    escaped = json.dumps(text, ensure_ascii=False)[1:-1]
    return list(dict.fromkeys([escaped, text]))


def key_forms(key: str) -> List[str]:
    """How the key appears next to the text: as is, a plural's key without its "/<key>:dict/…" path, or a
    storyboard object's id."""
    if not key:
        return []
    plural = PLURAL_KEY.match(key)
    forms = [plural[1] if plural else key]
    interface_builder = INTERFACE_BUILDER_KEY.match(key)
    if interface_builder:
        forms.append(interface_builder[1])
    return forms


def declared_key(line: str) -> Optional[str]:
    """The key a line of a strings file, string catalog or Swift source starts an entry for, if any."""
    match = KEY_DECLARATION.search(line)
    if not match:
        return None
    if match[3]:
        return match[3]
    in_catalog = match[2] == ':'
    return None if in_catalog and (match[1] in CATALOG_FIELDS or LOCALE.match(match[1])) else match[1]


def mentions_key(line: str, keys: List[str]) -> bool:
    """Whether the line has one of the keys. A line that starts an entry must be the key's own, so that "OK" doesn't
    match `"OK, got it" : {`, and a catalog entry's field or locale never has it. Any other line, such as a Swift
    call, must have it as a whole, so that "target.key" doesn't match "target.key.tooltip"."""
    if KEY_DECLARATION.search(line):
        return declared_key(line) in keys
    return any(re.search(rf'(?<![\w.-]){re.escape(key)}(?![\w.-])', line) for key in keys)


def in_entry(lines: List[str], keys: List[str]) -> bool:
    """Whether the last line is in the key's entry: on the key's line, or below it with no other key's entry between."""
    for line in reversed(lines):
        if mentions_key(line, keys):
            return True
        if declared_key(line):
            return False
    return False


def entry_texts(hunk: str, side: str, texts: List[str], keys: List[str]) -> set:
    """The texts that the hunk's added ('+') or removed ('-') lines have in the string's own entry. A removed line
    must have the text as a whole literal, so that an edit that shortens the text still adds it. With no text, {''}
    if a line on that side has the key."""
    other = '-' if side == '+' else '+'
    lines = [line for line in hunk.splitlines() if not line.startswith(other)]
    found = set()
    for index, line in enumerate(lines):
        if not line.startswith(side):
            continue
        if not texts:
            found |= {''} if mentions_key(line, keys) else set()
            continue
        in_line = {text for text in texts if (text if side == '+' else f'"{text}"') in line}
        if in_line and (not keys or in_entry(lines[:index + 1], keys)):
            found |= in_line
    return found


def adds_string(diff: str, texts: List[str], keys: List[str]) -> bool:
    """Whether the diff adds a line with the text in the string's own entry, and doesn't remove it from the key's
    entry elsewhere, as a commit that moves the entry to another file does. The same words under another key don't
    count. With no text, whether it adds a line with the key without removing one."""
    hunks = re.split(r'^@@.*$', diff, flags=re.MULTILINE)[1:]
    added = set().union(*(entry_texts(hunk, '+', texts, keys) for hunk in hunks))
    removed = set().union(*(entry_texts(hunk, '-', texts, keys) for hunk in hunks))
    return bool(added - removed)


def string_commit(git: Git, github: GitHubClient, issue: OpenIssue, platform: str) -> Optional[Dict]:
    """The pull request of the newest commit before the issue that added its English text under its key, skipping
    bots. When the text isn't found as Smartling has it (placeholders, for example), the newest that added the key."""
    paths = PLATFORM_PATHS[platform]
    texts = text_forms(issue.english) if issue.english else []
    keys = key_forms(issue.key)
    searches = [(texts, texts, keys)] if texts else []  # What to search the history for, then what to check in the diff
    searches += [(keys, [], keys)] if keys else []
    shallow = git.shallow_commits()
    for terms, search_texts, search_keys in searches:
        candidates = list(dict.fromkeys(
            sha for term in terms for sha in git.commits_changing(term, paths, issue.created_at)
        ))
        for sha in candidates[:MAX_CANDIDATE_COMMITS]:
            if sha in shallow or not adds_string(git.diff(sha, paths), search_texts, search_keys):
                continue
            pull = human(pull_request(github, sha))
            if pull:
                return pull
    return None


def human(pull: Optional[Dict]) -> Optional[Dict]:
    return pull if pull and not is_bot(pull.get('user') or {}) else None


def label_job_pull(github: GitHubClient, issue: OpenIssue) -> Optional[Dict]:
    """The pull request, when the issue was raised in its /translate job."""
    match = LABEL_JOB_BRANCH.match(issue.job_name)
    return next((pull for pull in github.branch_pulls(match[1]) if human(pull)), None) if match else None


def merge_job_pull(git: Git, github: GitHubClient, issue: OpenIssue) -> Optional[Dict]:
    """The pull request of the commit the issue's merge job was named after."""
    match = MERGE_JOB_COMMIT.match(issue.job_name)
    sha = git.full_sha(match[1]) if match else None
    return human(pull_request(github, sha)) if sha else None


def find_person(git: Git, github: GitHubClient, user_map: Dict[str, str], issue: OpenIssue, platform: str) -> Optional[Person]:
    """Who to ask: the pull request the string's /translate job came from, or whoever added the string, or else the
    author of the merge job's commit. Once someone is found who isn't in the user map, no one: the later lookups are
    less sure, so the triage DRI is a better guess than them. A GitHub or git error is raised, so that the issue is
    retried instead of going to someone less sure."""
    lookups = (
        ('translate job', lambda: label_job_pull(github, issue)),
        ('added the string', lambda: string_commit(git, github, issue, platform)),
        ('merge job commit', lambda: merge_job_pull(git, github, issue)),
    )
    for source, find_pull in lookups:
        pull = find_pull()
        login = ((pull or {}).get('user') or {}).get('login')
        gid = asana_user(user_map, login)
        if gid:
            return Person(login=login, asana_gid=gid, pull_url=pull.get('html_url', ''), source=source)
        if login:
            log(f"⚠️ #{issue.number}: @{login} ({source}) isn't in the GitHub to Asana user map")
            return None
    return None


def task_name(issue: OpenIssue, platform: str) -> str:
    return f"{TASK_NAME_PREFIX} #{issue.number} ({platform}): {issue.key or 'unknown key'}"


def task_notes(issue: OpenIssue, platform: str, smartling: SmartlingClient, person: Optional[Person], workflow_url: str) -> str:
    who = "on an English string from your pull request" if person else "on an English string whose author couldn't be found"
    lines = [
        f"❓ A translator opened an issue {who}. Please answer it on issue #{issue.number} in Smartling"
        f"{', which was reopened' if issue.reopened else ''}.",
        "",
        f"📝 Issue: {' '.join(issue.text.split()) or 'no text'}",
        f"🔤 English: {' '.join(issue.english.split()) or 'unavailable'}",
        f"🔑 Key: {issue.key or 'unavailable'}",
        f"🏷️ Type: {issue.subtype or 'unknown'}",
    ]
    if issue.job_uid:
        lines.append(f"🔗 Smartling job: [{issue.job_name}]({job_url(smartling, issue.job_uid)})")
    lines.append(f"🔀 Pull request: {person.pull_url if person else 'not found'}")
    lines.append(f"⚙️ Workflow: {workflow_url}")
    return '\n'.join(lines)


def assignee_name(assignee: Optional[str], person: Optional[Person]) -> str:
    """Who the task is for, for the log and the summary: never a name or email, only a GitHub login."""
    if person and assignee == person.asana_gid:
        return f"@{person.login} ({person.source})"
    return 'the triage DRI' if assignee else 'no one'


def window(args, github: GitHubClient) -> datetime:
    """Where this run starts. --since moves it, but only a dry run may start before --not-before."""
    not_before = parse_time(args.not_before)
    if not args.since:
        return window_start(github, args.workflow, args.job_name, not_before)
    since = parse_time(args.since)
    return since if args.dry_run else max(since, not_before)


async def run(args, smartling: SmartlingClient, asana: AsanaClient, github: GitHubClient, git: Git, user_map: Dict[str, str]) -> Tuple[List[str], bool]:
    """Open the tasks and return the job summary's rows, and whether any issue failed. One issue failing doesn't stop
    the others; the run then fails, so the next night looks at the same window again."""
    today = date.today()
    since = window(args, github)
    log(f"🔎 {args.platform} issues opened or reopened since {since.isoformat()}")
    issues, failed = await load_issues(smartling, since)
    rows = [f"| #{number} | failed, retried next night | |" for number in failed]
    if not issues:
        log("✅ No new issues" if not failed else "❌ No issue could be loaded")
        return rows, bool(failed)

    existing = asana.project_tasks(args.asana_project, since)
    git.ensure_history()
    section_id = find_section(asana.sections(args.asana_project), args.section_name)
    dri = pick_dri(asana.rotation_tasks(args.rotation_section, today - timedelta(days=14)), today) if args.rotation_section else None
    dri_gid = (dri or {}).get('gid')

    for issue in issues:
        if has_task(existing, issue):
            log(f"⏭️ #{issue.number} already has a task")
            rows.append(f"| #{issue.number} | already has a task | |")
            continue
        try:
            person = find_person(git, github, user_map, issue, args.platform)
        except RuntimeError as error:
            log(f"❌ #{issue.number}: couldn't look for who added its string: {error}")
            rows.append(f"| #{issue.number} | failed, retried next night | |")
            failed.append(issue.number)
            continue
        assignee = person.asana_gid if person else dri_gid
        who = assignee_name(assignee, person)
        body = {
            'name': task_name(issue, args.platform),
            'html_notes': notes_html(task_notes(issue, args.platform, smartling, person, args.workflow_url)),
            'projects': [args.asana_project],
            'due_on': today.isoformat(),
        }
        if section_id:
            body['memberships'] = [{'project': args.asana_project, 'section': section_id}]
        if assignee:
            body['assignee'] = assignee
        if args.dry_run:
            log(f"🧪 #{issue.number}: would open a task for {who}")
            rows.append(f"| #{issue.number} | would open a task | {who} |")
            continue
        try:
            task = create_task(asana, body, dri_gid)
        except RuntimeError as error:
            log(f"❌ #{issue.number}: couldn't open its task: {error}")
            rows.append(f"| #{issue.number} | failed, retried next night | {who} |")
            failed.append(issue.number)
            continue
        who = assignee_name((task.get('assignee') or {}).get('gid'), person)
        log(f"✅ #{issue.number}: opened a task for {who}: {task.get('permalink_url', task.get('gid'))}")
        rows.append(f"| #{issue.number} | opened a task | {who} |")
    return rows, bool(failed)


def write_summary(platform: str, rows: List[str], dry_run: bool):
    summary_path = os.environ.get('GITHUB_STEP_SUMMARY')
    if not summary_path:
        return
    with open(summary_path, 'a', encoding='utf-8') as summary:
        summary.write(f"## {platform} Smartling open issues{' (dry run)' if dry_run else ''}\n\n")
        if not rows:
            summary.write("No new issues on English strings.\n")
            return
        summary.write("| Issue | Outcome | Assignee |\n|---|---|---|\n")
        summary.write('\n'.join(rows) + '\n')


async def main_async(args) -> int:
    asana_token = os.environ.get('ASANA_ACCESS_TOKEN')
    github_token = os.environ.get('GITHUB_TOKEN')
    creds = Credentials(
        os.environ.get('SMARTLING_USER_ID', ''), os.environ.get('SMARTLING_USER_SECRET', ''), os.environ.get('SMARTLING_PROJECT_ID', '')
    )
    if not (asana_token and github_token and creds.user_id and creds.user_secret and creds.project_id):
        log("❌ Missing ASANA_ACCESS_TOKEN, GITHUB_TOKEN or the Smartling credentials")
        return 1
    user_map_text = Path(args.user_map).read_text(encoding='utf-8') if args.user_map and Path(args.user_map).exists() else ''
    if not user_map_text:
        log("⚠️ No GitHub to Asana user map, so every task goes to the triage DRI")

    async with SmartlingClient(creds) as smartling:
        try:
            rows, failed = await run(args, smartling, AsanaClient(asana_token), GitHubClient(github_token), Git(), parse_user_map(user_map_text))
        except RuntimeError as error:
            log(f"❌ {error}")
            return 1
    write_summary(args.platform, rows, args.dry_run)
    return 1 if failed else 0


def main():
    parser = argparse.ArgumentParser(description='Open an Asana task for each new Smartling issue on an English string')
    parser.add_argument('--platform', required=True, choices=sorted(PLATFORM_PATHS))
    parser.add_argument('--asana-project', required=True)
    parser.add_argument('--section-name', required=True)
    parser.add_argument('--rotation-section', help="Triage rotation section, for issues whose author can't be found")
    parser.add_argument('--user-map', help='Path to the GitHub to Asana user_map.yml')
    parser.add_argument('--workflow', default='smartling_nightly.yml', help='Workflow file whose last successful job starts the window')
    parser.add_argument('--job-name', required=True, help='Name of this job in that workflow')
    parser.add_argument('--not-before', required=True, help='Never look at issues opened before this ISO time (go-live), even with --since unless it is a dry run')
    parser.add_argument('--since', help='Look at issues opened since this ISO time instead of since the last successful job, but not before --not-before')
    parser.add_argument('--workflow-url', default='')
    parser.add_argument('--dry-run', action='store_true', help='Look everything up, but open no task')
    sys.exit(asyncio.run(main_async(parser.parse_args())))


if __name__ == '__main__':
    main()
