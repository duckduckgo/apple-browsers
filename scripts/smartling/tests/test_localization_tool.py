#!/usr/bin/env python3

import argparse
import contextlib
import importlib.util
import io
import sys
import tempfile
import unittest
import unittest.mock
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

    def __init__(self,
                 report=None,
                 pending_jobs=None,
                 named_jobs=None,
                 batch_status='COMPLETED',
                 estimate_status='COMPLETED',
                 cancellation_state='COMPLETED',
                 job_status='CANCELLED',
                 locales=None,
                 file_statuses=None,
                 list_jobs_error=None,
                 failing_downloads=None,
                 awaiting_jobs=None,
                 awaiting_jobs_error=None,
                 file_status_error=None,
                 upload_code='SUCCESS',
                 polls_until_processed=0,
                 authorize_error=None):
        self.creds = LOCALIZATION_TOOL.Credentials('user', 'secret', 'project-123')
        self.report = report or {}
        self.pending_jobs = pending_jobs or []
        self.named_jobs = named_jobs or []
        self.batch_status = batch_status
        self.estimate_status = estimate_status
        self.cancellation_state = cancellation_state
        self.job_status = job_status
        self.locales = locales or ['de-DE']
        self.file_statuses = file_statuses or {}
        self.list_jobs_error = list_jobs_error
        self.failing_downloads = failing_downloads or set()
        self.awaiting_jobs = awaiting_jobs or []
        self.awaiting_jobs_error = awaiting_jobs_error
        self.file_status_error = file_status_error
        self.awaiting_jobs_calls = 0
        self.upload_code = upload_code
        self.polls_until_processed = polls_until_processed
        self.refreshed = []
        self.downloaded = []
        self.authorize_error = authorize_error
        self.authorized_jobs = []
        self.deleted_jobs = []
        self.created_jobs = []
        self.uploaded_file_uris = []
        self.operations = []

    async def list_jobs(self, _job_name, statuses):
        if self.list_jobs_error:
            raise self.list_jobs_error
        return self.pending_jobs if statuses else self.named_jobs

    async def get_project_locales(self):
        return self.locales

    async def create_job(self, name, _locales, _description):
        self.created_jobs.append(name)
        return 'job-123'

    async def create_batch(self, _job_id, _file_uris):
        return 'batch-123'

    async def upload_to_batch(self, _batch_id, _file_path, file_uri, _locales):
        self.uploaded_file_uris.append(file_uri)

    async def get_batch_status(self, _batch_id):
        return self.batch_status

    async def generate_cost_estimate(self, _job_id):
        return 'report-123'

    async def get_estimate_status(self, _report_id):
        return self.estimate_status

    async def get_estimate_report(self, _report_id):
        return self.report

    async def cancel_job(self, job_id):
        self.operations.append(f'cancel:{job_id}')
        return 'process-123'

    async def get_job_process_state(self, _job_id, _process_id):
        return self.cancellation_state

    async def get_job(self, _job_id):
        return {'jobStatus': self.job_status, 'jobName': 'PR job', 'targetLocaleIds': ['fr-FR']}

    async def get_job_files(self, _job_id):
        return ['feature/en.xliff']

    async def get_file_status(self, file_uri):
        if self.file_status_error:
            raise self.file_status_error
        if file_uri not in self.file_statuses:
            raise RuntimeError('HTTP 404: File not found')
        status = self.file_statuses[file_uri]
        if status.get('processing_polls_left'):
            status['processing_polls_left'] -= 1
            if not status['processing_polls_left']:
                status['lastUploaded'] = status.pop('pending_upload')
        return status

    async def upload_file(self, file_path, file_uri):
        self.refreshed.append((file_path.name, file_uri))
        status = self.file_statuses.setdefault(file_uri, {})
        upload_time = f'upload-{len(self.refreshed)}'
        if self.upload_code == 'ACCEPTED' and self.polls_until_processed:
            status['pending_upload'] = upload_time
            status['processing_polls_left'] = self.polls_until_processed
        elif self.upload_code != 'ACCEPTED':
            status['lastUploaded'] = upload_time
        return {'code': self.upload_code, 'data': {'stringCount': 42}}

    async def list_jobs_awaiting_authorization(self):
        self.awaiting_jobs_calls += 1
        if self.awaiting_jobs_error:
            raise self.awaiting_jobs_error
        return self.awaiting_jobs

    async def download_file(self, file_uri, locale):
        if (file_uri, locale) in self.failing_downloads:
            raise RuntimeError('HTTP 500: Server error')
        self.downloaded.append((file_uri, locale))
        return f'{file_uri} {locale}'.encode()

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_args):
        return None

    async def delete_job(self, job_id):
        self.operations.append(f'delete:{job_id}')
        self.deleted_jobs.append(job_id)

    async def authorize_job(self, job_id):
        self.authorized_jobs.append(job_id)
        if self.authorize_error:
            raise self.authorize_error


