"""Tests for verify-ios's own logic that need no simulator: locks, process ownership, state, preflight, telemetry
parsing, evidence. Run: python3 -m unittest discover -s .agents/skills/verify-ios/tests -p 'test_*.py'
"""
import json, multiprocessing, os, re, shlex, shutil, signal, struct, subprocess, sys, tempfile, textwrap, time, unittest, zlib
from unittest import mock

TMP = tempfile.mkdtemp(prefix="verify-ios-test-")
os.environ["VERIFY_IOS_HOME"] = TMP   # before importing: every path below lives in this temp dir
os.environ["VERIFY_IOS_REAP"] = "0"   # CLI runs here must never reap the Mac's real simulators; ReaperTests fake simctl
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))

from verify_ios import compare, device, env, gallery, harness, page, reap, steps, telemetry, video, web  # noqa: E402
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


    def test_runner_starts_outside_the_terminal_process_group(self):
        # A terminal Ctrl-C signals the whole foreground group; the runner must survive it so a cancelled proof can
        # still capture the final UI tree.
        from unittest import mock
        from verify_ios import driver
        with tempfile.TemporaryDirectory() as dd:
            os.makedirs(f"{dd}/Build/Products")
            open(f"{dd}/Build/Products/VRunner-iOS_x.xctestrun", "w").close()
            out = subprocess.CompletedProcess([], 0, stdout='{"ok":true,"xcodebuildPid":0,"hubPids":[]}\n', stderr="")
            with mock.patch.object(driver, "RUNNER_DD", dd), mock.patch.object(driver, "port_listening", return_value=False), \
                    mock.patch.object(driver.XCUITestRunner, "alive", return_value=False), \
                    mock.patch.object(driver.subprocess, "run", return_value=out) as run:
                driver.XCUITestRunner("-", 1, "t").start()
        start = next(c for c in run.call_args_list if c.args[0][0].endswith("vrunner_start.sh"))
        self.assertTrue(start.kwargs.get("start_new_session"))


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


class AppLogTests(unittest.TestCase):
    """`app_logs` reads the app's log for a window and keeps the end of a long one."""

    def setUp(self):
        self.saved, self.calls, self.out = device.run, [], ""
        device.run = lambda cmd, **_: self.calls.append(cmd) or subprocess.CompletedProcess(cmd, 0, self.out, "")
        self.d = device.Device("iphone")
        self.d._udid = "UDID"
        self.path = os.path.join(TMP, "app.log")

    def tearDown(self):
        device.run = self.saved

    def test_reads_from_the_start_of_the_run(self):
        start = time.mktime((2026, 11, 15, 10, 4, 5, 0, 0, -1))
        self.d.app_logs(self.path, start=start)
        self.assertIn(["--start", "2026-11-15 10:04:05"], [self.calls[-1][i:i + 2] for i in range(len(self.calls[-1]))])
        self.assertIn(device.Device.APP_LOG_PREDICATE, self.calls[-1])

    def test_keeps_the_end_of_a_long_log_and_says_so(self):
        self.out = "early\n" + "x" * device.Device.APP_LOG_LIMIT + "LAST LINE\n"
        with open(self.d.app_logs(self.path, start=time.time())) as f:
            text = f.read()
        self.assertTrue(text.startswith("[verify-ios: kept the last"), text[:80])
        self.assertTrue(text.endswith("LAST LINE\n"))
        self.assertNotIn("early", text)

    def test_a_failed_read_raises_instead_of_writing_an_empty_log(self):
        device.run = lambda cmd, **_: subprocess.CompletedProcess(cmd, 1, "", "no such device")
        with self.assertRaises(env.Failed):
            self.d.app_logs(self.path + ".missing", start=time.time())
        self.assertFalse(os.path.exists(self.path + ".missing"))


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


class LaunchProfileTests(unittest.TestCase):
    def test_profile_pins_the_flags_without_internal_user(self):
        profile = json.loads(device.launch_profile({"b": False, "a": True}))
        self.assertEqual(profile, {"featureFlags": {"a": True, "b": False}})

    def test_no_flags_means_no_profile(self):   # an empty object is an unknown key to the app
        self.assertIsNone(device.launch_profile({}))

    def test_newest_result_line_is_read_from_the_log(self):
        log = ("2026-11-25 14:49:20.1 Df DuckDuckGo[1:2] [com.duckduckgo.mobile.ios:LaunchProfile] LAUNCH_PROFILE_APPLIED keys=a\n"
               "2026-11-25 14:49:26.6 E  DuckDuckGo[3:4] [com.duckduckgo.mobile.ios:LaunchProfile] "
               'LAUNCH_PROFILE_FAILED Unknown key "featureFlags.x".\n')
        self.assertEqual(device.launch_profile_line(log), 'LAUNCH_PROFILE_FAILED Unknown key "featureFlags.x".')
        self.assertIsNone(device.launch_profile_line("Timestamp Ty Process[PID:TID]\n"))


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
            "language without a locale": ('"""x"""\nLANGUAGE = {"language": "fr"}\ndef run(ios): pass\n', "LANGUAGE"),
            "language as a string": ('"""x"""\nLANGUAGE = "fr"\ndef run(ios): pass\n', "LANGUAGE"),
        }
        for name, (body, expected) in cases.items():
            with self.subTest(name):
                _, problems = harness.load(self.write(body))
                self.assertTrue(any(expected in p for p in problems), problems)

    def test_language_override_is_accepted(self):
        _, problems = harness.load(self.write('"""x"""\nLANGUAGE = {"language": "fr", "locale": "fr_FR"}\ndef run(ios): pass\n'))
        self.assertEqual(problems, [])

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
        self.language = None

    def launch(self, flags=None, language=None):
        if self.fail_launch:
            raise env.Failed("running app is not this worktree's build")
        self.language = dict(language or env.LANGUAGE)
        return dict(build=dict(runningSha="a" * 64), flags=flags, language=self.language)

    def reset(self, flags=None, language=None):
        if getattr(self, "fail_reset", False):
            raise env.Failed("AutomationServer never reported /contentBlockerReady true")
        return self.launch(flags, language)

    def foreground(self):
        return self.fg

    def screenshot(self, path):
        if self.fail_screenshot:
            raise OSError("disk full")
        open(path, "w").close()

    def snapshot(self):
        return dict(tree="", focused=None)

    def wait(self, locator, state="visible", timeout=5):
        if locator in getattr(self, "absent", ()):
            raise env.Failed(f"{locator} not {state} within {timeout}s", runner={"code": "TIMEOUT"})
        return dict(ok=True)

    def data_container(self):
        return TMP

    def capture_conditions(self):
        fixed = getattr(self, "status_fixed", False) and not getattr(self, "status_ignored", False)
        return dict(appearance="light", textSize="large", orientation="portrait", statusBar="fixed (9:41)" if fixed else "live",
                    **(self.language or {}))

    def app_logs(self, path, since="5m", start=None):
        if getattr(self, "fail_app_logs", False):
            raise env.Failed("log show failed")
        self.app_log_start = start
        with open(path, "w") as f:
            f.write("DuckDuckGo: a line\n")
        return path

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

    def fired(self, name, occurrence=0, timeout=10):
        raise env.Missed(f"pixel {name} did not fire")

    def all(self):
        return []


class FakeVideo:
    """Stands in for Video: writes the file on stop, or fails to start or stop when told to."""
    FILE = harness.Video.FILE
    fail_start, stop_problem, made = False, None, []

    def __init__(self, udid, path):
        self.path, self.ok, self.stopped = path, False, False
        FakeVideo.made.append(self)

    def start(self):
        if FakeVideo.fail_start:
            raise RuntimeError("recordVideo exited 1: no display")
        return self

    def stop(self):
        self.stopped = True
        if FakeVideo.stop_problem:
            return [FakeVideo.stop_problem]
        open(self.path, "w").close()
        self.ok = True
        return []


class FakeRecorder:
    """Stands in for the `simctl io recordVideo` process."""
    def __init__(self, exit_on_sigint=0, writes=b"movie"):
        self.returncode, self.signals, self.exit_on_sigint, self.writes = None, [], exit_on_sigint, writes

    def poll(self):
        return self.returncode

    def send_signal(self, sig):
        self.signals.append(sig)

    def wait(self, timeout=None):
        self.returncode = self.exit_on_sigint
        return self.returncode

    def kill(self):
        self.returncode = -9


