#!/usr/bin/env python3
"""
Smartling Localization Tool - Minimal single-file implementation

Copyright © 2025 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import os
import sys
import json
import asyncio
import argparse
import subprocess
import time
import traceback
from contextlib import contextmanager
from pathlib import Path
from datetime import datetime, timedelta
from decimal import Decimal, InvalidOperation
from typing import List, Dict, Optional
from dataclasses import asdict, dataclass, field
from urllib.parse import urlencode

import aiohttp


# ============================================================================
# Data Models
# ============================================================================

@dataclass
class Credentials:
    """Smartling API credentials."""
    user_id: str
    user_secret: str
    project_id: str


@dataclass
class SubmitResult:
    """Machine-readable result for automated job submission."""
    outcome: str
    job_id: str = ""
    job_name: str = ""
    total_strings: Optional[int] = None  # Smartling's totalStrings: each string counted once per locale
    locales: Optional[int] = None
    max_usd: str = ""
    reason: str = ""
    failed: bool = False

    def as_dict(self) -> Dict:
        return asdict(self)


@dataclass
class ReleaseStatus:
    """Machine-readable result for checking whether a release's files are translated."""
    outcome: str
    job_id: str = ""
    job_url: str = ""
    job_status: str = ""
    total_strings: Optional[int] = None
    strings_left: Optional[int] = None
    incomplete_locales: List[str] = field(default_factory=list)
    locales: Optional[int] = None
    strings_awaiting_authorization: Optional[int] = None
    jobs_awaiting_authorization: List[str] = field(default_factory=list)
    reason: str = ""

    def as_dict(self) -> Dict:
        return asdict(self)


# ============================================================================
# Smartling API Client
# ============================================================================