class SubmitSmartlingTests(unittest.IsolatedAsyncioTestCase):

    def setUp(self):
        export_dir = tempfile.TemporaryDirectory()
        self.addCleanup(export_dir.cleanup)
        self.export_file = Path(export_dir.name) / 'en.xliff'
        self.export_file.write_text('<xliff/>', encoding='utf-8')

    async def run_submit(self,
                         client,
                         auto_authorize_max_usd='500.00',
                         delete_job_on_failure=False,
                         job_name='Nightly iOS - 2026-08-04',
                         pending_job_prefix='Nightly iOS - '):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return await LOCALIZATION_TOOL.run_submit(
                client=client,
                files=[self.export_file],
                job_name=job_name,
                pending_job_prefix=pending_job_prefix,
                file_uri_prefix='main',
                auto_authorize_max_usd=Decimal(auto_authorize_max_usd),
                delete_job_on_failure=delete_job_on_failure,
                sleep=no_sleep
            )

    async def testWhenNoStringsNeedTranslationThenJobIsDeleted(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 0,
            'priceInformation': None,
        })

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'no_new_strings')
        self.assertEqual(result.job_id, 'job-123')
        self.assertEqual(client.deleted_jobs, ['job-123'])
        self.assertEqual(client.authorized_jobs, [])
        self.assertEqual(client.operations, ['cancel:job-123', 'delete:job-123'])

    async def testWhenEmptyJobCancellationFailsThenJobIsNotDeleted(self):
        client = FakeSmartlingClient(
            report={
                'totalStrings': 0,
                'priceInformation': None,
            },
            cancellation_state='FAILED'
        )

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('cancellation failed', result.reason)
        self.assertEqual(client.operations, ['cancel:job-123'])

    async def testWhenMaximumEstimateIsExactlyLimitThenJobIsAuthorized(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 10,
            'priceInformation': [
                {'currencyCode': 'USD', 'priceMin': 450, 'priceMax': 500},
            ],
        })

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'authorized')
        self.assertEqual(result.max_usd, '500')
        self.assertEqual(client.authorized_jobs, ['job-123'])
        self.assertEqual(client.uploaded_file_uris, ['main/en.xliff'])

    async def testWhenMaximumEstimateExceedsLimitThenReviewIsRequired(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 10,
            'priceInformation': [
                {'currencyCode': 'USD', 'priceMin': 400, 'priceMax': 500.01},
            ],
        })

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertEqual(result.job_id, 'job-123')
        self.assertEqual(result.max_usd, '500.01')
        self.assertEqual((result.total_strings, result.locales), (10, 1))
        self.assertFalse(result.as_dict()['failed'])
        self.assertEqual(client.authorized_jobs, [])

    async def testWhenEstimateHasWarningsThenReviewIsRequired(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 10,
            'priceInformation': [
                {'currencyCode': 'USD', 'priceMin': 80, 'priceMax': 100},
            ],
            'warnings': [{'message': 'No rate found for de-DE'}],
        })

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('No rate found for de-DE', result.reason)
        self.assertEqual(client.authorized_jobs, [])

    async def testWhenLimitIsZeroThenZeroPricedJobIsNotAuthorized(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 10,
            'priceInformation': [
                {'currencyCode': 'USD', 'priceMin': 0, 'priceMax': 0},
            ],
        })

        result = await self.run_submit(client, auto_authorize_max_usd='0')

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('limit is 0', result.reason)
        self.assertEqual(client.authorized_jobs, [])

    async def testWhenEstimateHasNoUSDPriceThenReviewIsRequired(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 10,
            'priceInformation': [
                {'currencyCode': 'EUR', 'priceMin': 100, 'priceMax': 120},
            ],
        })

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('no maximum USD price', result.reason)

    async def testWhenEstimateHasSeveralUSDPricesThenReviewIsRequired(self):
        client = FakeSmartlingClient(report={
            'totalStrings': 10,
            'priceInformation': [
                {'currencyCode': 'USD', 'priceMin': 200, 'priceMax': 300},
                {'currencyCode': 'USD', 'priceMin': 250, 'priceMax': 400},
            ],
        })

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('2 USD prices', result.reason)
        self.assertEqual(client.authorized_jobs, [])

    async def testWhenEstimateFailsThenReviewIsRequired(self):
        client = FakeSmartlingClient(estimate_status='FAILED')

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('status FAILED', result.reason)
        self.assertTrue(result.as_dict()['failed'])
        self.assertEqual(client.operations, [])

    async def testWhenSubmissionFailsAndDeletingIsOnThenJobIsDeleted(self):
        client = FakeSmartlingClient(estimate_status='FAILED')

        result = await self.run_submit(client, delete_job_on_failure=True)

        self.assertTrue(result.failed)
        self.assertEqual((result.job_id, result.job_name), ('', ''))
        self.assertIn('rerun starts over', result.reason)
        self.assertEqual(client.operations, ['cancel:job-123', 'delete:job-123'])

    async def testWhenAuthorizationTimesOutThenTheJobIsNotDeleted(self):
        client = FakeSmartlingClient(
            report={
                'totalStrings': 10,
                'priceInformation': [{'currencyCode': 'USD', 'priceMin': 10, 'priceMax': 20}],
            },
            authorize_error=TimeoutError('read timed out')
        )

        result = await self.run_submit(client, delete_job_on_failure=True)

        self.assertTrue(result.failed)
        self.assertEqual(result.job_id, 'job-123')
        self.assertEqual(client.authorized_jobs, ['job-123'])
        self.assertEqual(client.operations, [])

    async def testWhenDeletingTheFailedJobFailsThenItIsKeptAndReported(self):
        client = FakeSmartlingClient(estimate_status='FAILED', cancellation_state='FAILED')

        result = await self.run_submit(client, delete_job_on_failure=True)

        self.assertTrue(result.failed)
        self.assertEqual(result.job_id, 'job-123')
        self.assertIn('delete it before a rerun', result.reason)
        self.assertEqual(client.operations, ['cancel:job-123'])

    async def testWhenEstimateTimesOutThenReviewIsRequired(self):
        client = FakeSmartlingClient(estimate_status='PROCESSING')

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertIn('timed out', result.reason)

    async def testWhenPendingJobWithPrefixExistsThenItIsReportedWithoutCreatingAJob(self):
        client = FakeSmartlingClient(pending_jobs=[{
            'jobName': 'Nightly iOS - 2026-08-03',
            'translationJobUid': 'pending-job',
        }])

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'pending_review')
        self.assertEqual(result.job_id, 'pending-job')
        self.assertEqual(result.job_name, 'Nightly iOS - 2026-08-03')
        self.assertIsNone(result.total_strings)
        self.assertIn('Nightly iOS - 2026-08-03', result.reason)
        self.assertEqual(client.created_jobs, [])

    async def testWhenThereIsNoPendingPrefixThenSimilarlyNamedPendingJobsDontBlock(self):
        client = FakeSmartlingClient(pending_jobs=[{
            'jobName': 'Release iOS 7.200.0 (test)',
            'translationJobUid': 'test-job',
        }])

        await self.run_submit(client, job_name='Release iOS 7.200.0', pending_job_prefix='')

        self.assertEqual(client.created_jobs, ['Release iOS 7.200.0'])

    async def testWhenJobWithSameNameExistsThenNoJobIsCreated(self):
        client = FakeSmartlingClient(named_jobs=[
            {'jobName': 'Nightly iOS - 2026-08-04 (copy)', 'translationJobUid': 'other-job'},
            {'jobName': 'Nightly iOS - 2026-08-04', 'translationJobUid': 'todays-job'},
        ])

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'skipped_existing_job')
        self.assertEqual(result.job_id, 'todays-job')
        self.assertEqual(client.created_jobs, [])

    async def testWhenBatchCompletesWithErrorsThenReviewIsRequired(self):
        client = FakeSmartlingClient(batch_status='COMPLETED_WITH_ERRORS')

        result = await self.run_submit(client)

        self.assertEqual(result.outcome, 'review_required')
        self.assertEqual(result.job_id, 'job-123')
        self.assertIn('COMPLETED_WITH_ERRORS', result.reason)
        self.assertEqual(client.authorized_jobs, [])


