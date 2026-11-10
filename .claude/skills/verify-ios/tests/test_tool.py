"""Tests for verify-ios's own logic that need no simulator: locks, process ownership, state, preflight, telemetry
parsing, evidence. Run: python3 -m unittest discover -s .claude/skills/verify-ios/tests -p 'test_*.py'
"""
import json, multiprocessing, os, subprocess, sys, tempfile, textwrap, time, unittest

TMP = tempfile.mkdtemp(prefix="verify-ios-test-")
os.environ["VERIFY_IOS_HOME"] = TMP   # before importing: every path below lives in this temp dir
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from verify_ios import device, env, harness, telemetry  # noqa: E402
from verify_ios.device import parse_locator  # noqa: E402


def _bump(_):
    env.update_state(lambda st: st.__setitem__("n", st.get("n", 0) + 1))


class LockTests(unittest.TestCase):
    def test_second_holder_is_refused_and_lock_is_never_broken(self):
        first = env.DeviceLock("iphone").acquire("first")
        try:
            with self.assertRaises(env.Busy) as cm:
                env.DeviceLock("iphone").acquire("second")
            self.assertIn("first", str(cm.exception))
            self.assertIn("never delete", str(cm.exception))
            self.assertTrue(os.path.exists(first.path))
        finally:
            first.release()
        env.DeviceLock("iphone").acquire("third").release()   # free again once released

    def test_devices_lock_independently(self):
        a = env.DeviceLock("iphone").acquire("a")
        try:
            env.DeviceLock("ipad").acquire("b").release()
        finally:
            a.release()

    def test_lock_held_by_another_process(self):
        holder = subprocess.Popen([sys.executable, "-c", textwrap.dedent(f"""
            import fcntl, sys, time
            f = open({env.DeviceLock('ipad').path!r}, 'a+'); fcntl.flock(f, fcntl.LOCK_EX); print('held', flush=True); time.sleep(30)""")],
            stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), "held")
            with self.assertRaises(env.Busy):
                env.DeviceLock("ipad").acquire("cli command")
        finally:
            holder.kill()
            holder.wait()


class StateTests(unittest.TestCase):
    def test_concurrent_updates_are_not_lost(self):
        env.update_state(lambda st: st.__setitem__("n", 0))
        with multiprocessing.get_context("fork").Pool(8) as pool:
            pool.map(_bump, range(40))
        self.assertEqual(env.load_state()["n"], 40)

    def test_token_is_stable_and_secret_sized(self):
        t = env.token()
        self.assertEqual(t, env.token())
        self.assertGreaterEqual(len(t), 32)


class ProcessOwnershipTests(unittest.TestCase):
    def test_identity_matches_live_process(self):
        p = subprocess.Popen(["sleep", "30"])
        try:
            ident = env.process_identity(p.pid)
            self.assertTrue(env.still_ours(ident))
        finally:
            p.kill()
            p.wait()
        self.assertFalse(env.still_ours(ident), "a dead pid is never ours")

    def test_reused_pid_is_not_ours(self):
        p = subprocess.Popen(["sleep", "30"])
        try:
            ident = env.process_identity(p.pid)
            self.assertFalse(env.still_ours({**ident, "lstart": "Mon Jan  1 00:00:00 2001"}), "different start time")
            self.assertFalse(env.still_ours({**ident, "command": "something else"}), "different command")
        finally:
            p.kill()
            p.wait()

    def test_runner_stop_leaves_processes_that_are_no_longer_ours(self):
        from verify_ios.driver import XCUITestRunner
        bystander = subprocess.Popen(["sleep", "30"])
        try:
            # We recorded a DTServiceHub with this pid long ago; the pid now belongs to an unrelated process.
            fake = dict(pid=bystander.pid, lstart="Mon Jan  1 00:00:00 2001", command="/Xcode/DTServiceHub")
            res = XCUITestRunner("-", 1, "t").stop([fake])
            self.assertIsNone(bystander.poll(), "an unrelated process with a recorded pid survives cleanup")
            self.assertEqual(res.get("notOursAnymore"), [bystander.pid])
        finally:
            bystander.kill()
            bystander.wait()