class VideoTests(unittest.TestCase):
    def recorder(self, proc, said=""):
        path = os.path.join(tempfile.mkdtemp(dir=TMP), video.Video.FILE)
        with open(path, "wb") as f:
            f.write(proc.writes)
        v = video.Video("udid", path)
        p = mock.patch.object(video.subprocess, "Popen", side_effect=lambda *a, **k: (open(v.log, "w").write(said), proc)[1])
        p.start()
        self.addCleanup(p.stop)
        return v

    def test_stopped_with_sigint_and_kept(self):
        proc = FakeRecorder()
        v = self.recorder(proc, said="Recording started").start()
        self.assertEqual(v.stop(), [])
        self.assertEqual(proc.signals, [signal.SIGINT])
        self.assertTrue(v.ok)

    def test_failed_finish_is_a_problem_even_with_a_file(self):
        v = self.recorder(FakeRecorder(exit_on_sigint=1), said="Recording started").start()
        problems = v.stop()
        self.assertEqual(len(problems), 1, problems)
        self.assertIn("failed to finish", problems[0])
        self.assertFalse(v.ok)

    def test_interrupted_start_stops_the_recorder(self):
        proc = FakeRecorder()
        v = self.recorder(proc)
        with mock.patch.object(video.time, "sleep", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                v.start()
        self.assertEqual(proc.signals, [signal.SIGINT], "the caller never gets the object, so start() must stop it")


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeDevice()
        self.saved = (harness.Device, harness.fixture, harness.Pixels, harness.WideEvents, harness.fixture_release,
                      harness.Video)
        FakeVideo.fail_start, FakeVideo.stop_problem, FakeVideo.made = False, None, []
        harness.Video = FakeVideo
        harness.Device = lambda device: self.fake
        harness.Device.check_build_current = staticmethod(lambda: {})
        harness.fixture = lambda stop=False, user=None: dict(url="http://127.0.0.1:1/index.html?token=")
        harness.fixture_release = lambda user: {}
        harness.Pixels = FakePixels
        harness.WideEvents = lambda container: telemetry.WideEvents(container)
        self.saved_compose, self.composed, self.compose_fails = gallery.compose, [], {}
        gallery.compose = self.fake_compose

    def fake_compose(self, jobs):
        """Stands in for compose.swift: 'draws' each job as an empty file unless told it fails."""
        self.composed += jobs
        for j in jobs:
            if os.path.basename(j["out"]) not in self.compose_fails:
                open(j["out"], "w").close()
        return {j["out"]: self.compose_fails[os.path.basename(j["out"])] for j in jobs
                if os.path.basename(j["out"]) in self.compose_fails}

    def tearDown(self):
        harness.Device, harness.fixture, harness.Pixels, harness.WideEvents, harness.fixture_release, \
            harness.Video = self.saved
        gallery.compose = self.saved_compose

    def run_proof(self, run, keep=False, video=True, **fake):
        self.fake.__dict__.update(fake)
        mod = type("Proof", (), {"run": staticmethod(run)})
        ev = tempfile.mkdtemp(dir=TMP)
        return harness._run_device(mod, "iphone", ev, keep=keep, flags={}, device_obj=self.fake, video=video)

    def test_video_is_stopped_and_kept_on_pass_fail_and_cancel(self):
        def cancel(ios):
            raise harness._Stop("SIGINT")
        for status, run in (("pass", lambda ios: ios.check("ok", True)), ("fail", lambda ios: ios.check("broken", False)),
                            ("cancelled", cancel)):
            FakeVideo.made = []
            r = self.run_proof(run)
            self.assertEqual(r["status"], status, r)
            self.assertTrue(FakeVideo.made[0].stopped, f"the recording was left running after {status}")
            self.assertEqual(r["video"], "recording.mp4")
            self.assertTrue(os.path.isfile(os.path.join(r["evidence"], "recording.mp4")))

    def test_recording_failure_is_an_evidence_problem_not_a_failed_proof(self):
        FakeVideo.fail_start = True
        r = self.run_proof(lambda ios: ios.check("ok", True))
        self.assertEqual(r["status"], "pass", r)
        self.assertIsNone(r["video"])
        self.assertTrue(any("screen recording" in p for p in r["problems"]), r["problems"])
        self.assertEqual(harness.exit_code([r["status"]], bool(r["problems"])), 2)
        FakeVideo.fail_start, FakeVideo.stop_problem = False, "screen recording wrote no recording.mp4"
        r = self.run_proof(lambda ios: ios.check("ok", True))
        self.assertEqual((r["status"], r["video"]), ("pass", None), r)
        self.assertIn("screen recording wrote no recording.mp4", r["problems"])

    def test_no_video_records_nothing(self):
        r = self.run_proof(lambda ios: ios.check("ok", True), video=False)
        self.assertEqual((r["status"], r["video"], r["problems"]), ("pass", None, []), r)
        self.assertEqual(FakeVideo.made, [])

    def prove_file(self, body, devices='["iphone"]'):
        proof = os.path.join(tempfile.mkdtemp(dir=TMP), "scenario.py")
        with open(proof, "w") as f:
            f.write(f'"""The thing works.\n\nMore about it."""\nDEVICES = {devices}\n\ndef run(ios):\n{body}')
        return harness.prove(proof, evidence_dir=tempfile.mkdtemp(dir=TMP))

    def test_an_image_not_drawn_is_an_evidence_problem_not_a_failed_proof(self):
        self.compose_fails = {"key-frames.png": "cannot read shot.png"}
        code, out = self.prove_file('    ios.shot("shot")\n    ios.check("the thing", True)\n')
        self.assertEqual(code, 2, out)
        self.assertEqual(out["results"][0]["status"], "pass")
        problem = "could not draw iphone/key-frames.png: cannot read shot.png"
        self.assertIn(problem, out["results"][0]["problems"])
        with open(os.path.join(out["evidence"], "iphone", "result.json")) as f:
            self.assertIn(problem, json.load(f)["problems"], "prove --base reads problems from result.json")
        with open(out["report"]) as f:
            report = f.read()
        self.assertIn(problem, report)
        self.assertIn('[<img src="iphone/final.png" width="200" alt="Key frames on iphone">]', report,
                      "without a strip, the final screen stands in")

    def test_a_page_that_fails_still_leaves_the_report(self):
        with mock.patch.object(harness.page, "proof_page", side_effect=KeyError("boom")):
            code, out = self.prove_file('    ios.check("the thing", True)\n')
        self.assertEqual(code, 2, out)
        self.assertIn("could not write index.html: KeyError: 'boom'", out["results"][0]["problems"])
        self.assertTrue(os.path.isfile(out["report"]))

    def test_a_shot_cannot_take_the_name_of_a_generated_image(self):
        for name in ("poster", "key-frames", "final"):
            r = self.run_proof(lambda ios, name=name: (ios.shot(name), ios.check("x", True)))
            self.assertEqual(r["status"], "error", r)
            self.assertIn("kept for an image prove writes itself", r["reason"])

    def test_screenshots_are_recorded_in_the_order_taken(self):
        code, out = self.prove_file('    ios.shot("second")\n    ios.shot("first")\n    ios.shot("second")\n'
                                    '    ios.check("the thing", True)\n')
        with open(os.path.join(out["evidence"], "iphone", "result.json")) as f:
            self.assertEqual(json.load(f)["shots"], ["first.png", "second.png"], "a retaken shot moves to the end")

    def test_index_page_puts_failures_first_and_links_only_inside_the_attempt(self):
        code, out = self.prove_file('    ios.shot("menu")\n    ios.check("fine thing", True)\n'
                                    '    try:\n        ios.check("broken thing", False)\n    except Exception:\n        pass\n'
                                    '    ios.unverified("the other thing", "needs a live service")\n')
        self.assertEqual(code, 1, out)
        with open(os.path.join(out["evidence"], "index.html")) as f:
            html = f.read()
        self.assertIn("<h1>The thing works.</h1>", html)
        self.assertIn('<span class="badge fail">iPhone: FAIL</span>', html)
        self.assertIn('poster="iphone/poster.png" src="iphone/recording.mp4"', html)
        self.assertIn('<a href="iphone/key-frames.png"><img src="iphone/key-frames.png"', html)
        self.assertLess(html.index("broken thing"), html.index("fine thing"), "failures come first")
        self.assertIn("iphone: the other thing: needs a live service", html)
        self.assertIn('<a href="scenario.py">proof.py</a>', html)
        links = re.findall(r'(?:src|href)="([^"]*)"', html)
        self.assertTrue(links)
        for link in links:
            self.assertFalse(re.match(r"[a-z]+:|/", link), f"{link}: every link stays inside the attempt folder")
            self.assertTrue(os.path.exists(os.path.join(out["evidence"], urllib_unquote(link))), link)
        self.assertNotIn("<script", html)

    def test_two_devices_get_a_side_by_side_image(self):
        code, out = self.prove_file('    ios.check("the thing", True)\n', devices='["iphone", "ipad"]')
        self.assertEqual(code, 0, out)
        sides = [j for j in self.composed if j["out"].endswith("/devices.png")]
        self.assertEqual([c["caption"] for c in sides[0]["rows"][0]["cells"]], ["iPhone", "iPad"])
        with open(out["report"]) as f:
            self.assertIn('[<img src="devices.png" width="200" alt="Final screen per device">](devices.png)', f.read())

    def test_report_is_one_scenario_with_relative_evidence_links(self):
        proof = os.path.join(tempfile.mkdtemp(dir=TMP), "scenario.py")
        with open(proof, "w") as f:
            f.write('"""The thing works.\n\nMore about what it covers."""\nDEVICES = ["iphone"]\n\n'
                    'def run(ios):\n    ios.shot("after-tap")\n    ios.check("the thing", True)\n'
                    '    ios.unverified("the other thing", "needs a live service")\n')
        out_dir = os.path.join(tempfile.mkdtemp(dir=TMP), "my evidence")   # a space: the rerun must quote it
        code, out = harness.prove(proof, evidence_dir=out_dir)
        self.assertEqual(code, 0, out)
        self.assertEqual(os.path.dirname(out["evidence"]), os.path.realpath(out_dir))
        with open(out["report"]) as f:
            report = f.read()
        sections = [line for line in report.splitlines() if line.startswith("## ")]
        self.assertEqual(sections, ["## Verified", "## Evidence", "## Outcome", "## Details", "## Unverified"])
        for link in ("[▶ Watch video](iphone/recording.mp4)", "[final.png](iphone/final.png)",
                     "[after-tap.png](iphone/after-tap.png)", "[transcript.jsonl](iphone/transcript.jsonl)",
                     '[<img src="iphone/poster.png" width="200" alt="Recording on iphone">](iphone/recording.mp4)',
                     '[<img src="iphone/key-frames.png" width="200" alt="Key frames on iphone">](iphone/key-frames.png)',
                     "[index.html](index.html)"):
            self.assertIn(link, report)
        self.assertTrue(os.path.isfile(os.path.join(out["evidence"], "index.html")))
        self.assertIn("More about what it covers.", report)
        self.assertIn("- iphone: the other thing: needs a live service", report)
        with open(os.path.join(out["evidence"], "manifest.json")) as f:
            manifest = json.load(f)
        self.assertEqual(manifest["video"], {"iphone": "iphone/recording.mp4"})
        self.assertEqual(manifest["evidenceDir"], os.path.realpath(out_dir))
        self.assertTrue(manifest["rerun"].startswith(f"cd {shlex.quote(env.ROOT)} && "), "the rerun proves the same checkout")
        argv = shlex.split(manifest["rerun"].split(" && ", 1)[1])
        self.assertEqual(argv[1], "prove")
        self.assertTrue(argv[2].startswith(out["evidence"] + os.sep), argv)   # the attempt's copy, space and all
        self.assertEqual(argv[-2:], ["--evidence-dir", os.path.realpath(out_dir)], manifest["rerun"])
        code, again = harness.prove(proof, evidence_dir=out_dir)
        self.assertNotEqual(again["evidence"], out["evidence"], "each run gets a fresh attempt folder")

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

    def test_a_proof_stopped_by_its_session_still_deletes_its_simulator(self):
        """Stopping or closing the session that runs `prove` (SIGTERM, SIGHUP) cancels the proof like Ctrl-C does."""
        for sig in (signal.SIGTERM, signal.SIGHUP):
            with self.subTest(sig.name):
                self.fake = FakeDevice()
                path = os.path.join(tempfile.mkdtemp(dir=TMP), "stopped.py")
                with open(path, "w") as f:
                    f.write(f'"""The session running this proof goes away."""\nimport os\n\n\ndef run(ios):\n'
                            f'    os.kill(os.getpid(), {int(sig)})\n    ios.check("never reached", True)\n')
                before = signal.getsignal(sig)
                code, out = harness.prove(path, ["iphone"], evidence_dir=tempfile.mkdtemp(dir=TMP), video=False)
                self.assertEqual((code, out["results"][0]["status"]), (130, "cancelled"), out)
                self.assertEqual(self.fake.cleaned, 1, "the simulator is deleted")
                self.assertIs(signal.getsignal(sig), before)

    def test_app_log_is_kept_whatever_the_outcome(self):
        outcomes = {"pass": lambda ios: ios.check("ok", True), "fail": lambda ios: ios.check("broken", False),
                    "cancelled": lambda ios: (_ for _ in ()).throw(harness._Stop("SIGINT"))}
        for status, run in outcomes.items():
            with self.subTest(status):
                self.fake = FakeDevice()
                t0 = time.time()
                r = self.run_proof(run)
                self.assertEqual(r["status"], status, r)
                self.assertTrue(r["appLog"])
                self.assertTrue(os.path.exists(os.path.join(r["evidence"], "app.log")))
                self.assertLessEqual(abs(self.fake.app_log_start - t0), 1, "the log covers the run's own window")

    def test_app_log_that_cannot_be_read_is_a_problem_not_a_failure(self):
        r = self.run_proof(lambda ios: ios.check("something", True), fail_app_logs=True)
        self.assertEqual(r["status"], "pass")
        self.assertFalse(r["appLog"])
        self.assertTrue(any("app log" in p for p in r["problems"]), r["problems"])

    def test_language_is_pinned_and_recorded(self):
        r = self.run_proof(lambda ios: (ios.reset(), ios.default_capture_conditions(), ios.check("ok", True)))
        self.assertEqual((r["launched"]["language"], r["capture"]["language"], r["capture"]["locale"]),
                         (env.LANGUAGE, "en", "en_US"))

    def test_a_proof_can_choose_another_language(self):
        mod = type("Proof", (), {"run": staticmethod(lambda ios: (ios.reset(), ios.check("ok", True)))})
        fr = {"language": "fr", "locale": "fr_FR"}
        r = harness._run_device(mod, "iphone", tempfile.mkdtemp(dir=TMP), keep=False, flags={}, device_obj=self.fake,
                                language=fr)
        self.assertEqual((r["launched"]["language"], r["capture"]["locale"]), (fr, "fr_FR"))

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


    def test_proofs_symlink_into_the_checkout_is_refused(self):
        audit = tempfile.mkdtemp(dir=TMP)
        log = os.path.join(audit, "decisions.tsv")
        open(log, "w").close()
        inside = tempfile.mkdtemp(dir=os.path.join(env.ROOT, ".claude"))
        os.symlink(inside, os.path.join(audit, "proofs"))
        try:
            with self.assertRaises(env.Failed):
                harness.evidence_root(log)
        finally:
            os.rmdir(inside)


class EvidenceDirTests(unittest.TestCase):
    def test_attempts_go_in_the_given_directory_created_if_missing(self):
        out = os.path.join(tempfile.mkdtemp(dir=TMP), "not", "yet")
        path = harness.new_proof("given", harness.evidence_root(evidence_dir=out))
        self.assertEqual(os.path.dirname(os.path.dirname(path)), os.path.realpath(out))

    def test_directory_inside_the_checkout_is_refused(self):
        for inside in (env.ROOT, os.path.join(env.ROOT, ".claude", "evidence")):
            with self.assertRaises(env.Failed):
                harness.evidence_root(evidence_dir=inside)

    def test_decision_log_and_evidence_dir_together_are_refused(self):
        log = os.path.join(tempfile.mkdtemp(dir=TMP), "decisions.tsv")
        open(log, "w").close()
        with self.assertRaises(env.Failed):
            harness.evidence_root(log, TMP)


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

    def test_proofs_write_their_attempts_in_the_given_evidence_dir(self):
        from verify_ios import selftest
        calls, out_dir = [], tempfile.mkdtemp(dir=TMP)
        passed = dict(proofs=[dict(proof="p.py", report="r.md", results=[dict(device="iphone", status="pass")])])
        with mock.patch.object(selftest, "_cli", side_effect=lambda *a, **k: calls.append(a) or (0, passed, "")), \
                mock.patch.object(selftest.Device, "check_build_current"), \
                mock.patch.object(selftest.Device, "_all", return_value=[]), \
                mock.patch.object(selftest.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "OK")):
            code, out = selftest.run(["iphone"], out_dir)
        self.assertEqual(code, 0, out)
        prove = next(c for c in calls if c[0] == "prove")
        self.assertEqual(prove[-2:], ("--evidence-dir", out_dir))


