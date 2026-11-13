"""The proof harness: the `ios` handle a proof receives, and `prove`, which runs a proof file and writes its evidence.

A proof is a short Python file written for one change, saved with its evidence, never committed. It defines `run(ios)`
and may set `DEVICES = ["iphone", "ipad"]`, `LIVE = ["duck.ai"]` (live services it depends on) and
`FLAGS = {"flagName": True}` (remote feature flags to pin, on top of env.PINNED_FLAGS).

A run passes only when the proof returned, recorded at least one passing check and no failing one, and the app was
still in the foreground at the end. Anything that goes wrong before the proof's own steps is an error, not a failure.
"""
import importlib.util, inspect, json, os, shutil, signal, sys, time, traceback, urllib.parse, uuid

from . import env
from .device import Device, fixture, fixture_release
from .env import APP, EVIDENCE, ROOT, SKILL, Busy, DeviceLock, Failed, SetupFailed, Unsupported, run
from .telemetry import Pixels, WideEvents

TEMPLATE = '''"""What this proves, in one sentence (the user-visible behavior, not the code path)."""
from verify_ios import steps

DEVICES = ["iphone", "ipad"]
LIVE = []    # live services this proof depends on, e.g. ["duck.ai"]; empty means local fixture / app only
FLAGS = {}   # remote feature flags to pin for this proof, e.g. {"someFlag": True}


def run(ios):
    steps.fresh_start(ios)
    token = ios.token("demo")
    ios.mark()                                   # telemetry assertions count from here
    steps.open_fixture(ios, token)               # the action under test, through the user's path
    ios.expect_web_text("#token", token)         # an independent read of the end state
'''

LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}


# Runner codes that mean "absent", as opposed to a refusal or an error that must surface.
ABSENT = {"NOT_FOUND", "TIMEOUT"}


