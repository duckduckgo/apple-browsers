#!/usr/bin/env python3

import importlib.util
import sys
import unittest
from decimal import Decimal
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / 'localization_tool.py'
SPEC = importlib.util.spec_from_file_location('localization_tool', MODULE_PATH)
LOCALIZATION_TOOL = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = LOCALIZATION_TOOL
SPEC.loader.exec_module(LOCALIZATION_TOOL)


async def no_sleep(_):
    return None


class FakeSmartlingClient:

    def __init__(self, report=None, pending_jobs=None, estimate_status='COMPLETED'):
        self.report = report or {}
        self.pending_jobs = pending_jobs or []
        self.estimate_status = estimate_status
        self.authorized_jobs = []
        self.deleted_jobs = []
        self.created_jobs = []

    async def list_jobs(self, _job_name, _statuses):
        return self.pending_jobs

    async def get_project_locales(self):
        return ['de-DE']

    async def create_job(self, name, _locales, _description):
        self.created_jobs.append(name)
        return 'job-123'

    async def create_batch(self, _job_id, _file_uris):
        return 'batch-123'

    async def upload_to_batch(self, _batch_id, _file_path, _file_uri, _locales):
        return None

    async def get_batch_status(self, _batch_id):
        return 'COMPLETED'

    async def generate_cost_estimate(self, _job_id):
        return 'report-123'

    async def get_estimate_status(self, _report_id):
        return self.estimate_status

    async def get_estimate_report(self, _report_id):
        return self.report

    async def delete_job(self, job_id):
        self.deleted_jobs.append(job_id)

    async def authorize_job(self, job_id):
        self.authorized_jobs.append(job_id)


class NightlySmartlingTests(unittest.IsolatedAsyncioTestCase):

    async def run_nightly(self, client):
        return await LOCALIZATION_TOOL.run_nightly(
            client=client,
            files=[Path('en.xliff')],
            job_name='Nightly iOS - 2026-08-04',
            job_prefix='Nightly iOS - ',
            threshold=Decimal('500.00'),
            sleep=no_sleep
        )

    async def testWhenNoStringsNeedTranslationThenJobIsDeleted(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 0,
            'priceInformation': None,
        })

        result = await self.run_nightly(client)

        self.assertEqual(result.outcome, 'no_content')
        self.assertEqual(client.deleted_jobs, ['job-123'])
        self.assertEqual(client.authorized_jobs, [])

    async def testWhenMaximumEstimateIsExactlyLimitThenJobIsAuthorized(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 10,
            'priceInformation': [
                {'currencyCode': 'USD', 'priceMin': 450, 'priceMax': 500},
            ],
        })

        result = await self.run_nightly(client)

        self.assertEqual(result.outcome, 'authorized')
        self.assertEqual(result.max_usd, '500')
        self.assertEqual(client.authorized_jobs, ['job-123'])

    async def testWhenMaximumEstimateExceedsLimitThenReviewIsRequired(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 10,
            'priceInformation': [
                {'currencyCode': 'USD', 'priceMin': 400, 'priceMax': 500.01},
            ],
        })

        result = await self.run_nightly(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertEqual(result.job_id, 'job-123')
        self.assertEqual(result.max_usd, '500.01')
        self.assertEqual(client.authorized_jobs, [])

    async def testWhenEstimateHasNoUSDPriceThenReviewIsRequired(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 10,
            'priceInformation': [
                {'currencyCode': 'EUR', 'priceMin': 100, 'priceMax': 120},
            ],
        })

        result = await self.run_nightly(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('no maximum USD price', result.reason)

    async def testWhenEstimateFailsThenReviewIsRequired(self):
        client = FakeSmartlingClient(estimate_status='FAILED')

        result = await self.run_nightly(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('status FAILED', result.reason)

    async def testWhenEstimateTimesOutThenReviewIsRequired(self):
        client = FakeSmartlingClient(estimate_status='PROCESSING')

        result = await self.run_nightly(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('timed out', result.reason)

    async def testWhenPendingNightlyJobExistsThenNoJobIsCreated(self):
        client = FakeSmartlingClient(pending_jobs=[{
            'jobName': 'Nightly iOS - 2026-08-03',
            'translationJobUid': 'pending-job',
        }])

        result = await self.run_nightly(client)

        self.assertEqual(result.outcome, 'skipped_active_job')
        self.assertEqual(result.job_id, 'pending-job')
        self.assertEqual(client.created_jobs, [])


if __name__ == '__main__':
    unittest.main()