class ReaperTests(unittest.TestCase):
    """Simulators whose worktree is gone, or that sat idle too long, are deleted from any worktree; nothing a live
    proof holds, and nothing that isn't a verify-ios simulator, is ever touched."""
    HOUR = 3600

    def setUp(self):
        self.calls, self.sims = [], []
        self.saved = (reap.run, os.environ.get("VERIFY_IOS_REAP"))
        reap.run = self.fake_run
        os.environ["VERIFY_IOS_REAP"] = "1"
        self.gone = os.path.join(TMP, "removed-worktree")   # never created: its worktree was removed

    def tearDown(self):
        reap.run = self.saved[0]
        os.environ["VERIFY_IOS_REAP"] = self.saved[1]

    def fake_run(self, cmd, **_):
        self.calls.append(cmd)
        out = ""
        if cmd[2:4] == ["list", "devices"]:
            out = json.dumps({"devices": {env.RUNTIME: self.sims}})
        elif cmd[2] == "delete":
            self.sims = [s for s in self.sims if s["udid"] != cmd[3]]
        return subprocess.CompletedProcess(cmd, 0, out, "")

    def worktree(self, name, root, used, device="iphone"):
        """A simulator and the state its worktree recorded (env.touch): where the worktree is, when it was last used."""
        key = f"{name}-{abs(hash(name)) % 999999:06d}"
        home = os.path.join(env.BASE, key)
        env.update_state(lambda st: st.update(root=root, devices={device: dict(lastUsed=used)}), home)
        os.makedirs(f"{home}/evidence/a-proof", exist_ok=True)
        udid = f"UDID-{key}-{device}"
        self.sims.append(dict(name=f"verify-ios-{key}-{device}", udid=udid, state="Booted", isAvailable=True))
        return key, home, udid

    def deleted(self):
        return [c[3] for c in self.calls if c[2] == "delete"]

    def test_a_simulator_name_maps_back_to_its_worktree_state(self):
        d = device.Device("ipad")
        self.assertEqual(reap.parse_name(d.name), (env.KEY, "ipad"))
        self.assertEqual(os.path.join(env.BASE, reap.parse_name(d.name)[0]), env.HOME)
        self.assertEqual(reap.parse_name("verify-ios-pr-review-verify-ios-7077a0-0a07df-iphone"),
                         ("pr-review-verify-ios-7077a0-0a07df", "iphone"))
        self.assertEqual(env.load_state()["root"], env.ROOT, "using a device records where its worktree is")
        for other in ("iPhone 17 Pro", "verify-ios-", "verify-ios-iphone", "verify-ios-abc-watch", "my-verify-ios-abc-iphone"):
            self.assertIsNone(reap.parse_name(other), other)

    def test_an_orphan_is_deleted_with_its_state_but_not_its_evidence(self):
        now = time.time()
        key, home, udid = self.worktree("orphan", self.gone, now)   # used just now, but its worktree is gone
        out = reap.reap(now=now)
        self.assertEqual(self.deleted(), [udid])
        self.assertEqual(out, [dict(name=f"verify-ios-{key}-iphone", why="orphan", deleted=True)])
        self.assertEqual(sorted(os.listdir(home)), ["evidence"], "pull requests link to the evidence")

    def test_a_live_worktrees_recent_simulator_is_kept(self):
        now = time.time()
        self.worktree("live", env.ROOT, now - 1.5 * self.HOUR)
        self.assertEqual(reap.reap(now=now), [])
        self.assertEqual(self.deleted(), [])

    def test_an_idle_simulator_expires_and_its_worktree_keeps_its_state(self):
        now = time.time()
        _, home, udid = self.worktree("kept", env.ROOT, now - 2.5 * self.HOUR)
        self.assertEqual(reap.reap(now=now)[0]["why"], "idle")
        self.assertEqual(self.deleted(), [udid])
        self.assertEqual(env.load_state(home)["root"], env.ROOT, "the worktree still exists: only the simulator goes")

    def test_the_idle_limit_is_configurable_and_can_be_turned_off(self):
        now = time.time()
        self.worktree("idle", env.ROOT, now - 0.75 * self.HOUR)
        with mock.patch.dict(os.environ, VERIFY_IOS_IDLE_HOURS="0"):
            self.assertEqual(reap.reap(now=now), [])
        with mock.patch.dict(os.environ, VERIFY_IOS_IDLE_HOURS="0.5"):
            self.assertEqual(reap.reap(now=now)[0]["why"], "idle")

    def test_a_held_lock_blocks_deletion(self):
        now = time.time()
        _, home, _ = self.worktree("busy", self.gone, now - 9 * self.HOUR)
        os.makedirs(f"{home}/locks", exist_ok=True)
        holder = subprocess.Popen([sys.executable, "-c", textwrap.dedent(f"""
            import fcntl, time
            f = open({home + '/locks/iphone.lock'!r}, 'a+'); fcntl.flock(f, fcntl.LOCK_EX); print('held', flush=True); time.sleep(30)""")],
            stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(holder.stdout.readline().strip(), "held")
            out = reap.reap(now=now)
        finally:
            holder.kill()
            holder.wait()
            holder.stdout.close()
        self.assertEqual(self.deleted(), [], "a live proof holds it, however old its worktree's state")
        self.assertTrue(out[0]["busy"])
        self.assertTrue(os.path.exists(f"{home}/state.json"))
        reap.reap(now=now)
        self.assertEqual(len(self.deleted()), 1, "once the lock is released, the next command reaps it")

    def test_only_verify_ios_simulators_are_ever_picked(self):
        now = time.time()
        for name in ("iPhone 17 Pro", "verify-ios-abc-watch", "my-verify-ios-orphan-iphone", "verify-ios"):
            self.sims.append(dict(name=name, udid=f"PERSONAL-{name}", state="Booted", isAvailable=True))
        self.assertEqual(reap.reap(now=now + 1000 * self.HOUR), [])
        self.assertEqual([c for c in self.calls if c[2:4] != ["list", "devices"]], [], "no simctl call but the listing")

    def test_untracked_simulators_age_by_their_own_files(self):
        """A verify-ios simulator with no state folder at all (made before worktree paths were recorded) is idle by
        the time its own simulator files last changed, and unknown files count as long unused."""
        self.sims.append(dict(name="verify-ios-803a95fcadd3-b74a35-ipad", udid="NO-SUCH-UDID", state="Booted",
                              isAvailable=True))
        self.assertEqual(reap.reap(now=time.time())[0]["why"], "idle")

    def test_the_commands_own_device_is_spared(self):
        now = time.time()
        own = env.KEY, "iphone"
        self.sims.append(dict(name=f"verify-ios-{own[0]}-iphone", udid="OURS", state="Booted", isAvailable=True))
        env.update_state(lambda st: st.setdefault("devices", {}).setdefault("iphone", {}).__setitem__("lastUsed", 0))
        self.assertEqual(reap.reap(spare={own}, now=now), [])
        self.assertEqual(reap.reap(now=now)[0]["why"], "idle", "another worktree's command would reap it")

    def test_reaping_can_be_turned_off(self):
        self.worktree("off", self.gone, 0)
        with mock.patch.dict(os.environ, VERIFY_IOS_REAP="0"):
            self.assertEqual(reap.reap(), [])
        self.assertEqual(self.calls, [])


class CliTests(unittest.TestCase):
    def test_check_rejects_a_bad_proof_with_exit_2(self):
        bad = os.path.join(TMP, "bad_proof.py")
        with open(bad, "w") as f:
            f.write("def run(ios): pass\n")   # no docstring
        cli = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "verify-ios")
        p = subprocess.run([cli, "--json", "check", bad], capture_output=True, text=True, env={**os.environ, "VERIFY_IOS_HOME": TMP})
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)

    def test_selftest_refuses_an_evidence_dir_inside_the_checkout_before_setup(self):
        cli = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "verify-ios")
        p = subprocess.run([cli, "--json", "selftest", "--evidence-dir", os.path.join(env.ROOT, "evidence")],
                           capture_output=True, text=True, env={**os.environ, "VERIFY_IOS_HOME": TMP}, timeout=30)
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)   # as new-proof and prove refuse it
        self.assertIn("outside this checkout", p.stdout)
        self.assertNotIn("simulator ready", p.stderr)