class SimulatorLifecycleTests(unittest.TestCase):
    """Simulators are found by name and deleted by cleanup; nothing else on the Mac is touched."""

    def setUp(self):
        self.calls, self.sims = [], []
        self.saved = device.run
        device.run = self.fake_run

    def tearDown(self):
        device.run = self.saved

    def sim(self, name, udid, available=True):
        self.sims.append(dict(name=name, udid=udid, state="Booted" if available else "Shutdown", isAvailable=available))

    def fake_run(self, cmd, **_):
        self.calls.append(cmd)
        out = ""
        if cmd[2:4] == ["list", "devices"]:
            out = json.dumps({"devices": {env.RUNTIME: self.sims}})
        elif cmd[2] == "create":
            self.sim(cmd[3], "NEW-UDID")
            out = "NEW-UDID"
        elif cmd[2] == "delete":
            self.sims = [s for s in self.sims if s["udid"] != cmd[3]]
        return subprocess.CompletedProcess(cmd, 0, out, "")

    def names(self):
        return sorted(s["name"] for s in self.sims)

    def test_cleanup_deletes_only_this_worktrees_simulator(self):
        d = device.Device("iphone")
        self.sim("verify-ios-other-worktree-abc123-iphone", "THEIRS")
        self.sim("iPhone 17 Pro", "PERSONAL")
        self.sim(d.name, "OURS")
        d.cleanup(delete_sim=True)
        self.assertEqual(self.names(), ["iPhone 17 Pro", "verify-ios-other-worktree-abc123-iphone"])
        self.assertNotIn("THEIRS", str(self.calls))
        self.assertNotIn("PERSONAL", str(self.calls))

    def test_an_unavailable_simulator_is_replaced_and_then_deleted(self):
        d = device.Device("iphone")
        self.sim(d.name, "DEAD", available=False)
        self.assertTrue(d._ensure(), "an unavailable simulator cannot run a proof, so a usable one is created")
        self.assertEqual(d.udid, "NEW-UDID")
        d.cleanup(delete_sim=True)
        self.assertEqual(self.sims, [], "cleanup leaves no simulator of this worktree behind, usable or not")

    def test_a_deleted_simulator_is_recreated_for_the_next_build(self):
        d = device.Device("iphone")
        with self.assertRaises(env.Failed) as cm:
            d.udid
        self.assertIn("launch", str(cm.exception))
        self.assertTrue(d._ensure(), "a missing simulator is created")
        self.assertEqual(d.udid, "NEW-UDID")
        self.assertFalse(d._ensure(), "an existing simulator is reused, not duplicated")
        self.assertEqual(sum(c[2] == "create" for c in self.calls), 1)


class BuildLocationTests(unittest.TestCase):
    def test_builds_live_in_the_worktree_and_git_ignores_them(self):
        for path in (env.APP_DD, env.RUNNER_DD):
            self.assertTrue(path.startswith(env.ROOT + os.sep), f"{path} is outside the worktree: it would outlive it")
            p = subprocess.run(["git", "-C", env.ROOT, "check-ignore", "-q", path])
            self.assertEqual(p.returncode, 0, f"git does not ignore {path}: builds would show up as changes")


class LocatorTests(unittest.TestCase):
    def test_native_and_web(self):
        self.assertEqual(parse_locator('role=button label="New Tab" nth=1')["sel"], {"role": "button", "label": "New Tab", "nth": "1"})
        self.assertEqual(parse_locator("name=x")["sel"], {"label": "x"})
        self.assertEqual(parse_locator("web:css=#token"), {"web": "css", "value": "#token"})


