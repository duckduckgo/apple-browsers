import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import report  # noqa: E402


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def batch(self, name, status, review=None, matches=1):
        folder = self.root / name / "evidence" / "macos-run-1"
        (folder / "snapshots").mkdir(parents=True)
        (folder / "snapshots" / "00000002-scan-extract-result.png").write_bytes(b"png")
        (folder / "result.json").write_text(json.dumps(dict(
            command="run", platform="macos", status=status, scenario="Scan finds the profile's record",
            checks=[dict(check="scan emitted Scan Started", passed=True)], startedAt=0, finishedAt=19)))
        (folder / "pir-final-run.json").write_text(json.dumps(dict(results=[{}] * matches, events=[])))
        if review:
            (folder / "verification.md").write_text(f"{review}\n\n1. ...\n")
        build = self.root / name / "evidence" / "macos-build-1"
        build.mkdir()
        (build / "result.json").write_text(json.dumps(dict(command="build", platform="macos", status="pass")))
        return self.root / name

    def test_report_groups_attempts_by_scenario_and_links_snapshots(self):
        batch = self.batch("tonight", "pass", review="confirmed")
        self.assertEqual(report.main([str(batch)]), 0)
        page = (batch / "report.html").read_text()
        self.assertIn("Scan finds the profile&#x27;s record", page)
        self.assertIn("<span class='badge confirmed'>confirmed</span>", page)
        self.assertIn("<tr data-n=1", page)
        self.assertIn("1 match(es)", page)
        self.assertIn("evidence/macos-run-1/snapshots/00000002-scan-extract-result.png", page)
        self.assertNotIn("macos-build-1", page)

    def test_baseline_comparison_flags_a_changed_result(self):
        baseline = self.batch("baseline", "pass", review="confirmed")
        batch = self.batch("stack", "pass", review="disputed", matches=0)
        report.main([str(batch), "--baseline", str(baseline)])
        page = (batch / "report.html").read_text()
        self.assertIn("changed: review, result", page)
        self.assertIn("class='flag'", page)
        self.assertIn("fromHash[1] : 1)", page)


if __name__ == "__main__":
    unittest.main()