class BaseExpectationTests(HarnessTests):
    """What a proof declares for the base build, and how the base run of `prove --base` treats it."""

    def run_base(self, run, **fake):
        self.fake.__dict__.update(fake)
        mod = type("Proof", (), {"run": staticmethod(run)})
        return harness._run_device(mod, "iphone", tempfile.mkdtemp(dir=TMP), keep=False, flags={}, device_obj=self.fake,
                                   video=False, as_base=True)

    @staticmethod
    def bug_fix_proof(ios):
        ios.check("set up", True)
        with ios.on_base("fail"):
            ios.expect_visible("id=fixed")
            with ios.on_base("pass"):
                ios.check("still there", True)
            ios.check("the fix", False)
        ios.check("after the fix", True)

    @staticmethod
    def outcomes(r):
        return [(c["check"], c["ok"], c["base"]) for c in r["checks"]]

    def test_base_run_records_an_expected_failure_and_carries_on(self):
        r = self.run_base(self.bug_fix_proof, absent={"id=fixed"})
        self.assertEqual(r["status"], "fail", r)
        self.assertEqual(self.outcomes(r), [("set up", True, "unchanged"), ("id=fixed visible", False, "fail"),
                                            ("still there", True, "pass"), ("the fix", False, "fail"),
                                            ("after the fix", True, "unchanged"),
                                            ("app still in the foreground at the end", True, "unchanged")])

    def test_the_same_failure_stops_a_normal_run(self):
        r = self.run_proof(self.bug_fix_proof, absent={"id=fixed"})
        self.assertEqual(r["status"], "fail", r)
        self.assertEqual(self.outcomes(r)[:2], [("set up", True, "unchanged"), ("id=fixed visible", False, "fail")])
        self.assertNotIn("after the fix", [c["check"] for c in r["checks"]])

    def test_base_run_stops_at_a_failure_the_proof_did_not_expect(self):
        def run(ios):
            ios.check("should be unchanged", False)
            ios.check("never reached", True)
        r = self.run_base(run)
        self.assertEqual(r["status"], "fail", r)
        self.assertNotIn("never reached", [c["check"] for c in r["checks"]])

    def test_failed_waits_and_telemetry_are_recorded_as_failed_checks(self):
        def run(ios):
            with ios.on_base("fail"):
                ios.expect_hidden("id=gone")
                ios.expect_keyboard(shown=True)
                ios.expect_pixel("m_x")
        r = self.run_base(run, absent={"id=gone", "role=keyboard"})
        self.assertEqual([(c["check"], c["ok"]) for c in r["checks"]][:3],
                         [("id=gone gone", False), ("keyboard shown", False), ("pixel m_x fired", False)])

    def test_check_keys_leave_out_this_runs_tokens_and_local_ports(self):
        def run(ios):
            ios.check(f"tab loaded http://127.0.0.1:20412/index.html?token={ios.token('demo')}", True)
        self.assertEqual(self.run_proof(run)["checks"][0]["key"],
                         "tab loaded http://127.0.0.1:<port>/index.html?token=<token:demo>")

    def test_base_run_never_takes_a_runner_refusal_for_the_expected_failure(self):
        def wait(locator, state="visible", timeout=5):
            raise env.Failed("2 elements match", runner={"code": "AMBIGUOUS"})

        def run(ios):
            with ios.on_base("fail"):
                ios.expect_visible('label="twin"')
            ios.check("never reached", True)
        self.fake.wait = wait
        r = self.run_base(run)
        self.assertEqual(r["status"], "error", r)
        self.assertIn("not observed on the base build", r["reason"])
        self.assertEqual(r["checks"], [], "a refused check was never observed, so it is not recorded as failed")

    def judge_base_run(self, run, **fake):
        """The device's `prove --base` verdict when this checkout passes every check the base run was meant to make."""
        before = self.run_base(run, **fake)
        after = [dict(c, ok=True) for c in before["checks"]] or [check("expected miss", True, "fail")]
        return before, compare.verdict(before["status"], "pass", compare.judge(before["checks"], after))[0]

    @staticmethod
    def live_pixel_stream(ios, dead=False):
        ios.pixels = telemetry.Pixels("-", os.path.join(tempfile.mkdtemp(dir=TMP), "pixels.ndjson"))
        ios.pixels.proc = subprocess.Popen(["true" if dead else "sleep", *([] if dead else ["30"])])
        if dead:
            ios.pixels.proc.wait()
        ios.pixels.since = 0

    def test_a_dead_pixel_stream_on_the_base_run_is_inconclusive_not_the_expected_failure(self):
        def run(ios):
            self.live_pixel_stream(ios, dead=True)
            with ios.on_base("fail"):
                ios.expect_pixel("m_new_pixel", timeout=0)
        before, verdict = self.judge_base_run(run)
        self.assertEqual(before["status"], "error", before)
        self.assertIn("pixel log stream is not running", before["reason"])
        self.assertEqual(verdict, "INCONCLUSIVE")

    def test_a_harness_error_inside_on_base_fail_is_inconclusive_too(self):
        def run(ios):
            with ios.on_base("fail"):
                ios.expect_wide_event("data-clearing", timeout=0)   # no ios.mark(): a proof bug, not a miss
        before, verdict = self.judge_base_run(run)
        self.assertEqual((before["status"], verdict), ("error", "INCONCLUSIVE"), before)

    def test_a_pixel_that_really_did_not_fire_on_the_base_run_is_as_expected(self):
        def run(ios):
            self.live_pixel_stream(ios)
            try:
                with ios.on_base("fail"):
                    ios.expect_pixel("m_new_pixel", timeout=0)
                ios.check("after the pixel", True)
            finally:
                ios.pixels.stop()
        before, verdict = self.judge_base_run(run)
        self.assertEqual(before["status"], "fail", before)
        self.assertEqual([(c["check"], c["ok"]) for c in before["checks"]][:2],
                         [("pixel m_new_pixel fired", False), ("after the pixel", True)])
        self.assertEqual(verdict, "AS EXPECTED")

    def test_eventually_keeps_the_last_errors_runner_code(self):
        def read(code):
            def fn():
                raise env.Failed(code, runner={"code": code})
            return fn
        raised = []

        def run(ios):
            try:
                ios.eventually("reads the token", read("AMBIGUOUS"), timeout=0)
            except env.Failed as e:
                raised.append(e)
        self.run_proof(run)
        self.assertEqual(harness._code(raised[0]), "AMBIGUOUS")
        self.assertNotIsInstance(raised[0], env.Missed)

        def on_base(code):
            def run(ios):
                with ios.on_base("fail"):
                    ios.eventually("reads the token", read(code), timeout=0)
                ios.check("after", True)
            return self.run_base(run)
        self.assertEqual(on_base("AMBIGUOUS")["status"], "error")
        absent = on_base("NOT_FOUND")
        self.assertEqual([(c["check"], c["ok"]) for c in absent["checks"]][:2], [("reads the token", False), ("after", True)])

    def test_base_run_carries_on_past_an_expected_alert(self):
        def alert(action, button=None, timeout=5):
            raise env.Failed("cannot answer", runner={"code": "NOT_FOUND", "alert": "Allow?"})

        def run(ios):
            with ios.on_base("fail"):
                ios.expect_no_alert()
            ios.check("after the alert", True)
        self.fake.alert = alert
        self.assertIn("after the alert", [c["check"] for c in self.run_base(run)["checks"]])

    def test_a_step_that_does_not_find_what_it_looks_for_is_the_expected_failure_on_the_base_run(self):
        class Driver:   # nothing on screen: every lookup comes back empty
            def find(self, sel):
                return []

            def swipe(self, direction, sel=None):
                return {}
        dev = device.Device.__new__(device.Device)
        dev._driver = Driver()
        self.fake.scroll_to = dev.scroll_to
        self.fake.web.eval = lambda js: {"t": ""}   # Duck.ai never answers
        page = web.Web(0, "-")
        page.page_url = lambda: None                 # the tab shows no web page
        misses = {
            "tab count": lambda ios: steps.expect_tab_count(ios, 2, timeout=0),   # no tab-switcher button in the tree
            "alternative controls": lambda ios: ios.eventually(
                "a New Tab control", lambda: steps.tap_first_present(ios, steps.NEW_TAB, timeout=0), timeout=0),
            "scrolling": lambda ios: ios.eventually("row reachable", lambda: ios.scroll_to('label="row"'), timeout=0),
            "Duck.ai answer": lambda ios: ios.eventually(
                "Duck.ai answered", lambda: steps.read_duckai_answer(ios, timeout=0), timeout=0),
            "page URL": lambda ios: ios.eventually("page shows the token", lambda: "t-1" in page.url(), timeout=0),
        }
        for name, miss in misses.items():
            def run(ios, miss=miss):
                with ios.on_base("fail"):
                    miss(ios)
                ios.check("after the miss", True)
            with self.subTest(name):
                before, verdict = self.judge_base_run(run, absent=set(steps.NEW_TAB))
                self.assertEqual((before["status"], verdict), ("fail", "AS EXPECTED"), before)
                self.assertIn("after the miss", [c["check"] for c in before["checks"]])

    def test_a_step_stopped_by_a_refusal_is_still_inconclusive_on_the_base_run(self):
        def snapshot():
            raise env.Failed("the app is not running", runner={"code": "APP_NOT_RUNNING"})

        def run(ios):
            with ios.on_base("fail"):
                steps.expect_tab_count(ios, 2, timeout=0)
        self.fake.snapshot = snapshot
        before, verdict = self.judge_base_run(run)
        self.assertEqual((before["status"], verdict), ("error", "INCONCLUSIVE"), before)

    def test_an_unknown_base_outcome_is_an_error(self):
        def run(ios):
            with ios.on_base("different"):
                ios.check("x", True)
        self.assertEqual(self.run_proof(run)["status"], "error")


