"""Regression contracts for the Safari shell harness.

These checks keep the safety-critical shell invariants visible without requiring
Safari, defaults, WPR, or a network connection.
"""

import pathlib
import unittest


HARNESS = (
    pathlib.Path(__file__).parents[1] / "test-safari.sh"
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
        self.assertIn('preserve_diagnostic "$WPR_LOG" "wpr-$site.log"', HARNESS)
        self.assertIn('preserve_diagnostic "$SAFARIDRIVER_LOG" safaridriver.log', HARNESS)


if __name__ == "__main__":
    unittest.main()