class PreflightTests(unittest.TestCase):
    def write(self, body):
        f = tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, dir=TMP)
        f.write(textwrap.dedent(body))
        f.close()
        return f.name

    def test_good_proof_passes(self):
        mod, problems = harness.load(self.write('''
            """Proves something."""
            DEVICES = ["iphone"]
            def run(ios):
                pass
            '''))
        self.assertEqual(problems, [])

    def test_bad_proofs_fail_before_any_device(self):
        cases = {
            "syntax": ('"""x"""\ndef run(ios)\n    pass\n', "does not compile"),
            "import": ('"""x"""\nimport no_such_module_xyz\ndef run(ios): pass\n', "import failed"),
            "no run": ('"""x"""\n', "run(ios)"),
            "devices": ('"""x"""\nDEVICES = ["mac"]\ndef run(ios): pass\n', "DEVICES"),
            "docstring": ('def run(ios): pass\n', "docstring"),
            "unknown flag": ('"""x"""\nFLAGS = {"newTabPageRedesgin": True}\ndef run(ios): pass\n', "not feature flags"),
            "flag the app won't override": ('"""x"""\nFLAGS = {"duckPlayer": True}\ndef run(ios): pass\n', "local overrides"),
        }
        for name, (body, expected) in cases.items():
            with self.subTest(name):
                _, problems = harness.load(self.write(body))
                self.assertTrue(any(expected in p for p in problems), problems)

    def test_overridable_flag_is_accepted(self):
        _, problems = harness.load(self.write('"""x"""\nFLAGS = {"newTabPageRedesign": False}\ndef run(ios): pass\n'))
        self.assertEqual(problems, [])

    def test_flags_declared_without_local_overriding_are_found(self):
        names, fixed = env.feature_flags()
        self.assertTrue({"duckPlayer", "sync", "autofillCredentialInjecting"} <= fixed, fixed)
        self.assertNotIn("newTabPageRedesign", fixed)
        self.assertIn("newTabPageRedesign", names)
        self.assertLessEqual(fixed, names)

    def test_run_proofs_refuses_all_when_one_is_broken(self):
        good = self.write('"""ok"""\ndef run(ios): pass\n')
        bad = self.write('def run(ios): pass\n')
        before = set(os.listdir(env.EVIDENCE)) if os.path.isdir(env.EVIDENCE) else set()
        code, out = harness.run_proofs([good, bad])
        self.assertEqual(code, 2)
        after = set(os.listdir(env.EVIDENCE)) if os.path.isdir(env.EVIDENCE) else set()
        self.assertEqual(after, before, "nothing ran, so no evidence folder was made")

    def test_exit_code_priority(self):
        self.assertEqual(harness.exit_code(["pass", "pass"]), 0)
        self.assertEqual(harness.exit_code(["pass", "busy"]), env.EXIT_BUSY)
        self.assertEqual(harness.exit_code(["busy", "fail"]), 1)
        self.assertEqual(harness.exit_code(["fail", "error"]), 2)
        self.assertEqual(harness.exit_code(["error", "cancelled"]), 130)


