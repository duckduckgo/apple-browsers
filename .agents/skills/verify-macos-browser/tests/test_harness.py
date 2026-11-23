"""Tests for the harness's pure parts: the verdict, report.md, and check. No app, build or VM.
Run: python3 -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import glob
import json
import os
import signal
import subprocess
import sys
import tempfile
import textwrap
import types
import unittest
import uuid
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "scripts"))
import harness  # noqa: E402
import vhelp  # noqa: E402


def record(checks=(), app_running=True, error=None, problems=(), cancelled=False):
    rec = harness.Record()
    rec.checks = [tuple(c) + ("unchanged",) * (4 - len(c)) for c in checks]   # (name, ok, detail[, base])
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
                    conditions=dict(appearance="light (system)", language="en", locale="en_US"),
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

    def test_a_vm_never_reserved_is_not_reported_as_this_mac(self):
        manifest = dict(self.MANIFEST, vm=None, target="vm-1")
        text = harness.report("x", record([], app_running=None, error="setup: NO VM FREE\n  vm-1: reserved"),
                              manifest, tempfile.mkdtemp())
        self.assertIn("- Target: vm-1 (no VM was reserved)", text)
        self.assertNotIn("this Mac", text)
        self.assertIn("**INCONCLUSIVE** (setup: NO VM FREE vm-1: reserved)\n", text)

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


class ConditionsDeclarationTests(unittest.TestCase):
    def problems(self, conditions):
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write(f'"""x"""\nCONDITIONS = {conditions}\n\n\ndef run(mac):\n    pass\n')
        return harness.load(f.name)[1]

    def test_every_condition_declared_well_is_accepted(self):
        self.assertEqual(self.problems('dict(appearance="dark", window=(40, 60, 1280, 800), language="pt-BR", '
                                       'locale="pt_BR")'), [])
        self.assertEqual(self.problems("{}"), [])

    def test_each_bad_condition_is_refused_by_check(self):
        for bad in ('dict(appearance="sepia")', 'dict(theme="dark")', "dict(window=(0, 0, 1280))",
                    "dict(window=(0, -5, 1280, 800))", "dict(window=(0, 0, 0, 800))", "dict(window=(0, 0, 1280.5, 800))",
                    'dict(language="English")', 'dict(locale="en-US")', '["dark"]'):
            with self.subTest(bad=bad):
                self.assertTrue(self.problems(bad))


class ActionEffectTests(unittest.TestCase):
    """Each action reports whether the accessibility tree changed (ax's last line); report.md lists the no-ops."""
    def run_actions(self, changed):
        rec = harness.Record()
        mac = harness.Mac("t", tempfile.mkdtemp(), rec)
        mac._sh = lambda command, *args: (0, f"{args[0]} done\nchanged={changed[args[0]]}")
        mac.press("Bookmarks")
        mac.click("target link")
        mac.type("hello")
        mac.key("cmd+t")
        rec.checks = [("tabs", True, None, "unchanged")]
        rec.app_running = True
        return rec, harness.report("x", rec, ReportTests.MANIFEST, tempfile.mkdtemp())

    def test_an_action_that_changed_nothing_is_a_warning_in_the_report_not_a_failure(self):
        rec, text = self.run_actions(dict(press="no", clickel="yes", type="no", key="yes"))
        warnings = text.split("Warnings:\n")[1].split("\n\n")[0]
        self.assertIn("press('Bookmarks') changed nothing", warnings)
        self.assertIn("type('hello') changed nothing", warnings)
        self.assertNotIn("target link", warnings)
        self.assertNotIn("cmd+t", warnings)
        self.assertEqual(harness.label(rec), ("PASS", 0))

    def test_actions_that_changed_the_tree_leave_no_warning(self):
        _, text = self.run_actions(dict(press="yes", clickel="yes", type="yes", key="yes"))
        self.assertNotIn("Warnings:", text)


class ConditionsRunTests(unittest.TestCase):
    """set_conditions and _finish against a fake verify.sh: what is set, read back, recorded and undone."""
    def fake(self, target="vm-1", fail=()):
        rec = harness.Record()
        mac = harness.Mac("t", tempfile.mkdtemp(), rec)
        ran, state = [], dict(appearance="light", window="0,38,1200,700")

        def sh(command, *args):
            ran.append((command, *map(str, args)))
            if command in fail:
                return 2, f"{command.upper()} BROKEN"
            if command == "appearance":
                state["appearance"] = "light" if args[0] == "restore" else args[0]
                return 0, f"appearance={state['appearance']} (system)"
            if command == "window":
                state["window"] = ",".join(map(str, args))
                return 0, f"window={state['window']}"
            if command == "ax" and args[0] == "winrect":
                return 0, state["window"]
            return 0, "yes" if command == "ax" else ""
        mac._sh = sh
        return mac, rec, ran, state

    def test_a_run_always_starts_from_the_default_appearance_even_undeclared(self):
        mac, rec, ran, state = self.fake()
        state["appearance"] = "dark"   # left by a run killed before its undo
        harness.set_conditions(mac, {}, "vm-1", launched=False)
        self.assertEqual(ran, [("appearance", "restore")])
        self.assertEqual(rec.conditions, dict(appearance="light (system)"))
        self.assertEqual(mac.undo, [])

    def test_declared_conditions_are_set_read_back_and_recorded(self):
        mac, rec, ran, state = self.fake()
        c = dict(appearance="dark", window=(40, 60, 1280, 800))
        harness.set_conditions(mac, c, "vm-1", launched=False)
        harness.set_conditions(mac, c, "vm-1", launched=True)
        self.assertEqual(rec.conditions, dict(appearance="dark (system)", window="40,60,1280,800"))
        self.assertEqual(state["appearance"], "dark")

    def test_undeclared_window_is_recorded_as_the_app_opened_it(self):
        mac, rec, ran, _ = self.fake()
        harness.set_conditions(mac, {}, "vm-1", launched=True)
        self.assertEqual(rec.conditions, dict(window="0,38,1200,700"))
        self.assertNotIn("window", [c[0] for c in ran])

    def test_everything_set_is_undone_last_first_before_cleanup_even_when_setup_failed(self):
        mac, rec, ran, state = self.fake(target="mac")
        c = dict(appearance="dark", window=(40, 60, 1280, 800))
        harness.set_conditions(mac, c, "mac", launched=False)
        harness.set_conditions(mac, c, "mac", launched=True)
        rec.phase = "setup"   # e.g. doctor failed after the window moved: the proof never started
        harness._finish(mac, rec, mac.evidence)
        after = ran[ran.index(("window", "40", "60", "1280", "800")) + 1:]
        undo = [c for c in after if c[0] in ("window", "appearance")]
        self.assertEqual(undo, [("window", "0", "38", "1200", "700"), ("appearance", "restore")])
        self.assertLess(after.index(undo[-1]), after.index(("cleanup",)))
        self.assertEqual((state["appearance"], state["window"]), ("light", "0,38,1200,700"))
        self.assertEqual(rec.problems, [])

    def test_a_vm_window_needs_no_undo(self):
        mac, rec, ran, _ = self.fake()
        harness.set_conditions(mac, dict(window=(40, 60, 1280, 800)), "vm-1", launched=True)
        self.assertEqual(mac.undo, [])

    def test_an_undo_that_fails_is_a_problem_and_the_rest_still_run(self):
        mac, rec, ran, _ = self.fake(target="mac")
        harness.set_conditions(mac, dict(appearance="dark"), "mac", launched=False)
        mac.undo.append(("window", ("window", "0", "38", "1200", "700")))
        real = mac._sh
        mac._sh = lambda command, *a: (2, "APP NOT RUNNING") if command == "window" else real(command, *a)
        harness._finish(mac, rec, mac.evidence)
        self.assertEqual(len(rec.problems), 1)
        self.assertIn("window not undone (exit 2): APP NOT RUNNING", rec.problems[0])
        self.assertEqual(ran[-2:], [("appearance", "restore"), ("cleanup",)])
        self.assertEqual(rec.action_errors, [])

    def test_a_failed_restore_is_a_problem_when_no_appearance_was_declared(self):
        mac, rec, ran, _ = self.fake(fail=("appearance",))
        harness.set_conditions(mac, {}, "vm-1", launched=False)
        self.assertEqual(rec.problems, ["appearance not restored (exit 2): APPEARANCE BROKEN"])
        self.assertEqual(rec.conditions, {})

    def test_a_failed_restore_stops_the_run_when_an_appearance_was_declared(self):
        mac, rec, ran, _ = self.fake(fail=("appearance",))
        with self.assertRaises(harness.ProofError):
            harness.set_conditions(mac, dict(appearance="dark"), "vm-1", launched=False)

    def test_a_condition_that_does_not_take_is_setup_trouble(self):
        mac, rec, ran, _ = self.fake(fail=("window",))
        with self.assertRaises(harness.ProofError):
            harness.set_conditions(mac, dict(window=(40, 60, 1280, 800)), "vm-1", launched=True)

    def test_manifest_and_report_record_each_condition_and_which_were_declared(self):
        mac, rec, ran, _ = self.fake()
        c = dict(appearance="dark", window=(40, 60, 1280, 800), language="de", locale="de_DE")
        harness.set_conditions(mac, c, "vm-1", launched=False)
        harness.set_conditions(mac, c, "vm-1", launched=True)
        evidence = tempfile.mkdtemp()
        with open(os.path.join(evidence, "manifest.json"), "w") as f:
            json.dump(dict(launch=dict(language="de", locale="de_DE", pid=1)), f)
        m = harness._manifest(evidence, rec, "p.py", "r", {}, [], "vm-1", None, sorted(c))
        saved = json.loads(read(os.path.join(evidence, "manifest.json")))
        self.assertEqual(saved["conditions"], dict(appearance="dark (system)", window="40,60,1280,800",
                                                   language="de", locale="de_DE"))
        self.assertEqual(saved["conditions_declared"], ["appearance", "language", "locale", "window"])
        self.assertIn("- Conditions: appearance dark (system) (declared), window 40,60,1280,800 (declared), "
                      "language de (declared), locale de_DE (declared); automation off\n",
                      harness.report("x", rec, m, evidence))

    def test_report_marks_only_declared_conditions(self):
        m = dict(conditions=dict(appearance="light (system)", window="0,38,1200,700", language="en", locale="en_US"))
        self.assertEqual(harness.conditions_line(m),
                         "appearance light (system), window 0,38,1200,700, language en, locale en_US")


class TabCountTests(unittest.TestCase):
    def test_counts_tabs_not_their_close_buttons(self):
        mac = harness.Mac("t", tempfile.mkdtemp(), harness.Record())
        mac._sh = lambda *a: (0, 'AXRadioButton id=TabBarViewItem title="New Tab" value="1" @408,89 240x38\n'
                                 'AXButton id=TabBarViewItem.closeButton desc="Close Tab" @618,97 22x22\n'
                                 'AXRadioButton id=TabBarViewItem title="New Tab" value="0" @648,89 240x38\n')
        self.assertEqual(mac.tab_count(), 2)

    def test_counts_in_the_front_window_only(self):
        mac = harness.Mac("t", tempfile.mkdtemp(), harness.Record())
        mac._sh = lambda *a: (0, "") if a == ("ax", "findmain", "TabBarViewItem") else self.fail(f"read {a}")
        self.assertEqual(mac.tab_count(), 0)


class TelemetryNeedsMarkTests(unittest.TestCase):
    def test_expect_pixel_without_mark_is_refused_before_running_anything(self):
        mac = harness.Mac("t", tempfile.mkdtemp(), harness.Record())
        mac._sh = lambda *a: self.fail("ran verify.sh without a mark")
        with self.assertRaises(harness.ProofError):
            mac.expect_pixel("m_mac_any")


class ActionErrorTests(unittest.TestCase):
    def mac(self, *outputs):
        mac = harness.Mac("t", tempfile.mkdtemp(), harness.Record())
        it = iter(outputs)
        mac._sh = lambda *a: next(it)
        return mac

    def test_a_failed_action_the_proof_catches_still_blocks_a_pass(self):
        mac = self.mac((2, "AMBIGUOUS: 2 matches"))
        try:
            mac.press("New Tab")
        except harness.ProofError:
            pass
        mac.check("tabs", True)
        mac.rec.app_running = True
        self.assertEqual(harness.label(mac.rec), ("INCONCLUSIVE", 2))

    def test_a_read_that_fails_once_then_works_passes(self):
        mac = self.mac((255, "ssh: timed out"), (0, "AXButton id=X @1,1 1x1"))
        mac.eventually("X shown", lambda: mac.find("X"), timeout=5, every=0)
        self.assertEqual(mac.rec.action_errors, [])

    def test_a_read_that_never_works_is_cant_tell_not_a_failed_check(self):
        mac = harness.Mac("t", tempfile.mkdtemp(), harness.Record())
        mac._sh = lambda *a: (255, "ssh: timed out")
        with self.assertRaises(harness.ProofError):
            mac.eventually("X shown", lambda: mac.find("X"), timeout=0, every=0)
        self.assertEqual(mac.rec.checks, [])


class FinalAppStateTests(unittest.TestCase):
    def state(self, front):
        rec = harness.Record()
        rec.phase = "proof"
        mac = harness.Mac("t", tempfile.mkdtemp(), rec)
        mac._sh = lambda command, *a: front if command == "ax" else (0, "")
        harness._finish(mac, rec, mac.evidence)
        return rec.app_running

    def test_ax_answer_decides(self):
        self.assertIs(self.state((0, "a warning line\nno")), True)
        self.assertIs(self.state((1, "APP NOT RUNNING: com.duckduckgo.macos.browser.debug")), False)

    def test_an_ssh_failure_leaves_it_unknown(self):
        self.assertIsNone(self.state((255, "ssh: connect to host vm-1 port 22: Operation timed out")))


class RecordingTests(unittest.TestCase):
    def finish(self, stop, video=True):
        """_finish after a passing proof, with `record stop` answering `stop`; returns (rec, commands run, report)."""
        rec = record([("2 tab(s) open", True, None)])
        rec.phase, rec.video = "proof", {} if video else None
        mac = harness.Mac("t", tempfile.mkdtemp(), rec)
        ran = []
        mac._sh = lambda command, *a: ran.append((command, *a)) or (stop if command == "record" else (0, "yes"))
        harness._finish(mac, rec, mac.evidence)
        if stop[0] in (0, 1) and video:
            open(os.path.join(mac.evidence, harness.VIDEO), "w").close()   # what verify.sh record stop leaves
        rec.app_running = True
        return rec, ran, harness.report("x", rec, {}, mac.evidence)

    def test_a_recording_links_from_evidence_with_its_length(self):
        rec, ran, text = self.finish((0, "recording.mp4 seconds=12.34 bytes=5678"))
        self.assertIn(("record", "stop"), ran)
        self.assertIn("- Recording: [recording.mp4](recording.mp4) (12.3 s)\n", text)
        self.assertEqual(rec.video, dict(path="recording.mp4", seconds=12.34, bytes=5678))
        self.assertEqual(harness.label(rec), ("PASS", 0))

    def test_a_failed_recording_is_a_problem_not_a_failed_check(self):
        rec, _, text = self.finish((2, "UNPLAYABLE: AVFoundation can't read the movie"))
        self.assertEqual(harness.label(rec), ("PASS", 2))
        self.assertEqual([ok for _, ok, *_ in rec.checks], [True])
        self.assertIn("- screen recording failed: UNPLAYABLE: AVFoundation can't read the movie\n", text)
        self.assertIn("- Recording: (none: see Problems)\n", text)
        self.assertNotIn("](recording.mp4)", text)

    def test_a_recording_cut_short_is_kept_and_is_a_problem(self):
        rec, _, text = self.finish((1, "recording.mp4 seconds=3.0 bytes=10\nCUT: another app came in front"))
        self.assertEqual(harness.label(rec), ("PASS", 2))
        self.assertIn("- Recording: [recording.mp4](recording.mp4) (3.0 s)\n", text)
        self.assertIn("CUT: another app came in front", rec.video["error"])
        self.assertIn("- screen recording cut short: ", text)
        self.assertNotIn("recording failed", text)

    def test_no_video_records_nothing_and_says_so(self):
        rec, ran, text = self.finish((0, "recording.mp4 seconds=1 bytes=1"), video=False)
        self.assertNotIn("record", [c for c, *_ in ran])
        self.assertIn("- Recording: off (--no-video)\n", text)
        self.assertEqual(harness.label(rec), ("PASS", 0))
        self.assertTrue(harness.rerun_command("/p/proof.py", "vm-1", None, video=False).endswith(" --no-video"))
        self.assertNotIn("--no-video", harness.rerun_command("/p/proof.py", "vm-1"))
        evidence = tempfile.mkdtemp()
        harness._manifest(evidence, rec, os.path.join(evidence, "proof.py"), "r", {}, [], "vm-1")
        self.assertEqual(json.loads(read(os.path.join(evidence, "manifest.json")))["video"], dict(off=True))


BIN = os.path.join(harness.SKILL, "bin", "verify-macos-browser")


def read(path):
    with open(path) as f:
        return f.read()


class ExamplesTests(unittest.TestCase):
    def test_check_accepts_every_example(self):
        examples = sorted(glob.glob(os.path.join(harness.SKILL, "examples", "*.py")))
        self.assertTrue(examples)
        p = subprocess.run([sys.executable, "-I", BIN, "check", *examples], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)


class EvidenceDirTests(unittest.TestCase):
    def cli(self, *args):
        return subprocess.run([sys.executable, "-I", BIN, *args], capture_output=True, text=True)

    def test_an_evidence_dir_inside_the_checkout_is_refused_and_nothing_is_written(self):
        inside = os.path.join(harness.ROOT, f"evidence-{uuid.uuid4().hex[:8]}")
        p = self.cli("new-proof", "x", "--evidence-dir", inside)
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        self.assertIn("inside the git checkout", p.stderr)
        self.assertFalse(os.path.exists(inside))

    def test_a_symlink_into_the_checkout_is_refused(self):
        link = os.path.join(tempfile.mkdtemp(), "link")
        os.symlink(os.path.join(harness.ROOT, f"evidence-{uuid.uuid4().hex[:8]}"), link)   # dangling until written
        with self.assertRaises(harness.Refused):
            harness.evidence_root(os.path.join(link, "proofs"))

    def test_an_unknown_target_is_refused_before_anything_is_written(self):
        d = os.path.realpath(tempfile.mkdtemp())
        proof = self.cli("new-proof", "x", "--evidence-dir", d).stdout.strip()
        before = sorted(os.listdir(d))
        p = self.cli("prove", proof, "--target", "vm-3", "--evidence-dir", d)
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        self.assertIn("--target must be one of", p.stdout)
        self.assertEqual(sorted(os.listdir(d)), before)
        self.assertEqual(os.listdir(os.path.dirname(proof)), ["proof.py"])

    def test_an_evidence_dir_outside_any_checkout_is_used_as_given(self):
        d = os.path.join(tempfile.mkdtemp(), "not-yet")
        proof = self.cli("new-proof", "Cmd T", "--evidence-dir", d).stdout.strip()
        self.assertEqual(os.path.dirname(os.path.dirname(proof)), os.path.realpath(d))
        self.assertRegex(os.path.basename(os.path.dirname(proof)), r"^\d{8}-\d{6}-cmd-t-[0-9a-f]{4}$")


class AttemptFolderTests(unittest.TestCase):
    def setUp(self):
        self.root = os.path.realpath(tempfile.mkdtemp())

    def test_each_new_proof_gets_its_own_folder(self):
        a, b = harness.new_proof("tabs", self.root), harness.new_proof("tabs", self.root)
        self.assertNotEqual(os.path.dirname(a), os.path.dirname(b))

    def test_an_untouched_attempt_folder_is_used_in_place(self):
        proof = harness.new_proof("tabs", self.root)
        self.assertEqual(harness.attempt_dir(proof, self.root), (os.path.dirname(proof), proof))

    def test_a_finished_attempt_is_never_overwritten(self):
        proof = harness.new_proof("tabs", self.root)
        with open(os.path.join(os.path.dirname(proof), "report.md"), "w") as f:
            f.write("first run")
        folder, copy = harness.attempt_dir(proof, self.root)
        self.assertNotEqual(folder, os.path.dirname(proof))
        self.assertEqual(os.path.dirname(folder), self.root)
        self.assertEqual(read(copy), read(proof))
        self.assertEqual(sorted(os.listdir(os.path.dirname(proof))), ["proof.py", "report.md"])
        self.assertRegex(os.path.basename(folder), r"^\d{8}-\d{6}-tabs-[0-9a-f]{4}$")

    def test_a_folder_whose_name_is_no_topic_gets_a_valid_one(self):
        lead = os.path.join(self.root, "_lead")
        os.makedirs(lead)
        with open(os.path.join(lead, "proof.py"), "w") as f:
            f.write(harness.TEMPLATE)
        folder, _ = harness.attempt_dir(os.path.join(lead, "proof.py"), self.root)
        self.assertRegex(harness.topic_of(folder), r"^lead-[0-9a-f]{4}$")   # verify.sh accepts ^[a-z0-9-]+$

    def test_a_long_name_still_gets_a_topic_short_enough_to_open_a_window(self):
        folder = os.path.dirname(harness.new_proof("Duck.ai sidebar keeps its chat", self.root))
        self.assertRegex(os.path.basename(folder), r"^\d{8}-\d{6}-duck-ai-sidebar-keeps-it-[0-9a-f]{4}$")
        self.assertRegex(harness.topic_of(folder), r"^duck-ai-s-[0-9a-f]{4}$")
        self.assertLessEqual(len(harness.topic_of(folder)), 14)

    def test_prove_without_the_option_keeps_a_proof_made_with_it_in_its_evidence_dir(self):
        evidence_dir, home = tempfile.mkdtemp(), tempfile.mkdtemp()
        proof = harness.new_proof("tabs", harness.evidence_root(evidence_dir))
        with mock.patch.object(harness, "HOME", home), \
                mock.patch.object(harness.Mac, "_sh", lambda self, *a: (2, "NO VM FREE")):
            _, out = harness.prove(proof, "vm")
        self.assertEqual(os.path.dirname(out["evidence"]), os.path.realpath(evidence_dir))
        self.assertEqual(os.listdir(home), [])


class PublishablePathTests(unittest.TestCase):
    HOME = os.path.expanduser("~")

    def test_rerun_shows_home_as_tilde_and_expands_back_in_zsh(self):
        proof = os.path.join(self.HOME, "ev dir", "20260101-000000-tabs-abcd", "proof.py")
        evidence_dir = os.path.join(self.HOME, "ev dir")
        rerun = harness.rerun_command(proof, "vm-1", evidence_dir)
        self.assertNotIn(self.HOME + os.sep, rerun)
        self.assertIn("--evidence-dir ~/", rerun)
        args = rerun.split(" prove ", 1)[1]
        words = subprocess.run(["zsh", "-fc", f"print -rl -- {args}"], capture_output=True, text=True).stdout
        self.assertEqual(words.splitlines(), [proof, "--target", "vm-1", "--evidence-dir", evidence_dir])

    def test_a_run_on_another_checkout_reruns_from_that_checkout(self):
        other = os.path.join(self.HOME, ".ddg-verify-macos", "base", "0123456789ab")
        rerun = harness.rerun_command("/ev/p/proof.py", "vm-1", checkout=other)
        self.assertTrue(rerun.startswith("cd ~/.ddg-verify-macos/base/0123456789ab && "), rerun)
        self.assertIn(" --checkout ~/.ddg-verify-macos/base/0123456789ab", rerun)
        self.assertNotIn("--checkout", harness.rerun_command("/ev/p/proof.py", "vm-1"))

    def test_a_checkout_without_the_workspace_is_refused(self):
        with self.assertRaises(harness.Refused):
            harness.checkout_of(tempfile.mkdtemp())
        self.assertEqual(harness.checkout_of(harness.ROOT), harness.ROOT)

    def test_manifest_and_report_show_home_as_tilde(self):
        evidence = tempfile.mkdtemp()
        with open(os.path.join(evidence, "manifest.json"), "w") as f:
            json.dump(dict(worktree=os.path.join(self.HOME, "repo")), f)
        rec = record([("t", True, None)], problems=[f"cleanup failed: {self.HOME}/repo/x"])
        m = harness._manifest(evidence, rec, os.path.join(evidence, "proof.py"), "rerun", {}, [], "vm-1",
                              os.path.join(self.HOME, "ev"))
        written = read(os.path.join(evidence, "manifest.json"))
        self.assertNotIn(self.HOME + os.sep, written)
        self.assertEqual(json.loads(written)["evidence_dir"], "~/ev")
        self.assertNotIn(self.HOME + os.sep, harness.report("x", rec, m, evidence))



class BaseFlagsTests(unittest.TestCase):
    def checkout(self, *cases):
        root = tempfile.mkdtemp()
        path = os.path.join(root, vhelp.FEATURE_FLAG_SWIFT)
        os.makedirs(os.path.dirname(path))
        with open(path, "w") as f:
            f.write("public enum FeatureFlag {\n" + "".join(f"    case {c}\n" for c in cases) + "}\n")
        return root

    def test_the_base_run_skips_a_flag_the_base_revision_does_not_define(self):
        flags = {"oldFlag": True, "newFlag": False}
        self.assertEqual(harness.flags_to_pin(flags, self.checkout("oldFlag"), as_base=True),
                         ({"oldFlag": True}, ["newFlag"]))

    def test_every_other_run_pins_them_all(self):
        flags = {"oldFlag": True, "newFlag": False}
        self.assertEqual(harness.flags_to_pin(flags, self.checkout("oldFlag"), as_base=False), (flags, []))

class CleanupSignalTests(unittest.TestCase):
    def test_a_child_started_during_cleanup_can_still_be_stopped_with_sigterm(self):
        # SIGINT/SIGTERM are held off during cleanup; a child (ssh, log show) must not inherit that, or a hung one
        # can only be stopped with kill -9.
        exits = []

        def finish(*_):
            exits.append(subprocess.run(["/bin/sh", "-c", "kill -TERM $$; sleep 5"], timeout=10).returncode)

        with tempfile.TemporaryDirectory() as home:
            proof = os.path.join(home, "p.py")
            with open(proof, "w") as f:
                f.write('"""x"""\ndef run(mac):\n    pass\n')
            with mock.patch.object(harness, "HOME", home), mock.patch.object(harness, "_finish", finish), \
                    mock.patch.object(harness.Mac, "_sh", lambda self, *a: (2, "NO VM FREE")):
                harness.prove(proof, "vm")
        self.assertEqual(exits, [-signal.SIGTERM])


if __name__ == "__main__":
    unittest.main()


class MacGrantTests(unittest.TestCase):
    def run_on_mac(self, grants):
        evidence, ran = tempfile.mkdtemp(), []

        def sh(mac, command, *args):
            ran.append((command, *args))
            if (command, *args) == ("ax", "grants"):
                return 0, grants
            return (0, "appearance=unset (app setting)") if command == "appearance" else (0, "")
        mod = types.SimpleNamespace(__doc__="Claim.", run=lambda mac: None)
        real = harness.Mac._sh
        harness.Mac._sh = sh
        try:
            rec, _ = harness.run_one(mod, os.path.join(evidence, "p.py"), evidence, "t", "mac", False, harness.ROOT,
                                     "rerun", evidence)
        finally:
            harness.Mac._sh = real
        return rec, [c[0] for c in ran]

    def test_a_missing_grant_stops_a_mac_run_before_the_build(self):
        rec, ran = self.run_on_mac("accessibility=true screen-recording=false")
        self.assertIn("NO GRANT", rec.error)
        self.assertIn("Screen Recording", rec.error)
        self.assertNotIn("Accessibility or", rec.error)
        self.assertNotIn("build", ran)
        self.assertEqual(harness.label(rec)[0], "INCONCLUSIVE")

    def test_both_grants_let_the_build_start(self):
        _, ran = self.run_on_mac("accessibility=true screen-recording=true")
        self.assertIn("build", ran)
