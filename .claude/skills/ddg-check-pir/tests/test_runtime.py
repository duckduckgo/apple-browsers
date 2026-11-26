import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.parse
import uuid

SPEC = importlib.util.spec_from_file_location("pir_runtime", Path(__file__).parents[1] / "runtime.py")
runtime = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runtime)
REAL_RUN = subprocess.run
REAL_POPEN = subprocess.Popen
REAL_READY = runtime.Runtime._ready
OWNED_SIM = "19E2BA91-D2EB-4216-9DC2-063D561C5486"


class FakeTools:
    def __init__(self, root):
        self.root = root
        self.calls = []
        self.simulators = [{"udid": "USER-SIM", "name": "My simulator", "state": "Booted"}]
        self.processes = {}
        self.fail_launch = False
        self.fail_launch_after_start = False
        self.exit_on_start = False
        self.timeout_launch = False
        self.timeout_launch_without_pid = False
        self.fail_build = False
        self.source_changes_during_build = False
        self.foreign_agent = None
        self.bad_json = False
        self.settings = None
        self.child = None
        self.extra_pids = []
        self.products_override = None
        self.launch_profile_log = ("2026-11-26 12:00:00.000 Df DuckDuckGo[412:1a] [com.duckduckgo.mobile.ios:LaunchProfile] "
                                   "LAUNCH_PROFILE_APPLIED keys=internalUser\n")

    def materialize(self, mac):
        app = self.root / ("DerivedData/ddg-check-pir/macos/deployment/Applications/DEBUG/DuckDuckGo.app" if mac else
                           "DerivedData/ddg-check-pir/ios/build/Build/Products/Debug-iphonesimulator/DuckDuckGo.app")
        info = {"CFBundleIdentifier": runtime.BROWSER_BUNDLE if mac else runtime.BUNDLES["ios"],
                "CFBundleExecutable": "DuckDuckGo"}
        if mac:
            info.update(DBP_BACKGROUND_AGENT_PRODUCT_NAME="PIR", DBP_BACKGROUND_AGENT_BUNDLE_ID=runtime.BUNDLES["macos"])
        self.write_bundle(app, info, mac)
        if mac:
            agent = app / "Contents/Library/LoginItems/PIR.app"
            self.write_bundle(agent, {"CFBundleIdentifier": runtime.BUNDLES["macos"], "CFBundleExecutable": "PIRAgent"}, True)
        return app

    @staticmethod
    def write_bundle(app, info, mac):
        plist = app / ("Contents/Info.plist" if mac else "Info.plist")
        executable = app / ("Contents/MacOS" if mac else "") / info["CFBundleExecutable"]
        plist.parent.mkdir(parents=True, exist_ok=True)
        executable.parent.mkdir(parents=True, exist_ok=True)
        plist.write_bytes(plistlib.dumps(info))
        executable.write_bytes(b"fake Mach-O build product")

    def run(self, command, **options):
        command = list(map(str, command))
        self.calls.append((command, options))
        if command[0] == "git":
            return REAL_RUN(command, **options)
        output, code = "", 0
        if command[0] == "ps":
            if "-axo" in command:
                identifiers = list(self.processes) + self.extra_pids + ([999] if self.foreign_agent else [])
                output = "\n".join(str(pid) for pid in identifiers)
            else:
                executable = self.processes.get(int(command[command.index("-p") + 1]))
                output = "Tue Nov 17 16:46:00 2026\n" if executable else ""
                code = 0 if executable else 1
        elif command[0] == "sh":
            assert command[-1] == "on"
            overrides = self.root / "macOS/LocalOverrides.xcconfig"
            overrides.parent.mkdir(exist_ok=True)
            previous = overrides.read_text() if overrides.exists() else ""
            if "DEPLOYMENT_LOCATION[config=Debug] = YES" not in previous:
                overrides.write_text(previous + "\nDEPLOYMENT_LOCATION[config=Debug] = YES\n")
        elif command[0] == "xcodebuild":
            mac = command[command.index("-scheme") + 1] == "macOS Browser"
            app = self.root / ("DerivedData/ddg-check-pir/macos/deployment/Applications/DEBUG/DuckDuckGo.app" if mac else
                               "DerivedData/ddg-check-pir/ios/build/Build/Products/Debug-iphonesimulator/DuckDuckGo.app")
            if "-showBuildSettings" in command:
                self.settings = {"TARGET_BUILD_DIR": str(app.parent), "FULL_PRODUCT_NAME": app.name,
                                 "PRODUCT_BUNDLE_IDENTIFIER": runtime.BROWSER_BUNDLE if mac else runtime.BUNDLES["ios"],
                                 "DEPLOYMENT_LOCATION": "YES" if mac else "NO",
                                 "BUILT_PRODUCTS_DIR": str(self.products_override or (self.root / "DerivedData/ddg-check-pir" /
                                     ("macos" if mac else "ios") / "build/Build/Products" / ("Debug" if mac else "Debug-iphonesimulator")))}
                output = json.dumps([{"action": "build", "target": "DuckDuckGo", "buildSettings": self.settings}])
            else:
                if mac:
                    link = Path(self.settings["BUILT_PRODUCTS_DIR"]) / "Applications"
                    assert link.is_symlink(), "Build must not enter the global deployment branch"
                    assert link.resolve() == (self.root / "DerivedData/ddg-check-pir/macos/deployment/Applications").resolve()
                self.materialize(mac)
                if self.source_changes_during_build:
                    (self.root / "iOS/input.swift").write_text("changed during build")
                output, code = "BUILD FAILED" if self.fail_build else "BUILD SUCCEEDED", int(self.fail_build)
        elif command[:2] == ["xcrun", "simctl"]:
            args = command[2:]
            if args == ["list", "runtimes", "--json"]:
                output = {"runtimes": [{"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2", "version": "27.2",
                                        "isAvailable": True, "supportedDeviceTypes": [
                                            {"identifier": "iPhone-type"}, {"identifier": "iPad-type"}]}]}
            elif args == ["list", "devicetypes", "--json"]:
                output = {"devicetypes": [{"identifier": "iPhone-type", "name": "iPhone 18"},
                                           {"identifier": "iPad-type", "name": "iPad 18"}]}
            elif args in (["list", "devices", "--json"], ["list", "devices", "available", "--json"]):
                output = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-2": self.simulators}}
            elif args[0] == "create":
                self.simulators.append({"udid": OWNED_SIM, "name": args[1], "state": "Shutdown"})
                output = OWNED_SIM + "\n"
            elif args[0] == "boot":
                next(s for s in self.simulators if s["udid"] == args[1])["state"] = "Booted"
            elif args[0] == "bootstatus":
                pass
            elif args[0] == "install":
                self.installed = Path(args[2])
                (self.root / "SimulatorDevices" / OWNED_SIM / "app-data").mkdir(parents=True, exist_ok=True)
            elif args == ["get_app_container", OWNED_SIM, runtime.BUNDLES["ios"], "data"]:
                output = str(self.root / "SimulatorDevices" / OWNED_SIM / "app-data") + "\n"
            elif args[0] == "launch":
                if self.fail_launch:
                    output, code = "launch failed", 1
                else:
                    executable = self.root / f"SimulatorDevices/{OWNED_SIM}/data/Application/DuckDuckGo.app/DuckDuckGo"
                    executable.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(self.installed / "DuckDuckGo", executable)
                    self.processes[412] = str(executable)
                    output = runtime.BUNDLES["ios"] + ": 412\n"
                    code = int(self.fail_launch_after_start)
                    if self.timeout_launch or self.timeout_launch_without_pid:
                        captured = b"launch started" if self.timeout_launch_without_pid else output.encode()
                        raise subprocess.TimeoutExpired(command, 120, output=captured, stderr=b"private timeout detail")
            elif args[0] == "spawn":
                output = self.launch_profile_log
            elif args[0] == "terminate":
                self.processes.pop(412, None)
            elif args[0] == "shutdown":
                next(s for s in self.simulators if s["udid"] == args[1])["state"] = "Shutdown"
                self.processes.pop(412, None)
            elif args[0] == "delete":
                self.simulators = [s for s in self.simulators if s["udid"] != args[1]]
                self.processes.pop(412, None)
            else:
                raise AssertionError(command)
            if not isinstance(output, str):
                output = "invalid JSON" if self.bad_json else json.dumps(output)
        else:
            raise AssertionError(f"Unexpected executable {command}")
        return subprocess.CompletedProcess(command, code, output, "")

    def proc_pidpath(self, pid, buffer, size):
        executable = self.processes.get(pid) or (self.foreign_agent if pid == 999 else None)
        if not executable:
            return 0
        buffer.value = os.fsencode(executable)
        return len(buffer.value) + 1

    def popen(self, command, **options):
        if str(command[0]) == "git":
            return REAL_POPEN(command, **options)
        self.calls.append((list(map(str, command)), options))
        self.processes[412] = str(command[0])
        self.child = Mock(pid=412)
        self.child.wait.return_value = 0
        self.child.poll.return_value = None
        if self.exit_on_start:
            self.child.poll.return_value = 17
            self.child.wait.side_effect = lambda **kwargs: self.processes.pop(412, None) and 17
        return self.child

    def kill(self, pid, signal):
        self.processes.pop(pid, None)


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / "checkout"
        self.root.mkdir()
        (self.root / "iOS").mkdir()
        (self.root / "iOS/input.swift").write_text("original source")
        (self.root / "macOS").mkdir()
        (self.root / "macOS/LocalOverrides.xcconfig").write_text("UNRELATED_SETTING = preserve\n")
        (self.root / ".gitignore").write_text("macOS/LocalOverrides.xcconfig\n")
        self.skill = self.root / ".claude/skills/ddg-check-pir/runtime.py"
        self.skill.parent.mkdir(parents=True)
        REAL_RUN(["git", "init", "-q", str(self.root)], check=True)
        REAL_RUN(["git", "-C", str(self.root), "add", "iOS/input.swift", ".gitignore"], check=True)
        self.tools = FakeTools(self.root)
        self.addCleanup(patch.stopall)
        patch.object(runtime, "__file__", str(self.skill)).start()
        patch.object(runtime.subprocess, "run", side_effect=self.tools.run).start()
        patch.object(runtime.subprocess, "Popen", side_effect=self.tools.popen).start()
        patch.object(runtime.os, "kill", side_effect=self.tools.kill).start()
        patch.object(runtime, "_libproc", None).start()
        self.libproc = Mock()
        self.libproc.proc_pidpath.side_effect = self.tools.proc_pidpath
        patch.object(runtime.ctypes, "CDLL", return_value=self.libproc).start()
        self.ready = patch.object(runtime.Runtime, "_ready").start()
        self.socket = patch.object(runtime.socket, "socket").start()

    def make_runtime(self, platform="ios", **kwargs):
        instance = runtime.Runtime(platform, Path(self.directory.name) / "evidence", str(uuid.uuid4()), 54837, **kwargs)
        self.addCleanup(instance._release)
        return instance

    def agent_bundle(self, identifier):
        bundle = Path(self.directory.name) / "OtherAgent.app"
        self.tools.write_bundle(bundle, {"CFBundleIdentifier": identifier, "CFBundleExecutable": "PIRAgent"}, True)
        return bundle / "Contents/MacOS/PIRAgent"

    def test_ios_lifecycle_uses_apple_tools_and_only_deletes_owned_simulator(self):
        instance = self.make_runtime(pir_environment="staging")
        build = instance.build()
        build_commands = [c for c, _ in self.tools.calls if c[0] == "xcodebuild"]
        destinations = [c[c.index("-destination") + 1] for c in build_commands]
        self.assertEqual(destinations, ["platform=iOS Simulator,id=USER-SIM"] * 2)
        self.assertFalse(any(c[:2] == ["xcrun", "simctl"] and c[2] != "list" for c, _ in self.tools.calls))
        launched = instance.launch()
        self.assertEqual(launched["sourceSHA256"], build["sourceSHA256"])
        self.assertEqual(launched["simulator"]["udid"], OWNED_SIM)
        command, options = next((c, o) for c, o in self.tools.calls if c[:3] == ["xcrun", "simctl", "launch"])
        self.assertIn("--stdout=" + str(instance.stdout), command)
        self.assertIn(OWNED_SIM, command)
        self.assertEqual(options["env"]["SIMCTL_CHILD_PIR_DEBUG_ENVIRONMENT"], "staging")
        self.assertEqual(options["env"]["SIMCTL_CHILD_PIR_DEBUG_INSTANCE_ID"], instance.instance)
        self.assertEqual(command[command.index("-launchProfile") + 1:], [json.dumps(runtime.IOS_LAUNCH_PROFILE, separators=(",", ":"))])
        self.assertNotIn("isRunningUITests", command)
        self.assertEqual(launched["launchProfile"], {"merged": runtime.IOS_LAUNCH_PROFILE,
                                                     "result": "LAUNCH_PROFILE_APPLIED keys=internalUser"})
        self.assertTrue(instance.stop()["stopped"])
        self.assertTrue(instance.stop()["alreadyStopped"])
        self.assertEqual([s["udid"] for s in self.tools.simulators], ["USER-SIM"])
        self.assertFalse(self.tools.processes)

    def test_simulator_snapshots_are_collected_incrementally_from_the_owned_app(self):
        instance = self.make_runtime()
        instance.snapshots_enabled = True
        instance.evidence.mkdir()
        instance.build()
        instance.launch()
        _, options = next((c, o) for c, o in self.tools.calls if c[:3] == ["xcrun", "simctl", "launch"])
        self.assertEqual(options["env"]["SIMCTL_CHILD_PIR_DEBUG_SNAPSHOTS"], "1")
        self.assertNotIn("SIMCTL_CHILD_PIR_DEBUG_SNAPSHOT_DIRECTORY", options["env"])
        directory = self.root / "SimulatorDevices" / OWNED_SIM / "app-data/tmp" / f"pir-snapshots-{instance.instance}"
        instance.collect_snapshots()
        directory.mkdir(parents=True)
        name = "00000001-scan-extract-before.png"
        (directory / name).write_bytes(b"first")
        (directory / ".in-progress.png").write_bytes(b"partial")
        (directory / "linked.png").symlink_to(directory / name)
        instance.collect_snapshots()
        evidence = instance.evidence / "snapshots"
        self.assertEqual([p.name for p in evidence.iterdir()], [name])
        self.assertEqual((evidence / name).read_bytes(), b"first")
        missing = "00000002-scan-extract-result.unavailable"
        (directory / missing).write_text("Timed out")
        instance.collect_snapshots()
        self.assertEqual((evidence / missing).read_text(), "Timed out")
        instance.stop()

    def test_mac_agent_writes_snapshots_to_the_attempt_directly(self):
        instance = self.make_runtime("macos")
        instance.evidence.mkdir()
        instance.snapshots_enabled = True
        instance.build()
        instance.launch()
        command, options = next((c, o) for c, o in self.tools.calls if c[0].endswith("Contents/MacOS/PIRAgent"))
        self.assertEqual(command[1:6], ["isRunningUITests", "-ff.dbpCustomWebViewUserAgent", "true",
                                        "-ff.dbpExtractedProfileRefresh", "true"])
        self.assertNotIn("-launchProfile", command)
        self.assertEqual(options["env"]["PIR_DEBUG_SNAPSHOTS"], "1")
        destination = Path(options["env"]["PIR_DEBUG_SNAPSHOT_DIRECTORY"])
        self.assertEqual(destination, instance.evidence / "snapshots")
        self.assertTrue(destination.is_dir())
        instance.collect_snapshots()
        instance.stop()

    def test_supplied_token_is_only_in_native_launch_environment_on_both_platforms(self):
        token = "private-launch-credential"
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform):
                instance = self.make_runtime(platform, pir_environment="staging")
                build = instance.build()
                with patch.dict(os.environ, {"PIR_DEBUG_ACCESS_TOKEN": "unrelated-parent-secret",
                                             "SIMCTL_CHILD_PIR_DEBUG_ACCESS_TOKEN": "unrelated-child-secret"}):
                    launched = instance.launch(access_token=token)
                command, options = next((c, o) for c, o in reversed(self.tools.calls)
                                        if c[:3] == ["xcrun", "simctl", "launch"] or c[0].endswith("Contents/MacOS/PIRAgent"))
                key = "SIMCTL_CHILD_PIR_DEBUG_ACCESS_TOKEN" if platform == "ios" else "PIR_DEBUG_ACCESS_TOKEN"
                self.assertEqual(options["env"][key], token)
                self.assertNotIn(token, " ".join(command))
                self.assertNotIn("unrelated-parent-secret", str(options))
                self.assertNotIn("unrelated-child-secret", str(options))
                for metadata in (build, launched, json.loads(instance.state.read_text())):
                    self.assertNotIn(token, json.dumps(metadata))
                instance.stop()

    def test_invalid_supplied_token_is_rejected_before_native_launch(self):
        instance = self.make_runtime()
        for token in ("", "white space", "control\x00", "a" * 65_537):
            with self.subTest(token_length=len(token)), self.assertRaisesRegex(runtime.RuntimeError, "Invalid supplied PIR credential"):
                instance.launch(access_token=token)
        self.assertFalse(any(c[:3] == ["xcrun", "simctl", "launch"] for c, _ in self.tools.calls))

    def test_keep_stops_app_and_preserves_simulator(self):
        instance = self.make_runtime(keep=True)
        instance.build()
        instance.launch()
        self.assertTrue(instance.stop()["simulatorKept"])
        self.assertFalse(self.tools.processes)
        self.assertEqual(len(self.tools.simulators), 2)
        self.assertFalse(any(c[:3] == ["xcrun", "simctl", "delete"] for c, _ in self.tools.calls))

    def test_changed_source_requires_rebuild_before_device_work(self):
        for platform, path in (("ios", "iOS/input.swift"), ("ios", "iOS/new.swift"), ("macos", "macOS/LocalOverrides.xcconfig")):
            with self.subTest(path=path):
                instance = self.make_runtime(platform)
                instance.build()
                source = self.root / path
                original = source.read_text() if source.exists() else None
                source.write_text("OTHER_SETTING = changed\n")
                checkpoint = len(self.tools.calls)
                with self.assertRaisesRegex(runtime.RuntimeError, "Source differs"):
                    instance.launch()
                self.assertFalse(any(c[:2] == ["xcrun", "simctl"] for c, _ in self.tools.calls[checkpoint:]))
                instance.stop()
                source.unlink() if original is None else source.write_text(original)

    def test_commit_with_uninitialized_submodule_keeps_build_current(self):
        git = ["git", "-C", str(self.root), "-c", "user.name=test", "-c", "user.email=test@example.com"]
        (self.root / "iOS/submodule").mkdir()
        REAL_RUN([*git, "update-index", "--add", "--cacheinfo", f"160000,{'1' * 40},iOS/submodule"], check=True)
        REAL_RUN([*git, "commit", "-q", "-m", "base"], check=True)
        instance = self.make_runtime()
        instance.build()
        REAL_RUN([*git, "commit", "-q", "--allow-empty", "-m", "unrelated"], check=True)
        instance.launch()
        instance.stop()

    def test_changed_executable_requires_rebuild(self):
        instance = self.make_runtime()
        metadata = instance.build()
        Path(metadata["product"]["executable"]).write_bytes(b"foreign binary")
        with self.assertRaisesRegex(runtime.RuntimeError, "product changed"):
            instance.launch()
        self.assertEqual(len(self.tools.simulators), 1)
        instance.stop()

    def test_source_edit_during_build_invalidates_previous_record(self):
        instance = self.make_runtime()
        instance.build()
        self.tools.source_changes_during_build = True
        with self.assertRaisesRegex(runtime.RuntimeError, "Source changed during"):
            instance.build()
        self.assertFalse(instance.state.exists())

    def test_scheduler_launch_uses_verified_browser_and_keeps_profile_out_of_arguments(self):
        instance = self.make_runtime("macos")
        instance.evidence.mkdir()
        instance.build()
        fixture = '{"synthetic":"fixture"}'
        lock = Path(self.directory.name) / "scheduler.lock"
        with patch.object(runtime, "SCHEDULER_LOCK", lock):
            launched = instance.launch_scheduler("seed", fixture)
            argv, options = next((argv, options) for argv, options in self.tools.calls
                                 if argv == [launched["product"]["browserExecutable"]])
            self.assertEqual(len(argv), 1)
            self.assertEqual(options["env"]["PIR_PROFILE_JSON"], fixture)
            self.assertEqual(options["env"]["PIR_SCHEDULER_MODE"], "seed")
            self.assertEqual(options["env"]["PIR_SCHEDULER_INSTANCE_ID"], instance.instance)
            self.assertNotIn("PIR_DEBUG_SERVER", options["env"])
            self.assertNotIn("PIR_SCHEDULER_BROKERS", options["env"])
            receipt = Path(options["env"]["PIR_SCHEDULER_RECEIPT"])
            receipt.write_text(json.dumps({"status": "ready"}))
            self.assertEqual(instance.scheduler_receipt()["status"], "ready")
            self.assertTrue(instance.stop()["stopped"])
            self.assertFalse(self.tools.processes)

    def test_macos_scheduler_ignores_a_running_ios_simulator_app_with_the_same_executable_name(self):
        instance = self.make_runtime("macos")
        instance.evidence.mkdir()
        build = instance.build()
        simulator_app = Path(self.directory.name) / "SimulatorApp" / "DuckDuckGo.app"
        FakeTools.write_bundle(simulator_app, {"CFBundleIdentifier": runtime.BUNDLES["ios"],
                                          "CFBundleExecutable": Path(build["product"]["browserExecutable"]).name}, False)
        self.tools.processes[701] = str(simulator_app / Path(build["product"]["browserExecutable"]).name)
        with patch.object(runtime, "SCHEDULER_LOCK", Path(self.directory.name) / "scheduler.lock"):
            launched = instance.launch_scheduler("seed", "{}")
        self.assertTrue(any(argv == [launched["product"]["browserExecutable"]] for argv, _ in self.tools.calls))
        self.tools.processes.pop(701)
        instance.stop()

    def test_scheduler_launch_passes_seed_brokers_in_the_environment(self):
        instance = self.make_runtime("macos")
        instance.evidence.mkdir()
        instance.build()
        with patch.object(runtime, "SCHEDULER_LOCK", Path(self.directory.name) / "scheduler.lock"):
            launched = instance.launch_scheduler("seed", "{}", ("a.com", "b.com"))
            _, options = next((argv, options) for argv, options in self.tools.calls
                              if argv == [launched["product"]["browserExecutable"]])
            self.assertEqual(json.loads(options["env"]["PIR_SCHEDULER_BROKERS"]), ["a.com", "b.com"])
        instance.stop()

    def test_ios_scheduler_launch_uses_its_own_simulator_port_and_container_receipt(self):
        instance = self.make_runtime("ios", device="ipad")
        instance.evidence.mkdir()
        instance.build()
        fixture = '{"synthetic":"fixture"}'
        lock = Path(self.directory.name) / "scheduler.lock"
        with patch.object(runtime, "SCHEDULER_LOCK", lock), lock.open("w") as held:
            runtime.fcntl.flock(held, runtime.fcntl.LOCK_EX)
            launched = instance.launch_scheduler("reseed", fixture)
        self.assertEqual(launched["simulator"]["udid"], OWNED_SIM)
        self.assertIn("ddg-check-pir-ipad-", launched["simulator"]["name"])
        command, options = next((c, o) for c, o in self.tools.calls if c[:3] == ["xcrun", "simctl", "launch"])
        self.assertNotIn(fixture, command)
        self.assertEqual(json.loads(command[command.index("-launchProfile") + 1]), runtime.IOS_LAUNCH_PROFILE)
        env = options["env"]
        self.assertEqual(env["SIMCTL_CHILD_PIR_PROFILE_JSON"], fixture)
        self.assertEqual(env["SIMCTL_CHILD_PIR_SCHEDULER_MODE"], "reseed")
        self.assertEqual(env["SIMCTL_CHILD_PIR_DEBUG_PORT"], str(instance.port))
        self.assertEqual(env["SIMCTL_CHILD_PIR_DEBUG_INSTANCE_ID"], instance.instance)
        self.assertNotIn("SIMCTL_CHILD_PIR_DEBUG_SERVER", env)
        receipt = Path(env["SIMCTL_CHILD_PIR_SCHEDULER_RECEIPT"])
        self.assertEqual(receipt.parent, self.root / "SimulatorDevices" / OWNED_SIM / "app-data" / "tmp")
        receipt.write_text(json.dumps({"status": "ready"}))
        self.assertEqual(instance.scheduler_receipt()["status"], "ready")
        self.assertEqual(json.loads((instance.evidence / "scheduler-launch.json").read_text()), {"status": "ready"})
        self.assertTrue(instance.stop()["stopped"])
        self.assertEqual([s["udid"] for s in self.tools.simulators], ["USER-SIM"])
        self.assertFalse(self.tools.processes)

    def test_ios_scheduler_reports_an_app_that_exits_before_its_receipt(self):
        instance = self.make_runtime("ios")
        instance.evidence.mkdir()
        instance.build()
        instance.launch_scheduler("seed", "{}")
        self.tools.processes.pop(412)
        with self.assertRaisesRegex(runtime.RuntimeError, "exited before reporting"):
            instance.scheduler_receipt()
        instance.stop()

    def test_scheduler_refuses_a_changed_browser_or_an_existing_debug_browser(self):
        instance = self.make_runtime("macos")
        build = instance.build()
        browser = Path(build["product"]["browserExecutable"])
        self.tools.processes[700] = str(browser)
        with patch.object(runtime, "SCHEDULER_LOCK", Path(self.directory.name) / "scheduler.lock"):
            with self.assertRaisesRegex(runtime.RuntimeError, "DEBUG browser is already running"):
                instance.launch_scheduler("reseed", "{}")
        self.assertIn(700, self.tools.processes)
        instance.stop()
        self.tools.processes.clear()
        attempt = self.make_runtime("macos")
        browser.write_bytes(b"changed browser binary")
        with self.assertRaisesRegex(runtime.RuntimeError, "build product changed"):
            attempt.launch_scheduler("reseed", "{}")
        attempt.stop()

    def test_failed_native_readiness_still_cleans_owned_launch(self):
        for platform in ("ios", "macos"):
            with self.subTest(platform=platform):
                instance = self.make_runtime(platform)
                instance.build()
                self.ready.side_effect = runtime.RuntimeError("wrong native instance")
                with self.assertRaisesRegex(runtime.RuntimeError, "wrong native instance"):
                    instance.launch()
                instance.stop()
                self.assertFalse(self.tools.processes)
                self.assertEqual(len(self.tools.simulators), 1)

    def test_pid_reuse_refuses_process_and_simulator_cleanup(self):
        instance = self.make_runtime()
        instance.build()
        instance.launch()
        self.tools.processes[412] = "/Applications/User.app/Contents/MacOS/User"
        with self.assertRaisesRegex(runtime.RuntimeError, "ownership changed"):
            instance.stop()
        self.assertIn(412, self.tools.processes)
        self.assertEqual(len(self.tools.simulators), 2)
        self.assertFalse(any(c[:3] == ["xcrun", "simctl", "terminate"] for c, _ in self.tools.calls))

    def test_renamed_simulator_refuses_control(self):
        instance = self.make_runtime()
        instance.build()
        instance.launch()
        self.tools.simulators[-1]["name"] = "User adopted simulator"
        with self.assertRaisesRegex(runtime.RuntimeError, "Simulator ownership changed"):
            instance.stop()
        self.assertIn(412, self.tools.processes)

    def test_macos_enables_toggle_before_settings_and_build_then_launches_embedded_agent(self):
        instance = self.make_runtime("macos", pir_environment="staging")
        instance.build()
        commands = [c for c, _ in self.tools.calls]
        toggle = next(i for i, c in enumerate(commands) if c[0] == "sh")
        settings = next(i for i, c in enumerate(commands) if "-showBuildSettings" in c)
        build = next(i for i, c in enumerate(commands) if c[0] == "xcodebuild" and c[-1] == "build")
        self.assertLess(toggle, settings)
        self.assertLess(settings, build)
        self.assertIn("UNRELATED_SETTING = preserve", (self.root / "macOS/LocalOverrides.xcconfig").read_text())
        with patch.dict(os.environ, {"PRIVATE_SERVICE_TOKEN": "never-pass-to-native"}):
            launched = instance.launch()
        command, options = next((c, o) for c, o in self.tools.calls if c[0].endswith("Contents/MacOS/PIRAgent"))
        self.assertIn("Contents/Library/LoginItems/PIR.app/Contents/MacOS/PIRAgent", command[0])
        self.assertEqual(options["env"]["PIR_DEBUG_INSTANCE_ID"], instance.instance)
        self.assertEqual(options["env"]["PIR_DEBUG_ENVIRONMENT"], "staging")
        self.assertNotIn("PRIVATE_SERVICE_TOKEN", options["env"])
        self.assertEqual(command[command.index("-pirDebugPort") + 1], str(instance.port))
        self.assertEqual(launched["product"]["browserPath"], str((self.root / "DerivedData/ddg-check-pir/macos/deployment/Applications/DEBUG/DuckDuckGo.app").resolve()))
        instance.stop()
        self.assertFalse(self.tools.processes)

    def test_deployed_debug_browser_blocks_rebuild_before_replacing_binary(self):
        instance = self.make_runtime("macos")
        app = self.tools.materialize(True)
        self.tools.processes[999] = str(app / "Contents/MacOS/DuckDuckGo")
        with self.assertRaisesRegex(runtime.RuntimeError, "deployed DEBUG browser or agent is running.*launchctl bootout gui/"):
            instance.build()
        self.assertFalse(any(c[0] == "xcodebuild" and c[-1] == "build" for c, _ in self.tools.calls))
        self.assertIn(999, self.tools.processes)

    def test_global_debug_agent_can_coexist_with_private_standalone_agent(self):
        instance = self.make_runtime("macos")
        global_agent = self.agent_bundle(runtime.BUNDLES["macos"])
        self.tools.processes[999] = str(global_agent)
        instance.build()
        instance.launch()
        instance.stop()
        self.assertEqual(self.tools.processes, {999: str(global_agent)})

    def test_unrelated_inaccessible_process_is_skipped_in_build_inventory(self):
        instance = self.make_runtime("macos")
        self.tools.extra_pids = [123]
        instance.build()
        self.assertTrue(instance.state.is_file())

    def test_build_lock_prevents_overwrite_during_run(self):
        instance = self.make_runtime()
        instance.build()
        instance.launch()
        other = self.make_runtime()
        with self.assertRaisesRegex(runtime.RuntimeError, "Another PIR run"):
            other.build()
        instance.stop()
        other.build()

    def test_busy_port_is_refused_before_creating_simulator(self):
        instance = self.make_runtime()
        instance.build()
        self.socket.return_value.__enter__.return_value.bind.side_effect = OSError("in use")
        with self.assertRaisesRegex(runtime.RuntimeError, "port is unavailable"):
            instance.launch()
        instance.stop()
        self.assertEqual(len(self.tools.simulators), 1)

    def test_native_readiness_correlates_request_and_launch(self):
        instance = self.make_runtime()
        instance.build()
        instance.launch()
        seen = []

        def response(request, timeout):
            seen.append(request)
            query = urllib.parse.parse_qs(urllib.parse.urlparse(request.full_url).query)
            check_id = query["checkID"][0]
            uuid.UUID(check_id)
            return io.StringIO(json.dumps({"instanceID": instance.instance, "checkID": check_id, "debugRunnerReady": True}))

        with patch.object(runtime.urllib.request, "build_opener") as opener:
            opener.return_value.open.side_effect = response
            REAL_READY(instance)
        self.assertEqual(len(seen), 1)
        self.assertEqual(seen[0].get_header("X-pir-debug-instance"), instance.instance)
        instance.stop()

    def test_stale_prerequisite_reply_is_rejected(self):
        instance = self.make_runtime()
        instance.build()
        instance.launch()
        with patch.object(runtime.urllib.request, "build_opener") as opener:
            opener.return_value.open.return_value = io.StringIO(json.dumps({
                "instanceID": instance.instance, "checkID": str(uuid.uuid4()), "debugRunnerReady": True}))
            with self.assertRaisesRegex(runtime.RuntimeError, "did not match"):
                REAL_READY(instance)
        instance.stop()

    def test_apple_tool_failure_reports_private_diagnostic_path(self):
        instance = self.make_runtime()
        self.tools.fail_build = True
        with self.assertRaises(runtime.RuntimeError) as caught:
            instance.build()
        self.assertIn("xcodebuild failed with exit 1", str(caught.exception))
        self.assertTrue(Path(caught.exception.log_path).is_file())
        self.assertIn("BUILD FAILED", Path(caught.exception.log_path).read_text())
        self.assertEqual(Path(caught.exception.log_path).stat().st_mode & 0o777, 0o600)
        self.assertNotIn("BUILD FAILED", str(caught.exception))

    def test_created_simulator_survives_inventory_failure_for_owned_cleanup(self):
        instance = self.make_runtime()
        instance.build()
        with patch.object(instance, "_verify_simulator", side_effect=runtime.RuntimeError("inventory unavailable")):
            with self.assertRaisesRegex(runtime.RuntimeError, "inventory unavailable"):
                instance.launch()
        self.assertEqual(instance.simulator["udid"], OWNED_SIM)
        instance.stop()
        self.assertEqual(len(self.tools.simulators), 1)

    def test_failed_simulator_launch_after_start_retains_pid_for_keep_cleanup(self):
        instance = self.make_runtime(keep=True)
        instance.build()
        self.tools.fail_launch_after_start = True
        with self.assertRaisesRegex(runtime.RuntimeError, "xcrun failed with exit 1"):
            instance.launch()
        self.assertEqual(instance.identity["pid"], 412)
        instance.stop()
        self.assertFalse(self.tools.processes)
        self.assertEqual(len(self.tools.simulators), 2)

    def test_macos_child_that_exits_at_start_is_reaped_and_cleanup_succeeds(self):
        instance = self.make_runtime("macos")
        instance.build()
        self.tools.exit_on_start = True
        with self.assertRaisesRegex(runtime.RuntimeError, "process exited"):
            instance.launch()
        self.assertEqual(instance.app["pid"], 412)
        instance.stop()
        self.assertFalse(self.tools.processes)
        runtime.os.kill.assert_not_called()

    def test_build_destination_prefers_requested_device_and_is_reused(self):
        self.tools.simulators += [{"udid": "IPAD-SIM", "name": "My tablet", "state": "Shutdown",
                                   "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro"}]
        instance = self.make_runtime(device="ipad")
        instance.build()
        destinations = [c[c.index("-destination") + 1] for c, _ in self.tools.calls if c[0] == "xcodebuild"]
        self.assertEqual(destinations, ["platform=iOS Simulator,id=IPAD-SIM"] * 2)
        inventory = [c for c, _ in self.tools.calls if c[:3] == ["xcrun", "simctl", "list"]]
        self.assertEqual(len(inventory), 1)

    def test_build_fails_clearly_without_an_available_ios_simulator(self):
        self.tools.simulators = []
        instance = self.make_runtime()
        with self.assertRaisesRegex(runtime.RuntimeError, "No available iOS simulator"):
            instance.build()
        self.assertFalse(any(c[0] == "xcodebuild" for c, _ in self.tools.calls))

    def test_simulator_launch_timeout_preserves_pid_for_keep_cleanup(self):
        instance = self.make_runtime(keep=True)
        instance.build()
        self.tools.timeout_launch = True
        with self.assertRaisesRegex(runtime.RuntimeError, "xcrun timed out") as caught:
            instance.launch()
        self.assertEqual(instance.identity["pid"], 412)
        self.assertIn(": 412", caught.exception._diagnostics["stdout"])
        self.assertEqual(caught.exception._diagnostics["stderr"], "private timeout detail")
        self.assertNotIn("private timeout detail", str(caught.exception))
        instance.stop()
        self.assertFalse(self.tools.processes)
        self.assertEqual(len(self.tools.simulators), 2)
        self.assertEqual(self.tools.simulators[-1]["state"], "Booted")

    def test_unknown_pid_timeout_shuts_down_owned_simulator_even_when_kept(self):
        instance = self.make_runtime(keep=True)
        instance.build()
        self.tools.timeout_launch_without_pid = True
        with self.assertRaisesRegex(runtime.RuntimeError, "xcrun timed out"):
            instance.launch()
        self.assertIsNone(instance.app)
        self.assertIn(412, self.tools.processes)
        self.assertTrue(instance.stop()["simulatorKept"])
        self.assertFalse(self.tools.processes)
        self.assertEqual(len(self.tools.simulators), 2)
        self.assertEqual(self.tools.simulators[-1]["state"], "Shutdown")
        shutdown = [c for c, _ in self.tools.calls if c[:3] == ["xcrun", "simctl", "shutdown"]]
        self.assertEqual(shutdown, [["xcrun", "simctl", "shutdown", OWNED_SIM]])

    def test_unknown_pid_cleanup_refuses_renamed_simulator(self):
        instance = self.make_runtime(keep=True)
        instance.build()
        self.tools.timeout_launch_without_pid = True
        with self.assertRaises(runtime.RuntimeError):
            instance.launch()
        self.tools.simulators[-1]["name"] = "User adopted simulator"
        with self.assertRaisesRegex(runtime.RuntimeError, "Simulator ownership changed"):
            instance.stop()
        self.assertIn(412, self.tools.processes)
        self.assertFalse(any(c[:3] == ["xcrun", "simctl", "shutdown"] for c, _ in self.tools.calls))

    def test_successful_stop_removes_only_instance_raw_logs(self):
        instance = self.make_runtime()
        instance.build()
        instance.launch()
        instance.stdout.write_text("private native output")
        instance.stderr.write_text("private native error")
        other_log = instance.base / "native-other-instance.stdout.log"
        other_log.write_text("preserve another run")
        instance.stop()
        self.assertFalse(instance.stdout.exists())
        self.assertFalse(instance.stderr.exists())
        self.assertEqual(other_log.read_text(), "preserve another run")

    def test_private_deployment_override_is_used_for_settings_and_build(self):
        instance = self.make_runtime("macos")
        metadata = instance.build()
        commands = [command for command, _ in self.tools.calls if command[0] == "xcodebuild"]
        self.assertEqual(len(commands), 2)
        for command in commands:
            self.assertIn("DSTROOT=" + str(instance.deployment), command)
        self.assertTrue(Path(metadata["product"]["browserPath"]).is_relative_to(instance.deployment))

    def test_old_global_deployment_build_metadata_is_rejected_before_launch(self):
        instance = self.make_runtime("macos")
        metadata = instance.build()
        metadata["settings"]["TARGET_BUILD_DIR"] = "/Applications/DEBUG"
        instance.state.write_text(json.dumps(metadata))
        with self.assertRaisesRegex(runtime.RuntimeError, "outside the private deployment root"):
            instance.launch()
        instance.stop()
        self.assertIsNone(self.tools.child)

    def test_mac_build_prepares_private_applications_link_before_deployment_phase(self):
        instance = self.make_runtime("macos")
        metadata = instance.build()
        link = Path(metadata["settings"]["BUILT_PRODUCTS_DIR"]) / "Applications"
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), instance.deployment / "Applications")
        self.assertNotEqual(link.resolve(), Path("/Applications"))

    def test_legacy_global_applications_symlink_is_replaced_without_touching_target(self):
        instance = self.make_runtime("macos")
        products = instance.derived / "Build/Products/Debug"
        products.mkdir(parents=True)
        link = products / "Applications"
        link.symlink_to("/Applications", target_is_directory=True)
        instance.build()
        self.assertEqual(link.resolve(), instance.deployment / "Applications")

    def test_real_applications_directory_is_preserved_and_build_refused(self):
        instance = self.make_runtime("macos")
        directory = instance.derived / "Build/Products/Debug/Applications"
        directory.mkdir(parents=True)
        sentinel = directory / "unrelated.txt"
        sentinel.write_text("preserve")
        with self.assertRaisesRegex(runtime.RuntimeError, "Applications is a real directory"):
            instance.build()
        self.assertEqual(sentinel.read_text(), "preserve")
        self.assertFalse(any(c[0] == "xcodebuild" and c[-1] == "build" for c, _ in self.tools.calls))

    def test_external_products_directory_is_refused_before_link_creation(self):
        instance = self.make_runtime("macos")
        self.tools.products_override = self.root / "outside-derived"
        with self.assertRaisesRegex(runtime.RuntimeError, "outside isolated DerivedData"):
            instance.build()
        self.assertFalse((self.tools.products_override / "Applications").exists())

    def test_private_applications_alias_to_global_is_refused(self):
        instance = self.make_runtime("macos")
        instance.deployment.mkdir(parents=True)
        (instance.deployment / "Applications").symlink_to("/Applications", target_is_directory=True)
        with self.assertRaisesRegex(runtime.RuntimeError, "Private Applications points outside"):
            instance.build()
        self.assertTrue((instance.deployment / "Applications").is_symlink())
        self.assertFalse(any(c[0] == "xcodebuild" and c[-1] == "build" for c, _ in self.tools.calls))

    def test_user_launch_profile_is_merged_over_the_base_profile(self):
        instance = self.make_runtime(launch_profile={"onboardingCompleted": False, "featureFlags": {"x": True},
                                                     "featureFlags.y": False, "internalUser": True})
        instance.build()
        launched = instance.launch()
        command = next(c for c, _ in self.tools.calls if c[:3] == ["xcrun", "simctl", "launch"])
        expected = {**runtime.IOS_LAUNCH_PROFILE, "onboardingCompleted": False, "featureFlags.x": True, "featureFlags.y": False}
        self.assertEqual(json.loads(command[command.index("-launchProfile") + 1]), expected)
        self.assertNotIn("isRunningUITests", command)
        self.assertEqual(launched["launchProfile"]["merged"], expected)
        instance.stop()

    def test_rejected_or_missing_launch_profile_line_stops_before_the_runner_and_keeps_cleanup(self):
        for log, message in (("[LaunchProfile] LAUNCH_PROFILE_FAILED Unknown key \"featureFlags.x\".\n",
                              'LAUNCH_PROFILE_FAILED Unknown key "featureFlags.x".'),
                             ("", "no LAUNCH_PROFILE_ line")):
            with self.subTest(message=message), patch.object(runtime, "LAUNCH_PROFILE_TIMEOUT", 0):
                self.tools.launch_profile_log = log
                instance = self.make_runtime()
                instance.build()
                with self.assertRaisesRegex(runtime.RuntimeError, message):
                    instance.launch()
                self.ready.assert_not_called()
                self.assertEqual(instance.identity["pid"], 412)
                self.assertTrue(instance.stop()["stopped"])
                self.assertFalse(self.tools.processes)

    def test_no_new_launch_for_missing_build(self):
        instance = self.make_runtime()
        with self.assertRaisesRegex(runtime.RuntimeError, "No recorded PIR build"):
            instance.launch()
        instance.stop()
        self.assertEqual(len(self.tools.simulators), 1)