class TelemetryTests(unittest.TestCase):
    def test_parse_fired_skipped_and_wide(self):
        fired = telemetry.parse_pixel('👾[Standard-Fired(dryRun)] mf_bp_ios_phone ["appVersion": "7.244.0", "browsing_mode": "normal"]')
        self.assertEqual(fired, dict(name="mf_bp_ios_phone", status="Fired", frequency="Standard",
                                     params={"appVersion": "7.244.0", "browsing_mode": "normal"}))
        skipped = telemetry.parse_pixel('👾[Daily and Count-Skipped] m_x_daily ["appVersion": "1"]')
        self.assertEqual((skipped["status"], skipped["frequency"]), ("Skipped", "Daily and Count"))
        wide = telemetry.parse_pixel("👾[Daily-Fired(dryRun)] m_ios_wide_data_clearing_daily")
        self.assertEqual((wide["name"], wide["params"]), ("m_ios_wide_data_clearing_daily", {}))
        self.assertIsNone(telemetry.parse_pixel("👾 PixelKit initialised: dryRun: true"))

    def test_skipped_does_not_count_as_fired(self):
        path = os.path.join(TMP, "pixels.ndjson")
        with open(path, "w") as f:
            # PixelKit logs a Skipped pixel without the _ios_phone suffix it has when it fires.
            for msg in ('👾[Daily-Skipped] m_a_daily ["k": "v"]', "not json", '👾[Standard-Fired(dryRun)] m_b_ios_phone ["k": "v"]'):
                f.write((json.dumps({"eventMessage": msg, "timestamp": "t"}) if msg != "not json" else msg) + "\n")
        px = telemetry.Pixels("-", path)
        px.proc = subprocess.Popen(["sleep", "30"])   # a live stream
        px.since = 0                                    # marked before these lines
        try:
            self.assertEqual([p["name"] for p in px.all()], ["m_a_daily", "m_b_ios_phone"])
            self.assertEqual(px.fired("m_b_ios_phone", timeout=0)["params"], {"k": "v"})
            with self.assertRaises(env.Failed) as cm:
                px.fired("m_a_daily_ios_phone", timeout=0)
            self.assertEqual(len(cm.exception.extra["skipped"]), 1, "the unsuffixed Skipped line is shown as evidence")
            with self.assertRaises(env.Failed):
                px.not_fired("m_b_ios_phone", within=0.3)
            px.since = 2   # a mark after both lines: neither counts
            px.not_fired("m_b_ios_phone", within=0.3)
        finally:
            px.stop()

    def test_stop_ends_the_log_stream_child(self):
        px = telemetry.Pixels("-", os.path.join(TMP, "unused.ndjson"))
        # Stands in for `xcrun simctl spawn … log stream`: a child that replaced its own command after starting.
        px.proc = subprocess.Popen(["sh", "-c", "exec sleep 30"], start_new_session=True)
        pid = px.proc.pid
        px.stop()
        self.assertIsNone(env.process_identity(pid), "the stream process must be gone after stop()")

    def test_wide_events_only_from_this_run(self):
        container = os.path.join(TMP, "container")
        os.makedirs(os.path.join(container, "Library/Caches"), exist_ok=True)
        log = os.path.join(container, telemetry.WideEvents.FILE)
        with open(log, "w") as f:
            f.write(json.dumps({"feature": {"name": "old"}}) + "\n")
        we = telemetry.WideEvents(lambda: container)
        self.assertEqual(we.all(), [])
        with open(log, "a") as f:
            f.write(json.dumps({"feature": {"name": "new", "status": "SUCCESS"}}) + "\n")
        self.assertEqual([e["feature"]["name"] for e in we.all()], ["new"])
        with open(log, "w") as f:   # the app clears the file on its first event after a relaunch
            f.write(json.dumps({"feature": {"name": "after-relaunch"}}) + "\n")
        self.assertEqual([e["feature"]["name"] for e in we.all()], ["after-relaunch"])
        other = os.path.join(TMP, "container2")   # a reinstall moves to a new container: all of it is new
        os.makedirs(os.path.join(other, "Library/Caches"), exist_ok=True)
        with open(os.path.join(other, telemetry.WideEvents.FILE), "w") as f:
            f.write(json.dumps({"feature": {"name": "old"}}) + "\n")
        we.container = lambda: other
        self.assertEqual([e["feature"]["name"] for e in we.all()], ["old"])


class EvidenceTests(unittest.TestCase):
    def test_attempt_dir_reuses_only_an_untouched_folder(self):
        path = harness.new_proof("demo")
        attempt, used = harness.attempt_dir(path)
        self.assertEqual((attempt, used), (os.path.dirname(os.path.realpath(path)), os.path.realpath(path)))
        with open(f"{attempt}/traceback.txt", "w") as f:   # a crashed attempt: no manifest, but not untouched either
            f.write("boom")
        again, copy = harness.attempt_dir(path)
        self.assertNotEqual(again, attempt, "a used attempt folder is never reused")
        self.assertTrue(os.path.exists(copy))
        self.assertTrue(os.path.exists(f"{attempt}/traceback.txt"))

    def test_same_second_attempts_get_distinct_folders(self):
        src = harness.new_proof("same")
        folders = {harness.attempt_dir(src)[0] for _ in range(1)} | {harness._new_attempt("same") for _ in range(5)}
        self.assertEqual(len(folders), 6)

    def test_check_leaves_a_new_proof_folder_reusable(self):
        path = harness.new_proof("checked")
        self.assertEqual(harness.load(path)[1], [])
        self.assertEqual(os.listdir(os.path.dirname(path)), ["proof.py"], "checking must not write __pycache__ there")
        self.assertEqual(harness.attempt_dir(path)[0], os.path.dirname(os.path.realpath(path)))

    def test_template_passes_preflight(self):
        self.assertEqual(harness.load(harness.new_proof("template"))[1], [])

    def test_async_and_generator_proofs_are_rejected(self):
        for body in ('"""x"""\nasync def run(ios):\n    pass\n', '"""x"""\ndef run(ios):\n    yield 1\n'):
            path = os.path.join(TMP, f"p{abs(hash(body))}.py")
            with open(path, "w") as f:
                f.write(body)
            self.assertTrue(any("plain function" in p for p in harness.load(path)[1]))


