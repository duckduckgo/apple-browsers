#!/usr/bin/env python3

import unittest
from pathlib import Path


WORKFLOW = (
    Path(__file__).parents[4]
    / ".github"
    / "workflows"
    / "macos_ddg_lcp.yml"
).read_text(encoding="utf-8")
CHROME_WORKFLOW = (
    Path(__file__).parents[4]
    / ".github"
    / "workflows"
    / "macos_crossbench_chrome.yml"
).read_text(encoding="utf-8")
SAFARI_WORKFLOW = (
    Path(__file__).parents[4]
    / ".github"
    / "workflows"
    / "macos_crossbench_safari.yml"
).read_text(encoding="utf-8")
WPR_VALIDATION_WORKFLOW = (
    Path(__file__).parents[4]
    / ".github"
    / "workflows"
    / "wpr_archive_validation.yml"
).read_text(encoding="utf-8")
LAUNCHER = (
    Path(__file__).parents[1] / "launch-ddg-app.sh"
).read_text(encoding="utf-8")
HARNESS = (
    Path(__file__).parents[1] / "test-ddg.sh"
).read_text(encoding="utf-8")
PROVISION_MACOS = (
    Path(__file__).parents[1] / "provision-macos.sh"
).read_text(encoding="utf-8")
PROVISION_DDG_RUNTIME = (
    Path(__file__).parents[1] / "provision-ddg-runtime.sh"
).read_text(encoding="utf-8")


