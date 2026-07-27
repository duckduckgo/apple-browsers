#!/usr/bin/env python3

import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "test-chrome.sh"
MANIFEST_HEADER = (
    "site\tarchive\tsha256\tarchive_bytes\tverdict\treason_code\thttp_status\t"
    "detail\tstatus_chain\tfinal_url\tcontent_type\tblocked_marker\n"
)


class ChromeHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.crossbench = self.root / "crossbench"
        self.bin = self.root / "bin"
        self.archives = self.root / "archives"
        self.results = self.root / "fake-results"
        for directory in (self.crossbench, self.bin, self.archives):
            directory.mkdir()
        (self.crossbench / "cb.py").write_text("")
        chrome = self.bin / "chrome"
        chrome.write_text("#!/bin/sh\necho 'Google Chrome 1.2.3'\n")
        chrome.chmod(0o755)
        wpr = self.bin / "wpr"
        wpr.write_text("#!/bin/sh\nexit 0\n")
        wpr.chmod(0o755)
        poetry = self.bin / "poetry"
        poetry.write_text(
            """#!/bin/bash
site=
out_dir=
for arg in "$@"; do
  case "$arg" in
    --url=*) site="${arg#--url=}"; site="${site%%,*}";;
    --out-dir=*) out_dir="${arg#--out-dir=}";;
  esac
done
if [ "${FAKE_RESULTS:-0}" = 1 ]; then
  result_root="${out_dir:-$FAKE_RESULTS_ROOT/$site}"
  path="$result_root/stories/navToLCP+$site/0/cold/trace_processor"
  mkdir -p "$path"
  if [ "${FAKE_METRIC:-0}" = 1 ] && [ "$site" != "${FAKE_NO_METRIC_SITE:-}" ]; then
    if [ "$site" = "${FAKE_UNFINALIZED_SITE:-}" ]; then
      echo 'double_value: -1' > "$path/v2_metrics.textproto"
    else
      echo 'double_value: 1000000000' > "$path/v2_metrics.textproto"
    fi
  fi
  if [ "${FAKE_TRACE:-0}" = 1 ]; then
    echo trace > "$path/perfetto.trace.pb.gz"
  fi
  if [ "${FAKE_INCOMPLETE_RESULTS:-0}" = 1 ]; then
    echo "RESULTS (maybe incomplete/broken): $result_root"
  else
    echo "RESULTS: $result_root"
  fi
fi
if [ "$site" = "${FAKE_FAIL_SITE:-}" ]; then
  exit 7
fi
exit "${FAKE_EXIT:-0}"
"""
        )
        poetry.chmod(0o755)
        archive = self.archives / "navToLCP_apple.com.wprgo"
        archive.write_bytes(b"archive")
        sha = hashlib.sha256(b"archive").hexdigest()
        (self.archives / "manifest.tsv").write_text(
            MANIFEST_HEADER
            + f"apple.com\t{archive.name}\t{sha}\t7\tok\t\t\t\t200\t"
              "https://apple.com/\ttext/html\t\n"
        )
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "CROSSBENCH_DIR": str(self.crossbench),
            "CHROME_BIN": str(chrome),
            "WPR_BIN": str(wpr),
            "WPR_DIR": str(self.archives),
            "WPR_ARCHIVES_PREPARED": "1",
            "SHAPE": "0",
            "FAKE_RESULTS_ROOT": str(self.results),
            "RUN_WORK_BASE": str(self.root / "work"),
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_harness(self, **env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SCRIPT), "--sites", "apple.com", "--reps", "1"],
            cwd=self.root, env={**self.env, **env}, text=True,
            capture_output=True,
        )

    def disposition(self) -> list[str]:
        path = next((self.root / "crossbench-dispositions").glob("*.tsv"))
        return path.read_text().splitlines()[1].split("\t")

    def add_valid_site(self, site: str) -> None:
        archive = self.archives / f"navToLCP_{site}.wprgo"
        archive.write_bytes(site.encode())
        sha = hashlib.sha256(site.encode()).hexdigest()
        with (self.archives / "manifest.tsv").open("a") as manifest:
            manifest.write(
                f"{site}\t{archive.name}\t{sha}\t{len(site)}\tok\t\t\t\t200\t"
                f"https://{site}/\ttext/html\t\n"
            )

    def add_invalid_site(self, site: str, reason: str, status: str = "",
                         sha: str = "") -> None:
        archive = f"navToLCP_{site}.wprgo"
        detail = reason
        with (self.archives / "manifest.tsv").open("a") as manifest:
            manifest.write(
                f"{site}\t{archive}\t{sha}\t0\terror\t{reason}\t{status}\t"
                f"{detail}\t{status}\thttps://{site}/\ttext/html\t\n"
            )

    def test_crossbench_nonzero_with_results_is_infra_error_and_keeps_sample(self) -> None:
        result = self.run_harness(FAKE_RESULTS="1", FAKE_METRIC="1", FAKE_EXIT="7")
        self.assertEqual(result.returncode, 1)
        row = self.disposition()
        self.assertEqual(row[3], "infra_error")
        self.assertEqual(row[9:14], ["1", "1", "1", "0", "0"])
        measurement = next((self.root / "crossbench-results").glob("*.tsv")).read_text()
        self.assertIn("1000.0", measurement)

    def test_incomplete_results_keep_completed_sample(self) -> None:
        result = self.run_harness(
            FAKE_RESULTS="1",
            FAKE_METRIC="1",
            FAKE_EXIT="7",
            FAKE_INCOMPLETE_RESULTS="1",
        )
        self.assertEqual(result.returncode, 1)
        row = self.disposition()
        self.assertEqual(row[3], "infra_error")
        self.assertEqual(row[11], "1")

    def test_generated_crossbench_output_is_removed(self) -> None:
        result = self.run_harness(FAKE_RESULTS="1", FAKE_METRIC="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        work = self.root / "work"
        self.assertEqual(list(work.glob("chrome-crossbench.*")), [])

    def test_failure_keeps_diagnostics_before_removing_raw_output(self) -> None:
        diagnostics = self.root / "diagnostics"
        result = self.run_harness(
            FAKE_RESULTS="1",
            FAKE_METRIC="1",
            FAKE_TRACE="1",
            FAKE_EXIT="7",
            DIAGNOSTICS_DIR=str(diagnostics),
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            len(list(diagnostics.glob("apple.com/**/perfetto.trace.pb.gz"))), 1
        )
        self.assertTrue((diagnostics / "apple.com" / "crossbench.log").is_file())
        self.assertEqual(
            list((self.root / "work").glob("chrome-crossbench.*")), []
        )

    def test_cleanup_has_an_explicit_diagnostic_escape_hatch(self) -> None:
        result = self.run_harness(
            FAKE_RESULTS="1",
            FAKE_METRIC="1",
            KEEP_CROSSBENCH_OUTPUT="1",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            len(list((self.root / "work").glob("chrome-crossbench.*"))), 1
        )

    def test_low_disk_guard_reports_infrastructure_failure(self) -> None:
        result = self.run_harness(
            FAKE_RESULTS="1",
            FAKE_METRIC="1",
            MIN_FREE_DISK_MB="999999999",
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.disposition()[3], "infra_error")
        self.assertIn("minimum is 999999999 MB", result.stderr)

    def test_missing_results_is_infra_error(self) -> None:
        result = self.run_harness(FAKE_RESULTS="0", FAKE_EXIT="0")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.disposition()[3], "infra_error")

    def test_zero_usable_samples_fails_after_disposition(self) -> None:
        result = self.run_harness(FAKE_RESULTS="1", FAKE_METRIC="0", FAKE_EXIT="0")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.disposition()[3], "no_samples")
        self.assertIn("eligible sites produced no usable LCP", result.stderr)

    def test_harness_failure_does_not_stop_later_sites(self) -> None:
        self.add_valid_site("example.com")
        result = subprocess.run(
            [str(SCRIPT), "--sites", "apple.com,example.com", "--reps", "1"],
            cwd=self.root,
            env={
                **self.env,
                "FAKE_RESULTS": "1",
                "FAKE_METRIC": "1",
                "FAKE_FAIL_SITE": "apple.com",
            },
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 1)
        path = next((self.root / "crossbench-dispositions").glob("*.tsv"))
        rows = [line.split("\t") for line in path.read_text().splitlines()[1:]]
        self.assertEqual([(row[2], row[3]) for row in rows],
                         [("apple.com", "infra_error"), ("example.com", "measured")])

    def test_censored_site_does_not_fail_when_another_site_has_data(self) -> None:
        self.add_valid_site("example.com")
        result = subprocess.run(
            [str(SCRIPT), "--sites", "apple.com,example.com", "--reps", "1"],
            cwd=self.root,
            env={
                **self.env,
                "FAKE_RESULTS": "1",
                "FAKE_METRIC": "1",
                "FAKE_UNFINALIZED_SITE": "apple.com",
            },
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        path = next((self.root / "crossbench-dispositions").glob("*.tsv"))
        rows = [line.split("\t") for line in path.read_text().splitlines()[1:]]
        self.assertEqual([(row[2], row[3]) for row in rows],
                         [("apple.com", "no_samples"), ("example.com", "measured")])

    def test_manifest_errors_preserve_reason_status_hash_and_requested_count(self) -> None:
        blocked_sha = "b" * 64
        self.add_invalid_site("blocked.test", "http_403", "403", blocked_sha)
        self.add_invalid_site("missing.test", "archive_missing")
        result = subprocess.run(
            [
                str(SCRIPT), "--sites",
                "apple.com,blocked.test,missing.test", "--reps", "1",
            ],
            cwd=self.root,
            env={**self.env, "FAKE_RESULTS": "1", "FAKE_METRIC": "1"},
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        path = next((self.root / "crossbench-dispositions").glob("*.tsv"))
        rows = {
            fields[2]: fields
            for fields in (
                line.split("\t") for line in path.read_text().splitlines()[1:]
            )
        }
        blocked = rows["blocked.test"]
        self.assertEqual(blocked[3:7], ["excluded", "error", "http_403", "403"])
        self.assertEqual(blocked[8:14], [blocked_sha, "1", "0", "0", "0", "0"])
        missing = rows["missing.test"]
        self.assertEqual(missing[3:7], ["excluded", "error", "archive_missing", "-"])
        self.assertEqual(missing[8:14], ["-", "1", "0", "0", "0", "0"])


if __name__ == "__main__":
    unittest.main()
