import csv
import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "runtime-failure-report.py"
SPEC = importlib.util.spec_from_file_location("runtime_failure_report", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)

HEADER = [
    "browser",
    "site",
    "outcome",
    "requested_repetitions",
    "observed_repetitions",
    "recorded_samples",
    "dropped_unfinalized",
    "dropped_no_metric",
]


class RuntimeFailureReportTests(unittest.TestCase):
    def write_rows(self, rows: list[dict[str, str]]) -> Path:
        root = Path(self.temp.name)
        path = root / "dispositions.tsv"
        with path.open("w", newline="", encoding="utf-8") as output:
            writer = csv.DictWriter(output, fieldnames=HEADER, delimiter="\t")
            writer.writeheader()
            writer.writerows(rows)
        return path

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_reports_all_runtime_problem_outcomes(self) -> None:
        path = self.write_rows(
            [
                {
                    "browser": "chrome",
                    "site": "good.test",
                    "outcome": "measured",
                    "requested_repetitions": "10",
                    "observed_repetitions": "10",
                    "recorded_samples": "10",
                    "dropped_unfinalized": "0",
                    "dropped_no_metric": "0",
                },
                {
                    "browser": "chrome",
                    "site": "partial.test",
                    "outcome": "partial",
                    "requested_repetitions": "10",
                    "observed_repetitions": "10",
                    "recorded_samples": "8",
                    "dropped_unfinalized": "2",
                    "dropped_no_metric": "0",
                },
                {
                    "browser": "chrome",
                    "site": "broken.test",
                    "outcome": "infra_error",
                    "requested_repetitions": "10",
                    "observed_repetitions": "3",
                    "recorded_samples": "3",
                    "dropped_unfinalized": "0",
                    "dropped_no_metric": "0",
                },
            ]
        )

        report, count = MODULE.build_report(path)

        self.assertEqual(count, 2)
        self.assertNotIn("good.test", report)
        self.assertIn("[SITE ERROR] partial.test", report)
        self.assertIn("[SITE ERROR] broken.test", report)
        self.assertIn("Samples: 3/10 (observed 3", report)

    def test_measured_and_excluded_sites_do_not_report(self) -> None:
        path = self.write_rows(
            [
                {
                    "browser": "chrome",
                    "site": "good.test",
                    "outcome": "measured",
                    "requested_repetitions": "2",
                    "observed_repetitions": "2",
                    "recorded_samples": "2",
                    "dropped_unfinalized": "0",
                    "dropped_no_metric": "0",
                },
                {
                    "browser": "chrome",
                    "site": "excluded.test",
                    "outcome": "excluded",
                    "requested_repetitions": "2",
                    "observed_repetitions": "0",
                    "recorded_samples": "0",
                    "dropped_unfinalized": "0",
                    "dropped_no_metric": "0",
                },
            ]
        )

        report, count = MODULE.build_report(path)

        self.assertEqual(count, 0)
        self.assertEqual(report, "")


if __name__ == "__main__":
    unittest.main()