def check(name, ok, base="unchanged", key=None):
    return dict(check=name, ok=ok, base=base, key=key or name)


class JudgeTests(unittest.TestCase):
    @staticmethod
    def judged(before, after):
        return [(r["check"], r["before"], r["after"], r["judged"]) for r in compare.judge(before, after)]

    def test_each_declared_outcome_against_the_base_run(self):
        after = [check("bug fixed", True, "fail"), check("menu works", True, "pass"), check("page loads", True)]
        self.assertEqual(self.judged([check("bug fixed", False, "fail"), check("menu works", True, "pass"),
                                      check("page loads", True)], after),
                         [("bug fixed", "fail", "pass", "as expected"), ("menu works", "pass", "pass", "as expected"),
                          ("page loads", "pass", "pass", "as expected")])
        self.assertEqual(self.judged([check("bug fixed", True, "fail"), check("menu works", False, "pass"),
                                      check("page loads", False)], after),
                         [("bug fixed", "pass", "pass", "unexpected"), ("menu works", "fail", "pass", "unexpected"),
                          ("page loads", "fail", "pass", "unexpected")])

    def test_a_check_the_base_run_never_made_is_not_shown(self):
        rows = self.judged([check("set up", True)], [check("set up", True), check("bug fixed", True, "fail")])
        self.assertEqual(rows[1], ("bug fixed", "not run", "pass", "not shown"))

    def test_a_declared_check_this_checkout_never_made_is_not_shown(self):
        rows = self.judged([check("bug", False, "fail")], [])
        self.assertEqual(rows, [("bug", "fail", "not run", "not shown")])

    def test_checks_only_the_base_run_made_come_last(self):
        rows = self.judged([check("old path", True), check("set up", True)], [check("set up", True)])
        self.assertEqual(rows, [("set up", "pass", "pass", "as expected"), ("old path", "pass", "not run", "not shown")])

    def test_checks_line_up_by_token_free_key_and_occurrence(self):
        before = [check("reads a-1", True, key="reads <t>"), check("reads a-2", False, "fail", key="reads <t>")]
        after = [check("reads b-1", True, key="reads <t>"), check("reads b-2", True, "fail", key="reads <t>")]
        self.assertEqual(self.judged(before, after), [("reads b-1", "pass", "pass", "as expected"),
                                                      ("reads b-2", "fail", "pass", "as expected")])

    def test_verdicts(self):
        ok = [dict(check="x", judged="as expected")]
        self.assertEqual(compare.verdict("fail", "pass", ok)[0], "AS EXPECTED")
        self.assertEqual(compare.verdict("fail", "pass", [dict(check="x", judged="unexpected")])[0], "UNEXPECTED")
        self.assertEqual(compare.verdict("fail", "fail", ok)[0], "UNEXPECTED")
        self.assertEqual(compare.verdict("error", "pass", ok)[0], "INCONCLUSIVE")
        self.assertEqual(compare.verdict("fail", "busy", ok)[0], "INCONCLUSIVE")
        self.assertEqual(compare.verdict("fail", "pass", [dict(check="x", judged="not shown")])[0], "INCONCLUSIVE")
        self.assertEqual(compare.verdict("fail", "pass", ok, ["appearance"])[0], "INCONCLUSIVE")
        self.assertEqual(compare.verdict("cancelled", "pass", ok)[0], "CANCELLED")

    def test_capture_conditions_compare_every_key(self):
        self.assertEqual(compare.capture_differs(dict(appearance="light", textSize="large"),
                                                 dict(appearance="dark", textSize="large", locale="en_US")),
                         ["appearance", "locale"])

    def test_exit_codes(self):
        self.assertEqual(compare.exit_code(["AS EXPECTED", "AS EXPECTED"]), 0)
        self.assertEqual(compare.exit_code(["AS EXPECTED"], problems=True), 2)
        self.assertEqual(compare.exit_code(["AS EXPECTED", "UNEXPECTED"]), 1)
        self.assertEqual(compare.exit_code(["UNEXPECTED", "INCONCLUSIVE"]), 2)
        self.assertEqual(compare.exit_code(["INCONCLUSIVE", "CANCELLED"]), 130)


