from __future__ import annotations

import builtins
import ctypes
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import socket
import stat
import subprocess
import time
import urllib.request
import uuid


class RuntimeError(builtins.RuntimeError):
    def __init__(self, message, *, stdout="", stderr="", log_path=None):
        super().__init__(f"{message}; diagnostic: {log_path}" if log_path else message)
        self._diagnostics = {"stdout": stdout[-16384:], "stderr": stderr[-16384:]}
        self.log_path = str(log_path) if log_path else None


BUNDLES = {"ios": "com.duckduckgo.mobile.ios",
           "macos": "com.duckduckgo.macos.DBP.backgroundAgent.debug"}
BROWSER_BUNDLE = "com.duckduckgo.macos.browser.debug"
SCHEDULER_LOCK = Path(f"/tmp/ddg-check-pir-scheduler-{os.getuid()}.lock")
SCHEDULER_SETUP_TIMEOUT = 180
MACOS_FLAG_ARGUMENTS = ["isRunningUITests", "-ff.dbpCustomWebViewUserAgent", "true",
                        "-ff.dbpExtractedProfileRefresh", "true"]
IOS_LAUNCH_PROFILE = {"internalUser": True, "onboardingCompleted": True,
                      "featureFlags.dbpCustomWebViewUserAgent": True, "featureFlags.dbpExtractedProfileRefresh": True}
REQUIRED_LAUNCH_PROFILE_KEYS = ("internalUser", "onboardingCompleted", "featureFlags.dbpCustomWebViewUserAgent",
                                "featureFlags.dbpExtractedProfileRefresh")
LAUNCH_PROFILE_PREFIX = "LAUNCH_PROFILE_"
LAUNCH_PROFILE_TIMEOUT = 60


def _flatten(profile, prefix=""):
    flat = {}
    for key, value in profile.items():
        if isinstance(value, dict) and value:
            flat.update(_flatten(value, f"{prefix}{key}."))
        else:
            flat[prefix + key] = value
    return flat


def ios_launch_profile(profile=None):
    """The base iOS launch profile updated by `profile`, as dotted keys."""
    if profile is None:
        profile = {}
    if not isinstance(profile, dict):
        raise ValueError("The launch profile must be a JSON object")
    flat = _flatten(profile)
    for key, value in flat.items():
        if key == "tabs" or key.startswith("tabs."):
            raise ValueError("The launch profile must not set tabs")
        if key in REQUIRED_LAUNCH_PROFILE_KEYS and value is not True:
            raise ValueError(f"The launch profile must keep {key} true; PIR runs need it")
    return {**IOS_LAUNCH_PROFILE, **flat}


def _run(command, root, timeout=120, *, env=None, log_path=None):
    command = list(map(str, command))
    try:
        result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or "", error.stderr or ""
        stdout = stdout.decode(errors="replace") if isinstance(stdout, bytes) else stdout
        stderr = stderr.decode(errors="replace") if isinstance(stderr, bytes) else stderr
        if log_path:
            with os.fdopen(os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as stream:
                stream.write(stdout + "\n" + stderr)
        raise RuntimeError(f"{Path(command[0]).name} timed out after {timeout}s", stdout=stdout,
                           stderr=stderr, log_path=log_path) from error
    except OSError as error:
        raise RuntimeError(f"Unable to execute {command[0]}: {type(error).__name__}", log_path=log_path) from error
    if log_path:
        with os.fdopen(os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as stream:
            stream.write(result.stdout + "\n" + result.stderr)
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name} failed with exit {result.returncode}",
                           stdout=result.stdout, stderr=result.stderr, log_path=log_path)
    return result.stdout


def _json(text):
    try:
        return json.loads(text)
    except ValueError as error:
        raise RuntimeError("Apple tool returned invalid JSON") from error


def _sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


_libproc = None


def _pidpath(pid):
    global _libproc
    if _libproc is None:
        _libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        _libproc.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        _libproc.proc_pidpath.restype = ctypes.c_int
    buffer = ctypes.create_string_buffer(4096)
    return os.fsdecode(buffer.value) if _libproc.proc_pidpath(pid, buffer, len(buffer)) > 0 else None


