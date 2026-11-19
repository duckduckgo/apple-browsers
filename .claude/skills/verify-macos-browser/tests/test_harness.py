"""Tests for the harness's pure parts: the verdict, report.md, and check. No app, build or VM.
Run: python3 -m unittest discover -s .claude/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import os
import sys
import tempfile
import textwrap
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "scripts"))
import harness  # noqa: E402
import vhelp  # noqa: E402


def record(checks=(), app_running=True, error=None, problems=(), cancelled=False):
    rec = harness.Record()
    rec.checks = list(checks)
    rec.app_running, rec.error, rec.problems, rec.cancelled = app_running, error, list(problems), cancelled
    return rec


class LabelTests(unittest.TestCase):
    def test_pass_needs_a_passing_check_and_the_app_running(self):
        self.assertEqual(harness.label(record([("tabs", True, None)])), ("PASS", 0))

    def test_any_failed_check_fails(self):
        self.assertEqual(harness.label(record([("tabs", True, None), ("pixel", False, "not fired")],
                                              error="proof: check failed: pixel")), ("FAIL", 1))

    def test_nothing_checked_is_inconclusive_not_pass(self):
        self.assertEqual(harness.label(record([])), ("INCONCLUSIVE", 2))

    def test_setup_failure_is_inconclusive(self):
        self.assertEqual(harness.label(record([], app_running=None, error="setup: build failed")), ("INCONCLUSIVE", 2))

    def test_an_action_error_after_passing_checks_is_inconclusive(self):
        self.assertEqual(harness.label(record([("tabs", True, None)], error="proof: ProofError: AMBIGUOUS")),
                         ("INCONCLUSIVE", 2))

    def test_app_gone_at_the_end_fails(self):
        self.assertEqual(harness.label(record([("tabs", True, None)], app_running=False)), ("FAIL", 1))

    def test_unknown_app_state_is_never_a_pass(self):
        self.assertEqual(harness.label(record([("tabs", True, None)], app_running=None)), ("INCONCLUSIVE", 2))

    def test_a_pass_with_problems_exits_2(self):
        self.assertEqual(harness.label(record([("tabs", True, None)], problems=["VM vm-1 not released"])), ("PASS", 2))

    def test_cancelled_is_inconclusive_130(self):
        self.assertEqual(harness.label(record([("tabs", True, None)], cancelled=True, error="proof: cancelled")),
                         ("INCONCLUSIVE", 130))


class ReportTests(unittest.TestCase):
    MANIFEST = dict(revision="0123456789abcdef", dirty=False, macos="26.0", flags=["someFlag=on"],
                    launch=dict(language="en", locale="en_US", automation_port=None),
                    vm=dict(host="vm-1", macos="27.2.1"), rerun="cd /x && prove p.py --target vm-1",
                    build_hashes={"App": "a" * 64, "App.debug.dylib": "b" * 64},
                    running_hashes={"App": "a" * 64, "App.debug.dylib": "b" * 64})

    def write(self, rec, files=()):
        d = tempfile.mkdtemp()
        for name in files:
            open(os.path.join(d, name), "w").close()
        return harness.report("Cmd+T opens a new tab.\n\nMore detail.", rec, self.MANIFEST, d)

    def test_sections_in_verify_ios_order(self):
        text = self.write(record([("2 tab(s) open", True, None)]))
        positions = [text.index(f"## {s}\n") for s in ("Verified", "Evidence", "Outcome", "Details", "Unverified")]
        self.assertEqual(positions, sorted(positions))
        self.assertIn("## Verified\n\nCmd+T opens a new tab.", text)

    def test_outcome_lists_only_the_checks_that_ran(self):
        rec = record([("2 tab(s) open", True, None), ("pixel nope fired", False, "FAIL pixel nope not fired")],
                     error="proof: check failed: pixel nope fired")
        outcome = self.write(rec).split("## Outcome")[1].split("## Details")[0]
        self.assertIn("**FAIL**", outcome)
        self.assertIn("Passed:\n- 2 tab(s) open\n- app still running at the end\n", outcome)
        self.assertIn("Failed:\n- pixel nope fired: FAIL pixel nope not fired\n", outcome)

    def test_problems_are_always_shown(self):
        rec = record([("2 tab(s) open", True, None)], problems=["final screenshot not taken: NOT FRONTMOST"])
        text = self.write(rec)
        self.assertIn("**PASS** with problems (exit 2)", text)
        self.assertIn("- final screenshot not taken: NOT FRONTMOST", text)

    def test_evidence_links_only_files_that_exist(self):
        rec = record([("2 tab(s) open", True, None)])
        rec.shots = ["two-tabs.png", "missing.png"]
        evidence = self.write(rec, files=["two-tabs.png", "final.png", "pixels.json", "manifest.json"])
        self.assertIn("- Screenshots: [two-tabs.png](two-tabs.png)\n", evidence)
        self.assertNotIn("missing.png", evidence)
        self.assertIn("- Final screen: [final.png](final.png)", evidence)
        self.assertIn("- Telemetry: [pixels.json](pixels.json)\n", evidence)
        self.assertIn("- App log: (not captured)", evidence)
        self.assertIn("[manifest.json](manifest.json)", evidence)

    def test_details_name_revision_target_flags_and_binary(self):
        details = self.write(record([("t", True, None)])).split("## Details")[1]
        for want in ("`0123456789ab` (clean)", "VM vm-1 (macOS 27.2.1)", "someFlag=on", "locale en_US",
                     "`bbbbbbbbbbbbbbbb…`", "same binary", "--target vm-1"):
            self.assertIn(want, details)

    def test_unverified_items_are_listed(self):
        rec = record([("t", True, None)])
        rec.unverified = [("menu entry point", "menu bar not reachable in the VM")]
        self.assertTrue(self.write(rec).endswith("## Unverified\n\n- menu entry point: menu bar not reachable in the VM\n"))


class CheckTests(unittest.TestCase):
    names, fixed = vhelp.feature_flags(harness.ROOT)
    OVERRIDABLE = sorted(names - fixed)[0]
    FIXED = sorted(fixed)[0]

    def problems(self, source):
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write(textwrap.dedent(source))
        return harness.load(f.name)[1]

    def test_a_good_proof_passes(self):
        self.assertEqual(self.problems(f'''
            """Cmd+T opens a tab."""
            FLAGS = {{"{self.OVERRIDABLE}": True}}
            def run(mac):
                mac.key("cmd+t")
        '''), [])

    def test_needs_a_docstring(self):
        self.assertEqual(self.problems("def run(mac):\n    pass\n"), ["needs a docstring saying what it proves"])

    def test_needs_run_with_one_argument(self):
        self.assertEqual(self.problems('"""x"""\ndef run(mac, extra):\n    pass\n'),
                         ["must define run(mac) taking exactly one argument"])

    def test_refuses_an_unknown_flag(self):
        self.assertEqual(self.problems('"""x"""\nFLAGS = {"noSuchFlagEver": True}\ndef run(mac):\n    pass\n'),
                         ["FLAGS: noSuchFlagEver is not a FeatureFlag case"])

    def test_refuses_a_flag_the_app_would_ignore(self):
        problems = self.problems(f'"""x"""\nFLAGS = {{"{self.FIXED}": False}}\ndef run(mac):\n    pass\n')
        self.assertEqual(len(problems), 1)
        self.assertIn("supportsLocalOverriding: false", problems[0])

    def test_reports_a_syntax_error_without_running(self):
        self.assertTrue(self.problems('"""x"""\ndef run(mac)\n')[0].startswith("does not compile"))


class TabCountTests(unittest.TestCase):
    def test_counts_tabs_not_their_close_buttons(self):
        mac = harness.Mac("t", tempfile.mkdtemp(), harness.Record())
        mac._sh = lambda *a: (0, 'AXRadioButton id=TabBarViewItem title="New Tab" value="1" @408,89 240x38\n'
                                 'AXButton id=TabBarViewItem.closeButton desc="Close Tab" @618,97 22x22\n'
                                 'AXRadioButton id=TabBarViewItem title="New Tab" value="0" @648,89 240x38\n')
        self.assertEqual(mac.tab_count(), 2)


class TelemetryNeedsMarkTests(unittest.TestCase):
    def test_expect_pixel_without_mark_is_refused_before_running_anything(self):
        mac = harness.Mac("t", tempfile.mkdtemp(), harness.Record())
        mac._sh = lambda *a: self.fail("ran verify.sh without a mark")
        with self.assertRaises(harness.ProofError):
            mac.expect_pixel("m_mac_any")


if __name__ == "__main__":
    unittest.main()
