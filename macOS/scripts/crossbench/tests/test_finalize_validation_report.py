#!/usr/bin/env python3

import importlib.util
import unittest
from pathlib import Path

PROGRAM = Path(__file__).resolve().parents[1] / "finalize-validation-report.py"
SPEC = importlib.util.spec_from_file_location("finalize_validation_report", PROGRAM)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


def report(status: str = "READY", errors: int = 0) -> str:
    return (
        "WPR archive validation: COMPLETE\n"
        f"Package status: {status}\n"
        "Eligible sites: 1/1\n"
        f"Site errors: {errors}\n"
        f"Detected issues: {errors}\n"
    )


class FinalizeValidationReportTests(unittest.TestCase):
    def test_missing_report_is_infrastructure_failure(self) -> None:
        text, has_errors, package_failed = MODULE.finalize(None, "failure")
        self.assertIn("[PACKAGE ERROR] validation infrastructure", text)
        self.assertTrue(has_errors)
        self.assertTrue(package_failed)

    def test_intentional_failed_package_is_not_reclassified(self) -> None:
        original = report("FAILED", 1)
        text, has_errors, package_failed = MODULE.finalize(original, "failure")
        self.assertEqual(text, original)
        self.assertNotIn("validation handoff", text)
        self.assertTrue(has_errors)
        self.assertTrue(package_failed)

    def test_ready_failed_job_becomes_handoff_failure(self) -> None:
        text, has_errors, package_failed = MODULE.finalize(report(), "failure")
        self.assertIn("Package status: FAILED", text)
        self.assertIn("Detected issues: 1", text)
        self.assertIn("[PACKAGE ERROR] validation handoff", text)
        self.assertTrue(has_errors)
        self.assertTrue(package_failed)

    def test_success_preserves_valid_report(self) -> None:
        original = report("READY", 1)
        text, has_errors, package_failed = MODULE.finalize(original, "success")
        self.assertEqual(text, original)
        self.assertTrue(has_errors)
        self.assertFalse(package_failed)

    def test_inconsistent_counts_become_infrastructure_failure(self) -> None:
        text, has_errors, package_failed = MODULE.finalize(
            report("READY", 1).replace("Detected issues: 1", "Detected issues: 2"),
            "success",
        )
        self.assertIn("inconsistent issue counts", text)
        self.assertTrue(has_errors)
        self.assertTrue(package_failed)

    def test_malformed_report_becomes_infrastructure_failure(self) -> None:
        text, has_errors, package_failed = MODULE.finalize("not a report", "success")
        self.assertIn("malformed report", text)
        self.assertTrue(has_errors)
        self.assertTrue(package_failed)


if __name__ == "__main__":
    unittest.main()