class DDGWorkflowContractTests(unittest.TestCase):
    def test_real_measurement_runs_daily_and_on_demand(self) -> None:
        self.assertIn("workflow_dispatch:", WORKFLOW)
        self.assertIn('- cron: "41 4 * * *"', WORKFLOW)
        self.assertNotIn("push:", WORKFLOW)
        # A scheduled run carries no workflow_dispatch inputs, so the upload has
        # to be gated on the event rather than on the input alone.
        self.assertIn(
            "(github.event_name == 'schedule' || inputs.upload-to-clickhouse)",
            WORKFLOW,
        )

    def test_measurement_uses_the_same_runner_as_the_other_browsers(self) -> None:
        measurement = WORKFLOW[
            WORKFLOW.index("\n  ddg-lcp:\n") :
            WORKFLOW.index("\n  upload-to-clickhouse:\n")
        ]
        # Comparability with Chrome and Safari depends on all three measuring on
        # the same self-hosted Apple Silicon runner.
        runner = "runs-on: [self-hosted, macOS, ARM64]"
        self.assertIn(runner, measurement)
        self.assertIn(runner, CHROME_WORKFLOW)
        self.assertIn(runner, SAFARI_WORKFLOW)
        self.assertIn("environment: macos-performance", measurement)
        self.assertNotIn("sudo ", measurement)
        self.assertIn(
            'installed_app="/Applications/DuckDuckGo Performance Review-',
            measurement,
        )
        self.assertIn("Remove dedicated Review app", measurement)

    def test_url_or_exact_commit_build_feeds_review_validation(self) -> None:
        self.assertIn("review-build-url:", WORKFLOW)
        self.assertIn("commit-sha: ${{ github.sha }}", WORKFLOW)
        self.assertIn(
            "REVIEW_BUILD_URL: ${{ inputs.review-build-url }}",
            WORKFLOW,
        )
        self.assertIn("./prepare-ddg-review.py", WORKFLOW)
        self.assertIn("ddg-review-validation-report", WORKFLOW)

    def test_replay_identity_and_reporting_are_explicit(self) -> None:
        self.assertIn("uses: ./.github/workflows/wpr_archive_validation.yml", WORKFLOW)
        self.assertIn(
            "alert-asana: ${{ github.event_name != 'workflow_dispatch' || "
            "inputs.alert-asana }}",
            WORKFLOW,
        )
        self.assertEqual(WORKFLOW.count("--webview-type ddg"), 2)
        self.assertEqual(WORKFLOW.count("--webview-channel review"), 2)
        self.assertIn("Browser Measurement Failure: DuckDuckGo LCP", WORKFLOW)
        self.assertIn("Review Build Validation Failure: DuckDuckGo LCP", WORKFLOW)
        self.assertIn("DuckDuckGo disposition artifact was unavailable", WORKFLOW)

    def test_ddg_provisioning_does_not_install_crossbench(self) -> None:
        self.assertIn("./provision-ddg-runtime.sh", WORKFLOW)
        self.assertNotIn("./provision-macos.sh", WORKFLOW)

    def test_cleanup_removes_partial_install_only_at_the_exact_review_path(self) -> None:
        cleanup = WORKFLOW[
            WORKFLOW.index("      - name: Remove dedicated Review app") :
            WORKFLOW.index("      - name: Upload results TSV")
        ]
        self.assertIn(
            'expected="/Applications/DuckDuckGo Performance Review-'
            '${GITHUB_RUN_ID}.app"',
            cleanup,
        )
        self.assertIn('if [ "$DDG_APP" != "$expected" ]; then', cleanup)
        self.assertIn(
            'if [ -e "$DDG_APP" ]; then\n'
            '            rm -rf -- "$DDG_APP"',
            cleanup,
        )
        self.assertNotIn("defaults read", cleanup)
        self.assertNotIn("Info.plist", cleanup)

    def test_review_app_uses_launch_services_without_token_logging(self) -> None:
        self.assertIn("/usr/bin/open -n", LAUNCHER)
        self.assertIn('--env "AUTOMATION_TOKEN=$AUTOMATION_TOKEN"', LAUNCHER)
        self.assertNotIn("set -x", LAUNCHER)
        self.assertNotIn("echo \"$AUTOMATION_TOKEN\"", LAUNCHER)

    def test_app_is_launched_without_the_runner_ci_variable(self) -> None:
        # A non-empty CI puts the app in UI-test mode, where it opens no window
        # and the automation server has no tab to drive.
        self.assertIn("/usr/bin/env -u CI /usr/bin/open -n", LAUNCHER)

    def test_normal_launch_does_not_arm_the_updater(self) -> None:
        self.assertIn("-SUEnableAutomaticChecks false", HARNESS)

    def test_provisioning_scripts_install_gh_when_missing(self) -> None:
        # The self-hosted runner does not ship the GitHub CLI, and the
        # aggregation steps read this run's metadata with `gh api`.
        for script in (PROVISION_MACOS, PROVISION_DDG_RUNTIME):
            self.assertIn("command -v gh >/dev/null 2>&1 || brew install gh", script)

    def test_workflows_do_not_bootstrap_gh_inline(self) -> None:
        # gh installation now lives in the provisioning scripts above; a
        # per-workflow "Ensure gh is available" step must not creep back.
        for workflow in (WORKFLOW, CHROME_WORKFLOW, SAFARI_WORKFLOW):
            self.assertNotIn("Ensure gh is available", workflow)
            self.assertNotIn("brew install gh", workflow)

    def test_asana_step_wires_the_followers_repo_variable(self) -> None:
        for workflow in (WORKFLOW, CHROME_WORKFLOW, SAFARI_WORKFLOW):
            self.assertIn(
                "ASANA_FOLLOWERS: ${{ vars.CROSSBENCH_ALERT_FOLLOWERS }}",
                workflow,
            )

    def test_asana_alerts_target_the_ci_alerts_project_section(self) -> None:
        # Alerts land as top-level tasks in the "Alerts" section of the
        # "macOS Site-Loading CI Test Alerts" project, not as subtasks of the
        # old hardcoded parent task. wpr_archive_validation.yml calls the same
        # helper and was updated alongside the three measurement workflows.
        for workflow in (WORKFLOW, CHROME_WORKFLOW, SAFARI_WORKFLOW, WPR_VALIDATION_WORKFLOW):
            self.assertIn("1217628708169653", workflow)
            self.assertIn("1217628708169657", workflow)
            self.assertNotIn("1216902374642227", workflow)
            self.assertNotIn("1217628789139804", workflow)


if __name__ == "__main__":
    unittest.main()