class Ios:
    """The handle a proof receives: user actions, reads, waiting assertions, telemetry and evidence for one device."""

    def __init__(self, device, evidence, flags=None, device_obj=None, launch=None):
        self.device = device                     # "iphone" | "ipad"
        self.form_factor = "phone" if device == "iphone" else "tablet"   # pixel names end in _ios_<form_factor>
        self.d = device_obj or Device(device)
        self.evidence = evidence
        self.flags = dict(flags or {})
        self.launch_config = env.validate_launch(launch or {})
        self.checks, self.unverified_items, self.notes, self.warnings = [], [], [], []
        self.hosts = set()                       # non-local hosts the proof saw, to check LIVE
        self.cleanups = []                       # (what, fn) undo steps, run in reverse after the proof
        self.capture = {}                        # capture conditions screenshots depend on, for the manifest
        self.pixels = None
        self.wide_events = None
        self.launched = None                     # what the last launch/reset verified (build identity, flags)

    # transcript ------------------------------------------------------------------
    def _log(self, action, args, fn):
        t0 = time.time()
        entry = dict(t=time.strftime("%Y-%m-%dT%H:%M:%S%z"), device=self.device, action=action, args=args)
        try:
            out = fn()
            entry.update(ok=True, result=_trim(out))
            after = out.get("after") if isinstance(out, dict) else None
            if isinstance(after, dict) and after.get("changed") is False:
                self.warnings.append(f"{action} {args[:1]} changed nothing in the UI tree")
            return out
        except Exception as e:
            entry.update(ok=False, error=f"{type(e).__name__}: {e}", detail=_trim(getattr(e, "extra", None)))
            raise
        finally:
            entry["ms"] = int((time.time() - t0) * 1000)
            with open(os.path.join(self.evidence, "transcript.jsonl"), "a") as f:
                f.write(json.dumps(entry, default=str) + "\n")

    # session ---------------------------------------------------------------------
    def reset(self):
        """Reinstall and launch: no app data, one blank tab, per-site permissions and daily pixel state cleared."""
        return self._session("reset", lambda: self.d.reset(flags=self.flags, **({"launch": self.launch_config} if any(self.launch_config.values()) else {})))

    def launch(self):
        return self._session("launch", lambda: self.d.launch(flags=self.flags, **({"launch": self.launch_config} if any(self.launch_config.values()) else {})))

    def _session(self, action, fn):
        """A launch that fails is setup trouble (build identity, readiness, runner), not the behavior under proof."""
        try:
            self.launched = self._log(action, [self.flags], fn)
        except Failed as e:
            raise SetupFailed(f"{action}: {e}", **e.extra) from e
        return self.launched

    def checkpoint(self, instruction, timeout=900):
        """Pause in this attempt; acknowledge or cancel with the paths written to checkpoint.json."""
        if not isinstance(timeout, (int, float)) or not 0 < timeout <= 3600:
            raise SetupFailed("checkpoint timeout must be between 0 and 3600 seconds")
        checkpoint_id = uuid.uuid4().hex
        ack = os.path.join(self.evidence, f"ack-{checkpoint_id}")
        cancel = os.path.join(self.evidence, f"cancel-{checkpoint_id}")
        record = dict(id=checkpoint_id, instruction=instruction, acknowledge=ack, cancel=cancel, timeout=timeout,
                      startedAt=time.time(), deadlineAt=time.time() + timeout, status="pending")
        path = os.path.join(self.evidence, "checkpoint.json")
        def save():
            _write(path, json.dumps(record, indent=2))
        save()
        print(f"{instruction}\nAcknowledge: touch {ack}\nCancel: touch {cancel}", flush=True)
        deadline = time.monotonic() + timeout
        try:
            while True:
                if os.path.exists(cancel):
                    record["status"] = "cancelled"
                    raise _Stop("manual checkpoint")
                if os.path.exists(ack):
                    record["status"] = "acknowledged"
                    record["acknowledgedAt"] = time.time()
                    return checkpoint_id
                if time.monotonic() >= deadline:
                    record["status"] = "timedOut"
                    raise SetupFailed("manual checkpoint timed out")
                time.sleep(0.2)
        finally:
            if record["status"] == "pending":
                record["status"] = "interrupted"
            record["finishedAt"] = time.time()
            save()
            self._log("checkpoint", [checkpoint_id], lambda: record)

    def doctor(self):
        return self._log("doctor", [], self.d.doctor)

    def on_cleanup(self, what, fn):
        """Register an undo step for a change this proof makes outside the app (a simulator setting, a simulated
        location). Undo steps run in reverse order after the proof, whether it passed, failed or was cancelled; one that
        fails doesn't stop the others and is reported under Problems."""
        self.cleanups.append((what, fn))

    def _run_cleanups(self):
        problems = []
        for what, fn in reversed(self.cleanups):
            try:
                self._log("undo", [what], fn)
            except Exception as e:
                problems.append(f"undo '{what}' failed: {type(e).__name__}: {e}")
        self.cleanups = []
        return problems

    # capture conditions (each one is undone after the proof and recorded in the manifest) ---------------------
    TEXT_SIZES = ("extra-small", "small", "medium", "large", "extra-large", "extra-extra-large", "extra-extra-extra-large",
                  "accessibility-medium", "accessibility-large", "accessibility-extra-large",
                  "accessibility-extra-extra-large", "accessibility-extra-extra-extra-large")

    def appearance(self, mode):
        """Light or dark mode for the whole simulator."""
        if mode not in ("light", "dark"):
            raise Failed("appearance must be light or dark")
        self._condition("appearance", lambda: self.d.ui("appearance"), lambda v: self.d.ui("appearance", v), mode)

    def text_size(self, size):
        """Dynamic Type size: "large" is the iOS default; see Ios.TEXT_SIZES."""
        if size not in self.TEXT_SIZES:
            raise Failed(f"text size must be one of {self.TEXT_SIZES}")
        self._condition("textSize", lambda: self.d.ui("content_size"), lambda v: self.d.ui("content_size", v), size)

    ORIENTATIONS = ("portrait", "landscapeLeft", "landscapeRight")   # the app doesn't support upside-down portrait

    def rotate(self, orientation):
        """portrait, landscapeLeft or landscapeRight. Fails if the app's window didn't follow the device."""
        if orientation not in self.ORIENTATIONS:
            raise Failed(f"orientation must be one of {self.ORIENTATIONS}")

        def apply(v):
            after = self.d.driver.orientation(set_to=v)
            w, h = after.get("window") or [0, 0]
            if (w > h) != v.startswith("landscape"):   # the app's window must have followed the device
                raise Failed(f"the app did not rotate to {v} (window {w}×{h})", orientation=after)
            return after

        def read():   # before anything rotates, XCUITest reports "unknown": the simulator starts in portrait
            current = self.d.driver.orientation().get("orientation")
            return current if current in self.ORIENTATIONS else "portrait"
        self._condition("orientation", read, apply, orientation)

    def fixed_status_bar(self):
        """Status bar fixed at 9:41 with full battery and signal, so screenshots compare across runs. Read back from
        the simulator before it is recorded."""
        self.on_cleanup("clear the status bar override", lambda: self.d.status_bar(False))   # before the change
        self._setup("status bar", ["fixed"], lambda: self.d.status_bar(True))
        if not self.d.capture_conditions()["statusBar"].startswith("fixed"):
            raise SetupFailed("the status bar override did not take effect")
        self.capture["statusBar"] = "fixed (9:41)"

    def default_capture_conditions(self):
        """Light mode, default text size, portrait, live status bar: the known state every fresh start begins in, even
        if an earlier run was killed before its undo steps ran."""
        def apply():
            self.d.ui("appearance", "light")
            self.d.ui("content_size", "large")
            self.d.status_bar(False)
            self.d.driver.orientation(set_to="portrait")
        self._setup("default capture conditions", [], apply)
        self.capture = self.d.capture_conditions()

    def _condition(self, name, read, write, value):
        previous = read()
        if previous != value:   # registered before the change, so a change that fails halfway is still undone
            self.on_cleanup(f"restore {name} {previous}", lambda: write(previous))
        self._setup(name, [value], lambda: write(value))
        self.capture[name] = value

    def _setup(self, action, args, fn):
        """Run a setup step; its failure is setup trouble (INCONCLUSIVE), not the behavior under proof."""
        try:
            return self._log(action, args, fn)
        except Failed as e:
            if isinstance(e, SetupFailed):
                raise
            raise SetupFailed(f"{action}: {e}", **e.extra) from e

    def token(self, prefix="t"):
        """A fresh token for this run; never reuse one."""
        return f"{prefix}-{uuid.uuid4().hex[:8]}"

    def fixture_url(self, token):
        return fixture()["url"] + token

    def mark(self):
        """Start counting pixels and wide events from here: call it just before the action under test."""
        def both():
            self.pixels.mark()
            self.wide_events.mark()
        self._log("mark", [], both)

    # native UI ---------------------------------------------------------------------
    def tap(self, locator):
        return self._log("tap", [locator], lambda: self.d.tap(locator))

    def long_press(self, locator, ms=800):
        return self._log("long-press", [locator, ms], lambda: self.d.long_press(locator, ms))

    def type(self, locator, text, submit=False):
        """`locator` "-" types into whatever has focus (fails if nothing has)."""
        return self._log("type", [locator, text, submit], lambda: self.d.type(locator, text, submit))

    def clear(self, locator):
        return self._log("clear", [locator], lambda: self.d.clear(locator))

    def key(self, combo):
        return self._log("key", [combo], lambda: self.d.key(combo))

    def swipe(self, direction, locator=None):
        return self._log("swipe", [direction, locator], lambda: self.d.swipe(direction, locator))

    def scroll_to(self, locator):
        return self._log("scroll-to", [locator], lambda: self.d.scroll_to(locator))

    def alert(self, action="accept", button=None, timeout=5):
        """Answer an app or iOS alert. With more than two buttons, name one with `button=`."""
        return self._log("alert", [action, button], lambda: self.d.alert(action, button, timeout))

    def wait(self, locator, state="visible", timeout=5):
        """States: visible (on screen and hittable), exists, enabled, hidden (no match)."""
        return self._log("wait", [locator, state, timeout], lambda: self.d.wait(locator, state, timeout))

    def exists(self, locator, timeout=1.5):
        """True if the element appears within `timeout`, False if it doesn't. A refusal (ambiguous locator) or a driver
        error (app not running) raises: those are not "absent"."""
        try:
            self.d.wait(locator, "exists", timeout)
            return True
        except Failed as e:
            if _code(e) in ABSENT:
                return False
            raise

    def get(self, locator, attr="value"):
        return self._log("get", [locator, attr], lambda: self.d.get(locator, attr))["value"]

    def find(self, locator):
        """Matches for `locator`; [] only when nothing matches (errors raise)."""
        try:
            return self.d.find(locator)["matches"]
        except Failed as e:
            if str(e) in ("no match", "no web match") or _code(e) in ABSENT:
                return []
            raise

    def snapshot(self):
        return self.d.snapshot()

    def focused(self):
        """The accessibility id of the element with keyboard focus, or None. Fails if the tree can't be read."""
        return self.d.snapshot().get("focused")

    # web channel (setup and read-back only) ---------------------------------------
    def url(self):
        """The current tab's URL. Fails when the tab shows no web page (use page_url to test for that)."""
        return self._seen(self.d.web.url())

    def page_url(self):
        """The current tab's URL, or None when it shows no web page (the new-tab page, native Duck.ai UI)."""
        return self._seen(self.d.web.page_url())

    def _seen(self, url):
        host = urllib.parse.urlparse(url).hostname if url else None
        if host and host not in LOCAL_HOSTS:
            self.hosts.add(host)
        return url

    def eval(self, js):
        return self._log("web eval", [js[:200]], lambda: self.d.web.eval(js))

    def navigate(self, url):
        """Setup only: a proof of navigation must use the address bar (steps.open_url)."""
        self._seen(url)
        return self._log("web navigate", [url], lambda: self.d.web.navigate(url))

    def handles(self):
        return self.d.web.handles()

    # assertions ------------------------------------------------------------------
    def eventually(self, what, fn, timeout=8, every=0.3):
        """Poll `fn` until it returns a truthy value; return it, or fail naming `what` and the last value.
        A Failed raised by `fn` counts as "not yet"; anything else (a driver error, a bug) stops the proof."""
        end, last = time.time() + timeout, None
        while True:
            try:
                last = fn()
                ok = bool(last)
            except Failed as e:
                last, ok = f"<{e}>", False
            if ok:
                return self._record(what, True, last)
            if time.time() > end:
                self._record(what, False, last)
                raise Failed(f"{what}: not true within {timeout}s (last: {_trim(last)})")
            time.sleep(every)

    def check(self, what, ok, detail=None):
        """Record a named check; fail the proof if it is false."""
        self._record(what, bool(ok), detail)
        if not ok:
            raise Failed(f"check failed: {what}", detail=_trim(detail))
        return True

    def expect_url_contains(self, text, timeout=10):
        return self.eventually(f"URL contains {text!r}", lambda: text in (self.page_url() or "") and self.page_url(), timeout)

    def expect_no_web_page(self, timeout=8):
        """The current tab shows no web page (e.g. the new-tab page after the Fire button)."""
        return self.eventually("current tab shows no web page", lambda: self.page_url() is None, timeout)

    def expect_web_text(self, css, value, timeout=8):
        return self.eventually(f"{css} reads {value!r}", lambda: self.d.get(f"web:css={css}")["value"] == value, timeout)

    def expect_visible(self, locator, timeout=8):
        self.wait(locator, "visible", timeout)
        return self._record(f"{locator} visible", True)

    def expect_hidden(self, locator, timeout=8):
        self.wait(locator, "hidden", timeout)
        return self._record(f"{locator} gone", True)

    def expect_keyboard(self, shown, timeout=5):
        self.wait("role=keyboard", "exists" if shown else "hidden", timeout)
        return self._record(f"keyboard {'shown' if shown else 'hidden'}", True)

    def expect_focused(self, element_id, timeout=5):
        return self.eventually(f"{element_id} has focus", lambda: self.focused() == element_id, timeout)

    def expect_not_focused(self, element_id, timeout=5):
        return self.eventually(f"{element_id} lost focus", lambda: self.focused() != element_id, timeout)

    def expect_no_alert(self, within=2):
        """No app or iOS alert appears within `within` seconds."""
        try:
            self.d.alert("dismiss", None, within)
        except Failed as e:
            runner = (getattr(e, "extra", None) or {}).get("runner") or {}
            if _code(e) == "NOT_FOUND" and "alert" not in runner:   # the runner saw no alert at all
                return self._record("no alert shown", True)
            if "alert" in runner:   # an alert was on screen, just not answerable
                self.check("no alert shown", False, runner)
            raise
        self.check("no alert shown", False, "an alert appeared (and was dismissed)")

    def expect_pixel(self, name, params=None, occurrence=0, timeout=10):
        """Wait for pixel `name` to fire after ios.mark(); check `params` is a subset of what it carried."""
        px = self._log("pixel", [name, occurrence], lambda: self.pixels.fired(name, occurrence, timeout))
        if params:
            wrong = {k: (v, px["params"].get(k)) for k, v in params.items() if px["params"].get(k) != v}
            self.check(f"pixel {name} params {params}", not wrong, dict(mismatched=wrong, pixel=px))
        else:
            self._record(f"pixel {name} fired", True, px)
        return px

    def expect_no_pixel(self, name, within=3):
        """Pixel `name` does not fire between ios.mark() and `within` seconds from now."""
        self._log("no pixel", [name, within], lambda: self.pixels.not_fired(name, within))
        return self._record(f"pixel {name} not fired", True)

    def expect_wide_event(self, feature, status=None, occurrence=0, timeout=10):
        """Wait for a wide event of `feature` written after ios.mark(); check its status."""
        ev = self._log("wide event", [feature, occurrence], lambda: self.wide_events.wait(feature, occurrence, timeout))
        got = ev.get("feature", {}).get("status")
        self.check(f"wide event {feature}" + (f" status {status}" if status else ""), status is None or got == status, ev)
        return ev

    # evidence --------------------------------------------------------------------
    def shot(self, name):
        """Screenshot the simulator; take one before and after each key action."""
        return self._log("screenshot", [name], lambda: self.d.screenshot(os.path.join(self.evidence, f"{name}.png")))

    def note(self, text):
        self.notes.append(text)

    def unverified(self, what, why):
        """Name behavior this proof could not verify, and why; it appears in the report."""
        self.unverified_items.append(dict(what=what, why=why))

    def _record(self, what, ok, detail=None):
        self.checks.append(dict(check=what, ok=ok, detail=_trim(detail)))
        return detail if detail is not None else ok


