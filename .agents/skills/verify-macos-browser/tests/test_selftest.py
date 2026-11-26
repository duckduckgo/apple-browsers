"""Tests for selftest's pure parts: step order and stop-at-first-failure, the why and fix of each failure from canned
command output, and the JSON result. No build, VM or app.
Run: python3 -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import os
import plistlib
import sys
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "scripts"))
import selftest  # noqa: E402


def ioreg(*sessions):
    return plistlib.dumps({"IOConsoleUsers": list(sessions)}).decode()


def session(name="virtualmachine", login_done=True, locked=None, on_console=True):
    s = {"kCGSSessionUserNameKey": name, "kCGSessionLoginDoneKey": login_done, "kCGSSessionOnConsoleKey": on_console}
    if locked is not None:
        s["CGSSessionScreenIsLocked"] = locked
    return s


class RunStepsTests(unittest.TestCase):
    def run_steps(self, steps):
        return selftest.run_steps(steps, lambda _: None)

    def test_runs_in_order_and_stops_at_the_first_failure(self):
        ran = []

        def step(name, why=None):
            return name, lambda: ran.append(name) or why

        out = self.run_steps([step("ssh without a prompt"), step("display never sleeps", "display sleeps after 10 min"),
                              step("screen not locked")])
        self.assertEqual(ran, ["ssh without a prompt", "display never sleeps"])
        self.assertEqual([(s["step"], s["ok"]) for s in out], [("ssh without a prompt", True), ("display never sleeps", False)])
        self.assertEqual(out[-1]["why"], "display sleeps after 10 min")
        self.assertIn("Turn display off", out[-1]["fix"])

    def test_all_passing_steps_have_no_why(self):
        out = self.run_steps([("Xcode selected", lambda: None), ("unit tests", lambda: None)])
        self.assertEqual(out, [dict(step="Xcode selected", ok=True), dict(step="unit tests", ok=True)])

    def test_a_check_that_raises_fails_that_step_and_stops(self):
        def boom():
            raise RuntimeError("ioreg over ssh: Connection reset")
        out = self.run_steps([("auto-login session up", boom), ("screen not locked", lambda: self.fail("ran on"))])
        self.assertEqual(out, [dict(step="auto-login session up", ok=False, why="RuntimeError: ioreg over ssh: Connection reset",
                                    fix=selftest.FIX["auto-login session up"])])


class FixTests(unittest.TestCase):
    def test_launch_failures_point_at_their_setup_section(self):
        step = "app launches and shows a window"
        self.assertIn("SKILL.md, Signing", selftest.fix_for(step, "NOT LAUNCHED: no app process after 60 s in vm-1 (AMFI? …)"))
        self.assertIn("section 4", selftest.fix_for(step, "NOT READY: no window after 60 s (keychain dialog in vm-1?)"))
        self.assertIn("unlock", selftest.fix_for(step, "ONBOARDING NOT SKIPPED: no regular tab"))
        self.assertIn("build.log", selftest.fix_for(step, "COPY FAILED: vm-1"))

    def test_a_broken_build_product_gets_its_own_fix(self):
        self.assertIn("assetcatalog_output", selftest.fix_for("build is current", "BROKEN BUILD PRODUCT: Assets.car is 512 bytes"))
        self.assertIn("first error", selftest.fix_for("build is current", "error: cannot find type 'X'"))

    def test_missing_signing_assets_point_at_the_signing_setup(self):
        for why in ('error: No signing certificate "Developer ID Application" found',
                    "error: No profile for team 'HKE973VLUW' matching 'match Direct com.duckduckgo.macos.browser.debug macos' found"):
            self.assertIn("SKILL.md, Signing", selftest.fix_for("build is current", why), why)
        self.assertIn("SKILL.md, Signing", selftest.fix_for("build signed with Developer ID", "x"))

    def test_every_proof_step_shares_the_proof_fix(self):
        self.assertEqual(selftest.fix_for("prove must_fail.py", "FAIL: …"), selftest.FIX["proof"])

    def test_vm_setup_steps_point_into_vm_setup(self):
        for step, section in (("ssh without a prompt", "section 3"), ("same macOS major as this Mac", "section 1"),
                              ("auto-login session up", "section 2"), ("Accessibility grant over ssh", "Accessibility"),
                              ("Screen Recording grant over ssh", "Screen & System Audio Recording")):
            self.assertIn("VM-SETUP.md", selftest.fix_for(step, "x"), step)
            self.assertIn(section, selftest.fix_for(step, "x"), step)

    def test_every_step_a_target_runs_has_a_fix(self):
        run = selftest.Run("/tmp/20261119-120000-selftest-abcd")
        setup, _, rest = run.vm_steps("vm-1", [], set())
        names = [n for n, _ in run.host_steps() + setup + rest + run.mac_steps([], set())]
        for name in names:
            self.assertTrue(selftest.fix_for(name, "why"), name)
        self.assertEqual(names[:4], ["Xcode selected", "build is current", "build signed with Developer ID", "unit tests"])
        self.assertEqual([n for n, _ in setup][:2], ["ssh without a prompt", "VM free and reserved"])
        self.assertEqual([n for n, _ in rest], ["prove must_fail.py", "prove t3_fixture_page.py", "nothing left running",
                                                "VM lock released at the end"])

    def test_vm_grant_steps_read_both_grants_from_one_ax_grants_over_ssh(self):
        run, calls = selftest.Run("/tmp/20261119-120000-selftest-abcd"), []
        run.ssh = lambda host, script, timeout=120: calls.append((host, script)) or (0, "accessibility=true screen-recording=false\n")
        steps = dict(run.vm_steps("vm-1", [], set())[0])
        self.assertIsNone(steps["Accessibility grant over ssh"]())
        self.assertEqual(steps["Screen Recording grant over ssh"](), "the process that drives has no screen-recording grant")
        self.assertEqual(calls, [("vm-1", "cd ~/verify && ./ax grants")])


class JudgeTests(unittest.TestCase):
    def test_ssh(self):
        self.assertIsNone(selftest.judge_exit(0, ""))
        self.assertEqual(selftest.judge_exit(255, "ssh: Could not resolve hostname no-such-vm: nodename nor servname provided\n"),
                         "ssh: Could not resolve hostname no-such-vm: nodename nor servname provided")
        self.assertEqual(selftest.judge_exit(255, ""), "exit 255")

    def test_same_major(self):
        self.assertIsNone(selftest.judge_same_major("27.2.1", "27.0"))
        self.assertEqual(selftest.judge_same_major("27.2.1", "26.4"), "the VM runs macOS 26.4, this Mac 27.2.1")

    def test_logged_in(self):
        self.assertIsNone(selftest.judge_logged_in(ioreg(session())))
        self.assertIsNotNone(selftest.judge_logged_in(ioreg()))
        self.assertIsNotNone(selftest.judge_logged_in(ioreg(session("loginwindow"))))
        self.assertIsNotNone(selftest.judge_logged_in(ioreg(session(login_done=False))))
        self.assertIsNotNone(selftest.judge_logged_in(ioreg(session(on_console=False))))

    def test_unlocked(self):
        self.assertIsNone(selftest.judge_unlocked(ioreg(session())))
        self.assertIsNone(selftest.judge_unlocked(ioreg(session(locked=False))))
        self.assertEqual(selftest.judge_unlocked(ioreg(session(locked=True))), "the screen is locked (session of virtualmachine)")

    def test_display_sleep(self):
        self.assertIsNone(selftest.judge_display_sleep(" sleep                 0\n displaysleep         0\n"))
        self.assertEqual(selftest.judge_display_sleep(" displaysleep         10\n"), "display sleeps after 10 min")
        self.assertEqual(selftest.judge_display_sleep(" sleep 0\n"), "pmset -g shows no displaysleep")

    def test_signing(self):
        developer_id = "Executable=/x\nAuthority=Developer ID Application: Duck Duck Go, Inc. (HKE973VLUW)\nAuthority=Developer ID Certification Authority\n"
        any_mac = plistlib.dumps({"Name": "match Direct com.duckduckgo.macos.browser.debug macos", "ProvisionsAllDevices": True}).decode()
        self.assertIsNone(selftest.judge_signing(developer_id, any_mac))
        development = "Authority=Apple Development: Someone (ABC123)\n"
        self.assertEqual(selftest.judge_signing(development, any_mac),
                         "signed by Apple Development: Someone (ABC123), not Developer ID Application")
        self.assertEqual(selftest.judge_signing("Signature=adhoc\n", any_mac), "signed by (no authority), not Developer ID Application")
        team = plistlib.dumps({"Name": "Mac Team Provisioning Profile: x", "ProvisionedDevices": ["AAA111", "fa22a9"]}).decode()
        self.assertEqual(selftest.judge_signing(developer_id, team),
                         "the profile 'Mac Team Provisioning Profile: x' lists 2 devices: the app runs only on those")

    def test_grants(self):
        both = "accessibility=true screen-recording=true\n"
        self.assertIsNone(selftest.judge_grant(both, "accessibility"))
        self.assertIsNone(selftest.judge_grant(both, "screen-recording"))
        out = "accessibility=true screen-recording=false\n"
        self.assertIsNone(selftest.judge_grant(out, "accessibility"))
        self.assertEqual(selftest.judge_grant(out, "screen-recording"), "the process that drives has no screen-recording grant")
        self.assertEqual(selftest.judge_grant("swiftc: error\n", "accessibility"), "ax grants: swiftc: error")

    def test_proof(self):
        self.assertIsNone(selftest.judge_proof(0, dict(verdict="PASS", report="/r/report.md")))
        self.assertEqual(selftest.judge_proof(2, dict(verdict="INCONCLUSIVE", reason="setup: NOT READY", report="/r/report.md")),
                         "INCONCLUSIVE: setup: NOT READY (report: /r/report.md)")

    def test_left_running(self):
        self.assertIsNone(selftest.judge_left("\n"))
        self.assertEqual(selftest.judge_left("in vm-1: 812 screencapture\n"), "still running: in vm-1: 812 screencapture")


class ResultTests(unittest.TestCase):
    def test_ok_lists_every_report(self):
        out = selftest.result([dict(step="unit tests", ok=True)],
                              {"vm-1": dict(steps=[dict(step="prove t3_fixture_page.py", ok=True)], reports=["/a/report.md"]),
                               "vm-2": dict(steps=[dict(step="prove t3_fixture_page.py", ok=True)], reports=["/b/report.md"])},
                              "/sel", 90)
        self.assertTrue(out["ok"])
        self.assertNotIn("failed", out)
        self.assertEqual(out["reports"], ["/a/report.md", "/b/report.md"])
        self.assertEqual(out["minutes"], 1.5)

    def test_a_failed_target_step_is_named_with_its_target(self):
        bad = dict(step="screen not locked", ok=False, why="the screen is locked", fix="unlock it")
        out = selftest.result([dict(step="unit tests", ok=True)],
                              {"vm-1": dict(steps=[dict(step="ssh without a prompt", ok=True)], reports=[]),
                               "vm-2": dict(steps=[dict(step="ssh without a prompt", ok=True), bad], reports=[])}, "/sel", 1)
        self.assertFalse(out["ok"])
        self.assertEqual(out["failed"], dict(target="vm-2", **bad))

    def test_a_failed_host_step_has_no_target(self):
        bad = dict(step="build is current", ok=False, why="error: x", fix="fix it")
        out = selftest.result([dict(step="Xcode selected", ok=True), bad], {}, "/sel", 1)
        self.assertFalse(out["ok"])
        self.assertEqual(out["failed"], dict(target=None, **bad))


if __name__ == "__main__":
    unittest.main()
