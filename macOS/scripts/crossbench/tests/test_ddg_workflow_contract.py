#!/usr/bin/env python3

import unittest
from pathlib import Path


WORKFLOW = (
    Path(__file__).parents[4]
    / ".github"
    / "workflows"
    / "macos_ddg_lcp.yml"
).read_text(encoding="utf-8")


class DDGWorkflowContractTests(unittest.TestCase):
    def test_real_measurement_uses_only_trusted_branches(self) -> None:
        self.assertIn("workflow_dispatch:", WORKFLOW)
        self.assertNotIn("schedule:", WORKFLOW)
        self.assertIn("TEMPORARY_TEST_BRANCH: diego/crossbench-ddg-ci", WORKFLOW)
        self.assertIn('branch="${GITHUB_REF#refs/heads/}"', WORKFLOW)
        self.assertIn("git merge-base --is-ancestor", WORKFLOW)

    def test_measurement_uses_only_the_dedicated_runner(self) -> None:
        measurement = WORKFLOW[
            WORKFLOW.index("\n  ddg-lcp:\n") :
            WORKFLOW.index("\n  upload-to-clickhouse:\n")
        ]
        self.assertIn(
            "runs-on: [self-hosted, macOS, ARM64, performance]",
            measurement,
        )
        self.assertIn("environment: macos-performance", measurement)
        self.assertNotIn("sudo ", measurement)

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
        self.assertEqual(WORKFLOW.count("--webview-type ddg-wpr"), 2)
        self.assertEqual(WORKFLOW.count("--webview-channel review"), 2)
        self.assertIn("Browser Measurement Failure: DuckDuckGo LCP", WORKFLOW)
        self.assertIn("Review Build Validation Failure: DuckDuckGo LCP", WORKFLOW)
        self.assertIn("DuckDuckGo disposition artifact was unavailable", WORKFLOW)

    def test_ddg_provisioning_does_not_install_crossbench(self) -> None:
        self.assertIn("./provision-ddg-runtime.sh", WORKFLOW)
        self.assertNotIn("./provision-macos.sh", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
