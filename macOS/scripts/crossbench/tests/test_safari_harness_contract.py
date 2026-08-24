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

    def test_ci_raises_open_file_limit_for_the_forward_proxy(self):
        self.assertIn("ulimit -n 4096", WORKFLOW)
        self.assertLess(
            WORKFLOW.index("ulimit -n 4096"),
            WORKFLOW.index("python3 ./run-with-watchdog.py"),
        )

    def test_marker_lookup_failure_skips_task_creation(self):
        for workflow in (WORKFLOW, CHROME_WORKFLOW):
            self.assertIn('echo "exists=unknown" >> "$GITHUB_OUTPUT"', workflow)
            self.assertIn("skipping task creation to avoid duplicates", workflow)

    def test_clickhouse_inserts_are_attempted_independently(self):
        for workflow in (WORKFLOW, CHROME_WORKFLOW):
            self.assertIn("failed=0", workflow)
            self.assertEqual(workflow.count("failed=$((failed + 1))"), 2)
            self.assertIn('if [ "$failed" -gt 0 ]; then', workflow)

    def test_run_refuses_to_start_while_another_safari_is_open(self):
        self.assertIn('[ -z "$(safari_pids)" ] || {', HARNESS)
        self.assertIn("Safari is already running; refusing to start", HARNESS)

    def test_safari_is_quit_before_every_measurement(self):
        self.assertIn("quit_safari()", HARNESS)
        self.assertLess(
            HARNESS.index("if ! quit_safari; then"),
            HARNESS.index('"$SAFARIDRIVER_PORT" measure'),
        )
        self.assertIn("safari_quit_failed", HARNESS)

    def test_session_stores_are_pruned_at_start_between_reps_and_at_cleanup(self):
        self.assertIn("prune_safari_automation_stores() {", HARNESS)
        # Definition plus exactly three call sites: startup, per repetition, cleanup.
        self.assertEqual(HARNESS.count("prune_safari_automation_stores"), 4)
        # Startup: after the refusal to run alongside another Safari.
        self.assertIn('prune_safari_automation_stores\n  [ -x "$WPR_BIN" ]', HARNESS)
        # Cleanup: right after the quit that releases the last session's store.
        self.assertIn(
            'quit_safari || echo "WARNING: Safari did not quit during cleanup." >&2\n'
            "    # Removes the last repetition's store, which no earlier prune could reach.\n"
            "    prune_safari_automation_stores\n",
            HARNESS,
        )
        # Per repetition: after the quit, before the session that measures.
        rep = HARNESS.index("prune_safari_automation_stores\n    before=")
        self.assertLess(HARNESS.index("if ! quit_safari; then"), rep)
        self.assertLess(rep, HARNESS.index('"$SAFARIDRIVER_PORT" measure'))

    def test_pruning_refuses_an_unrecognized_store_root(self):
        prune = HARNESS[
            HARNESS.index("prune_safari_automation_stores() {") :
            HARNESS.index("capture_proxy_key() {")
        ]
        self.assertIn("*/SafariAutomation) ;;", prune)
        self.assertIn("refusing to prune unexpected session-store path", prune)
        self.assertLess(prune.index("*/SafariAutomation) ;;"), prune.index("rm -rf --"))
        self.assertLess(prune.index('[ -n "$(safari_pids)" ]'), prune.index("rm -rf --"))

    def test_cleanup_only_quits_a_safari_this_run_launched(self):
        self.assertIn(
            'if [ -n "$SAFARIDRIVER_PID" ]; then\n'
            '    quit_safari || echo "WARNING: Safari did not quit during cleanup."',
            HARNESS,
        )

    def test_crash_reports_from_this_run_are_collected_and_bounded(self):
        """A lost session is ambiguous; only a crash report names the cause."""
        self.assertIn("preserve_crash_reports()", HARNESS)
        # Collected wherever the other shared diagnostics are, so a site-level
        # failure preserves them without the whole job having to fail.
        self.assertIn("  preserve_crash_reports\n", HARNESS)
        # Bounded like every other diagnostic the harness keeps.
        self.assertIn('MAX_CRASH_REPORTS="${MAX_CRASH_REPORTS:-10}"', HARNESS)
        self.assertIn('[ "$copied" -lt "$MAX_CRASH_REPORTS" ] || continue', HARNESS)
        # Scoped to this run, so an unrelated earlier crash is not reported as
        # evidence about this one.
        self.assertIn('-newer "$RUN_START_MARKER"', HARNESS)
        self.assertIn('RUN_START_MARKER="$(mktemp)"', HARNESS)
        self.assertIn('rm -f "$RUN_START_MARKER"', HARNESS)

    def test_crash_report_collection_reports_its_own_outcome(self):
        """Silence would conflate "nothing crashed" with "cannot read them"."""
        self.assertIn("found=$candidates kept=$copied", HARNESS)
        self.assertIn('unreadable="$unreadable $directory"', HARNESS)

    def test_memory_pressure_kills_are_collected_too(self):
        """A jetsammed WebContent leaves no report under the process name."""
        self.assertIn("-o -name 'JetsamEvent*'", HARNESS)

    def test_failed_repetition_records_whether_the_browser_survived(self):
        """invalid-session-id and a dead browser are the same over WebDriver."""
        self.assertIn('surviving="$(safari_pids | tr \'\\n\' \' \')"', HARNESS)
        self.assertIn("Safari after failure: ${surviving:-no process}", HARNESS)

    def test_driver_diagnostics_are_opt_in_and_collected_when_requested(self):
        """--diagnose logs inside the timed window, so it must stay off."""
        self.assertIn('default: false', WORKFLOW)
        self.assertIn("safaridriver-diagnose:", WORKFLOW)
        self.assertIn(
            "SAFARIDRIVER_DIAGNOSE: ${{ inputs.safaridriver-diagnose && '1' || '' }}",
            WORKFLOW,
        )
        self.assertIn('SAFARIDRIVER_DIAGNOSE="${SAFARIDRIVER_DIAGNOSE:-}"', HARNESS)
        self.assertIn('if [ -n "$SAFARIDRIVER_DIAGNOSE" ]; then', HARNESS)
        self.assertIn("driver_args+=(--diagnose)", HARNESS)
        # Its output lands in its own directory, not on the driver's stdout.
        self.assertIn('"$HOME/Library/Logs/com.apple.WebDriver"', HARNESS)
        self.assertIn("preserve_driver_diagnostics", HARNESS)

    def test_a_stray_browser_is_quit_before_the_harness_runs(self):
        """A cancelled run leaves a Safari that blocks every later run."""
        self.assertIn("Quit any Safari left behind by an earlier run", WORKFLOW)
        self.assertIn("pkill -x Safari", WORKFLOW)
        # The harness keeps refusing on its own behalf; this only clears CI.
        self.assertIn("Safari is already running; refusing to start.", HARNESS)

    def test_diagnostics_artifact_includes_nested_crash_reports(self):
        self.assertIn("path: macOS/scripts/crossbench/safari-diagnostics/**", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