class CompareReportTests(unittest.TestCase):
    @staticmethod
    def run_dir(attempt, name, status, checks, shots):
        d = os.path.join(attempt, name, "iphone")
        os.makedirs(d)
        for shot in shots + ["final.png", "recording.mp4"]:
            open(os.path.join(d, shot), "w").close()
        return dict(status=status, reason=None, checks=checks, video="recording.mp4", capture=dict(appearance="light"))

    def test_before_after_key_frames_and_judged_checks(self):
        attempt = tempfile.mkdtemp(dir=TMP)
        b = self.run_dir(attempt, "before/run1", "fail", [check("hint | text", False, "fail")], ["menu.png"])
        a = self.run_dir(attempt, "after/run2", "pass", [check("hint | text", True, "fail")], ["menu.png", "extra.png"])
        rows = compare.judge(b["checks"], a["checks"])
        devices = dict(iphone=dict(verdict="AS EXPECTED", reason=None, rows=rows, before=b, after=a, captureDiffers=[]))
        cmp = dict(base=dict(ref="origin/main", sha="a" * 40), before="before/run1", after="after/run2", problems=[],
                   rerun="cd x && verify-ios prove p --base aaa")
        mod = type("Proof", (), {"__doc__": "The hint names the demo.\n\nDetails."})
        text = compare.report(mod, cmp, devices, attempt)
        self.assertEqual([line for line in text.splitlines() if line.startswith("## ")],
                         ["## Verified", "## Evidence", "## Outcome", "## Details", "## Unverified"])
        self.assertIn("| | Before | After |", text)
        self.assertIn('| menu | [<img src="before/run1/iphone/menu.png" width="200" alt="Before: menu on iphone">]'
                      '(before/run1/iphone/menu.png) | [<img src="after/run2/iphone/menu.png"', text)
        self.assertIn("| extra | not captured | [<img", text)
        self.assertIn("| final | [<img", text)
        self.assertIn("[▶ Watch video](before/run1/iphone/recording.mp4)", text)
        self.assertIn("### iphone: AS EXPECTED", text)
        self.assertIn("| hint \\| text | fail | fail | pass | as expected |", text)
        self.assertIn("[report](before/run1/report.md)", text)

    def test_drawing_errors_become_one_line_problems(self):
        proc = subprocess.CompletedProcess([], 0, json.dumps(dict(ok=[], failed={"/a/x.png": "Error (\n  Duration\n)"})), "")
        with mock.patch.object(gallery.subprocess, "run", return_value=proc):
            self.assertEqual(gallery.compose([dict(kind="poster", out="/a/x.png"), dict(kind="grid", out="/a/y.png")]),
                             {"/a/x.png": "Error ( Duration )", "/a/y.png": "not drawn"})

    def test_ctrl_c_while_drawing_the_comparison_still_writes_the_report(self):
        attempt = tempfile.mkdtemp(dir=TMP)
        def compose(jobs):
            os.kill(os.getpid(), signal.SIGINT)   # Ctrl-C lands while compose.swift draws
            return {os.path.join(attempt, "before-after-iphone.png"): "interrupted"}
        b = self.run_dir(attempt, "b/r", "fail", [check("hint", False, "fail")], [])
        with mock.patch.object(compare.Device, "check_build_current", staticmethod(lambda: {})), \
                mock.patch.object(compare, "_prove_base", return_value=(os.path.join(attempt, "b/r"), None)), \
                mock.patch.object(compare, "_remove_worktree", return_value=[]), \
                mock.patch.object(compare.harness, "prove", return_value=(0, dict(evidence=None))), \
                mock.patch.object(compare.harness, "_new_attempt", return_value=attempt), \
                mock.patch.object(gallery, "compose", compose), \
                mock.patch.object(compare, "_result", return_value=b), \
                mock.patch.object(page, "comparison_page", side_effect=KeyError("boom")):
            proof = ProveAgainstBaseTests.proof()
            compare.prove_against_base(proof, "HEAD", evidence_dir=tempfile.mkdtemp(dir=TMP))
        with open(os.path.join(attempt, "report.md")) as f:
            report = f.read()
        self.assertIn("could not draw before-after-iphone.png: interrupted", report)
        self.assertIn("could not write index.html: KeyError: 'boom'", report)
        self.assertFalse(os.path.exists(os.path.join(attempt, "index.html")), "no empty page left behind")
        self.assertTrue(os.path.isfile(os.path.join(attempt, "comparison.json")))

    def test_comparison_page_and_report_lead_with_the_before_after_image(self):
        attempt = tempfile.mkdtemp(dir=TMP)
        b = self.run_dir(attempt, "before/run1", "fail", [check("hint", False, "fail"), check("loads", True)], [])
        a = self.run_dir(attempt, "after/run2", "pass", [check("hint", True, "fail"), check("loads", False)], [])
        for name in ("before-after-iphone.png", "after/run2/iphone/poster.png"):
            open(os.path.join(attempt, name), "w").close()
        rows = compare.judge(b["checks"], a["checks"])
        devices = dict(iphone=dict(verdict="UNEXPECTED", reason="x", rows=rows, before=b, after=a, captureDiffers=[]))
        cmp = dict(base=dict(ref="origin/main", sha="a" * 40), before="before/run1", after="after/run2", problems=[],
                   rerun="cd x && verify-ios prove p --base aaa")
        mod = type("Proof", (), {"__doc__": "The hint names the demo."})
        text = compare.report(mod, cmp, devices, attempt)
        self.assertIn('[<img src="before-after-iphone.png" width="200" alt="Before and after on iphone">]'
                      '(before-after-iphone.png)', text)
        self.assertIn('| Video | [▶ Watch video](before/run1/iphone/recording.mp4) | [<img src="after/run2/iphone/poster.png" '
                      'width="200" alt="Recording on iphone">](after/run2/iphone/recording.mp4) '
                      '[▶ Watch video](after/run2/iphone/recording.mp4) |', text)
        html = page.comparison_page(mod, cmp, devices, attempt)
        self.assertIn('<span class="badge fail">iPhone: UNEXPECTED</span>', html)
        self.assertIn('<img src="before-after-iphone.png"', html)
        self.assertIn('src="before/run1/iphone/recording.mp4"', html)
        self.assertIn('poster="after/run2/iphone/poster.png" src="after/run2/iphone/recording.mp4"', html)
        self.assertLess(html.index("<td class=\"\">loads</td>"), html.index("<td class=\"\">hint</td>"),
                        "the unexpected check comes first")
        self.assertIn('<a href="before/run1/index.html">page</a>', html)