XLIFF_URI = 'release/ios/7.200.0/en.xliff'
STRINGSDICT_URI = 'release/ios/7.200.0/Localizable.stringsdict'


def file_status(total, **locale_counts):
    """A Smartling file status with total strings and (completed, excluded) counts per locale."""
    return {
        'totalStringCount': total,
        'items': [
            {'localeId': locale.replace('_', '-'), 'completedStringCount': completed, 'excludedStringCount': excluded}
            for locale, (completed, excluded) in locale_counts.items()
        ],
    }


class ReleaseStatusTests(unittest.IsolatedAsyncioTestCase):

    async def release_status(self, client, file_uris=(XLIFF_URI,)):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return await LOCALIZATION_TOOL.run_release_status(
                client=client,
                job_name='Release iOS 7.200.0',
                file_uris=list(file_uris)
            )

    async def testWhenEveryLocaleIsCompletedThenReleaseIsReady(self):
        client = FakeSmartlingClient(
            locales=['de-DE', 'fr-FR'],
            named_jobs=[{'jobName': 'Release iOS 7.200.0', 'translationJobUid': 'release-job', 'jobStatus': 'COMPLETED'}],
            file_statuses={
                XLIFF_URI: file_status(10, de_DE=(10, 0), fr_FR=(10, 0)),
                STRINGSDICT_URI: file_status(2, de_DE=(2, 0), fr_FR=(2, 0)),
            }
        )

        result = await self.release_status(client, (XLIFF_URI, STRINGSDICT_URI))

        self.assertEqual(result.outcome, 'ready')
        self.assertEqual((result.job_id, result.job_status), ('release-job', 'COMPLETED'))
        self.assertEqual((result.total_strings, result.strings_left), (24, 0))
        self.assertEqual(result.incomplete_locales, [])

    async def testWhenALocaleHasStringsLeftThenReleaseIsNotReady(self):
        client = FakeSmartlingClient(
            locales=['de-DE', 'fr-FR'],
            file_statuses={
                XLIFF_URI: file_status(10, de_DE=(10, 0), fr_FR=(7, 0)),
                STRINGSDICT_URI: file_status(2, de_DE=(1, 0), fr_FR=(2, 0)),
            }
        )

        result = await self.release_status(client, (XLIFF_URI, STRINGSDICT_URI))

        self.assertEqual(result.outcome, 'not_ready')
        self.assertEqual(result.strings_left, 4)
        self.assertEqual(result.incomplete_locales, ['de-DE', 'fr-FR'])

    async def testWhenStringsAreExcludedThenTheyCountAsDone(self):
        client = FakeSmartlingClient(file_statuses={XLIFF_URI: file_status(10, de_DE=(8, 2))})

        result = await self.release_status(client)

        self.assertEqual(result.outcome, 'ready')

    async def testWhenALocaleIsMissingFromTheFileStatusThenAllItsStringsAreLeft(self):
        client = FakeSmartlingClient(
            locales=['de-DE', 'fr-FR'],
            file_statuses={XLIFF_URI: file_status(10, de_DE=(10, 0))}
        )

        result = await self.release_status(client)

        self.assertEqual(result.outcome, 'not_ready')
        self.assertEqual(result.strings_left, 10)
        self.assertEqual(result.incomplete_locales, ['fr-FR'])

    async def testWhenThereIsNoReleaseJobThenTheFileStatusDecides(self):
        client = FakeSmartlingClient(
            named_jobs=[{'jobName': 'Release iOS 7.200.0 (copy)', 'translationJobUid': 'other-job'}],
            file_statuses={XLIFF_URI: file_status(10, de_DE=(10, 0))}
        )

        result = await self.release_status(client)

        self.assertEqual(result.outcome, 'ready')
        self.assertEqual(result.job_id, '')

    async def testWhenTheJobLookupFailsThenTheFileStatusStillDecides(self):
        client = FakeSmartlingClient(
            list_jobs_error=RuntimeError('HTTP 500: Server error'),
            file_statuses={XLIFF_URI: file_status(10, de_DE=(3, 0))}
        )

        result = await self.release_status(client)

        self.assertEqual(result.outcome, 'not_ready')
        self.assertEqual(result.strings_left, 7)

    async def testWhenAReleaseFileIsMissingThenItIsAnError(self):
        client = FakeSmartlingClient(file_statuses={XLIFF_URI: file_status(10, de_DE=(10, 0))})

        result = await self.release_status(client, (XLIFF_URI, STRINGSDICT_URI))

        self.assertEqual(result.outcome, 'error')
        self.assertIn(STRINGSDICT_URI, result.reason)

    async def testWhenTheReleaseFilesHaveNoStringsThenItIsAnError(self):
        client = FakeSmartlingClient(file_statuses={XLIFF_URI: file_status(0)})

        result = await self.release_status(client)

        self.assertEqual(result.outcome, 'error')
        self.assertIn('no strings', result.reason)