def _code(e):
    return ((getattr(e, "extra", None) or {}).get("runner") or {}).get("code")


def _trim(v, n=600):
    s = v if isinstance(v, str) else json.dumps(v, default=str) if v is not None else None
    return s if s is None or len(s) <= n else s[:n] + "…"


# ---------------------------------------------------------------- preflight
def load(path):
    """Compile and import a proof without running it; return (module, problems)."""
    problems = []
    try:   # compile in memory: py_compile would write a __pycache__ into the attempt folder
        with open(path) as f:
            compile(f.read(), path, "exec")
    except SyntaxError as e:
        return None, [f"does not compile: {e.msg} (line {e.lineno})"]
    name = f"proof_{uuid.uuid4().hex[:8]}"
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as e:
        return None, [f"import failed: {type(e).__name__}: {e}"]
    fn = getattr(mod, "run", None)
    if not callable(fn) or len(inspect.signature(fn).parameters) != 1:
        problems.append("must define run(ios) taking exactly one argument")
    elif inspect.iscoroutinefunction(fn) or inspect.isgeneratorfunction(fn) or inspect.isasyncgenfunction(fn):
        problems.append("run(ios) must be a plain function: an async or generator run() would return without running")
    devices = getattr(mod, "DEVICES", list(env.PORT_OFFSET))
    if not isinstance(devices, list) or not devices or any(d not in env.PORT_OFFSET for d in devices) or len(set(devices)) != len(devices):
        problems.append(f"DEVICES must be a non-empty list of distinct {list(env.PORT_OFFSET)}")
    live = getattr(mod, "LIVE", [])
    if not isinstance(live, list) or not all(isinstance(s, str) for s in live):
        problems.append("LIVE must be a list of service names")
    flags = getattr(mod, "FLAGS", {})
    if not isinstance(flags, dict) or not all(isinstance(k, str) and isinstance(v, bool) for k, v in flags.items()):
        problems.append("FLAGS must map feature flag names to True/False")
    elif env.flag_problem(flags):
        problems.append(f"FLAGS: {env.flag_problem(flags)}")
    try:
        env.validate_launch(getattr(mod, "LAUNCH", {}))
        validator = getattr(mod, "validate", None)
        if validator:
            validator()
    except Exception as error:
        problems.append(f"proof configuration: {error}")
    if not (mod.__doc__ or "").strip():
        problems.append("needs a docstring saying what it proves")
    return mod, problems


