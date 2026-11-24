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
            (folder / "review.md").write_text(f"{review}\n\n1. ...\n")
        build = self.root / name / "evidence" / "macos-build-1"
        build.mkdir()
        (build / "result.json").write_text(json.dumps(dict(command="build", platform="macos", status="pass")))
        return self.root / name

    def test_report_groups_attempts_by_scenario_and_links_snapshots(self):
        batch = self.batch("tonight", "pass", review="confirmed")
        self.assertEqual(report.main([str(batch)]), 0)
        page = (batch / "report.html").read_text()
        self.assertIn("Scan finds the profile&#x27;s record", page)
        self.assertIn("pass · confirmed", page)
        self.assertIn("data-n=1", page)
        self.assertIn("1 match(es)", page)
        self.assertIn("evidence/macos-run-1/snapshots/00000002-scan-extract-result.png", page)
        self.assertNotIn("macos-build-1", page)

    def test_baseline_comparison_flags_a_changed_result(self):
        baseline = self.batch("baseline", "pass", review="confirmed")
        batch = self.batch("stack", "pass", review="disputed", matches=0)
        report.main([str(batch), "--baseline", str(baseline)])
        page = (batch / "report.html").read_text()
        self.assertIn("changed: review, result", page)
        self.assertIn("class='cell fail'", page)
        self.assertIn("fromHash[1] : 1)", page)


    def test_a_broker_blocked_review_warns_without_needing_attention(self):
        baseline = self.batch("baseline", "pass", review="confirmed")
        batch = self.batch("stack", "pass", review="broker blocked")
        report.main([str(batch), "--baseline", str(baseline)])
        page = (batch / "report.html").read_text()
        self.assertNotIn("Needs attention", page)
        self.assertIn("1 of 1 scenario runs were blocked by the broker", page)
        self.assertIn("pass · broker blocked", page)

    def test_a_step_attempt_is_listed_but_not_counted_as_the_scenario_run(self):
        batch = self.batch("stack", "pass", review="confirmed")
        step = batch / "evidence" / "macos-scheduler-1"
        step.mkdir()
        (step / "result.json").write_text(json.dumps(dict(command="scheduler", platform="macos", status="fail",
                                                           scenario="An upgrade", step="seed", startedAt=50, finishedAt=60)))
        report.main([str(batch)])
        page = (batch / "report.html").read_text()
        self.assertIn("step: seed", page)
        self.assertNotIn("Needs attention", page)

    def test_refresh_keeps_the_baseline_until_the_report_is_written_without_one(self):
        baseline = self.batch("baseline", "pass", review="confirmed")
        batch = self.batch("stack", "pass", review="disputed", matches=0)
        report.main([str(batch), "--baseline", str(baseline)])
        (batch / "report.html").unlink()
        report.refresh(batch)
        self.assertIn("changed: review, result", (batch / "report.html").read_text())
        report.main([str(batch)])
        report.refresh(batch)
        self.assertNotIn("changed:", (batch / "report.html").read_text())

    def test_latest_attempt_counts_and_brokers_with_the_same_title_stay_apart(self):
        batch = self.batch("stack", "fail", review="disputed")
        evidence = batch / "evidence"
        for name, broker, status, started in (("macos-run-2", "peoplefinders.com", "pass", 30), ("macos-run-3", "411.com", "pass", 40)):
            folder = evidence / name
            folder.mkdir()
            (folder / "pir-broker.json").write_text(json.dumps(dict(url=broker)))
            (folder / "review.md").write_text("confirmed\n")
            (folder / "result.json").write_text(json.dumps(dict(
                command="run", platform="macos", status=status, scenario="Scan finds the profile's record",
                startedAt=started, finishedAt=started + 5)))
        (evidence / "macos-run-1" / "pir-broker.json").write_text(json.dumps(dict(url="peoplefinders.com")))
        report.main([str(batch)])
        page = (batch / "report.html").read_text()
        self.assertIn("All 2 scenario runs got their expected verdict and were confirmed", page)
        self.assertIn("retry #", page)
        self.assertIn("· 411.com", page)


    def test_an_expected_failure_is_not_a_problem_but_an_unexpected_pass_is(self):
        batch = self.batch("stack", "fail", review="confirmed")
        result = batch / "evidence" / "macos-run-1" / "result.json"
        data = json.loads(result.read_text())
        result.write_text(json.dumps(dict(data, expected="fail")))
        report.main([str(batch)])
        self.assertIn("All 1 scenario runs got their expected verdict", (batch / "report.html").read_text())
        result.write_text(json.dumps(dict(data, status="pass", expected="fail")))
        report.main([str(batch)])
        self.assertIn("expected fail, got pass", (batch / "report.html").read_text())


    def test_findings_outside_the_scenario_warn_without_failing(self):
        batch = self.batch("stack", "pass", review="confirmed")
        (batch / "evidence" / "macos-run-1" / "review.md").write_text(
            "confirmed\n\n## Findings\n\n- The broker JSON misses ages on every card.\n")
        report.main([str(batch)])
        page = (batch / "report.html").read_text()
        self.assertIn("Findings outside the scenarios", page)
        self.assertIn("misses ages on every card", page)
        self.assertIn("All 1 scenario runs got their expected verdict", page)
        self.assertIn("class='cell ok'", page)


if __name__ == "__main__":
    unittest.main()