# ---------------------------------------------------------------- the harness's pass/fail logic, with a fake device
class FakeWeb:
    def page_url(self):
        return None

    def url(self):
        raise env.Failed("no web page")


class FakeDevice:
    """Stands in for Device: records calls, can be told to fail at launch or report the app gone."""

    def __init__(self, fail_launch=False, foreground=True, left=None, fail_screenshot=False):
        self.udid, self.web = "-", FakeWeb()
        self.fail_launch, self.fg, self.left, self.fail_screenshot = fail_launch, foreground, left, fail_screenshot
        self.cleaned = 0

    def launch(self, flags=None):
        if self.fail_launch:
            raise env.Failed("running app is not this worktree's build")
        return dict(build=dict(runningSha="a" * 64), flags=flags)

    def reset(self, flags=None):
        if getattr(self, "fail_reset", False):
            raise env.Failed("AutomationServer never reported /contentBlockerReady true")
        return self.launch(flags)

    def foreground(self):
        return self.fg

    def screenshot(self, path):
        if self.fail_screenshot:
            raise OSError("disk full")
        open(path, "w").close()

    def snapshot(self):
        return dict(tree="", focused=None)

    def data_container(self):
        return TMP

    def capture_conditions(self):
        fixed = getattr(self, "status_fixed", False) and not getattr(self, "status_ignored", False)
        return dict(appearance="light", textSize="large", orientation="portrait", statusBar="fixed (9:41)" if fixed else "live")

    def ui(self, option, value=None):
        if value is None:
            return {"appearance": "light", "content_size": "large"}[option]
        if getattr(self, "fail_ui", False):
            raise env.Failed(f"simctl ui {option} {value} failed")
        self.ui_writes = getattr(self, "ui_writes", []) + [(option, value)]
        return value

    def status_bar(self, fixed):
        self.status_fixed = fixed

    def cleanup(self, shutdown=False, delete_sim=False):
        self.cleaned += 1
        self.deleted_sim = delete_sim
        return dict(left=self.left) if self.left else {}