def check_devices(devices):
    if not devices or any(d not in env.PORT_OFFSET for d in devices) or len(set(devices)) != len(devices):
        raise Failed(f"devices must be distinct names from {list(env.PORT_OFFSET)}, got {devices}")
    return devices


# ---------------------------------------------------------------- evidence folders
def evidence_root(decision_log=None):
    """Where attempt folders go: the default evidence folder, or `proofs/` next to an AStack show-me-your-work
    decision log (decisions.tsv), so the log can link its proofs."""
    if not decision_log:
        return EVIDENCE
    log = os.path.realpath(decision_log)
    if not os.path.isfile(log) or not log.endswith(".tsv"):
        raise Failed(f"--decision-log must be an existing decisions .tsv file: {decision_log}")
    root = os.path.join(os.path.dirname(log), "proofs")
    if os.path.realpath(root).startswith(os.path.realpath(ROOT) + os.sep):
        # evidence there would be untracked files that could be committed, and would change the source fingerprint
        raise Failed("keep the decision log outside this checkout: evidence written next to it would land in the repo")
    return root


def _new_attempt(stem, root=EVIDENCE):
    d = f"{root}/{time.strftime('%Y%m%d-%H%M%S')}-{stem}-{uuid.uuid4().hex[:4]}"
    os.makedirs(d)   # never exist_ok: two attempts never share a folder
    return d