class LaunchProfileTests(unittest.TestCase):
    def test_base_profile_applies_without_a_user_profile(self):
        self.assertEqual(runtime.ios_launch_profile(), runtime.IOS_LAUNCH_PROFILE)

    def test_nested_and_dotted_user_keys_override_the_base(self):
        merged = runtime.ios_launch_profile({"onboardingCompleted": False, "featureFlags": {"a": True, "b": {}},
                                             "settings.theme": "dark"})
        self.assertEqual(merged, {**runtime.IOS_LAUNCH_PROFILE, "onboardingCompleted": False, "featureFlags.a": True,
                                  "featureFlags.b": {}, "settings.theme": "dark"})

    def test_required_entries_and_tabs_are_rejected(self):
        for profile, message in (([], "JSON object"),
                                 ({"internalUser": False}, "internalUser true"),
                                 ({"featureFlags": {"dbpCustomWebViewUserAgent": False}}, "dbpCustomWebViewUserAgent true"),
                                 ({"featureFlags.dbpExtractedProfileRefresh": 1}, "dbpExtractedProfileRefresh true"),
                                 ({"tabs": ["https://example.com"]}, "tabs"),
                                 ({"tabs": {"x": 1}}, "tabs")):
            with self.subTest(profile=profile), self.assertRaisesRegex(ValueError, message):
                runtime.ios_launch_profile(profile)


if __name__ == "__main__":
    unittest.main()