class SmartlingClient:
    """Minimal Smartling API client with only essential methods."""

    BASE_URL = "https://api.smartling.com"

    def __init__(self, creds: Credentials):
        self.creds = creds
        self.token = None
        self.token_expiry = None
        self.session = None

    async def __aenter__(self):
        self.session = aiohttp.ClientSession()
        return self

    async def __aexit__(self, *args):
        if self.session:
            await self.session.close()

    async def _request(self, method: str, path: str, **kwargs) -> Dict:
        """Make authenticated API request."""
        if not self.token or datetime.now() >= self.token_expiry:
            await self._authenticate()

        headers = kwargs.pop('headers', {})
        headers['Authorization'] = f'Bearer {self.token}'

        url = f"{self.BASE_URL}{path}"
        async with self.session.request(method, url, headers=headers, **kwargs) as resp:
            text = await resp.text()

            if resp.status == 204 or not text:
                return {}

            data = json.loads(text) if text else {}

            if resp.status >= 400:
                error = data.get('response', {}).get('errors', [{}])[0].get('message', 'API Error')
                raise RuntimeError(f"HTTP {resp.status}: {error}")

            return data

    async def _authenticate(self):
        """Get access token."""
        async with self.session.post(
            f"{self.BASE_URL}/auth-api/v2/authenticate",
            json={'userIdentifier': self.creds.user_id, 'userSecret': self.creds.user_secret}
        ) as resp:
            data = await resp.json()
            token_data = data['response']['data']
            self.token = token_data['accessToken']
            self.token_expiry = datetime.now() + timedelta(seconds=token_data['expiresIn'] - 60)

    async def create_job(self, name: str, locales: List[str], description: str = "") -> str:
        """Create translation job."""
        data = await self._request(
            'POST',
            f'/jobs-api/v3/projects/{self.creds.project_id}/jobs',
            json={'jobName': name, 'targetLocaleIds': locales, 'description': description}
        )
        return data['response']['data']['translationJobUid']

    async def get_job(self, job_id: str) -> Dict:
        """Get job details."""
        data = await self._request(
            'GET', f'/jobs-api/v3/projects/{self.creds.project_id}/jobs/{job_id}'
        )
        return data['response']['data']

    async def list_jobs(self, job_name: str, statuses: List[str]) -> List[Dict]:
        """List jobs whose name contains job_name, in any of the statuses (all when empty)."""
        params = [('jobName', job_name), ('limit', '100')]
        params.extend(('translationJobStatus', status) for status in statuses)
        data = await self._request(
            'GET',
            f'/jobs-api/v3/projects/{self.creds.project_id}/jobs',
            params=params
        )
        return data['response']['data'].get('items', [])

    async def get_job_progress(self, job_id: str) -> int:
        """Get job progress percentage."""
        data = await self._request(
            'GET', f'/jobs-api/v3/projects/{self.creds.project_id}/jobs/{job_id}/progress'
        )
        return data['response']['data']['progress']['percentComplete']

    async def authorize_job(self, job_id: str):
        """Authorize job for translation."""
        await self._request(
            'POST',
            f'/jobs-api/v3/projects/{self.creds.project_id}/jobs/{job_id}/authorize',
            json={'localeWorkflows': []}
        )

    async def cancel_job(self, job_id: str) -> str:
        """Cancel a translation job and return its process ID."""
        data = await self._request(
            'POST',
            f'/jobs-api/v3/projects/{self.creds.project_id}/jobs/{job_id}/cancel',
            json={'reason': 'No untranslated strings'}
        )
        process_url = data['response']['data'].get('url', '')
        process_id = process_url.rstrip('/').rsplit('/', 1)[-1]
        if not process_url or not process_id:
            raise RuntimeError("Smartling cancellation returned no process ID")
        return process_id

    async def get_job_process_state(self, job_id: str, process_id: str) -> str:
        """Get an asynchronous job process state."""
        data = await self._request(
            'GET',
            f'/jobs-api/v3/projects/{self.creds.project_id}/jobs/{job_id}/processes/{process_id}'
        )
        return data['response']['data']['processState']

    async def delete_job(self, job_id: str):
        """Delete a cancelled translation job."""
        await self._request(
            'DELETE',
            f'/jobs-api/v3/projects/{self.creds.project_id}/jobs/{job_id}'
        )

    async def get_project_locales(self) -> List[str]:
        """Get valid project locales."""
        data = await self._request('GET', f'/projects-api/v2/projects/{self.creds.project_id}')
        return [
            loc['localeId'] for loc in data['response']['data']['targetLocales']
            if loc.get('enabled', True)
        ]

    async def create_batch(self, job_id: str, file_uris: List[str]) -> str:
        """Create file batch."""
        data = await self._request(
            'POST',
            f'/job-batches-api/v2/projects/{self.creds.project_id}/batches',
            json={'authorize': False, 'translationJobUid': job_id, 'fileUris': file_uris}
        )
        return data['response']['data']['batchUid']

    async def upload_to_batch(
        self, batch_id: str, file_path: Path, file_uri: str, locales: List[str]
    ):
        """Upload file to batch."""
        form = aiohttp.FormData()
        form.add_field('fileUri', file_uri)
        form.add_field(
            'fileType', 'xliff' if file_path.suffix == '.xliff' else 'stringsdict'
        )
        for locale in locales:
            form.add_field('localeIdsToAuthorize[]', locale)
        form.add_field('file', file_path.read_bytes(), filename=file_path.name)

        await self._request(
            'POST',
            f'/job-batches-api/v2/projects/{self.creds.project_id}/batches/{batch_id}/file',
            data=form
        )

    async def get_batch_status(self, batch_id: str) -> str:
        """Get batch processing status."""
        data = await self._request(
            'GET', f'/job-batches-api/v2/projects/{self.creds.project_id}/batches/{batch_id}'
        )
        return data['response']['data']['status']

    async def generate_cost_estimate(self, job_id: str) -> str:
        """Start an estimate for unauthorized job content."""
        data = await self._request(
            'POST',
            f'/estimates-api/v2/projects/{self.creds.project_id}/jobs/{job_id}/reports/cost',
            json={'contentType': 'UNAUTHORIZED'}
        )
        return data['response']['data']['reportUid']

    async def get_estimate_status(self, report_id: str) -> str:
        """Get estimate generation status."""
        data = await self._request(
            'GET',
            f'/estimates-api/v2/projects/{self.creds.project_id}/reports/{report_id}/status'
        )
        return data['response']['data']['reportStatus']

    async def get_estimate_report(self, report_id: str) -> Dict:
        """Get a completed estimate report."""
        data = await self._request(
            'GET',
            f'/estimates-api/v2/projects/{self.creds.project_id}/reports/{report_id}'
        )
        report_data = data['response']['data']
        if 'items' in report_data:
            matching_reports = [
                report for report in report_data['items']
                if report.get('reportUid') == report_id
            ]
            if not matching_reports:
                raise RuntimeError("Completed estimate report was not returned")
            return matching_reports[0]
        return report_data

    async def get_job_files(self, job_id: str) -> List[str]:
        """Get file URIs in job."""
        data = await self._request(
            'GET', f'/jobs-api/v3/projects/{self.creds.project_id}/jobs/{job_id}/files'
        )
        return [f['uri'] for f in data['response']['data'].get('items', [])]

    async def upload_file(self, file_path: Path, file_uri: str) -> Dict:
        """Upload a file outside any job, without authorizing any locale."""
        form = aiohttp.FormData()
        form.add_field('fileUri', file_uri)
        form.add_field(
            'fileType', 'xliff' if file_path.suffix == '.xliff' else 'stringsdict'
        )
        form.add_field('file', file_path.read_bytes(), filename=file_path.name)
        data = await self._request(
            'POST',
            f'/files-api/v2/projects/{self.creds.project_id}/file',
            data=form
        )
        return data.get('response', {})

    async def list_jobs_awaiting_authorization(self) -> List[Dict]:
        """List the project's jobs that are awaiting authorization."""
        data = await self._request(
            'GET',
            f'/jobs-api/v3/projects/{self.creds.project_id}/jobs',
            params=[('translationJobStatus', 'AWAITING_AUTHORIZATION'), ('limit', '100')]
        )
        return data['response']['data'].get('items', [])

    async def get_file_status(self, file_uri: str) -> Dict:
        """Get a file's string counts, in total and per locale."""
        data = await self._request(
            'GET',
            f'/files-api/v2/projects/{self.creds.project_id}/file/status',
            params={'fileUri': file_uri}
        )
        return data['response']['data']

    async def download_file(self, file_uri: str, locale: str) -> bytes:
        """Download translated file."""
        # Ensure token is valid
        if not self.token or datetime.now() >= self.token_expiry:
            await self._authenticate()

        params = {'fileUri': file_uri}
        url = (
            f"{self.BASE_URL}/files-api/v2/projects/{self.creds.project_id}/"
            f"locales/{locale}/file?{urlencode(params)}"
        )
        async with self.session.get(url, headers={'Authorization': f'Bearer {self.token}'}) as resp:
            if resp.status >= 400:
                text = await resp.text()
                error = json.loads(text).get('response', {}).get('errors', [{}])[0].get('message', 'API Error')
                raise RuntimeError(f"HTTP {resp.status}: {error}")
            return await resp.read()