def new_proof(name, root=EVIDENCE):
    """Create a fresh attempt folder with a proof template; return the proof path."""
    path = f"{_new_attempt(name, root)}/proof.py"
    with open(path, "w") as f:
        f.write(TEMPLATE)
    return path


def attempt_dir(path, root=EVIDENCE):
    """The proof's own folder if it is an untouched attempt folder (only the proof in it); otherwise a new attempt
    folder with a copy. A folder that has any other file (a finished or crashed attempt) is never reused."""
    path = os.path.realpath(path)
    parent = os.path.dirname(path)
    if parent.startswith(os.path.realpath(root) + os.sep) and set(os.listdir(parent)) == {os.path.basename(path)}:
        return parent, path
    d = _new_attempt(os.path.splitext(os.path.basename(path))[0], root)
    copy = f"{d}/{os.path.basename(path)}"
    shutil.copy2(path, copy)
    return d, copy


# ---------------------------------------------------------------- prove
class _Stop(BaseException):
    """Ctrl-C / SIGTERM. A BaseException, so a proof's `except Exception` can't swallow it."""


def _on_signal(signum, _frame):
    raise _Stop(signal.Signals(signum).name)


def _ignore_signals():
    return {s: signal.signal(s, signal.SIG_IGN) for s in (signal.SIGINT, signal.SIGTERM)}