class FakePixels:
    def __init__(self, *_):
        self.stopped = False

    def start(self):
        return self

    def stop(self):
        self.stopped = True

    def mark(self):
        pass

    def all(self):
        return []


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeDevice()
        self.saved = (harness.Device, harness.fixture, harness.Pixels, harness.WideEvents, harness.fixture_release)
        harness.Device = lambda device: self.fake
        harness.Device.check_build_current = staticmethod(lambda: {})
        harness.fixture = lambda stop=False, user=None: dict(url="http://127.0.0.1:1/index.html?token=")
        harness.fixture_release = lambda user: {}
        harness.Pixels = FakePixels
        harness.WideEvents = lambda container: telemetry.WideEvents(container)

    def tearDown(self):
        harness.Device, harness.fixture, harness.Pixels, harness.WideEvents, harness.fixture_release = self.saved

    def run_proof(self, run, keep=False, **fake):
        self.fake.__dict__.update(fake)
        mod = type("Proof", (), {"run": staticmethod(run)})
        ev = tempfile.mkdtemp(dir=TMP)
        return harness._run_device(mod, "iphone", ev, keep=keep, flags={}, device_obj=self.fake)

    def test_passes_with_a_passing_check(self):
        r = self.run_proof(lambda ios: ios.check("something", True))
        self.assertEqual(r["status"], "pass", r)
        self.assertEqual(self.fake.cleaned, 1)

    def test_simulator_is_deleted_whatever_the_outcome(self):
        outcomes = {"pass": lambda ios: ios.check("ok", True), "fail": lambda ios: ios.check("broken", False)}
        for status, run in outcomes.items():
            self.fake = FakeDevice()
            r = self.run_proof(run)
            self.assertEqual(r["status"], status, r)
            self.assertTrue(self.fake.deleted_sim, f"the simulator outlived a proof that ended in {status}")
        self.fake = FakeDevice()
        r = self.run_proof(lambda ios: ios.check("never reached", True), fail_launch=True)
        self.assertEqual(r["status"], "error", r)
        self.assertTrue(self.fake.deleted_sim, "the simulator outlived a proof whose setup failed")

    def test_keep_leaves_the_simulator_for_debugging(self):
        r = self.run_proof(lambda ios: ios.check("ok", True), keep=True)
        self.assertEqual(r["status"], "pass", r)
        self.assertEqual(self.fake.cleaned, 0)

    def test_swallowed_failed_check_still_fails(self):
        def run(ios):
            try:
                ios.check("the important thing", False)
            except env.Failed:
                pass
            ios.check("something else", True)
        r = self.run_proof(run)
        self.assertEqual(r["status"], "fail", r)
        self.assertIn("the important thing", r["reason"])

    def test_proof_with_no_checks_fails(self):
        r = self.run_proof(lambda ios: None)
        self.assertEqual(r["status"], "fail")
        self.assertIn("no checks", r["reason"])

    def test_app_gone_at_the_end_fails(self):
        r = self.run_proof(lambda ios: ios.check("something", True), fg=False)
        self.assertEqual(r["status"], "fail")
        self.assertIn("foreground", r["reason"])

    def test_setup_failure_is_an_error_not_a_product_failure(self):
        r = self.run_proof(lambda ios: ios.check("never reached", True), fail_launch=True)
        self.assertEqual(r["status"], "error")
        self.assertTrue(r["reason"].startswith("setup:"), r["reason"])
        self.assertEqual(self.fake.cleaned, 1, "cleanup still runs")

    def test_undo_steps_run_in_reverse_and_a_failing_one_is_reported(self):
        ran = []

        def run(ios):
            ios.on_cleanup("first", lambda: ran.append("first"))
            ios.on_cleanup("broken", lambda: (_ for _ in ()).throw(RuntimeError("simctl gone")))
            ios.on_cleanup("last", lambda: ran.append("last"))
            ios.check("something", True)
        r = self.run_proof(run)
        self.assertEqual(ran, ["last", "first"], "reverse order, and a failure doesn't stop the rest")
        self.assertTrue(any("undo 'broken' failed" in p for p in r["problems"]), r["problems"])
        self.assertEqual(harness.exit_code([r["status"]], bool(r["problems"])), 2)

    def test_undo_steps_run_after_a_failure_and_a_cancel(self):
        for raise_it in (lambda: (_ for _ in ()).throw(env.Failed("product broke")),
                         lambda: (_ for _ in ()).throw(harness._Stop("SIGINT"))):
            ran = []

            def run(ios, raise_it=raise_it, ran=ran):
                ios.on_cleanup("undo", lambda: ran.append("undo"))
                raise_it()
            r = self.run_proof(run)
            self.assertIn(r["status"], ("fail", "cancelled"))
            self.assertEqual(ran, ["undo"])

    def test_failed_condition_is_inconclusive_and_its_undo_still_runs(self):
        def run(ios):
            ios.appearance("dark")
        r = self.run_proof(run, fail_ui=True)
        self.assertEqual(r["status"], "error", r)
        self.assertTrue(r["reason"].startswith("setup:"), r["reason"])
        self.fake.fail_ui = False

    def test_undo_registered_before_the_change(self):
        def run(ios):
            ios.appearance("dark")
            ios.check("something", True)
        r = self.run_proof(run)
        self.assertEqual(r["status"], "pass", r)
        self.assertEqual(self.fake.ui_writes[-2:], [("appearance", "dark"), ("appearance", "light")], "changed, then restored")

    def test_upside_down_rotation_is_refused(self):
        r = self.run_proof(lambda ios: ios.rotate("portraitUpsideDown"))
        self.assertEqual(r["status"], "fail")
        self.assertIn("orientation must be one of", r["reason"])

    def test_status_bar_that_did_not_take_effect_is_inconclusive(self):
        r = self.run_proof(lambda ios: (ios.fixed_status_bar(), ios.check("never reached", True)), status_ignored=True)
        self.assertEqual(r["status"], "error", r)
        self.assertIn("did not take effect", r["reason"])
        self.assertFalse(self.fake.status_fixed, "the override was cleared again")

    def test_no_alert_check_fails_when_an_alert_is_on_screen_but_unanswerable(self):
        def alert(action, button, timeout):
            raise env.Failed("no button", runner=dict(code="NOT_FOUND", alert="Allow location?", buttons=[]))
        self.fake.alert = alert
        r = self.run_proof(lambda ios: ios.expect_no_alert(within=0))
        self.assertEqual(r["status"], "fail", r)

    def test_no_alert_check_passes_when_there_is_none(self):
        def alert(action, button, timeout):
            raise env.Failed("no alert", runner=dict(code="NOT_FOUND", message="no alert"))
        self.fake.alert = alert
        r = self.run_proof(lambda ios: ios.expect_no_alert(within=0))
        self.assertEqual(r["status"], "pass", r)

    def test_reset_failing_inside_the_proof_is_an_error(self):
        r = self.run_proof(lambda ios: (ios.reset(), ios.check("never reached", True)), fail_reset=True)
        self.assertEqual(r["status"], "error", r)
        self.assertTrue(r["reason"].startswith("setup:"), r["reason"])

    def test_cancel_inside_a_broad_except_still_cancels_and_cleans_up(self):
        def run(ios):
            try:
                raise harness._Stop("SIGINT")
            except Exception:   # a proof's broad except must not swallow Ctrl-C
                pass
        r = self.run_proof(run)
        self.assertEqual(r["status"], "cancelled")
        self.assertEqual(self.fake.cleaned, 1)
        env.DeviceLock("iphone").acquire("lock was released").release()

    def test_capture_failure_and_cleanup_survivors_are_reported(self):
        r = self.run_proof(lambda ios: ios.check("something", True), fail_screenshot=True, left=[123])
        self.assertEqual(r["status"], "pass")
        self.assertTrue(any("final screenshot" in p for p in r["problems"]), r["problems"])
        self.assertTrue(any("left processes" in p for p in r["problems"]), r["problems"])
        self.assertEqual(harness.exit_code([r["status"]], bool(r["problems"])), 2)
        self.assertEqual(self.fake.cleaned, 1)

    def test_telemetry_assertions_need_a_mark(self):
        def run(ios):
            ios.pixels = telemetry.Pixels("-", os.path.join(TMP, "nopixels.ndjson"))
            ios.pixels.proc = subprocess.Popen(["sleep", "30"])
            try:
                ios.pixels.fired("m_x", timeout=0)
            finally:
                ios.pixels.stop()
        r = self.run_proof(run)
        self.assertEqual(r["status"], "fail")
        self.assertIn("ios.mark()", r["reason"])

    def test_dead_pixel_stream_never_passes_not_fired(self):
        px = telemetry.Pixels("-", os.path.join(TMP, "dead.ndjson"))
        px.since = 0
        with self.assertRaises(env.Failed):
            px.not_fired("m_anything", within=0.2)

    def test_url_on_a_new_tab_page_fails_instead_of_returning_empty(self):
        def run(ios):
            ios.check("no web page", ios.page_url() is None)
            ios.url()
        r = self.run_proof(run)
        self.assertEqual(r["status"], "fail")