class ProjectLocalesTests(unittest.IsolatedAsyncioTestCase):

    async def testWhenALocaleIsDisabledThenItIsNotAProjectLocale(self):
        client = LOCALIZATION_TOOL.SmartlingClient(LOCALIZATION_TOOL.Credentials('user', 'secret', 'project'))
        client._request = unittest.mock.AsyncMock(return_value={'response': {'data': {'targetLocales': [
            {'localeId': 'de-DE', 'enabled': True},
            {'localeId': 'fr-FR', 'enabled': False},
            {'localeId': 'it-IT'},
        ]}}})

        locales = await client.get_project_locales()

        self.assertEqual(locales, ['de-DE', 'it-IT'])


class ReleaseStatusJobsAwaitingAuthorizationTests(unittest.IsolatedAsyncioTestCase):

    async def release_status(self, client):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return await LOCALIZATION_TOOL.run_release_status(
                client=client,
                job_name='Release iOS 7.200.0',
                file_uris=[XLIFF_URI]
            )

    async def testWhenNotReadyThenJobsAwaitingAuthorizationAreListedOldestFirstWithTheirLinks(self):
        client = FakeSmartlingClient(
            file_statuses={XLIFF_URI: file_status(10, de_DE=(3, 0))},
            awaiting_jobs=[
                {'jobName': 'pau/feature-2026-10-20', 'createdDate': '2026-10-20T10:00:00Z', 'translationJobUid': 'job-2'},
                {'jobName': 'keyChange', 'createdDate': '2025-04-04T14:23:00Z', 'translationJobUid': 'job-1'},
            ]
        )

        result = await self.release_status(client)

        self.assertEqual(result.outcome, 'not_ready')
        self.assertEqual(result.jobs_awaiting_authorization, [
            {
                'name': 'keyChange',
                'created': '2025-04-04',
                'url': 'https://dashboard.smartling.com/app/projects/project-123/account-jobs/project-123:job-1',
            },
            {
                'name': 'pau/feature-2026-10-20',
                'created': '2026-10-20',
                'url': 'https://dashboard.smartling.com/app/projects/project-123/account-jobs/project-123:job-2',
            },
        ])

    async def testWhenReadyThenJobsAwaitingAuthorizationAreNotLookedUp(self):
        client = FakeSmartlingClient(
            file_statuses={XLIFF_URI: file_status(10, de_DE=(10, 0))},
            awaiting_jobs=[{'jobName': 'keyChange', 'createdDate': '2025-04-04T14:23:00Z'}]
        )

        result = await self.release_status(client)

        self.assertEqual(result.outcome, 'ready')
        self.assertEqual(result.jobs_awaiting_authorization, [])
        self.assertEqual(client.awaiting_jobs_calls, 0)

    async def testWhenStringsAreNotAuthorizedThenTheyAreCountedAcrossLocales(self):
        status = file_status(10, de_DE=(3, 0), fr_FR=(9, 1))
        status['items'][0]['authorizedStringCount'] = 4
        client = FakeSmartlingClient(locales=['de-DE', 'fr-FR', 'it-IT'], file_statuses={XLIFF_URI: status})

        result = await self.release_status(client)

        self.assertEqual(result.outcome, 'not_ready')
        self.assertEqual(result.strings_left, 17)
        self.assertEqual(result.strings_awaiting_authorization, 13)

    async def testWhenListingJobsAwaitingAuthorizationFailsThenTheStatusIsStillReported(self):
        client = FakeSmartlingClient(
            file_statuses={XLIFF_URI: file_status(10, de_DE=(3, 0))},
            awaiting_jobs_error=RuntimeError('HTTP 500: Server error')
        )

        result = await self.release_status(client)

        self.assertEqual(result.outcome, 'not_ready')
        self.assertEqual(result.strings_left, 7)
        self.assertEqual(result.jobs_awaiting_authorization, [])