def _restore(handlers):
    for s, h in handlers.items():
        signal.signal(s, h)


def prove(path, devices=None, keep=False, decision_log=None):
    """Run one proof file on each device, always writing evidence and cleaning up. Returns (exit code, summary)."""
    mod, problems = load(path)
    if problems:
        return 2, dict(proof=path, ok=False, preflight=problems)
    devices = check_devices(devices or getattr(mod, "DEVICES", list(env.PORT_OFFSET)))
    attempt, proof_path = attempt_dir(path, evidence_root(decision_log))
    live, flags = getattr(mod, "LIVE", []), getattr(mod, "FLAGS", {})
    started = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    results, build = [], None
    old = {s: signal.signal(s, _on_signal) for s in (signal.SIGINT, signal.SIGTERM)}
    try:
        try:
            build = Device.check_build_current()
        except Failed as e:
            results = [dict(device=d, status="error", reason=f"setup: {e}", checks=[], problems=[], evidence=None) for d in devices]
        else:
            for dev in devices:
                results.append(_run_device(mod, dev, f"{attempt}/{dev}", keep, flags))
                if results[-1]["status"] == "cancelled":
                    break
    except _Stop as e:   # between devices, or before the first one started
        results.append(dict(device="-", status="cancelled", reason=f"cancelled by {e}", checks=[], problems=[], evidence=None))
    finally:
        _ignore_signals()   # writing the manifest and report must not be interrupted
    try:
        manifest = _manifest(proof_path, attempt, devices, live, flags, build, results, started, decision_log)
        with open(f"{attempt}/manifest.json", "w") as f:
            json.dump(manifest, f, indent=1)
        with open(f"{attempt}/report.md", "w") as f:
            f.write(_report(mod, manifest, results))
    finally:
        _restore(old)
    code = exit_code([r["status"] for r in results], any(r.get("problems") for r in results))
    return code, dict(proof=proof_path, evidence=attempt, report=f"{attempt}/report.md",
                      results=[{k: r[k] for k in ("device", "status", "reason", "problems") if r.get(k)} for r in results])


def _run_device(mod, device, evidence, keep, flags, device_obj=None):
    lock = DeviceLock(device)
    try:
        lock.acquire(f"prove {os.path.basename(os.path.dirname(evidence))}")
    except Busy as e:
        return dict(device=device, status="busy", reason=str(e), checks=[], problems=[], evidence=None)
    os.makedirs(evidence, exist_ok=True)
    t0 = time.time()
    status, reason, ios, phase = "error", None, None, "setup"
    try:
        try:
            ios = Ios(device, evidence, flags, device_obj, getattr(mod, "LAUNCH", {}))
            ios.launch()
            ios.capture = ios.d.capture_conditions()   # the defaults this run starts from; setters update it
            fixture(user=device)
            ios.pixels = Pixels(ios.d.udid, f"{evidence}/pixels.ndjson")
            ios.pixels.start()
            ios.wide_events = WideEvents(ios.d.data_container)
            phase = "proof"
            returned = mod.run(ios)
            if inspect.isawaitable(returned) or inspect.isgenerator(returned):
                raise Unsupported("run(ios) returned a coroutine or generator: its body never ran")
            phase = "after"
            status, reason = _verdict(ios)
        except _Stop as e:
            status, reason = "cancelled", f"cancelled by {e}"
        except SetupFailed as e:
            status, reason = "error", f"setup: {e}"
        except (Failed, AssertionError) as e:
            status = "fail" if phase == "proof" else "error"
            reason = f"{'' if phase == 'proof' else phase + ': '}{type(e).__name__}: {e}"
        except Exception as e:
            status, reason = "error", f"{phase}: {type(e).__name__}: {e}"
            with open(f"{evidence}/traceback.txt", "w") as f:
                f.write(traceback.format_exc())
    finally:
        handlers = _ignore_signals()   # a second Ctrl-C must not interrupt evidence collection or cleanup
        problems = []
        try:
            if ios:
                problems += _collect(ios)          # the final state first, before anything is undone
                problems += ios._run_cleanups()
        finally:
            try:
                if ios and ios.pixels:
                    ios.pixels.stop()
            finally:
                if not keep:
                    problems += _cleanup(device)
                lock.release()
                _restore(handlers)
        result = dict(device=device, status=status, reason=reason, secs=round(time.time() - t0, 1),
                      checks=ios.checks if ios else [], unverified=ios.unverified_items if ios else [],
                      notes=ios.notes if ios else [], warnings=ios.warnings if ios else [], problems=problems,
                      liveHostsSeen=sorted(ios.hosts) if ios else [], launched=ios.launched if ios else None,
                      capture=ios.capture if ios else {}, evidence=evidence)
        with open(f"{evidence}/result.json", "w") as f:
            json.dump(result, f, indent=1, default=str)
    return result


