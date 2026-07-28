#!/usr/bin/env python3

import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROGRAM = ROOT / "aggregate-dispositions.py"
HEADER = (
    "browser\tbrowser_version\tsite\toutcome\tvalidation_status\t"
    "validation_reason\tvalidation_http_status\tvalidation_detail\tarchive_sha256\t"
    "requested_repetitions\tobserved_repetitions\trecorded_samples\t"
    "dropped_unfinalized\tdropped_no_metric\tload_window_ms\trunner_image\n"
)
SHA = "a" * 64


class AggregateDispositionsTests(unittest.TestCase):
    def run_program(self, rows: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.tsv"
            output = Path(directory) / "output.tsv"
            source.write_text(HEADER + rows)
            result = subprocess.run(
                [
                    "python3", str(PROGRAM), "--input", str(source),
                    "--output", str(output), "--run-id", "42",
                    "--start-time", "2026-07-27T10:00:00Z",
                    "--gh-run-started-at", "2026-07-27T10:01:00Z",
                    "--webview-type", "chr-wpr",
                ],
                text=True, capture_output=True,
            )
            result.output = output.read_text() if output.exists() else ""
            return result

    def test_emits_exact_columns_null_and_clickhouse_escaping(self) -> None:
        detail = r'"path=C:\tmp\literal\N"'
        rows = (
            f"chrome\t1.2\tapple.com\tmeasured\tok\t-\t-\t{detail}\t{SHA}"
            "\t2\t2\t2\t0\t0\t12000\tmacOS-15\n"
            "chrome\t1.2\tmissing.test\texcluded\terror\tarchive_missing\t-\t-\t-"
            "\t2\t0\t0\t0\t0\t12000\tmacOS-15\n"
            f"chrome\t1.2\tblocked.test\texcluded\terror\thttp_403\t403\thttp_403\t{SHA}"
            "\t2\t0\t0\t0\t0\t12000\tmacOS-15\n"
        )
        result = self.run_program(rows)
        self.assertEqual(result.returncode, 0, result.stderr)
        emitted = [line.split("\t") for line in result.output.splitlines()]
        self.assertEqual([len(row) for row in emitted], [20, 20, 20])
        self.assertEqual(emitted[0][9], r"\N")
        self.assertEqual(emitted[0][10], r'"path=C:\\tmp\\literal\\N"')
        self.assertEqual(emitted[0][11], SHA)
        self.assertEqual(emitted[1][11], r"\N")
        self.assertEqual(emitted[1][12], "2")
        self.assertEqual(emitted[2][9], "403")
        self.assertEqual(emitted[2][11], SHA)

    def test_rejects_bad_counter_and_outcome_invariants(self) -> None:
        invalid_rows = [
            f"chrome\t1\tbad.test\tmeasured\tok\t-\t-\t-\t{SHA}\t2\t1\t1\t0\t0\t12000\tr\n",
            f"chrome\t1\tbad.test\texcluded\terror\tarchive_missing\t-\t-\t-\t2\t1\t0\t0\t1\t12000\tr\n",
            f"chrome\t1\tbad.test\tpartial\tok\t-\t-\t-\t{SHA}\t2\t2\t0\t1\t1\t12000\tr\n",
            f"chrome\t1\tbad.test\tinfra_error\tok\t-\t-\t-\t{SHA}\t-1\t0\t0\t0\t0\t12000\tr\n",
        ]
        for row in invalid_rows:
            with self.subTest(row=row):
                self.assertNotEqual(self.run_program(row).returncode, 0)

    def test_rejects_empty_data(self) -> None:
        self.assertNotEqual(self.run_program("").returncode, 0)

    def test_requires_webview_type(self) -> None:
        result = subprocess.run(
            ["python3", str(PROGRAM), "--help"],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--webview-type WEBVIEW_TYPE", result.stdout)
        self.assertNotIn("[--webview-type WEBVIEW_TYPE]", result.stdout)


if __name__ == "__main__":
    unittest.main()