# ============================================================================
# CLI Commands
# ============================================================================

def error_reason(error: Exception) -> str:
    """An error message on one line, short enough for step outputs and annotations."""
    return str(error).replace('\n', ' ').replace('\r', ' ')[:500]


def log(message: str):
    """Print a progress line for CI logs."""
    print(f"[smartling] {message}", flush=True)


def annotate(level: str, message: str):
    """Show a notice, warning or error at the top of a GitHub Actions run."""
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        escaped = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
        print(f"::{level}::{escaped}", flush=True)


@contextmanager
def log_group(title: str):
    """Fold the lines logged inside into one collapsible group on GitHub Actions."""
    in_actions = os.environ.get('GITHUB_ACTIONS') == 'true'
    if in_actions:
        print(f"::group::{title}", flush=True)
    else:
        log(f"⏳ {title}")
    try:
        yield
    finally:
        if in_actions:
            print("::endgroup::", flush=True)


def job_url(client: SmartlingClient, job_id: str) -> str:
    """Smartling dashboard link for a job."""
    project_id = client.creds.project_id
    return f"https://dashboard.smartling.com/app/projects/{project_id}/account-jobs/{project_id}:{job_id}"


async def poll_status(get_status, terminal: set, sleep, interval: int, attempts: int = 60) -> str:
    """Poll until get_status returns a terminal status, logging each change."""
    started = time.monotonic()
    last_status = None
    for _ in range(attempts):
        status = await get_status()
        if status != last_status:
            log(f"Status: {status} ({int(time.monotonic() - started)}s)")
            last_status = status
        if status in terminal:
            return status
        await sleep(interval)
    return last_status


async def wait_for_batch(client: SmartlingClient, batch_id: str, sleep=asyncio.sleep):
    """Wait for Smartling to finish ingesting a batch."""
    failed = {'FAILED', 'COMPLETED_WITH_ERRORS', 'CANCELED', 'CANCELLED'}
    with log_group(f"Waiting for Smartling to process batch {batch_id}"):
        status = await poll_status(
            lambda: client.get_batch_status(batch_id), {'COMPLETED'} | failed, sleep, 5
        )
    if status in failed:
        raise RuntimeError(f"Smartling batch processing ended with status {status}")
    if status != 'COMPLETED':
        raise RuntimeError("Smartling batch processing timed out")


async def wait_for_estimate(client: SmartlingClient, report_id: str, sleep=asyncio.sleep) -> Dict:
    """Wait for a Smartling cost estimate."""
    failed = {'FAILED', 'TIMEOUT', 'NOT_FOUND'}
    with log_group(f"Waiting for cost estimate {report_id}"):
        status = await poll_status(
            lambda: client.get_estimate_status(report_id), {'COMPLETED'} | failed, sleep, 5
        )
    if status in failed:
        raise RuntimeError(f"Smartling estimate ended with status {status}")
    if status != 'COMPLETED':
        raise RuntimeError("Smartling cost estimate timed out")
    return await client.get_estimate_report(report_id)


async def wait_for_job_cancellation(client: SmartlingClient,
                                    job_id: str,
                                    process_id: str,
                                    sleep=asyncio.sleep):
    """Wait until a Smartling job is cancelled."""
    for _ in range(60):
        state = await client.get_job_process_state(job_id, process_id)
        if state == 'FAILED':
            raise RuntimeError("Smartling job cancellation failed")
        if state == 'COMPLETED':
            job = await client.get_job(job_id)
            if job.get('jobStatus') == 'CANCELLED':
                return
        await sleep(2)
    raise RuntimeError("Smartling job cancellation timed out")


def parse_estimate(report: Dict) -> tuple[int, Decimal]:
    """Return untranslated string count and the maximum USD estimate."""
    errors = report.get('errors') or []
    if errors:
        raise RuntimeError("Smartling estimate contains errors")

    total_strings = int(report.get('totalStrings') or 0)
    if total_strings == 0:
        return 0, Decimal('0')

    # A warning (e.g. a missing rate) means the price may leave out some locales or workflows.
    warnings = report.get('warnings') or []
    if warnings:
        details = '; '.join(
            warning.get('message', str(warning)) if isinstance(warning, dict) else str(warning)
            for warning in warnings
        )
        raise RuntimeError(f"Smartling estimate may be incomplete: {details}")

    usd_prices = []
    for price in report.get('priceInformation') or []:
        if price.get('currencyCode') != 'USD' or price.get('priceMax') is None:
            continue
        try:
            usd_prices.append(Decimal(str(price['priceMax'])))
        except InvalidOperation as error:
            raise RuntimeError("Smartling returned an invalid USD estimate") from error

    if not usd_prices:
        raise RuntimeError("Smartling estimate has no maximum USD price")
    # One USD entry is the job's total. Several could be parts to add up, so don't guess.
    if len(usd_prices) > 1:
        raise RuntimeError(f"Smartling estimate has {len(usd_prices)} USD prices, expected one total")

    return total_strings, usd_prices[0]