def _verdict(ios):
    """Pass needs at least one passing check, no failing check, and the app still in the foreground."""
    failed = [c["check"] for c in ios.checks if not c["ok"]]
    if failed:
        return "fail", f"recorded checks failed: {failed}"
    if not any(c["ok"] for c in ios.checks):
        return "fail", "the proof recorded no checks: nothing was verified"
    if not ios.d.foreground():
        ios._record("app still in the foreground at the end", False)
        return "fail", "the app was not in the foreground at the end (crashed or backgrounded)"
    ios._record("app still in the foreground at the end", True)
    return "pass", None


def exit_code(statuses, problems=False):
    """cancelled 130 > error 2 > fail 1 > busy 75 > pass 0. A pass with cleanup or evidence problems exits 2."""
    for status, code in (("cancelled", 130), ("error", 2), ("fail", 1), ("busy", env.EXIT_BUSY)):
        if status in statuses:
            return code
    return 2 if problems else 0


def _collect(ios):
    """Final state, whatever happened: screenshot, native tree, decoded pixels, wide events. Returns problems."""
    problems = []
    steps = [("final screenshot", lambda: ios.d.screenshot(f"{ios.evidence}/final.png")),
             ("final UI tree", lambda: _write(f"{ios.evidence}/final-snapshot.txt", ios.d.snapshot()["tree"]))]
    if ios.pixels:
        steps.append(("pixels", lambda: _write(f"{ios.evidence}/pixels.json", json.dumps(ios.pixels.all(), indent=1))))
    if ios.wide_events:
        steps.append(("wide events", lambda: _write(f"{ios.evidence}/wide-events.json", json.dumps(ios.wide_events.all(), indent=1))))
    for name, fn in steps:
        try:
            fn()
        except Exception as e:
            problems.append(f"could not capture {name}: {type(e).__name__}: {e}")
    return problems


def _write(path, text):
    with open(path, "w") as f:
        f.write(text)


def _cleanup(device):
    """Stop what this proof started for the device, delete its simulator, and, if no other device's proof is running,
    stop the fixture server. Returns problems (survivors, errors); never raises."""
    problems = []
    try:
        res = Device(device).cleanup(delete_sim=True)
        if res.get("left"):
            problems.append(f"cleanup left processes running: {res['left']} (recorded; `cleanup` retries them)")
        problems += [p for r in res.get("removed", []) if isinstance(r, dict) for p in r.get("problems", [])]
    except Exception as e:
        problems.append(f"cleanup failed: {type(e).__name__}: {e}")
    try:   # the server is shared: it stops only when no other device's proof still uses it (no lock taken)
        fixture_release(device)
    except Exception as e:
        problems.append(f"fixture server stop failed: {type(e).__name__}: {e}")
    return problems


def _git(*args):
    return run(["git", "-C", ROOT, *args]).stdout.strip()


def _skill_hash():
    import hashlib
    h = hashlib.sha256()
    for base, dirs, files in sorted(os.walk(SKILL)):
        dirs[:] = sorted(d for d in dirs if d not in ("__pycache__", "xcuserdata"))
        for name in sorted(files):
            p = os.path.join(base, name)
            h.update(os.path.relpath(p, SKILL).encode())
            with open(p, "rb") as f:
                h.update(f.read())
    return h.hexdigest()


