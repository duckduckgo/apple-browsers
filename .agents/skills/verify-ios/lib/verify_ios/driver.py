"""The native-UI driver: the only module that knows how the app's UI is driven.

Everything above it (Device, Proof, steps) uses these operations and nothing else, so another driver means another
class with the same methods. Contract every driver must keep (checked by tests/must_fail.py, which a new driver must
pass before it is used):
  - resolve a locator fresh for every action; never guess between several matches (AMBIGUOUS);
  - refuse missing, disabled and covered targets (NOT_FOUND, DISABLED, NOT_HITTABLE) and typing with nothing focused
    (NOT_FOCUSED); a refused action changes nothing;
  - report what changed after every action (`after`: changed, keyboard, focused);
  - `wait` states: exists, visible (exists and hittable), enabled, hidden (no match).
Failures raise env.Failed carrying the driver's response.
"""
import json, os, signal, subprocess, time, urllib.error, urllib.request

from .env import RUNNER_DD, SKILL, HOME, Failed, port_listening, process_identity, still_ours, run

RUNNER_APP = "com.duckduckgo.verifyios.runner.xctrunner"
APP_FOREGROUND = 4   # XCUIApplication.State.runningForeground


def _signal(recorded, sig):
    """Send `sig` only if the pid is still the process we recorded; True if sent."""
    if not still_ours(recorded):
        return False
    try:
        os.kill(recorded["pid"], sig)
        return True
    except ProcessLookupError:
        return False


def _still_running_after(recorded, secs):
    """Wait up to `secs` for a recorded process to exit; True if it is still running (and still ours) afterwards."""
    end = time.time() + secs
    while time.time() < end and still_ours(recorded):
        time.sleep(0.2)
    return still_ours(recorded)