async def run_submit(client: SmartlingClient,
                     files: List[Path],
                     job_name: str,
                     pending_job_prefix: str,
                     file_uri_prefix: str,
                     auto_authorize_max_usd: Decimal,
                     delete_job_on_failure: bool = False,
                     sleep=asyncio.sleep) -> SubmitResult:
    """Submit files to a new job and authorize it if its maximum USD estimate is at most auto_authorize_max_usd.

    With a pending_job_prefix, nothing is submitted while a job whose name starts with it awaits authorization.
    Without one, only a job named exactly job_name stops a new submission.
    With delete_job_on_failure, a job this run created is deleted if the submission fails before authorizing it,
    so a rerun with the same job name starts over instead of finding a half-submitted job.
    """
    job_id = ""
    unauthorized_job_id = ""
    try:
        pending_jobs = await client.list_jobs(
            pending_job_prefix,
            ['AWAITING_AUTHORIZATION']
        ) if pending_job_prefix else []
        pending_job = next(
            (
                job for job in pending_jobs
                if job.get('jobName', '').startswith(pending_job_prefix)
            ),
            None
        )
        if pending_job:
            job_id = job_uid(pending_job)
            log(f"⏸️ '{pending_job['jobName']}' is still awaiting authorization: {job_url(client, job_id)}")
            # The run that left this job waiting already opened a review task, so don't open another.
            return SubmitResult(
                outcome='pending_review',
                job_id=job_id,
                job_name=pending_job['jobName'],
                reason=f"'{pending_job['jobName']}' is still awaiting authorization, so no new job was created"
            )

        existing_job = await find_job(client, job_name)
        if existing_job:
            log(f"⏭️ A job named '{job_name}' already exists")
            return SubmitResult(
                outcome='skipped_existing_job',
                job_id=job_uid(existing_job),
                job_name=job_name,
                reason=f"A job named '{job_name}' already exists"
            )

        if pending_job_prefix:
            log(f"🔍 No pending '{pending_job_prefix}' job, no job named '{job_name}'")
        else:
            log(f"🔍 No job named '{job_name}'")

        locales = await client.get_project_locales()
        job_id = await client.create_job(
            job_name,
            locales,
            "Created by localization automation"
        )
        unauthorized_job_id = job_id
        log(f"✅ Created job '{job_name}' ({job_id}) for {len(locales)} locales: {job_url(client, job_id)}")
        file_uris = [f"{file_uri_prefix}/{file_path.name}" for file_path in files]
        batch_id = await client.create_batch(job_id, file_uris)
        for file_path, file_uri in zip(files, file_uris):
            await client.upload_to_batch(batch_id, file_path, file_uri, locales)
            log(f"📤 Uploaded {file_uri} ({file_path.stat().st_size // 1024} KB)")
        await wait_for_batch(client, batch_id, sleep)

        report_id = await client.generate_cost_estimate(job_id)
        report = await wait_for_estimate(client, report_id, sleep)
        total_strings, max_usd = parse_estimate(report)
        log(
            f"💵 Estimate: {total_strings} string translations across {len(locales)} locales, "
            f"max ${format(max_usd, 'f')} USD "
            f"(authorized automatically up to ${format(auto_authorize_max_usd, 'f')})"
        )

        if total_strings == 0:
            unauthorized_job_id = ""
            process_id = await client.cancel_job(job_id)
            await wait_for_job_cancellation(client, job_id, process_id, sleep)
            await client.delete_job(job_id)
            log(f"🗑️ Nothing to translate, cancelled and deleted job {job_id}")
            return SubmitResult(
                outcome='no_new_strings',
                job_id=job_id,
                job_name=job_name,
                total_strings=0,
                locales=len(locales)
            )
        if auto_authorize_max_usd > 0 and max_usd <= auto_authorize_max_usd:
            unauthorized_job_id = ""
            await client.authorize_job(job_id)
            log("✅ Authorized")
            return SubmitResult(
                outcome='authorized',
                job_id=job_id,
                job_name=job_name,
                total_strings=total_strings,
                locales=len(locales),
                max_usd=format(max_usd, 'f')
            )
        if auto_authorize_max_usd > 0:
            reason = f"Maximum USD estimate exceeds {format(auto_authorize_max_usd, 'f')}"
        else:
            reason = "Automatic authorization is off (limit is 0)"
        log(f"✋ {reason}, leaving the job for review")
        return SubmitResult(
            outcome='review_required',
            job_id=job_id,
            job_name=job_name,
            total_strings=total_strings,
            locales=len(locales),
            max_usd=format(max_usd, 'f'),
            reason=reason
        )
    except Exception as error:  # pylint: disable=broad-except
        log(f"❌ {error}")
        traceback.print_exc()
        reason = error_reason(error)
        if delete_job_on_failure and unauthorized_job_id:
            try:
                process_id = await client.cancel_job(unauthorized_job_id)
                await wait_for_job_cancellation(client, unauthorized_job_id, process_id, sleep)
                await client.delete_job(unauthorized_job_id)
                log(f"🗑️ Cancelled and deleted job {unauthorized_job_id}, so a rerun starts over")
                job_id = ""
                reason += ". The job was deleted, so a rerun starts over"
            except Exception as cleanup_error:  # pylint: disable=broad-except
                log(f"❌ Could not delete job {unauthorized_job_id}: {cleanup_error}")
                reason += f". Deleting the job also failed ({cleanup_error}), so delete it before a rerun"
        return SubmitResult(
            outcome='review_required',
            job_id=job_id,
            job_name=job_name if job_id else "",
            reason=reason,
            failed=True
        )