def _manifest(proof_path, attempt, devices, live, flags, build, results, started, decision_log=None):
    xcode = run(["xcodebuild", "-version"]).stdout.split()
    hosts = sorted({h for r in results for h in r.get("liveHostsSeen", [])})
    return dict(
        proof=os.path.relpath(proof_path, attempt),
        revision=_git("rev-parse", "HEAD"), branch=_git("rev-parse", "--abbrev-ref", "HEAD"),
        dirty=bool(_git("status", "--porcelain")), worktree=ROOT,
        appBuild=build,   # source fingerprint and sha256 the build was made from, checked before running
        launched={r["device"]: ((r.get("launched") or {}).get("build") or {}).get("runningSha") for r in results if r.get("device") != "-"},
        flags={**env.PINNED_FLAGS, **flags},
        capture={r["device"]: r.get("capture") for r in results if r.get("device") != "-"},
        skillSha256=_skill_hash(), xcode=" ".join(xcode[:4]),
        simulators={r["device"]: dict(udid=(r.get("launched") or {}).get("udid"), type=env.DEVICE_TYPES[r["device"]], runtime=env.RUNTIME,
                                    observed=(r.get("launched") or {}).get("simulator"))
                    for r in results if r.get("device") in env.DEVICE_TYPES},
        live=live or [], liveHostsSeen=hosts,
        evidenceKind="live services: " + ", ".join(live) if live else "local fixture and app only",
        rerun=f"{SKILL}/bin/verify-ios prove {proof_path} --devices {','.join(devices)}" + (f" --decision-log {os.path.realpath(decision_log)}" if decision_log else ""),
        decisionLog=os.path.realpath(decision_log) if decision_log else None,
        started=started, finished=time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        results=[{k: r.get(k) for k in ("device", "status", "reason", "secs", "problems")} for r in results])


def _report(mod, m, results):
    undeclared = [h for h in m["liveHostsSeen"] if not any(s in h for s in m["live"])]
    built = m.get("appBuild") or {}
    lines = [f"# Proof: {(mod.__doc__ or '').strip().splitlines()[0]}", "",
             f"- Revision: `{m['revision'][:12]}` on `{m['branch']}`{' (uncommitted changes)' if m['dirty'] else ''}",
             f"- App build: `{(built.get('sha256') or '?')[:16]}…`, built from this source (checked before running); "
             f"running binary per device: " + ", ".join(f"{d} `{(s or '?')[:16]}…`" for d, s in m["launched"].items()),
             f"- Evidence: {m['evidenceKind']}" + (f". **Undeclared live hosts seen: {', '.join(undeclared)}**" if undeclared else ""),
             f"- Pinned flags: {', '.join(f'{k}={v}' for k, v in m['flags'].items()) or '(none)'}",
             f"- Rerun: `{m['rerun']}`", ""]
    for r in results:
        label = "INCONCLUSIVE" if r["status"] == "error" and (r.get("reason") or "").startswith("setup") else r["status"].upper()
        lines.append(f"## {r['device']}: {label}" + (f" ({r['reason']})" if r.get("reason") else ""))
        if r.get("capture"):
            c = r["capture"]
            lines += ["", "Capture conditions: " + ", ".join(f"{k} {v}" for k, v in c.items() if k != "window")]
        passed = [c["check"] for c in r.get("checks", []) if c["ok"]]
        failed = [c["check"] for c in r.get("checks", []) if not c["ok"]]
        lines += ["", "Passed:"] + [f"- {c}" for c in passed or ["(none)"]]
        lines += ["", "Failed:"] + [f"- {c}" for c in failed or (["(the run stopped: see reason)"] if r["status"] != "pass" else ["(none)"])]
        lines += ["", "Unverified:"] + ([f"- {u['what']}: {u['why']}" for u in r.get("unverified", [])] or ["- (none)"])
        if r.get("problems"):
            lines += ["", "**Problems (cleanup or evidence):**"] + [f"- {p}" for p in r["problems"]]
        if r.get("warnings"):
            lines += ["", "Warnings (actions that changed nothing; check the proof confirmed their effect):"] + [f"- {w}" for w in r["warnings"]]
        if r.get("notes"):
            lines += ["", "Notes:"] + [f"- {n}" for n in r["notes"]]
        if r.get("evidence"):
            lines += ["", f"Evidence: `{r['evidence']}` (transcript.jsonl, screenshots, final-snapshot.txt, pixels.json, wide-events.json)"]
        lines.append("")
    return "\n".join(lines)


def check_only(paths):
    out = []
    for p in paths:
        mod, problems = load(p)
        out.append(dict(proof=p, ok=not problems, problems=problems,
                        devices=getattr(mod, "DEVICES", list(env.PORT_OFFSET)) if mod else None, live=getattr(mod, "LIVE", []) if mod else None))
    return out


def run_proofs(paths, devices=None, keep=False, decision_log=None):
    """Preflight every file first: a broken proof fails before any device is touched."""
    evidence_root(decision_log)   # a bad --decision-log fails before anything runs
    if devices:
        check_devices(devices)
    checked = check_only(paths)
    if not all(c["ok"] for c in checked):
        return 2, dict(ok=False, preflight=checked)
    codes, summaries = [], []
    for p in paths:
        code, s = prove(p, devices, keep, decision_log)
        codes.append(code)
        summaries.append(s)
        if code == 130:
            break
    worst = next((c for c in (130, 2, 1, env.EXIT_BUSY) if c in codes), 0)
    return worst, dict(ok=worst == 0, proofs=summaries)


if __name__ == "__main__":
    sys.exit("use bin/verify-ios prove")