class DecisionLogTests(unittest.TestCase):
    def test_evidence_goes_next_to_the_decision_log(self):
        audit = tempfile.mkdtemp(dir=TMP)
        log = os.path.join(audit, "decisions.tsv")
        open(log, "w").close()
        path = harness.new_proof("logged", harness.evidence_root(log))
        self.assertTrue(path.startswith(os.path.realpath(os.path.join(audit, "proofs")) + os.sep), path)
        with self.assertRaises(env.Failed):
            harness.evidence_root(os.path.join(audit, "missing.tsv"))

    def test_decision_log_inside_the_checkout_is_refused(self):
        inside = os.path.join(env.ROOT, "verify-ios-test-decision-log")
        os.makedirs(inside, exist_ok=True)
        log = os.path.join(inside, "decisions.tsv")
        try:
            open(log, "w").close()
            with self.assertRaises(env.Failed):
                harness.evidence_root(log)
        finally:
            os.remove(log)
            os.rmdir(inside)

    def test_decision_log_under_dot_claude_is_refused_too(self):
        inside = tempfile.mkdtemp(dir=os.path.join(env.ROOT, ".claude"))
        log = os.path.join(inside, "decisions.tsv")
        try:
            open(log, "w").close()
            with self.assertRaises(env.Failed):
                harness.evidence_root(log)
        finally:
            os.remove(log)
            os.rmdir(inside)