def _process(pid, timeout=5):
    executable = _pidpath(pid)
    if executable is None:
        return None
    result = subprocess.run(["ps", "-p", str(pid), "-o", "lstart="], capture_output=True, text=True, timeout=timeout)
    if result.returncode or not result.stdout.strip():
        return None
    return {"pid": int(pid), "started": result.stdout.strip(), "executable": executable}


def _info(bundle, platform="macos"):
    with (bundle / ("Info.plist" if platform == "ios" else "Contents/Info.plist")).open("rb") as stream:
        return plistlib.load(stream)


def _child_environment():
    names = ("PATH", "HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_ALL", "SHELL", "DEVELOPER_DIR", "TOOLCHAINS")
    return {name: os.environ[name] for name in names if name in os.environ}


class Runtime:
    def __init__(self, platform, evidence: Path, instance: str, port: int,
                 device="iphone", keep=False, pir_environment="production", launch_profile=None):
        if platform not in BUNDLES or device not in ("iphone", "ipad"):
            raise RuntimeError("Unsupported platform or simulator device")
        try:
            uuid.UUID(instance)
        except (ValueError, TypeError, AttributeError) as error:
            raise RuntimeError("The launch instance must be a UUID") from error
        if type(port) is not int or not 1024 <= port <= 65535:
            raise RuntimeError("The debug port must be between 1024 and 65535")
        if pir_environment not in ("production", "staging"):
            raise RuntimeError("The PIR environment must be production or staging")
        self.root = Path(_run(["git", "rev-parse", "--show-toplevel"], Path(__file__).parent).strip()).resolve()
        self.evidence = Path(evidence).resolve()
        if self.evidence.is_relative_to(self.root):
            raise RuntimeError("Evidence must be outside the checkout")
        self.platform, self.device = platform, device
        self.instance, self.port, self.keep = instance, port, keep
        self.pir_environment = pir_environment
        self.launch_profile = ios_launch_profile(launch_profile) if platform == "ios" else None
        self.launch_profile_result = None
        self.base = self.root / "DerivedData" / "ddg-check-pir" / platform
        self.derived = self.base / "build"
        self.deployment = self.base / "deployment"
        self.state = self.base / "build.json"
        self.simulator = None
        self.app = None
        self.identity = None
        self._child = None
        self._lock = None
        self._scheduler_lock = None
        self._closed = False
        self._launch_attempted = False
        self._build_destination = None
        self.snapshots_enabled = False
        self._simulator_snapshots = None
        self._receipt = self.evidence / "scheduler-launch.json"
        self.stdout = self.base / f"native-{instance}.stdout.log"
        self.stderr = self.base / f"native-{instance}.stderr.log"

    def _acquire(self, exclusive):
        if self._lock is not None:
            raise RuntimeError("This Runtime already holds its build lock")
        self.base.mkdir(parents=True, exist_ok=True)
        self._lock = (self.base / "build.lock").open("a")
        try:
            fcntl.flock(self._lock, (fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH) | fcntl.LOCK_NB)
        except BlockingIOError as error:
            self._release()
            raise RuntimeError("Another PIR run is using this build; retry after it finishes") from error

    def _release(self):
        if self._scheduler_lock is not None:
            self._scheduler_lock.close()
            self._scheduler_lock = None
        if self._lock is not None:
            self._lock.close()
            self._lock = None

    def _source(self):
        names = _run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
                      "--", "iOS", "macOS", "SharedPackages", "DuckDuckGo.xcworkspace", "scripts"], self.root)
        inputs = set(names.split("\0")) - {""}
        inputs.add("macOS/LocalOverrides.xcconfig")
        digest = hashlib.sha256()
        for name in sorted(inputs):
            path = self.root / name
            digest.update(name.encode() + b"\0")
            if path.is_file():
                digest.update(_sha(path).encode())
            elif path.is_dir():
                top = _run(["git", "-C", str(path), "rev-parse", "--show-toplevel"], self.root).strip()
                if Path(top).resolve() == path.resolve():
                    digest.update(_run(["git", "-C", str(path), "rev-parse", "HEAD"], self.root).encode())
                else:
                    # An uninitialized submodule resolves to the superproject's HEAD, which changes on every commit.
                    digest.update(_run(["git", "ls-files", "-s", "--", name], self.root).encode())
            else:
                digest.update(b"deleted")
        return digest.hexdigest()

    def _xcode(self):
        if self._build_destination is None:
            destination = "platform=macOS"
            if self.platform == "ios":
                devices = _json(self._simctl("list", "devices", "available", "--json"))["devices"]
                available = [device for identifier, entries in devices.items() if ".iOS-" in identifier
                             for device in entries if device.get("isAvailable", True)]
                if not available:
                    self._build_destination = None
                    raise RuntimeError("No available iOS simulator is installed for the build destination")
                prefix = "iPhone" if self.device == "iphone" else "iPad"
                preferred = [device for device in available if device.get("name", "").startswith(prefix)
                             or ("SimDeviceType." + prefix) in device.get("deviceTypeIdentifier", "")]
                target = (preferred or available)[0]["udid"]
                destination = f"platform=iOS Simulator,id={target}"
            self._build_destination = destination
        command = ["xcodebuild", "-workspace", str(self.root / "DuckDuckGo.xcworkspace"), "-scheme",
                "iOS Browser" if self.platform == "ios" else "macOS Browser", "-configuration", "Debug",
                "-destination", self._build_destination,
                "-derivedDataPath", str(self.derived)]
        if self.platform == "macos":
            command.append(f"DSTROOT={self.deployment}")
        return command

    def _browser_path(self, settings):
        browser = (Path(settings["TARGET_BUILD_DIR"]) / settings["FULL_PRODUCT_NAME"]).resolve()
        if self.platform == "macos":
            private = self.deployment.resolve()
            if not private.is_relative_to(self.base.resolve()) or not browser.is_relative_to(private):
                raise RuntimeError("The DEBUG browser points outside the private deployment root")
        return browser

    def _settings(self):
        log = self.base / f"build-settings-{self.instance}.log"
        output = _run([*self._xcode(), "-showBuildSettings", "-json"], self.root, 600, log_path=log)
        expected = BUNDLES["ios"] if self.platform == "ios" else BROWSER_BUNDLE
        candidates = [entry["buildSettings"] for entry in _json(output)
                      if entry.get("buildSettings", {}).get("PRODUCT_BUNDLE_IDENTIFIER") == expected]
        if len(candidates) != 1:
            raise RuntimeError("Build settings did not identify one DEBUG browser product", log_path=log)
        settings = candidates[0]
        if self.platform == "macos" and settings.get("DEPLOYMENT_LOCATION") != "YES":
            raise RuntimeError("The macOS DEBUG deployment toggle did not take effect", log_path=log)
        selected = {key: settings[key] for key in ("TARGET_BUILD_DIR", "FULL_PRODUCT_NAME", "PRODUCT_BUNDLE_IDENTIFIER", "BUILT_PRODUCTS_DIR")}
        if self.platform == "macos":
            self._prepare_deployment(selected)
        self._browser_path(selected)
        return selected

    def _prepare_deployment(self, settings):
        products = Path(settings["BUILT_PRODUCTS_DIR"]).resolve()
        private = self.deployment.resolve()
        if not self.derived.resolve().is_relative_to(self.base.resolve()) or not products.is_relative_to(self.derived.resolve()):
            raise RuntimeError("Built products point outside isolated DerivedData")
        if not private.is_relative_to(self.base.resolve()):
            raise RuntimeError("The DEBUG deployment root points outside its private cache")
        applications = (private / "Applications").resolve()
        if not applications.is_relative_to(private):
            raise RuntimeError("Private Applications points outside the deployment root")
        applications.mkdir(parents=True, exist_ok=True)
        products.mkdir(parents=True, exist_ok=True)
        link = products / "Applications"
        if link.is_symlink():
            if link.resolve() == applications:
                return
            link.unlink()
        elif link.exists():
            raise RuntimeError("Built products Applications is a real directory; refusing to replace it")
        # The project's deployment phase skips its global /Applications mutations when this link exists.
        link.symlink_to(applications, target_is_directory=True)

    def _product(self, settings):
        browser = self._browser_path(settings)
        metadata = _info(browser, self.platform)
        expected = BUNDLES["ios"] if self.platform == "ios" else BROWSER_BUNDLE
        if metadata.get("CFBundleIdentifier") != expected:
            raise RuntimeError("The built browser has the wrong bundle identity")
        product = browser
        browser_identity = {}
        if self.platform == "macos":
            executable = (browser / "Contents/MacOS" / metadata["CFBundleExecutable"]).resolve()
            if not executable.is_relative_to(browser):
                raise RuntimeError("The DEBUG browser executable points outside its app bundle")
            browser_identity = {"browserExecutable": str(executable), "browserSHA256": _sha(executable)}
            name = metadata.get("DBP_BACKGROUND_AGENT_PRODUCT_NAME")
            if not isinstance(name, str) or Path(name).name != name:
                raise RuntimeError("The DEBUG browser did not name its embedded PIR agent")
            product = (browser / "Contents/Library/LoginItems" / f"{name}.app").resolve()
            if not product.is_relative_to(browser):
                raise RuntimeError("The embedded agent points outside its DEBUG browser")
            if metadata.get("DBP_BACKGROUND_AGENT_BUNDLE_ID") != BUNDLES["macos"]:
                raise RuntimeError("The DEBUG browser has an unexpected PIR agent bundle identifier")
            metadata = _info(product)
        elif not product.is_relative_to(self.derived.resolve()):
            raise RuntimeError("The simulator product points outside isolated DerivedData")
        if metadata.get("CFBundleIdentifier") != BUNDLES[self.platform]:
            raise RuntimeError("The PIR product has the wrong bundle identity")
        executable = (product / ("" if self.platform == "ios" else "Contents/MacOS") / metadata["CFBundleExecutable"]).resolve()
        if not executable.is_relative_to(product):
            raise RuntimeError("The PIR executable points outside its app bundle")
        return {"path": str(product), "browserPath": str(browser), "bundleId": metadata["CFBundleIdentifier"],
                "executable": str(executable), "sha256": _sha(executable), **browser_identity}

    def _running_executables(self):
        identifiers = _run(["ps", "-axo", "pid="], self.root).split()
        return [Path(path) for value in identifiers if value.isdecimal() and (path := _pidpath(int(value)))]

    def build(self):
        self._acquire(True)
        try:
            if self.platform == "macos":
                _run(["sh", str(self.root / "scripts/toggle-macos-debug-deployment.sh"), "on"], self.root)
            settings = self._settings()
            if self.platform == "macos":
                browser = self._browser_path(settings)
                if any(executable.resolve().is_relative_to(browser) for executable in self._running_executables()):
                    raise RuntimeError("The deployed DEBUG browser or agent is running; refusing to replace its code. Quit the "
                                       "DEBUG browser. A scheduler seed leaves its agent registered with launchd, so stop it with "
                                       f"`launchctl bootout gui/{os.getuid()}/{BUNDLES['macos']}`")
            before = self._source()
            self.state.unlink(missing_ok=True)
            log = self.base / f"build-{self.instance}.log"
            _run([*self._xcode(), "build"], self.root, 3600, log_path=log)
            if self._source() != before:
                raise RuntimeError("Source changed during the build; rebuild before running", log_path=log)
            metadata = {"platform": self.platform, "sourceSHA256": before, "product": self._product(settings),
                        "settings": settings, "builtAt": time.time(), "root": str(self.root), "buildLog": str(log)}
            temporary = self.state.with_suffix(".tmp")
            temporary.write_text(json.dumps(metadata, indent=2) + "\n")
            temporary.replace(self.state)
            return metadata
        finally:
            self._release()

    def _simctl(self, *args, env=None, timeout=120):
        return _run(["xcrun", "simctl", *map(str, args)], self.root, timeout, env=env)

    def _simulators(self):
        devices = _json(self._simctl("list", "devices", "--json"))["devices"]
        return [device for values in devices.values() for device in values]

    def _create_simulator(self):
        runtimes = _json(self._simctl("list", "runtimes", "--json"))["runtimes"]
        runtimes = [r for r in runtimes if r.get("isAvailable") and ".iOS-" in r.get("identifier", "")]
        if not runtimes:
            raise RuntimeError("No installed iOS simulator runtime is available")
        runtime = max(runtimes, key=lambda r: tuple(int(n) for n in r["version"].split(".")))
        types = _json(self._simctl("list", "devicetypes", "--json"))["devicetypes"]
        prefix = "iPhone" if self.device == "iphone" else "iPad"
        supported = {entry["identifier"] for entry in runtime.get("supportedDeviceTypes", [])}
        choices = [entry for entry in types if entry["name"].startswith(prefix) and entry["identifier"] in supported]
        if not choices:
            raise RuntimeError(f"No {prefix} device type supports the installed runtime")
        name = f"ddg-check-pir-{self.device}-{self.instance}"
        if any(device.get("name") == name for device in self._simulators()):
            raise RuntimeError("A simulator already exists for this instance; refusing to adopt it")
        identifier = self._simctl("create", name, choices[0]["identifier"], runtime["identifier"]).strip()
        try:
            uuid.UUID(identifier)
        except ValueError as error:
            raise RuntimeError("Simulator creation did not return a UUID") from error
        self.simulator = {"udid": identifier, "name": name}
        self._verify_simulator()
        self._simctl("boot", identifier)
        self._simctl("bootstatus", identifier, "-b", timeout=180)
        return identifier

    def _verify_simulator(self):
        matches = [device for device in self._simulators() if device.get("udid") == self.simulator["udid"]]
        if len(matches) != 1 or matches[0].get("name") != self.simulator["name"]:
            raise RuntimeError("Simulator ownership changed; refusing to control it")
        return matches[0]

    def _owned_executable(self, identity, product):
        executable = Path(identity["executable"])
        if self.platform == "macos":
            return executable == Path(product["executable"])
        return self.simulator["udid"] in executable.parts and executable.name == Path(product["executable"]).name

    def _capture(self, pid, product):
        self.app = {"pid": pid, "bundleId": product["bundleId"]}
        if self._child is not None and self._child.poll() is not None:
            self._child.wait(timeout=1)
        identity = _process(pid)
        if identity is None:
            raise RuntimeError("The launched app process exited")
        if not self._owned_executable(identity, product):
            raise RuntimeError("The launched process executable does not belong to this runtime")
        self.identity = identity
        if _sha(Path(identity["executable"])) != product["sha256"]:
            raise RuntimeError("The launched executable does not match the recorded build")

    def _simulator_pid(self, output, product):
        try:
            bundle, pid = output.strip().rsplit(":", 1)
            if bundle != product["bundleId"] or int(pid) <= 0:
                raise ValueError("Wrong launch output")
            return int(pid)
        except ValueError as error:
            raise RuntimeError("Simulator launch did not report the app PID") from error

    def _ready(self):
        deadline = time.monotonic() + 180
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        check_id = str(uuid.uuid4())
        while time.monotonic() < deadline:
            if _process(self.identity["pid"]) != self.identity:
                raise RuntimeError("The owned app process exited before the PIR runner was ready")
            request = urllib.request.Request(f"http://127.0.0.1:{self.port}/api/debug/prerequisites?checkID={check_id}",
                                             headers={"X-PIR-Debug-Instance": self.instance})
            try:
                with opener.open(request, timeout=2) as response:
                    result = json.load(response)
                if result.get("instanceID") != self.instance:
                    raise RuntimeError("The PIR server belongs to another launch")
                if result.get("checkID") != check_id:
                    raise RuntimeError("The PIR prerequisite reply did not match this request")
                if result.get("debugRunnerReady"):
                    return
            except (OSError, ValueError):
                pass
            time.sleep(.2)
        raise RuntimeError("The owned PIR debug runner did not become ready")

    def _verified_build(self):
        if self.app is not None or self._closed:
            raise RuntimeError("A Runtime instance supports one launch")
        self._acquire(False)
        try:
            metadata = json.loads(self.state.read_text())
        except (OSError, ValueError) as error:
            raise RuntimeError("No recorded PIR build; run the standalone build command first") from error
        if metadata.get("root") != str(self.root) or metadata.get("sourceSHA256") != self._source():
            raise RuntimeError("Source differs from the recorded PIR build; rebuild before running")
        product = self._product(metadata["settings"])
        if metadata.get("product") != product:
            raise RuntimeError("The PIR build product changed; rebuild before running")
        return metadata, product

    def _secure_launch_logs(self):
        for path in (self.stdout, self.stderr):
            with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w"):
                pass

    def _reserve_port(self):
        with socket.socket() as probe:
            try:
                probe.bind(("127.0.0.1", self.port))
            except OSError as error:
                raise RuntimeError("The PIR debug port is unavailable or already in use") from error

    def _install_simulator_app(self, product):
        identifier = self._create_simulator()
        self._simctl("install", identifier, product["path"])
        container = Path(self._simctl("get_app_container", identifier, product["bundleId"], "data").strip())
        if not container.is_absolute():
            raise RuntimeError("Unable to locate the installed simulator app's data container")
        return identifier, container

    def _launch_simulator_app(self, identifier, product, environment):
        env = {**_child_environment(), **{f"SIMCTL_CHILD_{key}": value for key, value in environment.items()}}
        profile = json.dumps(self.launch_profile, separators=(",", ":"))
        since = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - 1))
        self._launch_attempted = True
        try:
            output = self._simctl("launch", f"--stdout={self.stdout}", f"--stderr={self.stderr}",
                                  identifier, product["bundleId"], "-launchProfile", profile, env=env)
        except RuntimeError as error:
            # simctl can fail after starting the process. Retain its PID for owned cleanup.
            try:
                self._capture(self._simulator_pid(error._diagnostics["stdout"], product), product)
            except RuntimeError:
                pass
            raise
        self._capture(self._simulator_pid(output, product), product)
        self._await_launch_profile(identifier, since)

    def _await_launch_profile(self, identifier, since):
        deadline = time.monotonic() + LAUNCH_PROFILE_TIMEOUT
        while True:
            try:
                log = self._simctl("spawn", identifier, "log", "show", "--start", since, "--style", "compact", "--predicate",
                                   f'subsystem == "{BUNDLES["ios"]}" AND category == "LaunchProfile"')
            except RuntimeError:
                log = ""
            lines = [line[line.index(LAUNCH_PROFILE_PREFIX):].strip() for line in log.splitlines() if LAUNCH_PROFILE_PREFIX in line]
            if lines or time.monotonic() >= deadline:
                break
            time.sleep(1)
        self.launch_profile_result = lines[-1] if lines else None
        if not (self.launch_profile_result or "").startswith(LAUNCH_PROFILE_PREFIX + "APPLIED"):
            raise RuntimeError("The app did not apply its launch profile: "
                               f"{self.launch_profile_result or 'no ' + LAUNCH_PROFILE_PREFIX + ' line'}")

    def _launch_profile_record(self):
        return {"merged": self.launch_profile, "result": self.launch_profile_result}

    def launch_scheduler(self, mode, profile_json, brokers=()):
        if mode not in ("seed", "reseed"):
            raise RuntimeError("Managed scheduler launches require seed or reseed")
        metadata, product = self._verified_build()
        environment = {"PIR_SCHEDULER_MODE": mode, "PIR_SCHEDULER_INSTANCE_ID": self.instance, "PIR_PROFILE_JSON": profile_json}
        if brokers:
            environment["PIR_SCHEDULER_BROKERS"] = json.dumps(list(brokers))
        if self.platform == "ios":
            self._reserve_port()
            self._secure_launch_logs()
            identifier, container = self._install_simulator_app(product)
            (container / "tmp").mkdir(exist_ok=True)
            self._receipt = container / "tmp" / f"pir-scheduler-{self.instance}.json"
            self._launch_simulator_app(identifier, product, {
                **environment, "PIR_SCHEDULER_RECEIPT": str(self._receipt),
                "PIR_DEBUG_PORT": str(self.port), "PIR_DEBUG_INSTANCE_ID": self.instance})
            return {"platform": "ios", "instanceID": self.instance, "port": self.port, "process": self.identity,
                    "product": product, "simulator": self.simulator, "sourceSHA256": metadata["sourceSHA256"],
                    "launchProfile": self._launch_profile_record()}
        self._acquire_scheduler_lock(product)
        environment["PIR_SCHEDULER_RECEIPT"] = str(self._receipt)
        return self._launch_browser(environment, metadata, product)

    def _acquire_scheduler_lock(self, product):
        descriptor = os.open(SCHEDULER_LOCK, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        lock = os.fdopen(descriptor, "r+")
        try:
            info = os.fstat(descriptor)
            if info.st_uid != os.getuid() or not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
                raise RuntimeError("The scheduler lock is not a private regular file")
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            lock.close()
            raise RuntimeError("Another ddg-check-pir command is seeding the DEBUG store") from error
        except BaseException:
            lock.close()
            raise
        self._scheduler_lock = lock
        browser = Path(product["browserExecutable"])
        for executable in self._running_executables():
            if executable.name == browser.name:
                bundle = next((parent for parent in executable.parents if parent.suffix == ".app"), None)
                # An iOS simulator app has the same executable name but a flat bundle.
                if bundle and (bundle / "Contents/Info.plist").is_file() and _info(bundle).get("CFBundleIdentifier") == BROWSER_BUNDLE:
                    raise RuntimeError("A DEBUG browser is already running; close it before seeding")

    def _launch_browser(self, environment, metadata, product):
        browser = Path(product["browserExecutable"])
        self._secure_launch_logs()
        with self.stdout.open("ab") as stdout, self.stderr.open("ab") as stderr:
            self._child = subprocess.Popen([str(browser)], cwd=self.root,
                                           env={**_child_environment(), **environment}, stdout=stdout, stderr=stderr)
        self._launch_attempted = True
        self._capture(self._child.pid, {"executable": str(browser), "bundleId": BROWSER_BUNDLE, "sha256": product["browserSHA256"]})
        return {"platform": "macos", "instanceID": self.instance, "port": self.port, "process": self.identity,
                "product": product, "sourceSHA256": metadata["sourceSHA256"]}

    def launch_existing(self, simulator=None):
        """Launches this build on the existing PIR store with its debug server on, without saving or resetting a profile."""
        metadata, product = self._verified_build()
        if self.platform == "ios":
            matches = [device for device in self._simulators() if device.get("udid") == simulator]
            if len(matches) != 1 or not matches[0].get("name", "").startswith("ddg-check-pir-"):
                raise RuntimeError("--simulator must name a simulator that a ddg-check-pir seed kept")
            self.simulator, self.keep = {"udid": simulator, "name": matches[0]["name"]}, True
            if matches[0].get("state") != "Booted":
                self._simctl("boot", simulator)
                self._simctl("bootstatus", simulator, "-b", timeout=180)
            self._reserve_port()
            self._secure_launch_logs()
            self._simctl("install", simulator, product["path"])
            self._launch_simulator_app(simulator, product, {"PIR_DEBUG_SERVER": "true", "PIR_DEBUG_PORT": str(self.port),
                                                            "PIR_DEBUG_INSTANCE_ID": self.instance})
            return {"platform": "ios", "instanceID": self.instance, "port": self.port, "process": self.identity,
                    "product": product, "simulator": self.simulator, "sourceSHA256": metadata["sourceSHA256"],
                    "launchProfile": self._launch_profile_record()}
        self._acquire_scheduler_lock(product)
        return self._launch_browser({"PIR_DEBUG_SERVER": "true"}, metadata, product)

    def scheduler_receipt(self):
        deadline = time.monotonic() + SCHEDULER_SETUP_TIMEOUT
        while time.monotonic() < deadline:
            try:
                raw = self._receipt.read_bytes()
            except FileNotFoundError:
                exited = self._child.poll() is not None if self._child else _process(self.identity["pid"]) != self.identity
                if exited:
                    raise RuntimeError("The DEBUG app exited before reporting scheduler setup")
                time.sleep(.2)
                continue
            if self._receipt != self.evidence / "scheduler-launch.json":
                (self.evidence / "scheduler-launch.json").write_bytes(raw)
            return json.loads(raw)
        raise RuntimeError(f"The DEBUG app did not report scheduler setup within {SCHEDULER_SETUP_TIMEOUT} seconds")

    def launch(self, access_token=None):
        if access_token is not None and (not isinstance(access_token, str) or not access_token
                or len(access_token.encode("utf-8")) > 65_536
                or any(c.isspace() or ord(c) < 32 or 127 <= ord(c) <= 159 for c in access_token)):
            raise RuntimeError("Invalid supplied PIR credential")
        metadata, product = self._verified_build()
        self._reserve_port()
        environment = {"PIR_DEBUG_SERVER": "true", "PIR_DEBUG_PORT": str(self.port),
                       "PIR_DEBUG_INSTANCE_ID": self.instance, "PIR_DEBUG_ENVIRONMENT": self.pir_environment}
        if access_token is not None:
            environment["PIR_DEBUG_ACCESS_TOKEN"] = access_token
        if self.snapshots_enabled:
            directory = self.evidence / "snapshots"
            directory.mkdir(mode=0o700)
            environment["PIR_DEBUG_SNAPSHOTS"] = "1"
            if self.platform == "macos":
                environment["PIR_DEBUG_SNAPSHOT_DIRECTORY"] = str(directory)
        self._secure_launch_logs()
        if self.platform == "ios":
            identifier, container = self._install_simulator_app(product)
            if self.snapshots_enabled:
                self._simulator_snapshots = container / "tmp" / f"pir-snapshots-{self.instance}"
            self._launch_simulator_app(identifier, product, environment)
        else:
            arguments = [*MACOS_FLAG_ARGUMENTS, "-pirDebugServer", "true", "-pirDebugPort", str(self.port),
                         "-pirDebugInstanceID", self.instance, "-pirDebugEnvironment", self.pir_environment]
            with self.stdout.open("ab") as stdout, self.stderr.open("ab") as stderr:
                self._child = subprocess.Popen([product["executable"], *arguments], cwd=self.root,
                                               env={**_child_environment(), **environment}, stdout=stdout, stderr=stderr)
            self._launch_attempted = True
            self._capture(self._child.pid, product)
        self._ready()
        launch = {"platform": self.platform, "instanceID": self.instance, "port": self.port,
                  "process": self.identity, "product": product, "simulator": self.simulator,
                  "sourceSHA256": metadata["sourceSHA256"], "pirEnvironment": self.pir_environment}
        if self.platform == "ios":
            launch["launchProfile"] = self._launch_profile_record()
        return launch

    def collect_snapshots(self):
        source = self._simulator_snapshots
        if source is None or not source.is_dir():
            return
        if source.is_symlink():
            raise RuntimeError("Unexpected symbolic link for simulator snapshots")
        directory = self.evidence / "snapshots"
        for path in sorted(source.iterdir()):
            if path.name.startswith(".") or path.suffix not in (".png", ".unavailable") or path.is_symlink():
                continue
            destination = directory / path.name
            if destination.exists() or not path.is_file():
                continue
            temporary = directory / (".copy-" + path.name)
            try:
                shutil.copyfile(path, temporary)
                temporary.replace(destination)
            finally:
                temporary.unlink(missing_ok=True)

    def stop(self):
        if self._closed:
            return {"stopped": True, "alreadyStopped": True, "simulatorKept": bool(self.simulator and self.keep)}
        uncertain = self._launch_attempted and self.app is None
        try:
            if self.app is not None:
                if self._child is not None and self._child.poll() is not None:
                    self._child.wait(timeout=1)
                current = _process(self.app["pid"])
                if current is not None:
                    if self.identity is None or current != self.identity:
                        raise RuntimeError("App process ownership changed; refusing to stop it")
                    if self.platform == "ios":
                        self._verify_simulator()
                        self._simctl("terminate", self.simulator["udid"], self.app["bundleId"])
                    else:
                        os.kill(current["pid"], signal.SIGTERM)
                        if self._child is not None:
                            self._child.wait(timeout=5)
                    deadline = time.monotonic() + 5
                    while _process(current["pid"]) == current and time.monotonic() < deadline:
                        time.sleep(.1)
                    if _process(current["pid"]) == current:
                        raise RuntimeError("The owned PIR process did not stop")
                self.app = None
                self._launch_attempted = False
            if uncertain and self.platform == "ios" and self.simulator is not None:
                state = self._verify_simulator()
                if state.get("state") == "Booted":
                    self._simctl("shutdown", self.simulator["udid"])
                uncertain = False
                self._launch_attempted = False
            if self.simulator is not None and not self.keep:
                state = self._verify_simulator()
                if state.get("state") == "Booted":
                    self._simctl("shutdown", self.simulator["udid"])
                self._simctl("delete", self.simulator["udid"])
                self.simulator = None
            if uncertain:
                raise RuntimeError("Launch ownership is uncertain; cannot confirm process cleanup")
            for path in (self.stdout, self.stderr):
                path.unlink(missing_ok=True)
            self._closed = True
            return {"stopped": True, "simulatorKept": bool(self.simulator and self.keep)}
        finally:
            self._release()