class XCUITestRunner:
    """Long-lived XCUITest runner (runner/Sources/Runner/VRunner.swift) serving JSON commands on 127.0.0.1:<port>."""

    name = "xcuitest-runner"

    def __init__(self, udid, port, token):
        self.udid, self.port, self.token = udid, port, token

    # transport -----------------------------------------------------------------
    def call(self, body, timeout=180):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}/", data=json.dumps({**body, "token": self.token}).encode(),
                                     method="POST", headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except (urllib.error.URLError, OSError) as e:
            raise RuntimeError(f"runner unreachable on 127.0.0.1:{self.port}: {e} (launch starts it)")

    def act(self, body, timeout=180):
        r = self.call(body, timeout)
        if not r.get("ok"):
            raise Failed(r.get("message") or r.get("code", "failed"), runner=r)
        return r

    # lifecycle -----------------------------------------------------------------
    def alive(self):
        """True only for our runner: another worktree's runner on this port answers UNAUTHORIZED."""
        try:
            return self.call({"op": "ping"}, timeout=3).get("ok", False)
        except Exception:
            return False

    def start(self):
        """Start the runner if ours isn't already up. Returns the started process records, or [] if it was running."""
        if self.alive():
            return []
        if port_listening(self.port):
            raise Failed(f"port {self.port} answers but not with this worktree's runner token; refusing to drive it")
        products = f"{RUNNER_DD}/Build/Products"
        xtr = sorted(f for f in os.listdir(products) if f.endswith(".xctestrun")) if os.path.isdir(products) else []
        if not xtr:
            raise Failed("runner not built: run `build --runner-only`")
        pidfile = f"{HOME}/logs/runner-{self.udid}.pid"
        try:
            # Own session: a Ctrl-C at the terminal signals the whole foreground process group, and the runner must
            # outlive it so the cancelled proof can still collect the final UI state. stop() ends it by recorded pid.
            p = subprocess.run([f"{SKILL}/lib/vrunner_start.sh", self.udid, str(self.port), f"{products}/{xtr[0]}", f"{HOME}/logs", pidfile],
                               capture_output=True, text=True, env={**os.environ, "VRUNNER_TOKEN": self.token}, start_new_session=True)
        except BaseException:
            # Cancelled while waiting for the runner: stop the xcodebuild it already started, then re-raise.
            self.stop(self._from_pidfile(pidfile))
            raise
        try:
            d = json.loads(p.stdout.strip().splitlines()[-1])
        except (IndexError, ValueError):
            self.stop(self._from_pidfile(pidfile))
            raise RuntimeError(f"vrunner_start.sh: {p.stdout[-300:]} {p.stderr[-300:]}")
        started = [x for x in [process_identity(d.get("xcodebuildPid"))] + [process_identity(h) for h in d.get("hubPids", [])] if x]
        if not d.get("ok"):
            self.stop(started)
            raise Failed("runner did not start", log=d.get("log"))
        return started

    @staticmethod
    def _from_pidfile(pidfile):
        try:
            ident = process_identity(int(open(pidfile).read().strip()))
        except (OSError, ValueError):
            return []
        return [ident] if ident and "xcodebuild" in ident["command"] else []

    def stop(self, started):
        """Stop by recorded processes only. Every signal is preceded by a fresh check that the pid is still the process
        we recorded, so a pid reused by an unrelated process is never signalled. Survivors are returned in `left`."""
        xcb = [s for s in started if "xcodebuild" in s["command"]]
        hubs = [s for s in started if "DTServiceHub" in s["command"]]
        for x in xcb:   # DTServiceHub processes started under xcodebuild after we recorded it
            if still_ours(x):
                hubs += [h for h in (process_identity(c) for c in run(["pgrep", "-P", str(x["pid"]), "DTServiceHub"]).stdout.split())
                         if h and h["pid"] not in {s["pid"] for s in hubs}]
        not_ours = [s["pid"] for s in xcb + hubs if not still_ours(s)]
        removed = []
        try:
            self.call({"op": "shutdown"}, timeout=5)   # the runner ends its test, so xcodebuild exits on its own
        except Exception:
            pass
        for x in xcb:   # xcodebuild may take a while to finish the test run after shutdown
            # It can also hang after the test ("Checking for reports corresponding to termination…" when the app was
            # terminated during the run) and ignore SIGTERM: escalate, re-checking ownership before each signal.
            if _still_running_after(x, 60) and _signal(x, signal.SIGTERM) and _still_running_after(x, 10):
                _signal(x, signal.SIGKILL)
                _still_running_after(x, 5)
            removed.append(f"xcodebuild:{x['pid']}")
        for h in hubs:   # orphaned DTServiceHub ignores SIGTERM: escalate, re-checking ownership each time
            if _signal(h, signal.SIGTERM) and _still_running_after(h, 1):
                _signal(h, signal.SIGKILL)
                _still_running_after(h, 3)
            removed.append(f"DTServiceHub:{h['pid']}")
        problems = []
        if self.udid != "-":
            try:   # blocks while a stuck xcodebuild still holds the runner app; never let that stall cleanup
                if run(["xcrun", "simctl", "uninstall", self.udid, RUNNER_APP], timeout=60).returncode == 0:
                    removed.append(f"runner-app@{self.udid}")
            except subprocess.TimeoutExpired:
                problems.append("uninstalling the runner app timed out (it is reinstalled on the next start)")
        left = [s for s in xcb + hubs if still_ours(s)]
        res = dict(port=self.port, removed=" ".join(removed), left=left)
        if problems:
            res["problems"] = problems
        if port_listening(self.port):
            res["portStillListening"] = True
        if not_ours:
            res["notOursAnymore"] = not_ours
        return res

    # app -----------------------------------------------------------------------
    def launch(self, env, args=()):
        r = self.call({"op": "launch", "env": env, "args": list(args)})
        if not r.get("ok"):
            raise Failed("app did not reach the foreground", runner=r)
        return r

    def terminate(self):
        return self.call({"op": "terminate"})

    def orientation(self, set_to=None):
        """Current orientation and app window size; with `set_to`, rotate first (portrait, landscapeLeft, …)."""
        return self.act({"op": "orientation", **({"set": set_to} if set_to else {})})

    def state(self):
        """XCUIApplication.State raw value: 4 = running in the foreground."""
        return self.call({"op": "state"}).get("state")

    # observe -------------------------------------------------------------------
    def tree(self):
        return self.act({"op": "tree"})

    def find(self, sel):
        r = self.call({"op": "find", "sel": sel})
        if not r.get("ok") and r.get("code"):   # a refusal or error, not "no matches"
            raise Failed(r.get("message") or r["code"], runner=r)
        return r.get("matches", [])

    def get(self, sel):
        return self.act({"op": "get", "sel": sel})["element"]

    def wait(self, sel, state="visible", timeout=5):
        return self.act({"op": "wait", "sel": sel, "timeout": timeout, "state": state}, timeout=timeout + 60)

    # act -----------------------------------------------------------------------
    def tap(self, sel):
        return self.act({"op": "tap", "sel": sel})

    def long_press(self, sel, ms=800):
        return self.act({"op": "longpress", "sel": sel, "ms": ms})

    def type(self, sel, text):
        body = {"op": "type", "text": text}
        if sel is not None:
            body["sel"] = sel
        return self.act(body)

    def key(self, combo):
        return self.act({"op": "key", "combo": combo})

    def swipe(self, direction, sel=None):
        body = {"op": "swipe", "dir": direction}
        if sel is not None:
            body["sel"] = sel
        return self.act(body)

    def alert(self, action, button=None, timeout=5):
        body = {"op": "alert", "action": action, "timeout": timeout}
        if button:
            body["button"] = button
        return self.act(body, timeout=timeout + 60)
