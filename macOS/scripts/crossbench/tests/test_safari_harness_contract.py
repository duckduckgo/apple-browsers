"""Regression contracts for the Safari shell harness.

These checks keep the safety-critical shell invariants visible without requiring
Safari, defaults, WPR, or a network connection.
"""

import pathlib
import unittest


HARNESS = (
    pathlib.Path(__file__).parents[1] / "test-safari.sh"
).read_text(encoding="utf-8")
WORKFLOW = (
    pathlib.Path(__file__).parents[4]
    / ".github"
    / "workflows"
    / "macos_crossbench_safari.yml"
).read_text(encoding="utf-8")
CHROME_WORKFLOW = (
    pathlib.Path(__file__).parents[4]
    / ".github"
    / "workflows"
    / "macos_crossbench_chrome.yml"
).read_text(encoding="utf-8")


class SafariHarnessContractTests(unittest.TestCase):

    def test_requires_validator_staged_archives(self):
        self.assertIn('WPR_ARCHIVES_PREPARED" != "1"', HARNESS)
        self.assertIn("validated WPR manifest missing", HARNESS)
        self.assertNotIn("curl -fLSs -o \"$archive.tmp\"", HARNESS)

    def test_replay_proof_requires_the_requested_connect_after_the_snapshot(self):
        self.assertIn("proxy_saw_requested_connect()", HARNESS)
        self.assertIn('expected="CONNECT $site:443"', HARNESS)
        self.assertIn("NR > line_before && $0 == expected", HARNESS)

    def test_proxy_restore_is_aggregated_and_precedes_proxy_shutdown(self):
        self.assertIn('restore_proxy_key "$SAFARI_HTTP_PROXY_KEY" "$HTTP_PROXY_WAS_SET" "$HTTP_PROXY_VALUE" || status=1', HARNESS)
        self.assertIn('restore_proxy_key "$SAFARI_HTTPS_PROXY_KEY" "$HTTPS_PROXY_WAS_SET" "$HTTPS_PROXY_VALUE" || status=1', HARNESS)
        cleanup = HARNESS[HARNESS.index("cleanup() {") : HARNESS.index("trap cleanup EXIT")]
        self.assertLess(cleanup.index('kill_pid "$SAFARIDRIVER_PID"'), cleanup.index("restore_proxy_state"))
        self.assertLess(cleanup.index("restore_proxy_state"), cleanup.index('kill_pid "$HTTPPROXY_PID"'))

    def test_failed_runs_retain_diagnostics(self):
        self.assertIn("preserve_diagnostic()", HARNESS)
        self.assertIn("preserve_site_diagnostics()", HARNESS)
        self.assertIn('preserve_diagnostic "$WPR_LOG" "wpr-$site.log"', HARNESS)
        self.assertIn('preserve_diagnostic "$SAFARIDRIVER_LOG" safaridriver.log', HARNESS)

    def test_shared_services_reject_zombies_and_account_for_remaining_sites(self):
        self.assertIn('[[ "$state" != Z* ]]', HARNESS)
        shared_check = HARNESS[
            HARNESS.index("shared_services_alive() {") :
            HARNESS.index("measure_site() {")
        ]
        self.assertNotIn("WPR", shared_check)
        self.assertIn("SHARED_SERVICE_FAILURE=1", HARNESS)
        self.assertIn("record_site_after_shared_failure", HARNESS)

    def test_failed_job_without_dispositions_still_reports_runtime_failure(self):
        self.assertIn("BENCHMARK_RESULT: ${{ needs.safari-lcp.result }}", WORKFLOW)
        self.assertIn("write_run_failure_report()", WORKFLOW)
        self.assertIn(
            'write_run_failure_report "Safari disposition artifact was unavailable"',
            WORKFLOW,
        )
        self.assertIn('--job-result "$BENCHMARK_RESULT"', WORKFLOW)

    def test_whole_harness_watchdog_leaves_reporting_time(self):
        self.assertIn("run-with-watchdog.py", WORKFLOW)
        self.assertIn("python3 ./run-with-watchdog.py", WORKFLOW)
        self.assertIn("--timeout-seconds 9600", WORKFLOW)
        self.assertIn('exit "$harness_status"', WORKFLOW)

    def test_marker_lookup_failure_skips_task_creation(self):
        for workflow in (WORKFLOW, CHROME_WORKFLOW):
            self.assertIn('echo "exists=unknown" >> "$GITHUB_OUTPUT"', workflow)
            self.assertIn("skipping task creation to avoid duplicates", workflow)


if __name__ == "__main__":
    unittest.main()
