"""Exercise method-only retry orchestration, reporting and fail-closed boundaries."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location("run_ui", Path(__file__).parents[1] / "run-ios-ui-tests.py")
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)
PASS = "UI Tests/ExampleUITests/testPassed()"
FAIL = "UI Tests/ExampleUITests/testFailed()"


def case(identifier, result):
    return {"nodeType": "Test Case", "nodeIdentifier": identifier.removeprefix("UI Tests/"),
            "result": result, "durationInSeconds": 1,
            "children": ([{"nodeType": "Failure Message", "name": "Expected page missing"}]
                         if result == "Failed" else [])}


def evidence(cases):
    summary = {"totalTestCount": len(cases), "expectedFailures": 0,
               **{key: sum(c["result"] == status for c in cases)
                  for key, status in (("passedTests", "Passed"), ("failedTests", "Failed"), ("skippedTests", "Skipped"))}}
    summary["result"] = "Failed" if summary["failedTests"] else "Passed"
    lines = []
    for item in cases:
        cls, method = item["nodeIdentifier"].removesuffix("()").split("/")
        lines += [f"Test Case '-[UI_Tests.{cls} {method}]' started.",
                  f"Test Case '-[UI_Tests.{cls} {method}]' {item['result'].lower()} (1.000 seconds)."]
    return summary, {"testNodes": cases}, "\n".join(lines), 65 if summary["failedTests"] else 0


class FailedOnlyRetryTests(unittest.TestCase):
    def run_workflow(self, initial, retry=None, mutation=None, enumeration=None, report_error=False):
        commands = []
        original_writer = RUN.write_report

        def report_writer(*args):
            if report_error:
                raise OSError("Injected report write failure")
            return original_writer(*args)
        attempts = [initial] + ([retry] if retry else [])
        with tempfile.TemporaryDirectory() as directory:
            before = Path.cwd()
            os.chdir(directory)
            try:
                def enumerate_command(command, **_):
                    output = Path(command[command.index("-test-enumeration-output-path") + 1])
                    output.write_text(json.dumps(enumeration or {"errors": [], "values": [{"enabledTests": [{"identifier": PASS}, {"identifier": FAIL}]}]}))
                def capture(command, path):
                    index = len(commands)
                    commands.append(command)
                    path.write_text(attempts[index][2])
                    return attempts[index][3]
                def native(kind, path):
                    index = len(commands) - 1
                    data = copy.deepcopy(attempts[index][0 if kind == "summary" else 1])
                    return mutation(index, kind, data) if mutation else data
                env = {"DEVICE": "iphone", "USER_MODE": "production", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_RUN_ID": "42", "GITHUB_SHA": "abc"}
                with patch.dict(os.environ, env), patch.object(sys, "argv", ["run", "--xctestrun", "matching.xctestrun", "--destination", "platform=iOS Simulator,id=owned", "--test-class", "ExampleUITests"]), patch.object(RUN.subprocess, "run", enumerate_command), patch.object(RUN, "capture", capture), patch.object(RUN, "native", native), patch.object(RUN, "write_report", report_writer), contextlib.redirect_stderr(io.StringIO()):
                    code = RUN.main()
                reports = Path("reports")
                meta = json.loads(next(reports.glob("*.meta.json")).read_text())
                xmls = list(reports.glob("*.xml"))
                xml = ET.parse(xmls[0]).getroot() if xmls else ET.Element("testsuites")
                return code, commands, meta, xml, bool(list(reports.glob("*.invalid")))
            finally:
                os.chdir(before)

    def test_cached_native_first_attempt_selects_only_actual_failure(self):
        fixture = json.loads((Path(__file__).parent / "fixtures/ios-native-first-failure.json").read_text())
        cases = RUN.cases_from_tree(fixture["tree"])
        expected = ["UI Tests/" + case["nodeIdentifier"] for case in cases]
        _, failed = RUN.validate_attempt(fixture["summary"], fixture["tree"], fixture["log"], expected, 65)
        self.assertEqual(failed, ["UI Tests/ContentBlockingUITests/testBrowsingMenuTogglesProtectionAndUndoRestoresPreviousState()"])
        self.assertNotIn("UI Tests/ContentBlockingUITests/testPrivacyDashboardReportsBlockedTrackerAndPersistsDisabledProtection()", failed)

    def test_passed_peer_excluded_and_initial_failure_reported_as_recovered(self):
        code, commands, meta, xml, invalid = self.run_workflow(evidence([case(PASS, "Passed"), case(FAIL, "Failed")]), evidence([case(FAIL, "Passed")]))
        self.assertEqual(code, 0)
        self.assertFalse(invalid)
        self.assertTrue(meta["complete"])
        self.assertEqual([item for item in commands[1] if item.startswith("-only-testing:")], ["-only-testing:" + FAIL.removesuffix("()")])
        self.assertEqual([c.get("name") for c in xml.iter("testcase")], ["testPassed", "testFailed", "testFailed"])
        self.assertEqual(len(list(xml.iter("failure"))), 1)
        self.assertNotIn("-retry-tests-on-failure", commands[0])
        self.assertNotIn("-test-iterations", commands[0])

    def test_complete_pass_does_not_retry(self):
        code, commands, _, _, invalid = self.run_workflow(evidence([case(PASS, "Passed"), case(FAIL, "Passed")]))
        self.assertEqual((code, len(commands), invalid), (0, 1, False))

    def test_second_failure_remains_failed_with_two_native_occurrences(self):
        code, commands, meta, xml, invalid = self.run_workflow(evidence([case(PASS, "Passed"), case(FAIL, "Failed")]), evidence([case(FAIL, "Failed")]))
        self.assertEqual((code, len(commands), invalid), (1, 2, False))
        self.assertEqual(meta["final_failed_selectors"], [FAIL])
        self.assertEqual(len(list(xml.iter("failure"))), 2)

    def test_skip_preserved_and_not_retried(self):
        code, commands, _, xml, invalid = self.run_workflow(evidence([case(PASS, "Passed"), case(FAIL, "Skipped")]))
        self.assertEqual((code, len(commands), invalid), (0, 1, False))
        self.assertEqual(len(list(xml.iter("skipped"))), 1)

    def test_incomplete_or_crashed_attempt_never_retries_any_method(self):
        initial = evidence([case(PASS, "Passed"), case(FAIL, "Failed")])
        variations = [evidence([case(PASS, "Passed")]), evidence([case(PASS, "Skipped"), case(FAIL, "Skipped")]),
                      (initial[0], initial[1], initial[2] + "\nRestarting after unexpected exit, crash, or test timeout", 65),
                      (initial[0], initial[1], initial[2] + "\nTest runner exited unexpectedly.", 65),
                      (initial[0], initial[1], initial[2].replace(" failed (1.000 seconds).", " exceeded execution time allowance"), 65),
                      (initial[0], initial[1], initial[2], 1),
                      evidence([case(PASS, "Passed"), case(FAIL, "Unknown")])]
        for item in variations:
            with self.subTest(item=item):
                code, commands, meta, _, invalid = self.run_workflow(item)
                self.assertEqual((code, len(commands), invalid), (1, 1, True))
                self.assertFalse(meta["complete"])

    def test_report_write_failure_retains_invalid_marker(self):
        code, commands, meta, _, invalid = self.run_workflow(evidence([case(PASS, "Passed"), case(FAIL, "Passed")]), report_error=True)
        self.assertEqual((code, len(commands), invalid), (1, 1, True))
        self.assertFalse(meta["complete"])
        self.assertEqual(meta["exit_code"], 1)

    def test_unknown_native_result_is_not_reported_as_a_pass(self):
        code, commands, _, xml, invalid = self.run_workflow(evidence([case(PASS, "Passed"), case(FAIL, "Unknown")]))
        self.assertEqual((code, len(commands), invalid), (1, 1, True))
        self.assertEqual(len(list(xml.iter("error"))), 1)

    def test_retry_missing_method_or_skipping_failure_is_invalid(self):
        for retry in (evidence([case(PASS, "Passed")]), evidence([case(FAIL, "Skipped")])):
            code, commands, meta, _, invalid = self.run_workflow(evidence([case(PASS, "Passed"), case(FAIL, "Failed")]), retry)
            self.assertEqual((code, len(commands), invalid), (1, 2, True))
            self.assertFalse(meta["complete"])

    def test_bad_enumeration_fails_before_execution(self):
        for enum in ({"errors": ["discovery failed"], "values": []}, {"errors": [], "values": [{"enabledTests": []}]}, {"errors": [], "values": [{"enabledTests": [{"identifier": "UI Tests/Other/testOops()"}]}]}):
            code, commands, _, _, invalid = self.run_workflow(None, enumeration=enum)
            self.assertEqual((code, commands, invalid), (1, [], True))

    def test_existing_attempt_summary_renderer_retains_recovered_failure(self):
        _, _, meta, xml, _ = self.run_workflow(evidence([case(PASS, "Passed"), case(FAIL, "Failed")]), evidence([case(FAIL, "Passed")]))
        import subprocess
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "reports").mkdir()
            ET.ElementTree(xml).write(root / "reports/ExampleUITests-iphone-production.xml")
            (root / "reports/ExampleUITests-iphone-production.meta.json").write_text(json.dumps(meta))
            env = dict(os.environ, MATRIX='[{"test":"ExampleUITests","device":"iphone"}]', RUN_PRODUCTION="true", RUN_INTERNAL="false", RUN_ID="42", GITHUB_STEP_SUMMARY=str(root / "summary.md"))
            subprocess.run([sys.executable, str(Path(__file__).parents[1] / "render-ios-ui-test-attempts.py")], cwd=root, env=env, check=True)
            text = (root / "summary.md").read_text()
            self.assertIn("failed, then passed", text)
            self.assertIn("Expected page missing", text)
            self.assertNotIn("Jobs without a complete", text)


if __name__ == "__main__":
    unittest.main()