def strings_left_per_locale(file_status: Dict, locales: List[str]) -> Dict[str, int]:
    """Strings neither completed nor excluded, for each locale that still has some."""
    total = int(file_status.get('totalStringCount') or 0)
    by_locale = {item.get('localeId'): item for item in file_status.get('items') or []}
    strings_left = {}
    for locale in locales:
        item = by_locale.get(locale, {})
        done = int(item.get('completedStringCount') or 0) + int(item.get('excludedStringCount') or 0)
        if done < total:
            strings_left[locale] = total - done
    return strings_left


def job_uid(job: Dict) -> str:
    """A job's ID, whichever field the endpoint returned it in."""
    return job.get('translationJobUid') or job.get('jobUid', '')


def strings_awaiting_authorization(file_status: Dict, locales: List[str]) -> int:
    """Strings not authorized for translation, in a job awaiting authorization or in no job, summed over locales."""
    total = int(file_status.get('totalStringCount') or 0)
    by_locale = {item.get('localeId'): item for item in file_status.get('items') or []}
    awaiting = 0
    for locale in locales:
        item = by_locale.get(locale, {})
        handled = sum(
            int(item.get(count) or 0)
            for count in ('authorizedStringCount', 'completedStringCount', 'excludedStringCount')
        )
        awaiting += max(total - handled, 0)
    return awaiting


async def find_job(client: SmartlingClient, job_name: str) -> Optional[Dict]:
    """The job named exactly job_name, if there is one."""
    jobs = await client.list_jobs(job_name, [])
    return next((job for job in jobs if job.get('jobName') == job_name), None)


def failed_release_status(error: Exception, job_id: str = "", job_status: str = "") -> ReleaseStatus:
    """Log the error and report it as the release status."""
    log(f"❌ {error}")
    traceback.print_exc()
    return ReleaseStatus(outcome='error', job_id=job_id, job_status=job_status, reason=error_reason(error))


async def run_release_status(client: SmartlingClient,
                             job_name: str,
                             file_uris: List[str]) -> ReleaseStatus:
    """Report whether every string in the release files is translated in every locale."""
    job_id = ""
    job_status = ""
    try:
        job = await find_job(client, job_name)
        if job:
            job_id = job_uid(job)
            job_status = job.get('jobStatus', '')
            log(f"📋 '{job_name}' is {job_status}: {job_url(client, job_id)}")
        else:
            log(f"📋 No job named '{job_name}'")
    except Exception as error:  # pylint: disable=broad-except
        log(f"⚠️ Could not look up '{job_name}': {error}")

    try:
        locales = await client.get_project_locales()
        total_strings = 0
        strings_left = 0
        awaiting_authorization = 0
        incomplete_locales = set()
        for file_uri in file_uris:
            try:
                file_status = await client.get_file_status(file_uri)
            except Exception as error:  # pylint: disable=broad-except
                raise RuntimeError(f"Could not read the status of {file_uri}: {error}") from error
            file_total = int(file_status.get('totalStringCount') or 0)
            left = strings_left_per_locale(file_status, locales)
            log(
                f"📊 {file_uri}: {file_total} strings, "
                f"{len(locales) - len(left)} of {len(locales)} locales complete"
            )
            total_strings += file_total * len(locales)
            strings_left += sum(left.values())
            awaiting_authorization += strings_awaiting_authorization(file_status, locales)
            incomplete_locales.update(left)

        if total_strings == 0:
            raise RuntimeError("The release files have no strings")

        outcome = 'not_ready' if strings_left else 'ready'
        if awaiting_authorization:
            log(f"✋ {awaiting_authorization} string translations aren't authorized for translation")
        log(f"{'⏳' if strings_left else '✅'} {strings_left} of {total_strings} string translations left")
        return ReleaseStatus(
            outcome=outcome,
            job_id=job_id,
            job_status=job_status,
            total_strings=total_strings,
            strings_left=strings_left,
            strings_awaiting_authorization=awaiting_authorization,
            incomplete_locales=sorted(incomplete_locales),
            locales=len(locales),
            jobs_awaiting_authorization=await describe_jobs_awaiting_authorization(client) if strings_left else []
        )
    except Exception as error:  # pylint: disable=broad-except
        return failed_release_status(error, job_id, job_status)