class RefreshTests(unittest.IsolatedAsyncioTestCase):

    def setUp(self):
        export_dir = tempfile.TemporaryDirectory()
        self.addCleanup(export_dir.cleanup)
        self.xliff = Path(export_dir.name) / 'en.xliff'
        self.stringsdict = Path(export_dir.name) / 'Localizable.stringsdict'
        self.xliff.write_text('<xliff/>', encoding='utf-8')
        self.stringsdict.write_text('<plist/>', encoding='utf-8')

    async def refresh(self, client):
        with contextlib.redirect_stdout(io.StringIO()):
            return await LOCALIZATION_TOOL.run_refresh(
                client, [self.xliff, self.stringsdict], 'release/ios/7.200.0', sleep=no_sleep
            )

    async def testWhenRefreshingThenEachFileReplacesTheReleaseFileWithTheSameName(self):
        client = FakeSmartlingClient()

        file_uris = await self.refresh(client)

        self.assertEqual(file_uris, [XLIFF_URI, STRINGSDICT_URI])
        self.assertEqual(client.refreshed, [('en.xliff', XLIFF_URI), ('Localizable.stringsdict', STRINGSDICT_URI)])
        self.assertEqual(client.created_jobs, [])
        self.assertEqual(client.authorized_jobs, [])

    async def testWhenSmartlingIsStillProcessingAnUploadThenTheRefreshWaitsForIt(self):
        client = FakeSmartlingClient(
            upload_code='ACCEPTED',
            polls_until_processed=3,
            file_statuses={
                XLIFF_URI: {'lastUploaded': 'code-freeze'},
                STRINGSDICT_URI: {'lastUploaded': 'code-freeze'},
            }
        )

        await self.refresh(client)

        self.assertEqual(client.file_statuses[XLIFF_URI]['lastUploaded'], 'upload-1')
        self.assertEqual(client.file_statuses[STRINGSDICT_URI]['lastUploaded'], 'upload-2')

    async def testWhenThePreviousUploadCannotBeReadThenNothingIsUploaded(self):
        client = FakeSmartlingClient(
            file_statuses={XLIFF_URI: {'lastUploaded': 'code-freeze'}},
            file_status_error=RuntimeError('HTTP 500: Server error')
        )

        with self.assertRaisesRegex(RuntimeError, 'HTTP 500'):
            await self.refresh(client)
        self.assertEqual(client.refreshed, [])

    async def testWhenSmartlingRejectsAnUploadThenTheRefreshFails(self):
        client = FakeSmartlingClient(upload_code='VALIDATION_ERROR')

        with self.assertRaisesRegex(RuntimeError, 'VALIDATION_ERROR'):
            await self.refresh(client)

    async def testWhenSmartlingNeverFinishesProcessingThenTheRefreshFails(self):
        client = FakeSmartlingClient(
            upload_code='ACCEPTED',
            file_statuses={XLIFF_URI: {'lastUploaded': 'code-freeze'}}
        )

        with self.assertRaisesRegex(RuntimeError, 'did not finish processing'):
            await self.refresh(client)


