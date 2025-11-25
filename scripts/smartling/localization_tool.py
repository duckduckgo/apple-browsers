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
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict
from dataclasses import dataclass
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

    async def get_project_locales(self) -> List[str]:
        """Get valid project locales."""
        data = await self._request('GET', f'/projects-api/v2/projects/{self.creds.project_id}')
        return [loc['localeId'] for loc in data['response']['data']['targetLocales']]

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

    async def get_job_files(self, job_id: str) -> List[str]:
        """Get file URIs in job."""
        data = await self._request(
            'GET', f'/jobs-api/v3/projects/{self.creds.project_id}/jobs/{job_id}/files'
        )
        return [f['uri'] for f in data['response']['data'].get('items', [])]

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
        job = await client.get_job(args.job_id)
        print(f"📋 Job: {job['jobName']}")
        print(f"📊 Status: {job['jobStatus']}")

        if job['jobStatus'] != "COMPLETED":
            print("DOWNLOADED=0")
            print(f"⚠️  Job not completed (status: {job['jobStatus']})")
            return

        file_uris = await client.get_job_files(args.job_id)
        if not file_uris:
            print("DOWNLOADED=0")
            print("⚠️  No files found in job")
            return

        print(f"📁 Found {len(file_uris)} files")

        count = 0
        for file_uri in file_uris:
            for locale in job['targetLocaleIds']:
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

    # Status
    status_parser = subparsers.add_parser('status')
    status_parser.add_argument('--job-id', required=True)

    # Approve
    approve_parser = subparsers.add_parser('approve')
    approve_parser.add_argument('--job-id', required=True)

    # Download
    download_parser = subparsers.add_parser('download')
    download_parser.add_argument('--job-id', required=True)
    download_parser.add_argument('--out-dir', default='./downloads')

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Run command
    commands = {
        'upload': upload_command,
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