async def describe_jobs_awaiting_authorization(client: SmartlingClient) -> List[str]:
    """The project's jobs awaiting authorization, which keep their strings out of other jobs."""
    try:
        jobs = await client.list_jobs_awaiting_authorization()
    except Exception as error:  # pylint: disable=broad-except
        log(f"⚠️ Could not list the jobs awaiting authorization: {error}")
        return []
    jobs = sorted(jobs, key=lambda job: job.get('createdDate') or '')
    descriptions = []
    for job in jobs:
        name = job.get('jobName', 'unnamed')
        created = (job.get('createdDate') or '')[:10]
        descriptions.append(f"{name} (created {created})" if created else name)
    if descriptions:
        log(f"✋ Jobs awaiting authorization: {', '.join(descriptions)}")
    return descriptions


async def get_last_upload(client: SmartlingClient, file_uri: str) -> str:
    """When file_uri was last uploaded, or nothing if it was never uploaded."""
    try:
        status = await client.get_file_status(file_uri)
    except RuntimeError as error:
        if str(error).startswith('HTTP 404') or 'could not be found' in str(error):
            return ''
        raise
    return status.get('lastUploaded') or ''


async def wait_for_file_upload(client: SmartlingClient,
                               file_uri: str,
                               previous_upload: str,
                               sleep=asyncio.sleep):
    """Wait until Smartling reports an upload of file_uri newer than previous_upload."""
    for _ in range(60):
        try:
            last_uploaded = (await client.get_file_status(file_uri)).get('lastUploaded') or ''
        except Exception:  # pylint: disable=broad-except
            last_uploaded = ''
        if last_uploaded and last_uploaded != previous_upload:
            return
        await sleep(5)
    raise RuntimeError(f"Smartling did not finish processing {file_uri}")


async def wait_for_file_status(client: SmartlingClient, file_uri: str, sleep=asyncio.sleep):
    """Wait until Smartling stops answering HTTP 423 for file_uri, which it does while it processes an upload."""
    for attempt in range(60):
        try:
            await client.get_file_status(file_uri)
            return
        except RuntimeError as error:
            if not str(error).startswith('HTTP 423'):
                raise
        if attempt == 0:
            log(f"⏳ Smartling is still processing {file_uri}")
        await sleep(5)
    raise RuntimeError(f"Smartling did not finish processing {file_uri}")


async def run_refresh(client: SmartlingClient,
                      files: List[Path],
                      file_uri_prefix: str,
                      sleep=asyncio.sleep) -> List[str]:
    """Replace the content of <file_uri_prefix>/<file name> with files, outside any job."""
    file_uris = []
    for file_path in files:
        file_uri = f"{file_uri_prefix}/{file_path.name}"
        previous_upload = await get_last_upload(client, file_uri)
        upload_start = time.monotonic()
        response = await client.upload_file(file_path, file_uri)
        code = response.get('code')
        if code == 'ACCEPTED':
            log(f"⏳ Smartling is still processing {file_uri}")
            await wait_for_file_upload(client, file_uri, previous_upload, sleep)
        elif code == 'SUCCESS':
            await wait_for_file_status(client, file_uri, sleep)
        else:
            raise RuntimeError(f"Smartling answered {code or 'nothing'} to the upload of {file_uri}")
        details = response.get('data') or {}
        strings = details.get('stringCount')
        processing = f"processed in {time.monotonic() - upload_start:.0f}s"
        log(f"📤 Refreshed {file_uri} (" + (f"{strings} strings, " if strings is not None else "") + f"{processing})")
        file_uris.append(file_uri)
    return file_uris


def get_git_branch() -> str:
    """Get current git branch name."""
    result = subprocess.run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
                          capture_output=True, text=True, check=True)
    return result.stdout.strip()


def get_credentials(args) -> Credentials:
    """Get credentials from args or environment."""
    user_id = getattr(args, 'user_id', None) or os.environ.get('SMARTLING_USER_ID')
    user_secret = getattr(args, 'user_secret', None) or os.environ.get('SMARTLING_USER_SECRET')
    project_id = getattr(args, 'project_id', None) or os.environ.get('SMARTLING_PROJECT_ID')

    if not all([user_id, user_secret, project_id]):
        print(
            "❌ Missing credentials. Set SMARTLING_USER_ID, "
            "SMARTLING_USER_SECRET, SMARTLING_PROJECT_ID"
        )
        sys.exit(1)

    return Credentials(user_id, user_secret, project_id)


async def upload_command(args):
    """Upload files."""
    files = [Path(f) for f in args.files]

    for file_path in files:
        if not file_path.exists():
            print(f"❌ File not found: {file_path}")
            sys.exit(1)

    print("📄 Files to upload:")
    for file_path in files:
        print(f"   • {file_path}")

    async with SmartlingClient(get_credentials(args)) as client:
        # Create job
        locales = await client.get_project_locales()
        job_id = await client.create_job(args.job_name, locales, "Created via LocalizationTool")
        print(f"✅ Created job: {job_id}")

        # Create batch with file URIs
        branch = get_git_branch()
        file_uris = [f"{branch}/{file_path.name}" for file_path in files]
        batch_id = await client.create_batch(job_id, file_uris)
        print(f"📦 Created batch: {batch_id}")

        # Upload files
        print("📤 Uploading files...")
        for file_path, file_uri in zip(files, file_uris):
            await client.upload_to_batch(batch_id, file_path, file_uri, locales)
            print(f"   ✅ {file_path.name}")

        # Check batch status
        await asyncio.sleep(2)
        try:
            status = await client.get_batch_status(batch_id)
            print(f"📝 Batch status: {status}")
        except Exception:  # pylint: disable=broad-except
            print("📝 Batch created successfully")

        print(f"JOB_ID={job_id}")
        print(f"BATCH_ID={batch_id}")
        print(f"\n🎉 Upload complete! Job ID: {job_id}")


