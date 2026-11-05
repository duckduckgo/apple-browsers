"""Fixture checks for original and automatic-retry UI-test evidence."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

RENDERER = Path(__file__).resolve().parents[1] / 'render-ios-ui-test-attempts.py'


class AttemptSummaryTests(unittest.TestCase):
    def render(self, reports, matrix=None, production='true', internal='false'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'reports').mkdir()
            for name, content in reports.items():
                (root / 'reports' / name).write_text(content)
            summary = root / 'summary.md'
            environment = dict(os.environ, RUN_ID='123', GITHUB_REPOSITORY='example/browser',
                               GITHUB_STEP_SUMMARY=str(summary), RUN_PRODUCTION=production,
                               RUN_INTERNAL=internal,
                               MATRIX=json.dumps(matrix if matrix is not None else [
                                   {'test': 'BrowsingUITests', 'device': 'iphone'}]))
            subprocess.run([sys.executable, str(RENDERER)], cwd=root, env=environment,
                           check=True, capture_output=True, text=True)
            return summary.read_text()

    def test_failed_then_passed_keeps_failure_and_both_attempt_identities(self):
        summary = self.render({
            'BrowsingUITests-iphone-production.xml': '''<testsuites name="generic">
              <testcase classname="BrowsingUITests" name="open"><failure message="file.swift:57 &lt;missing&gt;"/></testcase>
              <testcase classname="BrowsingUITests" name="open" time="48.335"/>
              </testsuites>''',
            'BrowsingUITests-iphone-production.meta.json': '{"workflow_attempt": 3}',
        })
        self.assertIn('BrowsingUITests.open` | BrowsingUITests-iphone-production | 1 | 3 | failed, then passed', summary)
        self.assertIn('file.swift:57 &lt;missing&gt;', summary)
        self.assertIn('/actions/runs/123?attempt=3', summary)
        self.assertIn('ios-uitest-logs-BrowsingUITests-iphone-production-attempt3', summary)
        self.assertNotIn('Jobs without a complete', summary)

    def test_fail_fail_skip_does_not_claim_recovery(self):
        summary = self.render({'BrowsingUITests-iphone-production.xml': '''<testsuite>
          <testcase classname="BrowsingUITests" name="open"><failure/></testcase>
          <testcase classname="BrowsingUITests" name="open"><error message="second"/></testcase>
          <testcase classname="BrowsingUITests" name="open"><skipped/></testcase></testsuite>'''})
        self.assertIn('1 | unknown | failed, then failed again', summary)
        self.assertIn('2 | unknown | failed, then skipped', summary)
        self.assertNotIn('failed, then passed', summary)
        self.assertIn('workflow attempt unknown; artifact name unavailable', summary)

    def test_missing_and_partial_reports_remain_incomplete_per_cell(self):
        summary = self.render({
            'BrowsingUITests-iphone-production.xml': '<testsuite><testcase name="ok"/></testsuite>',
            'BrowsingUITests-iphone-production.invalid': 'native evidence incomplete',
        }, internal='true')
        self.assertIn('BrowsingUITests-iphone-production`: job marked report invalid; partial test results', summary)
        self.assertIn('BrowsingUITests-iphone-internal`: report missing', summary)
        self.assertIn('no test failure is inferred from a missing report', summary)

    def test_malformed_empty_and_all_skipped_are_not_execution_proof(self):
        for xml, expected in [('<broken', 'could not be parsed'),
                              ('<testsuite/>', 'contains no executed testcases'),
                              ('<testsuite><testcase><skipped/></testcase></testsuite>', 'contains no executed testcases')]:
            with self.subTest(xml=xml):
                summary = self.render({'BrowsingUITests-iphone-production.xml': xml})
                self.assertIn(expected, summary)

    def test_retry_in_another_device_or_mode_does_not_recover_failure(self):
        matrix = [{'test': 'BrowsingUITests', 'device': device} for device in ['iphone', 'ipad']]
        summary = self.render({
            'BrowsingUITests-iphone-production.xml': '<testsuite><testcase classname="BrowsingUITests" name="open"><failure/></testcase></testsuite>',
            'BrowsingUITests-ipad-production.xml': '<testsuite><testcase classname="BrowsingUITests" name="open"/></testsuite>',
        }, matrix=matrix)
        self.assertIn('failed; no later attempt in report', summary)
        self.assertNotIn('failed, then passed', summary)


if __name__ == '__main__':
    unittest.main()