class DownloadCommandTests(unittest.IsolatedAsyncioTestCase):

    def setUp(self):
        out_dir = tempfile.TemporaryDirectory()
        self.addCleanup(out_dir.cleanup)
        self.out_dir = Path(out_dir.name)
        self.original_client = LOCALIZATION_TOOL.SmartlingClient
        self.addCleanup(setattr, LOCALIZATION_TOOL, 'SmartlingClient', self.original_client)
        for name in ('SMARTLING_USER_ID', 'SMARTLING_USER_SECRET', 'SMARTLING_PROJECT_ID'):
            patcher = unittest.mock.patch.dict('os.environ', {name: 'value'})
            patcher.start()
            self.addCleanup(patcher.stop)

    async def download(self, client, job_id=None, file_uris=None, allow_unfinished=False):
        LOCALIZATION_TOOL.SmartlingClient = lambda _creds: client
        args = argparse.Namespace(
            job_id=job_id,
            file_uris=file_uris,
            out_dir=str(self.out_dir),
            allow_unfinished=allow_unfinished
        )
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            await LOCALIZATION_TOOL.download_command(args)
        return output.getvalue()

    async def testWhenJobIsNotCompletedThenNothingIsDownloaded(self):
        client = FakeSmartlingClient(job_status='IN_PROGRESS')

        output = await self.download(client, job_id='pr-job')

        self.assertIn('DOWNLOADED=0', output)
        self.assertEqual(client.downloaded, [])

    async def testWhenJobIsCompletedThenItsFilesAreDownloadedForItsLocales(self):
        client = FakeSmartlingClient(job_status='COMPLETED', locales=['de-DE', 'fr-FR'])

        output = await self.download(client, job_id='pr-job')

        self.assertIn('DOWNLOADED=1', output)
        self.assertEqual(client.downloaded, [('feature/en.xliff', 'fr-FR')])
        self.assertEqual((self.out_dir / 'en_fr-FR.xliff').read_text(), 'feature/en.xliff fr-FR')

    async def testWhenAJobDownloadFailsThenTheOthersAreStillDownloaded(self):
        client = FakeSmartlingClient(job_status='COMPLETED', failing_downloads={('feature/en.xliff', 'fr-FR')})

        output = await self.download(client, job_id='pr-job')

        self.assertIn('DOWNLOADED=0', output)

    async def testWhenFileURIsAreGivenThenEachIsDownloadedForEveryProjectLocale(self):
        client = FakeSmartlingClient(job_status='IN_PROGRESS', locales=['de-DE', 'fr-FR'])

        output = await self.download(client, file_uris=[XLIFF_URI, STRINGSDICT_URI])

        self.assertIn('DOWNLOADED=4', output)
        self.assertEqual(client.downloaded, [
            (XLIFF_URI, 'de-DE'), (XLIFF_URI, 'fr-FR'),
            (STRINGSDICT_URI, 'de-DE'), (STRINGSDICT_URI, 'fr-FR'),
        ])
        self.assertTrue((self.out_dir / 'Localizable_de-DE.stringsdict').exists())

    async def testWhenAFileURIDownloadFailsThenTheCommandFails(self):
        client = FakeSmartlingClient(locales=['de-DE', 'fr-FR'], failing_downloads={(XLIFF_URI, 'fr-FR')})

        with self.assertRaisesRegex(RuntimeError, 'Downloaded 1 of 2 files'):
            await self.download(client, file_uris=[XLIFF_URI])


if __name__ == '__main__':
    unittest.main()