async def submit_command(args):
    """Create a translation job and authorize it if its maximum USD estimate is at most auto_authorize_max_usd."""
    try:
        files = [Path(file_path) for file_path in args.files]
        missing_files = [str(file_path) for file_path in files if not file_path.exists()]
        if missing_files:
            raise RuntimeError(f"Missing export files: {', '.join(missing_files)}")

        auto_authorize_max_usd = Decimal(args.auto_authorize_max_usd)
        log(f"Submitting {len(files)} files as '{args.job_name}' under {args.file_uri_prefix}/")
        async with SmartlingClient(get_credentials(args)) as client:
            result = await run_submit(
                client,
                files,
                args.job_name,
                args.pending_job_prefix,
                args.file_uri_prefix,
                auto_authorize_max_usd,
                args.delete_job_on_failure
            )
    except Exception as error:  # pylint: disable=broad-except
        log(f"❌ {error}")
        traceback.print_exc()
        result = SubmitResult(
            outcome='review_required',
            reason=error_reason(error),
            failed=True
        )

    summary = f"{result.job_name or args.job_name}: {result.outcome}"
    if result.reason:
        summary += f" ({result.reason})"
    if result.failed:
        annotate('error', summary)
    elif result.outcome in {'review_required', 'pending_review'}:
        annotate('warning', summary)
    else:
        annotate('notice', summary)

    result_path = Path(args.result_file)
    result_path.write_text(json.dumps(result.as_dict()), encoding='utf-8')
    print(f"OUTCOME={result.outcome}")
    print(f"JOB_ID={result.job_id}")
    print(f"JOB_NAME={result.job_name}")
    print(f"TOTAL_STRINGS={'' if result.total_strings is None else result.total_strings}")
    print(f"LOCALES={'' if result.locales is None else result.locales}")
    print(f"MAX_USD={result.max_usd}")
    print(f"REASON={result.reason}")


async def release_status_command(args):
    """Report whether a release's files are translated in every locale."""
    try:
        async with SmartlingClient(get_credentials(args)) as client:
            result = await run_release_status(client, args.job_name, args.file_uris)
            if result.job_id:
                result.job_url = job_url(client, result.job_id)
    except Exception as error:  # pylint: disable=broad-except
        result = failed_release_status(error)

    if result.outcome == 'error':
        annotate('error', f"{args.job_name}: {result.reason}")
    else:
        annotate('notice', f"{args.job_name}: {result.outcome}")

    Path(args.result_file).write_text(json.dumps(result.as_dict()), encoding='utf-8')
    print(f"OUTCOME={result.outcome}")
    print(f"JOB_ID={result.job_id}")
    print(f"JOB_STATUS={result.job_status}")
    print(f"STRINGS_LEFT={'' if result.strings_left is None else result.strings_left}")
    print(f"REASON={result.reason}")


async def refresh_files_command(args):
    """Replace the content of release files with the current export, outside any job."""
    files = [Path(file_path) for file_path in args.files]
    missing_files = [str(file_path) for file_path in files if not file_path.exists()]
    if missing_files:
        raise RuntimeError(f"Missing export files: {', '.join(missing_files)}")

    async with SmartlingClient(get_credentials(args)) as client:
        file_uris = await run_refresh(client, files, args.file_uri_prefix)
    print(f"REFRESHED={' '.join(file_uris)}")


async def status_command(args):
    """Check job status."""
    async with SmartlingClient(get_credentials(args)) as client:
        job = await client.get_job(args.job_id)

        print(f"STATUS={job['jobStatus']}")
        print(f"\n📊 Job Status: {job['jobStatus']}")
        print(f"📋 Job Name: {job['jobName']}")
        print(f"🎯 Target Locales: {len(job['targetLocaleIds'])}")

        if job['jobStatus'] != "AWAITING_AUTHORIZATION":
            try:
                progress = await client.get_job_progress(args.job_id)
                print(f"PERCENT={progress}")
                print(f"📈 Progress: {progress}%")
            except Exception:  # pylint: disable=broad-except
                print("PERCENT=0")
                print("⚠️  Could not get progress")
        else:
            print("PERCENT=0")
            print("⏳ Job is awaiting authorization")


async def approve_command(args):
    """Approve job for translation."""
    async with SmartlingClient(get_credentials(args)) as client:
        print(f"🔍 Approving job: {args.job_id}")
        job = await client.get_job(args.job_id)
        print(f"📋 Job: {job['jobName']}")

        if job['jobStatus'] != "AWAITING_AUTHORIZATION":
            print(f"❌ Job is not ready for authorization (status: {job['jobStatus']})")
            sys.exit(1)

        try:
            await client.authorize_job(args.job_id)
            print("APPROVED=1")
            print("✅ Job authorized successfully!")
        except Exception as e:  # pylint: disable=broad-except
            print("APPROVED=0")
            print(f"❌ Authorization failed: {e}")
            sys.exit(1)