def urllib_unquote(path):
    import urllib.parse
    return urllib.parse.unquote(path)


def write_png(path, width, height, rgb=(200, 80, 40)):
    """A solid-colour PNG, written without any imaging library."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    assert head[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG"
    return struct.unpack(">II", head[16:24])


class GalleryTests(unittest.TestCase):
    @staticmethod
    def device_dir(root, name, shots):
        d = os.path.join(root, name)
        os.makedirs(d)
        for i, shot in enumerate(shots):   # taken in this order, whatever their names
            open(os.path.join(d, shot), "w").close()
            os.utime(os.path.join(d, shot), (1000 + i, 1000 + i))
        return d

    def test_key_frames_follow_the_order_taken_then_the_final_screen(self):
        d = self.device_dir(tempfile.mkdtemp(dir=TMP), "iphone", ["z-first.png", "a-second.png", "final.png",
                                                                  "key-frames.png", "poster.png"])
        self.assertEqual(gallery.key_frames(d), ["z-first.png", "a-second.png", "final.png"])
        self.assertEqual(gallery.key_frames(None), [])

    def test_the_recorded_order_survives_a_copy_that_resets_file_times(self):
        d = self.device_dir(tempfile.mkdtemp(dir=TMP), "iphone", ["b.png", "a.png", "final.png"])
        self.assertEqual(gallery.key_frames(d, ["a.png", "b.png", "gone.png"]), ["a.png", "b.png", "final.png"])

    def test_proof_jobs(self):
        attempt = tempfile.mkdtemp(dir=TMP)
        phone = self.device_dir(attempt, "iphone", ["menu.png", "final.png", "recording.mp4"])
        pad = self.device_dir(attempt, "ipad", ["final.png"])
        jobs = {os.path.relpath(j["out"], attempt): j for j in gallery.proof_jobs(attempt, [
            dict(device="iphone", evidence=phone, video="recording.mp4"), dict(device="ipad", evidence=pad, video=None),
            dict(device="-", evidence=None)])}
        self.assertEqual(sorted(jobs), ["devices.png", "iphone/key-frames.png", "iphone/poster.png"],
                         "a single frame is no strip, and no video means no poster")
        self.assertEqual([c["caption"] for c in jobs["iphone/key-frames.png"]["rows"][0]["cells"]], ["menu", "final"])
        self.assertEqual(jobs["iphone/poster.png"]["video"], os.path.join(phone, "recording.mp4"))
        self.assertEqual(gallery.proof_jobs(attempt, [dict(device="iphone", evidence=phone, video=None)])[0]["out"],
                         os.path.join(phone, "key-frames.png"), "one device: no side-by-side image")

    def test_before_after_lines_frames_up_by_name(self):
        attempt = tempfile.mkdtemp(dir=TMP)
        self.device_dir(attempt, "before/r1/iphone", ["menu.png", "gone.png", "final.png"])
        self.device_dir(attempt, "after/r2/iphone", ["extra.png", "menu.png", "final.png"])
        outcomes = dict(iphone=dict(before={}, after={}), ipad=dict(before={}, after={}))
        [job] = gallery.comparison_jobs(attempt, "before/r1", "after/r2", outcomes)
        self.assertEqual(job["out"], os.path.join(attempt, "before-after-iphone.png"))
        before, after = job["rows"]
        self.assertEqual((before["label"], after["label"]), ("Before\n(base build)", "After\n(this checkout)"))
        self.assertEqual([c["caption"] for c in after["cells"]], ["extra", "menu", "gone", "final"])
        self.assertEqual([c["path"] is not None for c in before["cells"]], [False, True, True, True])
        self.assertEqual([c["path"] is not None for c in after["cells"]], [True, True, False, True])
        self.assertEqual(gallery.comparison_jobs(attempt, None, "after/r2", outcomes), [], "no base run: no image")

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcrun"), "compose.swift needs Xcode")
    def test_compose_draws_with_xcode_alone_and_reports_each_failure(self):
        d = tempfile.mkdtemp(dir=TMP)
        write_png(os.path.join(d, "a.png"), 60, 130)
        write_png(os.path.join(d, "b.png"), 90, 130, (40, 80, 200))
        grid = os.path.join(d, "out dir", "grid.png")
        os.makedirs(os.path.dirname(grid))
        cells = lambda *paths: [dict(path=p and os.path.join(d, p), caption=f"c{i}") for i, p in enumerate(paths)]
        failed = gallery.compose([
            dict(kind="grid", out=grid, height=100, rows=[dict(label="Before", cells=cells("a.png", None)),
                                                          dict(label="After", cells=cells("a.png", "b.png"))]),
            dict(kind="poster", out=os.path.join(d, "poster.png"), video=os.path.join(d, "missing.mp4")),
            dict(kind="grid", out=os.path.join(d, "bad.png"), rows=[dict(label=None, cells=cells("nope.png"))])])
        self.assertEqual(sorted(os.path.basename(k) for k in failed), ["bad.png", "poster.png"], failed)
        self.assertIn("cannot read", failed[os.path.join(d, "bad.png")])
        width, height = png_size(grid)
        self.assertGreater(height, 2 * 100, "two rows of 100 px frames")
        self.assertGreater(width, 100 * 90 // 130 + 100 * 60 // 130, "two columns plus the row labels")


class ProveAgainstBaseTests(unittest.TestCase):
    @staticmethod
    def proof():
        path = os.path.join(tempfile.mkdtemp(dir=TMP), "p.py")
        with open(path, "w") as f:
            f.write('"""Proves a thing."""\nDEVICES = ["iphone"]\n\ndef run(ios):\n    ios.check("x", True)\n')
        return path

    def test_a_stale_build_here_fails_before_the_base_is_touched(self):
        def stale():
            raise env.Failed("the app source changed since the last build: run build --app-only")
        with mock.patch.object(compare.Device, "check_build_current", staticmethod(stale)), \
                mock.patch.object(compare, "_prove_base") as base:
            code, out = compare.prove_against_base(self.proof(), "HEAD", evidence_dir=tempfile.mkdtemp(dir=TMP))
        self.assertEqual((code, out["code"]), (2, "BUILD_NOT_CURRENT"))
        base.assert_not_called()

    def test_a_ref_that_is_not_a_commit_is_refused(self):
        with mock.patch.object(compare.Device, "check_build_current", staticmethod(lambda: {})), \
                mock.patch.object(compare, "_prove_base") as base:
            code, out = compare.prove_against_base(self.proof(), "no-such-ref-xyz", evidence_dir=tempfile.mkdtemp(dir=TMP))
        self.assertEqual((code, out["code"]), (2, "BAD_BASE"))
        base.assert_not_called()

    def test_a_base_worktree_another_run_is_using_is_left_in_place(self):
        worktree = tempfile.mkdtemp(dir=TMP)
        log = os.path.join(worktree, "log")
        with mock.patch.object(compare, "_step", return_value=(env.EXIT_BUSY, "")) as step:
            problems = compare._remove_worktree(worktree, log)
        self.assertEqual(step.call_count, 1, "only the cleanup ran: the worktree was not removed")
        self.assertIn("in use", problems[0])

    def test_ctrl_c_during_the_worktree_cleanup_does_not_cut_it_short(self):
        """The cleanup child runs in its own session (the terminal's Ctrl-C can't reach it) and the parent ignores
        signals from the first step to the last, then puts its handlers back."""
        worktree, scripts = tempfile.mkdtemp(dir=TMP), tempfile.mkdtemp(dir=TMP)
        log, seen, cleanup = os.path.join(worktree, "log"), os.path.join(scripts, "seen"), os.path.join(scripts, "cleanup")
        with open(cleanup, "w") as f:   # stands in for `verify-ios cleanup`: Ctrl-C reaches the parent while it runs
            f.write(f"import os, signal, time\nopen({seen!r}, 'w').write(str(os.getsid(0)))\n"
                    "os.kill(os.getppid(), signal.SIGINT)\ntime.sleep(0.2)\n")
        runs = []
        real_step = compare._step

        def step(cmd, cwd, log, interruptible=True):
            runs.append(cmd)
            if cmd[-1] == "--delete-sims":
                return real_step([sys.executable, cleanup], cwd, log, interruptible)
            os.kill(os.getpid(), signal.SIGINT)   # between the steps and during the second
            return 0, ""
        before = signal.getsignal(signal.SIGINT)
        with mock.patch.object(compare, "_step", step):
            problems = compare._remove_worktree(worktree, log)
        self.assertEqual(problems, [])
        self.assertEqual(len(runs), 2, "the worktree was removed after its simulators")
        with open(seen) as f:
            self.assertNotEqual(int(f.read()), os.getsid(0), "the cleanup child shares the terminal's session")
        self.assertIs(signal.getsignal(signal.SIGINT), before)

    def test_without_a_base_run_the_verdict_is_inconclusive_and_this_checkout_is_not_proved(self):
        with mock.patch.object(compare.Device, "check_build_current", staticmethod(lambda: {})), \
                mock.patch.object(compare, "_prove_base", return_value=(None, "the base build failed (exit 1)")), \
                mock.patch.object(compare.harness, "prove") as after:
            code, out = compare.prove_against_base(self.proof(), "HEAD", evidence_dir=tempfile.mkdtemp(dir=TMP))
        after.assert_not_called()
        self.assertEqual(code, 2, out)
        self.assertEqual(out["devices"]["iphone"]["verdict"], "INCONCLUSIVE")
        with open(out["report"]) as f:
            self.assertIn("the base build failed", f.read())


if __name__ == "__main__":
    unittest.main()


class SourceStampTests(unittest.TestCase):
    """The skills live in .agents/skills, with .claude/skills symlinks. Editing them while you work on a proof
    must not mark the build stale, and editing the app must."""

    def setUp(self):
        self.repo = tempfile.mkdtemp(dir=TMP)
        for args in (["init", "-q"], ["config", "user.email", "t@example.com"], ["config", "user.name", "T"]):
            subprocess.run(["git", "-C", self.repo, *args], check=True)
        for path in ("App/Main.swift", ".agents/skills/verify-x/SKILL.md", ".claude/notes.md"):
            self.write(path, "base\n")
        subprocess.run(["git", "-C", self.repo, "add", "-A"], check=True)
        subprocess.run(["git", "-C", self.repo, "commit", "-qm", "base"], check=True)

    def write(self, path, text):
        full = os.path.join(self.repo, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(text)

    def test_skill_edits_keep_the_stamp_and_app_edits_change_it(self):
        with mock.patch.object(env, "ROOT", self.repo):
            before = env.source_stamp()["stamp"]
            self.write(".agents/skills/verify-x/SKILL.md", "changed\n")
            self.write(".agents/skills/verify-x/new.py", "new\n")
            self.write(".claude/notes.md", "changed\n")
            self.assertEqual(env.source_stamp()["stamp"], before)
            self.write("App/Main.swift", "changed\n")
            self.assertNotEqual(env.source_stamp()["stamp"], before)
