"""Tests for the reset between runs: what a VM reset reports, what this Mac's reset parks, restores and moves to the Trash,
how a failed reset reaches Problems, and what the --base manifest says differs between the runs. No app, build or VM;
this Mac's reset runs against a temporary home with its system commands faked.
Run: python3 -I -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import types
import unittest

sys.dont_write_bytecode = True
SKILL = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
sys.path.insert(0, os.path.join(SKILL, "scripts"))
import base  # noqa: E402
import harness  # noqa: E402
import vhelp  # noqa: E402

B = vhelp.BUNDLE


def write(path, text="x"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def read(path):
    with open(path) as f:
        return f.read()


class FakeMac:
    """The system commands MacReset runs, against a dict for the defaults domain."""
    def __init__(self, root, other_app_open=False, defaults=None):
        self.temp, self.cache = os.path.join(root, "T") + "/", os.path.join(root, "C") + "/"
        self.other_app_open, self.domain, self.ran = other_app_open, defaults, []

    def __call__(self, *args):
        self.ran.append(args)
        out, code = "", 0
        if args[0] == "getconf":
            out = self.temp if args[1] == "DARWIN_USER_TEMP_DIR" else self.cache
        elif args[0] in ("pkill", "pgrep"):
            code = 1   # no verify app running
            assert args[2] == r"DuckDuckGo\ \-\ verify\-t\.app/Contents/MacOS", args   # only this run's app
        elif args[0] == "lsappinfo":
            out = f'bundleID="{B}"' if self.other_app_open else 'bundleID="com.apple.finder"'
        elif args[:2] == ("defaults", "read"):   # an emptied domain reads back {} with exit 0, as on macOS 27
            out = json.dumps(self.domain) if self.domain else "{\n}"
        elif args[:2] == ("defaults", "export"):
            write(args[3], json.dumps(self.domain))
        elif args[:2] == ("defaults", "delete"):
            self.domain = None
        elif args[:2] == ("defaults", "import"):
            self.domain = json.loads(read(args[3]))
        return types.SimpleNamespace(returncode=code, stdout=out)


class MacResetTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.home, self.vhome, self.run_dir = (os.path.join(self.root, d) for d in ("home", "verify", "run"))
        for d in (self.vhome, self.run_dir, os.path.join(self.home, "Downloads"), os.path.join(self.home, ".Trash")):
            os.makedirs(d)
        self.lib = os.path.join(self.home, "Library")
        # The engineer's own Debug app data, defaults and Downloads, and what the reset must never touch.
        self.mine = os.path.join(self.lib, "Application Support", B, "bookmarks.db")
        self.mine_state = os.path.join(self.lib, "Saved Application State", B + ".savedState", "windows.plist")
        groups = os.path.join(self.lib, "Group Containers")
        self.debug_group = os.path.join(groups, "HKE973VLUW.com.duckduckgo.macos.browser.app-configuration.debug", "c.json")
        self.group = os.path.join(groups, "HKE973VLUW.com.duckduckgo.macos.browser.app-configuration", "release.json")
        self.vpn_group = os.path.join(groups, "HKE973VLUW.com.duckduckgo.macos.browser.network-protection.system-extension"
                                              ".debug", "vpn.db")
        self.release = os.path.join(self.lib, "Application Support", "com.duckduckgo.macos.browser", "real.db")
        self.user_dl = os.path.join(self.home, "Downloads", "tax-return.pdf")
        for p in (self.mine, self.mine_state, self.debug_group, self.group, self.vpn_group, self.release, self.user_dl):
            write(p, "engineer's " + os.path.basename(p))

    def reset(self, sh, owner=111):
        return vhelp.MacReset(self.run_dir, self.vhome, "DuckDuckGo - verify-t", home=self.home, owner=owner, sh=sh)

    def checks(self):
        return json.loads(read(os.path.join(self.run_dir, "reset.json")))["checks"]

    def test_a_run_starts_with_no_debug_app_data_and_the_engineers_comes_back_after(self):
        sh = FakeMac(self.root, defaults={"themeName": "dark"})
        write(os.path.join(sh.cache, "com.apple.WebKit.Networking+" + B, "cache.db"))
        r = self.reset(sh)
        r.begin()
        self.assertEqual(r.data(), [])
        self.assertIsNone(sh.domain)
        self.assertTrue(all(self.checks().values()), self.checks())
        # The run writes app data, a default, a temp file and a download, and changes an engineer's Downloads file.
        write(os.path.join(self.lib, "Application Support", B, "bookmarks.db"), "run's")
        write(os.path.join(self.lib, "WebKit", B, "run-only"), "run's")
        write(os.path.join(sh.temp, B, "tmp"), "run's")
        sh.domain = {"verifyProbe": "1"}
        self.assertFalse(os.path.exists(self.debug_group))
        write(self.debug_group, "run's privacy config")
        write(os.path.join(self.home, "Downloads", "probe.txt"), "run's")
        write(self.user_dl, "engineer's, edited during the run")
        r.end()
        self.assertEqual(read(self.mine), "engineer's bookmarks.db")
        self.assertEqual(read(self.debug_group), "engineer's c.json")
        self.assertEqual(read(self.mine_state), "engineer's windows.plist")
        self.assertTrue(os.path.exists(os.path.join(sh.cache, "com.apple.WebKit.Networking+" + B, "cache.db")))
        self.assertFalse(os.path.exists(os.path.join(self.lib, "WebKit", B)))
        self.assertFalse(os.path.exists(os.path.join(sh.temp, B)))
        self.assertEqual(sh.domain, {"themeName": "dark"})
        self.assertFalse(os.path.exists(os.path.join(self.home, "Downloads", "probe.txt")))
        self.assertEqual(read(os.path.join(self.home, ".Trash", "probe.txt")), "run's")
        self.assertEqual(read(self.user_dl), "engineer's, edited during the run")
        self.assertEqual(read(self.group), "engineer's release.json")
        self.assertEqual(read(self.vpn_group), "engineer's vpn.db")
        self.assertEqual(read(self.release), "engineer's real.db")
        self.assertFalse(os.path.exists(os.path.join(self.vhome, ".mac-park")))
        self.assertTrue(all(self.checks().values()), self.checks())

    def test_nothing_is_parked_or_deleted_while_a_debug_app_outside_the_skill_is_open(self):
        sh = FakeMac(self.root, other_app_open=True, defaults={"themeName": "dark"})
        r = self.reset(sh)
        r.begin()
        self.assertEqual(read(self.mine), "engineer's bookmarks.db")
        self.assertEqual(sh.domain, {"themeName": "dark"})
        self.assertFalse(self.checks()["no other Debug app open (another worktree's verify app counts)"])
        self.assertFalse(self.checks()["app data and temp files removed"])
        r.end()
        self.assertEqual(read(self.mine), "engineer's bookmarks.db")
        self.assertEqual(sh.domain, {"themeName": "dark"})

    def test_a_park_left_by_a_run_that_died_is_put_back_first(self):
        sh = FakeMac(self.root, defaults={"themeName": "dark"})
        self.reset(sh, owner=999999).begin()   # a pid that isn't running: that run died before its end
        write(os.path.join(self.lib, "Application Support", B, "bookmarks.db"), "dead run's")
        r = self.reset(sh)
        r.begin()
        self.assertTrue(all(self.checks().values()), self.checks())
        r.end()
        self.assertEqual(read(self.mine), "engineer's bookmarks.db")
        self.assertEqual(sh.domain, {"themeName": "dark"})

    def test_a_park_held_by_a_live_run_is_left_alone(self):
        sh = FakeMac(self.root)
        self.reset(sh, owner=os.getpid()).begin()
        r = self.reset(sh, owner=111)
        r.begin()
        self.assertFalse(self.checks()["Debug app data free (another run holds it)"])
        r.end()
        self.assertTrue(os.path.isdir(os.path.join(self.vhome, ".mac-park")))
        self.reset(sh, owner=os.getpid()).end()
        self.assertEqual(read(self.mine), "engineer's bookmarks.db")

    def test_begin_dying_halfway_loses_nothing(self):
        sh = FakeMac(self.root, defaults={"themeName": "dark"})
        real_rename = vhelp.os.rename
        moved = []

        def move_once(src, dst):   # the second move never happens: the run died there
            if moved:
                raise KeyboardInterrupt
            moved.append(src)
            return real_rename(src, dst)
        vhelp.os.rename = move_once
        try:
            with self.assertRaises(KeyboardInterrupt):
                self.reset(sh, owner=999999).begin()
        finally:
            vhelp.os.rename = real_rename
        r = self.reset(sh)
        r.begin()
        r.end()
        self.assertEqual(read(self.mine), "engineer's bookmarks.db")
        self.assertEqual(read(self.mine_state), "engineer's windows.plist")
        self.assertEqual(sh.domain, {"themeName": "dark"})

    def test_mac_reset_lists_only_the_debug_apps_own_data(self):
        sh = FakeMac(self.root)
        for d, name in ((sh.temp, B), (sh.temp, "com.apple.WebKit.GPU+" + B), (sh.cache, "com.apple.WebKit.GPU+" + B),
                        (sh.temp, "com.duckduckgo.macos.browser"), (sh.cache, "com.duckduckgo.macos.browser")):
            write(os.path.join(d, name, "t"))
        data = self.reset(sh).data()
        self.assertEqual(sorted(data), sorted([os.path.join(self.lib, "Application Support", B),
                                               os.path.dirname(self.debug_group),
                                               os.path.join(self.lib, "Saved Application State", B + ".savedState"),
                                               os.path.join(sh.temp, B),
                                               os.path.join(sh.cache, "com.apple.WebKit.GPU+" + B)]))

    def test_a_folder_macos_will_not_move_is_named_with_the_fix(self):
        sh = FakeMac(self.root)
        real_rename = vhelp.os.rename

        def refuse_groups(src, dst):
            if "Group Containers" in src:
                raise PermissionError(1, "Operation not permitted")
            return real_rename(src, dst)
        vhelp.os.rename = refuse_groups
        try:
            self.reset(sh).begin()
        finally:
            vhelp.os.rename = real_rename
        failed = [k for k, ok in self.checks().items() if not ok]
        self.assertIn("app data and temp files removed", failed)
        self.assertIn("macOS refused to move HKE973VLUW.com.duckduckgo.macos.browser.app-configuration.debug: give the "
                      "app that runs prove Full Disk Access, or prove in a VM", failed)

    def test_a_folder_macos_will_not_move_stays_and_fails_the_check(self):
        sh = FakeMac(self.root)
        real_rename = vhelp.os.rename

        def refuse(src, dst):
            if src.endswith(".savedState"):
                raise PermissionError(1, "Operation not permitted")
            return real_rename(src, dst)
        vhelp.os.rename = refuse
        try:
            r = self.reset(sh)
            r.begin()
        finally:
            vhelp.os.rename = real_rename
        self.assertFalse(self.checks()["app data and temp files removed"])
        r.end()
        self.assertEqual(read(self.mine), "engineer's bookmarks.db")
        self.assertEqual(read(self.mine_state), "engineer's windows.plist")

    def test_end_without_a_snapshot_is_a_failed_check(self):
        self.reset(FakeMac(self.root)).end()
        self.assertIn(False, self.checks().values())


class DownloadsTests(unittest.TestCase):
    def test_only_names_new_since_the_run_started_are_the_runs(self):
        t = time.time()
        before = {"report.pdf": t - 100, "old.zip": t - 50}
        after = {"report.pdf": t + 5, "old.zip": t - 50, "probe.txt": t + 2, "copied-in.txt": t - 500}
        self.assertEqual(vhelp.created_since(before, after, t), ["probe.txt"])

    def test_listing_reads_names_and_mtimes(self):
        d = tempfile.mkdtemp()
        write(os.path.join(d, "a"))
        os.utime(os.path.join(d, "a"), (1000, 1000))
        self.assertEqual(vhelp.listing(d), {"a": 1000})
        self.assertEqual(vhelp.listing(os.path.join(d, "missing")), {})


class VMResetRecordTests(unittest.TestCase):
    def test_each_check_line_is_recorded_and_other_lines_ignored(self):
        out = "check\tDownloads empty\tfail\ncheck\tpasteboard empty\tok\n27.2.1\tABC-123\n"
        self.assertEqual(vhelp.parse_checks(out), {"Downloads empty": False, "pasteboard empty": True})

    def test_reset_record_writes_where_and_checks(self):
        d = tempfile.mkdtemp()
        p = subprocess.run([sys.executable, "-I", os.path.join(SKILL, "scripts", "vhelp.py"), "reset-record", d, "vm-1"],
                           input="check\tapp stopped\tok\n27.2.1\tX\n", capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout)
        self.assertEqual(json.loads(read(os.path.join(d, "reset.json"))),
                         dict(where="vm-1", checks={"app stopped": True}, kept=[]))

    def test_auto_tries_the_preferred_vm_first(self):
        home = tempfile.mkdtemp()
        p = subprocess.run([os.path.join(SKILL, "scripts", "verify.sh"), "vm", "pref-test", "auto", "nohost-c.invalid"],
                           env={**os.environ, "VERIFY_MACOS_HOME": home, "VERIFY_VMS": "nohost-a.invalid nohost-b.invalid",
                                "VERIFY_RUN_DIR": os.path.join(home, "run")},
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(p.returncode, 2, p.stdout)
        self.assertIn("NO VM FREE: nohost-c.invalid nohost-a.invalid nohost-b.invalid", p.stdout)


class ProblemTests(unittest.TestCase):
    def test_a_failed_check_is_a_problem(self):
        self.assertEqual(harness.reset_problems(dict(checks={"Downloads empty": False, "app stopped": True}), True),
                         ["reset: Downloads empty: failed"])

    def test_a_missing_reset_is_a_problem_only_when_one_was_due(self):
        self.assertEqual(harness.reset_problems(None, expected=True), ["start state not reset: no reset.json"])
        self.assertEqual(harness.reset_problems(None, expected=False), [])

    def fake(self, reset, end_code=0):
        rec = harness.Record()
        rec.checks, rec.app_running = [("works", True, None, "unchanged")], True
        mac = harness.Mac("t", tempfile.mkdtemp(), rec)
        mac.reset, ran = True, []
        if reset is not None:
            with open(os.path.join(mac.evidence, "reset.json"), "w") as f:
                json.dump(reset, f)

        def sh(command, *args):
            ran.append((command, *args))
            return (end_code, "PARK BROKEN") if command == "reset" else (0, "")
        mac._sh = sh
        return mac, rec, ran

    def test_a_failed_reset_before_the_run_stops_it_before_the_build_and_still_ends(self):
        evidence, ran = tempfile.mkdtemp(), []

        def sh(mac, command, *args):
            ran.append((command, *args))
            if (command, *args) == ("ax", "grants"):
                return 0, "accessibility=true screen-recording=true"
            if (command, *args) == ("reset", "begin"):
                return 0, "check\tapp stopped\tok\ncheck\tno other Debug app open (another worktree's verify app counts)\tfail"
            return 0, ""
        mod = types.SimpleNamespace(__doc__="Claim.", run=lambda mac: self.fail("the proof ran"))
        real = harness.Mac._sh
        harness.Mac._sh = sh
        try:
            rec, _ = harness.run_one(mod, os.path.join(evidence, "p.py"), evidence, "t", "mac", False, harness.ROOT,
                                     "rerun", evidence, reset=True)
        finally:
            harness.Mac._sh = real
        self.assertIn("no other Debug app open", rec.error)
        self.assertEqual(harness.label(rec)[0], "INCONCLUSIVE")
        self.assertNotIn("build", [c[0] for c in ran])
        self.assertEqual(ran[-1], ("reset", "end"))

    def test_a_failed_reset_makes_a_pass_exit_2_and_ends_after_cleanup(self):
        mac, rec, ran = self.fake(dict(where="mac", checks={"app data and temp files removed": False}))
        harness._finish(mac, rec, mac.evidence)
        self.assertEqual(rec.problems, ["reset: app data and temp files removed: failed"])
        self.assertEqual(harness.label(rec), ("PASS", 2))
        self.assertEqual(ran[-2:], [("cleanup",), ("reset", "end")])

    def test_a_reset_command_that_fails_is_a_problem(self):
        mac, rec, _ = self.fake(dict(where="mac", checks={}), end_code=2)
        harness._finish(mac, rec, mac.evidence)
        self.assertEqual(rec.problems, ["reset after the run failed (exit 2): PARK BROKEN"])

    def test_the_manifest_carries_the_reset(self):
        mac, rec, _ = self.fake(dict(where="vm-1", checks={"Downloads empty": True}))
        m = harness._manifest(mac.evidence, rec, os.path.join(mac.evidence, "proof.py"), "rerun", {}, [], "vm-1")
        self.assertEqual(m["reset"], dict(where="vm-1", checks={"Downloads empty": True}))


class BetweenRunsTests(unittest.TestCase):
    def m(self, host="vm-1", checks=None, **kw):
        return dict(vm=dict(host=host) if host else None, reset=dict(checks=checks or {"Downloads empty": True}), **kw)

    def test_only_the_app_and_the_output_folder_differ_after_good_resets_on_one_vm(self):
        self.assertEqual(base.between_runs(self.m(), self.m()), ["app under test", "output folder"])

    def test_another_vm_is_named(self):
        self.assertIn("VM: vm-1 then vm-2", base.between_runs(self.m(), self.m("vm-2")))

    def test_a_failed_or_missing_reset_is_named(self):
        self.assertIn("start state after: Downloads empty failed",
                      base.between_runs(self.m(), self.m(checks={"Downloads empty": False})))
        self.assertIn("start state before: not reset", base.between_runs(dict(vm=dict(host="vm-1")), self.m()))

    def test_a_differing_condition_is_named(self):
        self.assertIn("condition appearance", base.between_runs(self.m(conditions=dict(appearance="dark")),
                                                                self.m(conditions=dict(appearance="light"))))


if __name__ == "__main__":
    unittest.main()
