"""One device profile (iphone | ipad) on this worktree's own simulator: set up, build, launch, doctor, act, observe.

Native UI goes through the driver (driver.py); page content through the app's AutomationServer (web.py).
"""
import json, os, shlex, signal, subprocess, sys, time

from . import env
from .driver import XCUITestRunner
from .env import APP, APP_DD, BUNDLE, DEVICE_TYPES, HOME, KEY, ROOT, RUNNER_DD, RUNTIME, SKILL, Failed, Unsupported, run
from .web import SUMMARY_JS, Web


def parse_locator(s):
    """id=x | label="x" | role=button label="x" | text="x" | contains="x" | web:css=sel | web:text="x"; optional nth=<n>."""
    if s.startswith("web:"):
        k, _, v = s[4:].partition("=")
        return {"web": k, "value": v.strip('"')}
    sel = {}
    for tok in shlex.split(s):
        k, _, v = tok.partition("=")
        sel[{"name": "label"}.get(k, k)] = v
    return {"sel": sel}


def native(locator):
    loc = parse_locator(locator)
    if "web" in loc:
        raise Unsupported("web:* locators are read-only; act through the native tree (use web eval for setup only)")
    return loc["sel"]


class Device:
    def __init__(self, device):
        if device not in env.PORT_OFFSET:
            raise Failed(f"unknown device {device!r}: iphone or ipad")
        self.device = device
        self.web_port, self.runner_port = env.ports(device)
        self.token = env.token()
        os.environ["AUTOMATION_TOKEN"] = self.token
        self.web = Web(self.web_port, self.token)
        self._driver = None

    @property
    def udid(self):
        u = env.load_state().get("sims", {}).get(self.device)
        if not u:
            raise Failed(f"no {self.device} simulator for this worktree: run `setup --device {self.device}`")
        return u

    @property
    def driver(self):
        if self._driver is None:
            self._driver = XCUITestRunner(self.udid, self.runner_port, self.token)
        return self._driver

    def _dev_state(self):
        return env.load_state().get("devices", {}).get(self.device, {})

    # setup / build -------------------------------------------------------------
    def setup(self):
        """Create (or adopt) this worktree's dedicated simulator for the device, and boot it."""
        name = f"verify-ios-{KEY}-{self.device}"
        devs = json.loads(run(["xcrun", "simctl", "list", "devices", "-j"]).stdout)["devices"]
        found = [d for ds in devs.values() for d in ds if d["name"] == name and d.get("isAvailable", True)]
        created = False
        if found:
            udid = found[0]["udid"]
        else:
            p = run(["xcrun", "simctl", "create", name, DEVICE_TYPES[self.device], RUNTIME])
            if p.returncode:
                raise Failed("simctl create failed", stderr=p.stderr.strip())
            udid, created = p.stdout.strip(), True
        env.update_state(lambda st: st.setdefault("sims", {}).__setitem__(self.device, udid))
        run(["xcrun", "simctl", "boot", udid])
        p = run(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=300)
        if p.returncode:
            raise Failed("simulator did not finish booting", stderr=p.stderr.strip())
        self._driver = None
        return dict(udid=udid, name=name, created=created, ports=dict(web=self.web_port, runner=self.runner_port, fixture=env.fixture_port()))

    def booted(self):
        u = env.load_state().get("sims", {}).get(self.device)
        return bool(u) and "(Booted)" in run(["xcrun", "simctl", "list", "devices", u]).stdout

    def build(self, app=True, runner=True):
        """Build this worktree's app and the runner against this device's simulator (generic destinations fail)."""
        os.makedirs(f"{HOME}/logs", exist_ok=True)
        out, jobs = {}, []
        if app:
            jobs.append(("app", ["xcodebuild", "-project", f"{ROOT}/iOS/DuckDuckGo-iOS.xcodeproj", "-scheme", "iOS Browser",
                                 "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={self.udid}",
                                 "-derivedDataPath", APP_DD, "-skipPackagePluginValidation", "-skipMacroValidation", "build"]))
        if runner:
            jobs.append(("runner", ["xcodebuild", "build-for-testing", "-project", f"{SKILL}/runner/VRunner.xcodeproj",
                                    "-scheme", "VRunner-iOS", "-destination", f"platform=iOS Simulator,id={self.udid}",
                                    "-derivedDataPath", RUNNER_DD]))
        source = env.source_stamp() if app else None
        for name, cmd in jobs:
            log = f"{HOME}/logs/{name}-build.log"
            t0 = time.time()
            with open(log, "w") as f:
                code = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT).returncode
            out[name] = dict(exit=code, secs=int(time.time() - t0), log=log)
            if code:
                if name == "app":
                    env.update_state(lambda st: st.pop("appBuild", None))
                raise Failed(f"{name} build failed (see {log})", **out)
        if app:
            if env.source_stamp() != source:
                env.update_state(lambda st: st.pop("appBuild", None))
                raise Failed("the app source changed while it was building; build again")
            built = dict(source=source, sha256=env.sha256(f"{APP}/DuckDuckGo"), at=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
            env.update_state(lambda st: st.__setitem__("appBuild", built))
            out["appSha"] = built["sha256"]
        return out

    @staticmethod
    def check_build_current():
        """Fail unless the app build product was built by `build` from the source as it is now."""
        built = env.load_state().get("appBuild")
        if not built:
            raise Failed("no record of how the app build was made: run `build --app-only`")
        if not os.path.exists(f"{APP}/DuckDuckGo") or env.sha256(f"{APP}/DuckDuckGo") != built["sha256"]:
            raise Failed("the app build product changed since `build` recorded it: run `build --app-only`")
        now = env.source_stamp()
        if now != built["source"]:
            raise Failed("the app build is stale: the source changed since it was built. Run `build --app-only`",
                         builtFrom=built["source"], sourceNow=now)
        return built

    # app -----------------------------------------------------------------------
    def installed_sha(self):
        p = run(["xcrun", "simctl", "get_app_container", self.udid, BUNDLE, "app"])
        return None if p.returncode else env.sha256(os.path.join(p.stdout.strip(), "DuckDuckGo"))

    def install(self, fresh):
        if not os.path.exists(APP):
            raise Failed(f"no app build at {APP}: run `build --app-only`")
        run(["xcrun", "simctl", "terminate", self.udid, BUNDLE])
        if fresh:
            run(["xcrun", "simctl", "uninstall", self.udid, BUNDLE])
        if fresh or self.installed_sha() != env.sha256(f"{APP}/DuckDuckGo"):
            p = run(["xcrun", "simctl", "install", self.udid, APP])
            if p.returncode:
                raise Failed("simctl install failed", stderr=p.stderr.strip())
        for k, t, v in (("automationPort", "-int", str(self.web_port)), ("isOnboardingCompleted", "-string", "true")):
            run(["xcrun", "simctl", "spawn", self.udid, "defaults", "write", BUNDLE, k, t, v], check=True)

    def identity(self, app=APP):
        p = run([f"{SKILL}/lib/ios_identity.sh", self.udid, app])
        try:
            return json.loads(p.stdout.strip().splitlines()[-1])
        except (IndexError, ValueError):
            return dict(ok=False, reason=(p.stdout[-200:] + p.stderr[-200:]).strip())

    def launch(self, fresh=False, flags=None):
        """Install this worktree's build if it changed, start the runner, launch, and wait for a real ready signal.

        `flags` pins remote feature flags for this launch ({"newTabPageRedesign": True}) on top of env.PINNED_FLAGS, so
        a proof never depends on what the live privacy configuration currently says.
        """
        t0 = time.time()
        flags = {**env.PINNED_FLAGS, **(flags or {})}
        if not self.booted():
            self.setup()
        if env.port_listening(self.web_port, "::1") and not self.web.ready_now():
            raise Failed(f"port {self.web_port} is taken by something that is not this worktree's app; refusing to drive it")
        self.install(fresh=fresh)
        started = self.driver.start()
        if started:
            env.update_state(lambda st: st.setdefault("devices", {}).setdefault(self.device, {}).setdefault("started", []).append(
                dict(processes=started, port=self.runner_port)))
        unknown = sorted(set(flags) - env.feature_flag_names())
        if unknown:
            raise Failed(f"not feature flags in this app: {unknown} (see iOS/LocalPackages/FeatureFlags-iOS/…/FeatureFlag.swift)")
        # The app applies -ff. overrides only for internal users or in UI-test mode (AppDependencyProvider's
        # allowOverrides). UI-test mode is the narrower switch: it doesn't turn on internal-only features.
        args = ["isRunningUITests"] + [a for name, on in sorted(flags.items()) for a in (f"-ff.{name}", "true" if on else "false")]
        self.driver.launch({"AUTOMATION_TOKEN": self.token}, args)
        if self.web.wait_ready(60) is None:
            raise Failed(f"AutomationServer on [::1]:{self.web_port} never reported /contentBlockerReady true")
        self.driver.wait({"id": "searchEntry"}, "exists", 20)
        ident = self.identity()
        if not ident.get("ok"):
            raise Failed("running app is not this worktree's build", build=ident)
        return dict(device=self.device, udid=self.udid, bundleId=BUNDLE, build=ident, driver=self.driver.name, flags=flags,
                    ports=dict(web=self.web_port, runner=self.runner_port), readyMs=int((time.time() - t0) * 1000),
                    runnerStarted=bool(started))

    # capture conditions -----------------------------------------------------------
    def ui(self, option, value=None):
        """Read (or set) a simulator UI option: appearance (light|dark), content_size (Dynamic Type category)."""
        p = run(["xcrun", "simctl", "ui", self.udid, option, *([value] if value else [])])
        if p.returncode:
            raise Failed(f"simctl ui {option} {value or ''} failed", stderr=p.stderr.strip())
        return p.stdout.strip() if value is None else value

    def status_bar(self, fixed):
        """Fixed status bar (9:41, full battery and signal) so screenshots compare; or clear the override."""
        args = (["override", "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
                 "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4",
                 "--dataNetwork", "wifi"] if fixed else ["clear"])
        p = run(["xcrun", "simctl", "status_bar", self.udid, *args])
        if p.returncode:
            raise Failed("simctl status_bar failed", stderr=p.stderr.strip())

    def capture_conditions(self):
        """What a screenshot taken now depends on, beyond the device type and runtime."""
        o = self.driver.orientation().get("orientation")
        overrides = run(["xcrun", "simctl", "status_bar", self.udid, "list"]).stdout
        return dict(appearance=self.ui("appearance"), textSize=self.ui("content_size"),
                    orientation=o if o and o != "unknown" else "portrait",
                    statusBar="fixed (9:41)" if "9:41" in overrides else "live")

    def foreground(self):
        """True if the app is running in the foreground (not crashed, not backgrounded)."""
        from .driver import APP_FOREGROUND
        return self.driver.state() == APP_FOREGROUND

    def reset(self, flags=None):
        """Known state: reinstall (clears app data, per-site permissions and pixel frequency state), launch, one blank tab."""
        return self.launch(fresh=True, flags=flags)

    def terminate(self):
        self.driver.terminate()
        return {}

    def doctor(self):
        checks = []
        udid = env.load_state().get("sims", {}).get(self.device)
        checks.append(dict(name="simulator-recorded", ok=bool(udid), detail=udid))
        booted = self.booted()
        checks.append(dict(name="simulator-booted", ok=booted))
        checks.append(dict(name="app-build-present", ok=os.path.exists(APP), detail=APP))
        ident = self.identity() if booted else dict(ok=False, reason="simulator not booted")
        checks.append(dict(name="app-running", ok="pid" in ident, detail=ident.get("pid") or ident.get("reason")))
        checks.append(dict(name="build-is-this-worktree", ok=bool(ident.get("ok")), detail=ident))
        checks.append(dict(name="runner-alive", ok=booted and self.driver.alive(), detail=f"127.0.0.1:{self.runner_port}"))
        checks.append(dict(name="web-channel", ok=self.web.ready_now(), detail=f"[::1]:{self.web_port}"))
        if not all(c["ok"] for c in checks):
            raise Failed("doctor found problems", checks=checks)
        return dict(checks=checks, worktree=ROOT, home=HOME)

    def cleanup(self, shutdown=False, delete_sim=False):
        """Stop what this worktree started for the device, by recorded and re-checked process identity."""
        removed, survivors = [], []
        st = env.load_state()
        udid = st.get("sims", {}).get(self.device)
        for s in st.get("devices", {}).get(self.device, {}).get("started", []):
            res = XCUITestRunner(udid or "-", s["port"], self.token).stop(s.get("processes", []))
            removed.append(res)
            if res.get("left"):   # keep the record of anything that survived, so a later cleanup can retry it
                survivors.append(dict(processes=res["left"], port=s["port"]))
        env.update_state(lambda st: st.setdefault("devices", {}).setdefault(self.device, {}).__setitem__("started", survivors))
        if udid:
            run(["xcrun", "simctl", "terminate", udid, BUNDLE])
            if shutdown or delete_sim:
                run(["xcrun", "simctl", "shutdown", udid])
                removed.append(f"shutdown:{udid}")
            if delete_sim:
                run(["xcrun", "simctl", "delete", udid])
                env.update_state(lambda st: st.get("sims", {}).pop(self.device, None))
                removed.append(f"deleted:{udid}")
        out = dict(removed=removed, evidenceKept=env.EVIDENCE)
        if survivors:
            out["left"] = [p["pid"] for s in survivors for p in s["processes"]]
        return out

    # observe -------------------------------------------------------------------
    def snapshot(self, web=False):
        r = self.driver.tree()
        lines = [f'{"  " * min(n["d"], 12)}{n["type"]} id={n["id"]!r} label={n["label"]!r} value={n["value"]!r} enabled={n["enabled"]}'
                 for n in r.get("nodes", []) if n["id"] or n["label"] or n["value"]]
        out = dict(focused=r.get("focused"), tree="\n".join(lines), nodes=len(r.get("nodes", [])))
        if web:
            out["web"] = json.loads(self.web.eval(SUMMARY_JS))
        return out

    def find(self, locator):
        loc = parse_locator(locator)
        matches = [m for m in [self.web.find(loc["web"], loc["value"])] if m] if "web" in loc else self.driver.find(loc["sel"])
        if not matches:
            raise Failed("no match")
        return dict(matches=matches)

    def get(self, locator, attr="value"):
        loc = parse_locator(locator)
        if "web" in loc:
            m = self.web.find(loc["web"], loc["value"])
            if not m:
                raise Failed("no web match")
            return dict(value=m["text"])
        el = self.driver.get(loc["sel"])
        return dict(value=el.get(attr or "value"), element=el)

    def wait(self, locator, state="visible", timeout=5):
        loc = parse_locator(locator)
        if "web" in loc:
            ok = {"exists": lambda m: m is not None, "visible": lambda m: bool(m and m["visible"]),
                  "enabled": lambda m: bool(m and m["visible"] and m["enabled"]),
                  "hidden": lambda m: m is None or not m["visible"]}[state]
            end = time.time() + timeout
            while time.time() < end:
                if ok(self.web.find(loc["web"], loc["value"])):
                    return {}
                time.sleep(0.25)
            raise Failed("timeout", runner=dict(code="TIMEOUT"))
        return dict(polls=self.driver.wait(loc["sel"], state, timeout).get("polls"))

    # act -------------------------------------------------------------------------
    @staticmethod
    def _result(r):
        return dict(matched=r.get("matched"), after=r.get("after"), **{k: r[k] for k in ("valueAfter", "pressed", "alert") if k in r})

    def tap(self, locator):
        return self._result(self.driver.tap(native(locator)))

    def long_press(self, locator, ms=800):
        return self._result(self.driver.long_press(native(locator), ms))

    def type(self, locator, text, submit=False):
        return self._result(self.driver.type(None if locator == "-" else native(locator), text + ("\n" if submit else "")))

    def clear(self, locator):
        el = self.driver.get(native(locator))
        value = el.get("value") or ""
        if not value or value == el.get("placeholder"):   # an empty field reports its placeholder as its value
            return dict(matched=el, after=None)
        return self._result(self.driver.type(native(locator), "\b" * len(value)))

    def key(self, combo):
        return self._result(self.driver.key(combo))

    def swipe(self, direction, locator=None):
        return self._result(self.driver.swipe(direction, native(locator) if locator else None))

    def scroll_to(self, locator):
        sel = native(locator)
        for _ in range(12):
            matches = self.driver.find(sel)
            if any(m.get("hittable") for m in matches):
                return dict(matched=matches[0])
            self.driver.swipe("up")
        raise Failed("not reachable by scrolling")

    def alert(self, action, button=None, timeout=5):
        return self._result(self.driver.alert(action, button, timeout))

    # evidence ------------------------------------------------------------------
    def screenshot(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        p = run(["xcrun", "simctl", "io", self.udid, "screenshot", path])
        if p.returncode:
            raise Failed("screenshot failed", stderr=p.stderr.strip())
        return path

    def app_logs(self, path, since="5m"):
        out = run(["xcrun", "simctl", "spawn", self.udid, "log", "show", "--last", since, "--style", "compact",
                   "--predicate", 'process == "DuckDuckGo"']).stdout
        with open(path, "w") as f:
            f.write(out[-500000:])
        return path

    def data_container(self):
        p = run(["xcrun", "simctl", "get_app_container", self.udid, BUNDLE, "data"])
        if p.returncode:
            raise Failed("app not installed", stderr=p.stderr.strip())
        return p.stdout.strip()


# ---------------------------------------------------------------- fixture server (shared by both devices)
def _fixture_lock():
    import fcntl
    os.makedirs(HOME, exist_ok=True)
    lock = open(f"{HOME}/fixture.lock", "w")   # both devices' proofs may start or release it at the same moment
    fcntl.flock(lock, fcntl.LOCK_EX)
    return lock


def _stop_fixture(fx):
    if fx and env.still_ours(fx):
        os.kill(fx["pid"], signal.SIGTERM)
    env.update_state(lambda st: st.pop("fixture", None))


def fixture(stop=False, user=None):
    """Serve the skill's fixture pages on this worktree's fixture port; returns the page URL prefix.
    `user` (a device, or "cli") records who needs the server, so a proof finishing on one device never stops it under
    a proof running on the other. `stop=True` stops it regardless (callers hold both device locks)."""
    port = env.fixture_port()
    url = f"http://127.0.0.1:{port}/index.html?token="
    with _fixture_lock():
        fx = env.load_state().get("fixture")
        if stop:
            _stop_fixture(fx)
            return dict(stopped=bool(fx))
        if fx and env.still_ours(fx) and env.port_listening(port):
            if user and user not in fx.get("users", []):
                env.update_state(lambda st: st["fixture"].setdefault("users", []).append(user))
            return dict(url=url, port=port, pid=fx["pid"], started=False)
        if env.port_listening(port):
            raise Failed(f"fixture port {port} is taken by something this worktree did not start")
        os.makedirs(f"{HOME}/logs", exist_ok=True)
        p = subprocess.Popen([sys.executable, "-m", "http.server", str(port), "--bind", "127.0.0.1", "--directory", f"{SKILL}/fixture"],
                             stdout=open(f"{HOME}/logs/fixture.log", "a"), stderr=subprocess.STDOUT, start_new_session=True)
        for _ in range(100):
            if env.port_listening(port):
                break
            if p.poll() is not None:
                break
            time.sleep(0.1)
        if not env.port_listening(port):
            p.terminate()   # never leave an unrecorded server behind that would later block the port
            p.wait(5)
            raise Failed("fixture server did not start (see logs/fixture.log)")
        ident = dict(env.process_identity(p.pid), users=[user] if user else [])
        env.update_state(lambda st: st.__setitem__("fixture", ident))
        return dict(url=url, port=port, pid=p.pid, started=True)


def fixture_release(user):
    """`user` no longer needs the fixture server; stop it when nobody does."""
    with _fixture_lock():
        fx = env.load_state().get("fixture")
        if not fx:
            return dict(stopped=False)
        users = [u for u in fx.get("users", []) if u != user]
        if users:
            env.update_state(lambda st: st["fixture"].__setitem__("users", users))
            return dict(stopped=False, stillUsedBy=users)
        _stop_fixture(fx)
        return dict(stopped=True)


def info():
    st = env.load_state()
    return dict(worktree=ROOT, key=KEY, home=HOME, app=APP, evidence=env.EVIDENCE, sims=st.get("sims", {}),
                ports={d: dict(zip(("web", "runner"), env.ports(d))) for d in env.PORT_OFFSET} | {"fixture": env.fixture_port()})