async def download_command(args):
    """Download translated files."""
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    async with SmartlingClient(get_credentials(args)) as client:
        if args.file_uris:
            file_uris = args.file_uris
            locales = await client.get_project_locales()
            print(f"📁 Downloading {len(file_uris)} files for {len(locales)} locales")
        else:
            job = await client.get_job(args.job_id)
            print(f"📋 Job: {job['jobName']}")
            print(f"📊 Status: {job['jobStatus']}")

            if job['jobStatus'] != "COMPLETED":
                if not args.allow_unfinished:
                    print("DOWNLOADED=0")
                    print(f"⚠️  Job not completed (status: {job['jobStatus']})")
                    return
                print(f"⚠️  Job not completed (status: {job['jobStatus']}), downloading anyway (--allow-unfinished)")

            file_uris = await client.get_job_files(args.job_id)
            if not file_uris:
                print("DOWNLOADED=0")
                print("⚠️  No files found in job")
                return

            print(f"📁 Found {len(file_uris)} files")
            locales = job['targetLocaleIds']

        count = 0
        for file_uri in file_uris:
            for locale in locales:
                try:
                    data = await client.download_file(file_uri, locale)
                    file_name = Path(file_uri).name

                    # Add locale suffix before the last extension (or append if none)
                    if '.' in file_name:
                        name, ext = file_name.rsplit('.', 1)
                        file_name = f"{name}_{locale}.{ext}"
                    else:
                        file_name = f"{file_name}_{locale}"

                    (out_dir / file_name).write_bytes(data)
                    print(f"   ✅ {file_name} ({locale})")
                    count += 1
                except Exception as e:  # pylint: disable=broad-except
                    print(f"⚠️  Failed to download {file_uri} for {locale}: {e}")

        print(f"DOWNLOADED={count}")
        if args.file_uris and count < len(file_uris) * len(locales):
            raise RuntimeError(f"Downloaded {count} of {len(file_uris) * len(locales)} files")
        print(f"\n🎉 Downloaded {count} files")


# ============================================================================
# Main CLI
# ============================================================================

def main():
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(description='Smartling localization tool')
    subparsers = parser.add_subparsers(dest='command')

    # Upload
    upload_parser = subparsers.add_parser('upload')
    upload_parser.add_argument('--job-name', required=True)
    upload_parser.add_argument('--files', nargs='+', required=True)

    # Submit
    submit_parser = subparsers.add_parser('submit')
    submit_parser.add_argument('--job-name', required=True)
    submit_parser.add_argument('--pending-job-prefix', default='',
                               help='Skip submission while a job with this name prefix awaits authorization')
    submit_parser.add_argument('--file-uri-prefix', required=True,
                               help='Smartling file URIs become <prefix>/<file name>, e.g. main or release/ios/7.200.0')
    submit_parser.add_argument('--files', nargs='+', required=True)
    submit_parser.add_argument('--auto-authorize-max-usd', default='500.00',
                               help='Authorize the job when its maximum USD estimate is at most this amount')
    submit_parser.add_argument('--delete-job-on-failure', action='store_true',
                               help='Delete the job this run created if the submission fails before authorizing it')
    submit_parser.add_argument('--result-file', default='submit_result.json')

    # Release status
    release_status_parser = subparsers.add_parser('release-status')
    release_status_parser.add_argument('--job-name', required=True,
                                       help="The release's job, e.g. 'Release iOS 7.200.0', linked when it exists")
    release_status_parser.add_argument('--file-uris', nargs='+', required=True,
                                       help='The release files, e.g. release/ios/7.200.0/en.xliff')
    release_status_parser.add_argument('--result-file', default='release_status.json')

    # Refresh files
    refresh_parser = subparsers.add_parser('refresh-files')
    refresh_parser.add_argument('--file-uri-prefix', required=True,
                                help='Smartling file URIs become <prefix>/<file name>, e.g. release/ios/7.200.0')
    refresh_parser.add_argument('--files', nargs='+', required=True)

    # Status
    status_parser = subparsers.add_parser('status')
    status_parser.add_argument('--job-id', required=True)

    # Approve
    approve_parser = subparsers.add_parser('approve')
    approve_parser.add_argument('--job-id', required=True)

    # Download
    download_parser = subparsers.add_parser('download')
    download_source = download_parser.add_mutually_exclusive_group(required=True)
    download_source.add_argument('--job-id')
    download_source.add_argument('--file-uris', nargs='+',
                                 help="Download these files for every project locale, whatever their job's status")
    download_parser.add_argument('--out-dir', default='./downloads')
    download_parser.add_argument('--allow-unfinished', action='store_true',
                                 help='Download even if the job is not COMPLETED (defaults to False)')

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Run command
    commands = {
        'upload': upload_command,
        'submit': submit_command,
        'release-status': release_status_command,
        'refresh-files': refresh_files_command,
        'status': status_command,
        'approve': approve_command,
        'download': download_command,
    }

    try:
        asyncio.run(commands[args.command](args))
    except KeyboardInterrupt:
        print("\n❌ Cancelled")
        sys.exit(1)
    except Exception as e:  # pylint: disable=broad-except
        print(f"\n❌ Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