class BuildCurrentTests(unittest.TestCase):
    """`prove` and `selftest` must treat a runner built from older runner source as stale, like the app."""

    def setUp(self):
        from verify_ios import device
        self.device, self.saved = device, (device.APP, device.RUNNER_DD, env.source_stamp)
        app, self.dd = tempfile.mkdtemp(dir=TMP), tempfile.mkdtemp(dir=TMP)
        device.APP, device.RUNNER_DD = app, self.dd
        env.source_stamp = lambda: {"stamp": "now"}
        open(os.path.join(app, "DuckDuckGo"), "w").write("binary")
        os.makedirs(os.path.join(self.dd, "Build", "Products"))
        open(os.path.join(self.dd, "Build", "Products", "VRunner.xctestrun"), "w").close()
        env.update_state(lambda st: st.update(appBuild=dict(source={"stamp": "now"}, sha256=env.sha256(f"{app}/DuckDuckGo"))))

    def tearDown(self):
        self.device.APP, self.device.RUNNER_DD, env.source_stamp = self.saved
        env.update_state(lambda st: [st.pop(k, None) for k in ("appBuild", "runnerBuild")])

    def test_runner_built_from_old_source_is_stale(self):
        env.update_state(lambda st: st.__setitem__("runnerBuild", dict(source="older")))
        with self.assertRaises(env.Failed) as e:
            self.device.Device.check_build_current()
        self.assertEqual(e.exception.extra["stale"], ["runner"])
        self.assertIn("build --runner-only", str(e.exception))

    def test_current_app_and_runner_pass(self):
        env.update_state(lambda st: st.__setitem__("runnerBuild", dict(source=env.runner_stamp())))
        self.assertEqual(self.device.Device.check_build_current()["source"], {"stamp": "now"})

    def test_no_records_means_build_both(self):
        env.update_state(lambda st: [st.pop(k, None) for k in ("appBuild", "runnerBuild")])
        with self.assertRaises(env.Failed) as e:
            self.device.Device.check_build_current()
        self.assertIn("Run `build`", str(e.exception))


class SelftestTests(unittest.TestCase):
    def test_leftover_check_ignores_other_devices(self):
        from verify_ios import selftest
        me = env.process_identity(os.getpid())
        env.update_state(lambda st: st.setdefault("devices", {}).__setitem__("ipad", {"started": [{"processes": [me]}]}))
        try:
            self.assertEqual(selftest._running(["iphone"]), set())
            self.assertEqual(selftest._running(["ipad"]), {os.getpid()})
        finally:
            env.update_state(lambda st: st.get("devices", {}).pop("ipad", None))


class CliTests(unittest.TestCase):
    def test_check_rejects_a_bad_proof_with_exit_2(self):
        bad = os.path.join(TMP, "bad_proof.py")
        with open(bad, "w") as f:
            f.write("def run(ios): pass\n")   # no docstring
        cli = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "verify-ios")
        p = subprocess.run([cli, "--json", "check", bad], capture_output=True, text=True, env={**os.environ, "VERIFY_IOS_HOME": TMP})
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)


if __name__ == "__main__":
    unittest.main()
