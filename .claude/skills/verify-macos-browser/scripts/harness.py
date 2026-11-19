"""The proof harness: the `mac` handle a proof receives, and `prove`, which runs a proof file and writes its evidence.

A proof is a short Python file written for one change, saved with its evidence, never committed. Its docstring is the
claim; it defines `run(mac)` and may set `FLAGS = {"caseName": True}` (FeatureFlag cases to pin), `LIVE = ["duck.ai"]`
(live services it depends on) and `AUTOMATION = True` (start the AutomationServer for `url()` and `navigate()`; it
turns off popup blocking and the quit survey, so never use it to verify either).

Every action goes through verify.sh, the low-level layer. The harness keeps one run record (the checks in the order
they ran, problems, warnings, notes, unverified items, the phase reached); the verdict and report.md come from it alone.
"""
from __future__ import annotations

import importlib.util
import inspect
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import time
import traceback
import uuid

sys.dont_write_bytecode = True   # keep __pycache__ out of the skill directory
SCRIPTS = os.path.dirname(os.path.realpath(__file__))
SKILL = os.path.dirname(SCRIPTS)
ROOT = os.path.realpath(os.path.join(SKILL, "..", "..", ".."))   # the checkout this skill belongs to
VERIFY_SH = os.path.join(SCRIPTS, "verify.sh")
HOME = os.environ.get("VERIFY_MACOS_HOME", os.path.expanduser("~/.ddg-verify-macos"))
TARGETS = ("mac", "vm", "vm-1", "vm-2")
VIDEO = "recording.mp4"
sys.path.insert(0, SCRIPTS)
import vhelp  # noqa: E402

TEMPLATE = '''"""What this proves, in one sentence: what the user sees, under which conditions."""
FLAGS = {}          # FeatureFlag cases to pin, e.g. {"someFlag": True}; every flag the behavior depends on
LIVE = []           # live services this proof depends on, e.g. ["duck.ai"]
AUTOMATION = False  # True for url()/navigate(); turns off popup blocking and the quit survey


def run(mac):
    mac.mark()                                        # telemetry counts from here
    mac.key("cmd+t")                                  # the action under test, through the user's path
    mac.expect_tab_count(2)                           # an independent read of the end state
    mac.expect_pixel("m_mac_new-tab-page_loading_time")
    mac.shot("two-tabs")
'''

# macOS virtual key codes for key("cmd+t"): letters, digits and the keys proofs press.
KEYS = dict(zip("asdfhgzxcv", range(10)), b=11, q=12, w=13, e=14, r=15, y=16, t=17, o=31, u=32, i=34, p=35,
            l=37, j=38, k=40, n=45, m=46, **{"1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
                                              "8": 28, "0": 29, ",": 43, ".": 47, "/": 44, "[": 33, "]": 30},
            **{"return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
               "left": 123, "right": 124, "down": 125, "up": 126})
MODIFIERS = ("cmd", "shift", "opt", "ctrl")


class Refused(Exception):
    """A caller error caught before anything is written: exit 2."""


class ProofError(Exception):
    """The run can't tell: a setup step or an action failed, or a read was impossible."""


class CheckFailed(Exception):
    """A recorded check failed; the proof stops there."""


class _Stop(BaseException):
    """Ctrl-C / SIGTERM. A BaseException, so a proof's `except Exception` can't swallow it."""


# ---------------------------------------------------------------- the run record and its verdict
class Record:
    def __init__(self):
        self.checks = []        # (name, ok, detail) in the order they ran
        self.problems = []      # cleanup or evidence failures: never dropped
        self.warnings = []
        self.notes = []
        self.unverified = []    # (what, why)
        self.shots = []         # screenshot files the proof took, in order
        self.phase = "setup"    # setup | proof | cleanup: how far the run got
        self.error = None       # why the run stopped early, prefixed with the phase it stopped in
        self.action_errors = []  # actions or reads that failed, even if the proof caught the error
        self.app_running = None  # at the end of the proof; None when the proof never started
        self.cancelled = False
        self.video = {}         # None when off (--no-video); else path, seconds, bytes once written, error if it failed


def label(rec):
    """(label, exit code), by fixed rules. Never a pass by default."""
    if rec.cancelled:
        return "INCONCLUSIVE", 130
    if any(not ok for _, ok, _ in rec.checks):
        return "FAIL", 1
    if rec.app_running is False:
        return "FAIL", 1
    if rec.error or rec.action_errors or not any(ok for _, ok, _ in rec.checks) or rec.app_running is not True:
        return "INCONCLUSIVE", 2
    return "PASS", 2 if rec.problems else 0


def _line(text):
    """Multi-line command output on one Markdown line."""
    return " ".join(str(text).split())


def _short(sha):
    return f"`{sha[:16]}…`" if sha else "?"


def report(doc, rec, manifest, evidence):
    """report.md for one run, in verify-ios order: Verified, Evidence, Outcome, Details, Unverified."""
    def link(name):
        return f"[{name}]({name})" if os.path.isfile(os.path.join(evidence, name)) else None

    verdict, code = label(rec)
    m = manifest or {}
    shots = [s for s in (link(s) for s in rec.shots) if s]
    telemetry = [x for x in (link("pixels.json"), link("wide-events.json")) if x]
    if rec.video is None:
        recording = "off (--no-video)"
    elif link(VIDEO):
        recording = link(VIDEO) + (f" ({rec.video['seconds']:.1f} s)" if rec.video.get("seconds") else "")
    else:
        recording = "(none: see Problems)" if rec.video.get("error") else "(none: the proof never started)"
    lines = [f"# Proof: {doc.splitlines()[0]}", "", "## Verified", "", doc, "", "## Evidence", "",
             "Paths are relative to this report.", "",
             f"- Recording: {recording}",
             f"- Screenshots: {', '.join(shots) or '(none)'}",
             f"- Final screen: {link('final.png') or '(not captured)'}",
             f"- Telemetry: {', '.join(telemetry) or '(none)'}",
             f"- App log: {link('app.log') or '(not captured)'}" + (f", {link('log.txt')}" if link("log.txt") else ""),
             "", "## Outcome", "",
             f"**{verdict}**" + (" with problems (exit 2)" if verdict == "PASS" and code else "")
             + (f" ({_line(rec.error)})" if rec.error else ""), ""]
    passed = [name for name, ok, _ in rec.checks if ok]
    failed = [f"{name}" + (f": {_line(detail)}" if detail else "") for name, ok, detail in rec.checks if not ok]
    if rec.app_running is not None:
        (passed if rec.app_running else failed).append("app still running at the end")
    lines += ["Passed:"] + [f"- {c}" for c in passed or ["(none)"]]
    lines += ["", "Failed:"] + [f"- {c}" for c in failed or (["(the run stopped: see above)"] if verdict != "PASS" else ["(none)"])]
    lines += ["", "Problems (cleanup or evidence):"] + [f"- {p}" for p in rec.problems or ["(none)"]]
    if rec.action_errors:
        lines += ["", "Actions or reads that failed (the run can't tell):"] + [f"- {_line(e)}" for e in rec.action_errors]
    if rec.warnings:
        lines += ["", "Warnings:"] + [f"- {w}" for w in rec.warnings]
    if rec.notes:
        lines += ["", "Notes:"] + [f"- {n}" for n in rec.notes]
    launch, vm, hashes = m.get("launch") or {}, m.get("vm"), m.get("build_hashes") or {}
    running = m.get("running_hashes") or {}
    dylib = next((k for k in hashes if k.endswith(".debug.dylib")), None)
    if vm:
        target = f"VM {vm.get('host')} (macOS {vm.get('macos')})"
    elif m.get("target", "mac") != "mac":
        target = f"{m['target']} (no VM was reserved)"
    else:
        target = f"this Mac (macOS {m.get('macos') or '?'})"
    lines += ["", "## Details", "",
              f"- Revision: `{(m.get('revision') or '?')[:12]}`"
              + {True: " (uncommitted changes)", False: " (clean)"}.get(m.get("dirty"), ""),
              f"- App build: .debug.dylib {_short(hashes.get(dylib))}; running: {_short(running.get(dylib))}"
              + (" (same binary, checked by doctor)" if dylib and running.get(dylib) == hashes.get(dylib) else ""),
              f"- Target: {target}",
              f"- Pinned flags: {', '.join(m.get('flags') or []) or '(none)'}",
              f"- Language: {launch.get('language', '?')}, locale {launch.get('locale', '?')}; automation "
              + ("on" if launch.get("automation_port") else "off"),
              f"- Evidence: {'live services: ' + ', '.join(m['live']) if m.get('live') else 'app only'}",
              f"- Rerun: `{m.get('rerun', '?')}`",
              f"- Manifest: {link('manifest.json') or '(not written)'}",
              "", "## Unverified", ""]
    lines += [f"- {what}: {why}" for what, why in rec.unverified] or ["- (none)"]
    return _tilde("\n".join(lines) + "\n")


def _tilde(text):
    """The home folder as ~, so a published report or manifest doesn't carry the local user name."""
    return text.replace(os.path.expanduser("~") + os.sep, "~" + os.sep)


def _sh_path(path):
    """A path for a command pasted into zsh or bash: the home folder as an unquoted ~, so it still expands."""
    home = os.path.expanduser("~") + os.sep
    return "~/" + shlex.quote(path[len(home):]) if path.startswith(home) else shlex.quote(path)


# ---------------------------------------------------------------- the handle a proof receives
class Mac:
    """User actions, reads, waiting assertions, telemetry and evidence for one run. Each call runs one verify.sh step."""

    def __init__(self, topic, evidence, rec, automation=False):
        self.topic, self.evidence, self.rec, self.automation = topic, evidence, rec, automation
        self._marked = False

    def _sh(self, command, *args):
        """Run `verify.sh <command> <topic> args`; return (exit code, output). Logged to transcript.jsonl."""
        t0 = time.time()
        p = subprocess.run([VERIFY_SH, command, self.topic, *map(str, args)], cwd=ROOT, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env={**os.environ, "VERIFY_WORKTREE": ROOT,
                                                       "VERIFY_RUN_DIR": self.evidence})
        with open(os.path.join(self.evidence, "transcript.jsonl"), "a") as f:
            f.write(json.dumps(dict(t=time.strftime("%Y-%m-%dT%H:%M:%S%z"), cmd=[command, *map(str, args)],
                                    exit=p.returncode, secs=round(time.time() - t0, 1), out=p.stdout[-2000:])) + "\n")
        return p.returncode, p.stdout.strip()

    def _error(self, msg):
        """A failed action or read: recorded first, so a proof that catches it still can't pass."""
        self.rec.action_errors.append(msg)
        return ProofError(msg)

    def _do(self, command, *args):
        """An action or setup step: any nonzero exit stops the run (the run can't tell)."""
        code, out = self._sh(command, *args)
        if code:
            raise self._error(f"{command} {' '.join(map(str, args))}: exit {code}: {out[-600:]}")
        return out

    # act --------------------------------------------------------------------
    def press(self, target, nth=None):
        """AX press on the one element `target` names (id, then title); several matches are refused unless nth=."""
        return self._do("ax", "press", target, *([f"nth={nth}"] if nth is not None else []))

    def click(self, target, nth=None):
        """A real mouse click at the element's center."""
        return self._do("ax", "clickel", target, *([f"nth={nth}"] if nth is not None else []))

    def type(self, text):
        return self._do("ax", "type", text)

    def key(self, combo):
        """A key with modifiers, e.g. "cmd+t", "escape", "cmd+shift+n"."""
        *mods, key = combo.lower().split("+")
        if key not in KEYS or any(m not in MODIFIERS for m in mods):
            raise self._error(f"key({combo!r}): unknown key or modifier (keys: {sorted(KEYS)}, modifiers: {MODIFIERS})")
        return self._do("ax", "key", KEYS[key], *mods)

    # read -------------------------------------------------------------------
    def find(self, target):
        """Every element matching `target` (id, title, description or value), one description per line."""
        return [line for line in self._do("ax", "find", target).splitlines() if line.strip()]

    def tab_count(self):
        # The id alone: each tab's close button is TabBarViewItem.closeButton.
        return sum(" id=TabBarViewItem " in line for line in self.find("TabBarViewItem"))

    def url(self):
        """The current tab's URL, through the AutomationServer (AUTOMATION = True)."""
        return self._do("web", "url")

    # assert -----------------------------------------------------------------
    def check(self, what, ok, detail=None):
        """Record a named check; stop the proof if it is false."""
        self.rec.checks.append((what, bool(ok), None if ok else _trim(detail)))
        if not ok:
            raise CheckFailed(what)
        return True

    def eventually(self, what, fn, timeout=8, every=0.5):
        """Poll `fn` until it returns a truthy value; record check `what` either way. A ProofError counts as not yet."""
        end, last = time.time() + timeout, None
        while True:
            try:
                last = fn()
            except ProofError as e:
                self.rec.action_errors.remove(str(e))   # a read that fails now may work on the next poll
                last = e
            else:
                if last:
                    return self.check(what, True) and last
            if time.time() > end:
                if isinstance(last, ProofError):
                    raise self._error(f"{what}: can't tell within {timeout}s: {last}")
                self.check(what, False, f"not true within {timeout}s (last: {last})")
            time.sleep(every)

    def expect_tab_count(self, n, timeout=8):
        return self.eventually(f"{n} tab(s) open", lambda: self.tab_count() == n, timeout)

    def expect_url_contains(self, text, timeout=8):
        return self.eventually(f"URL contains {text!r}", lambda: text in self.url(), timeout)

    # telemetry --------------------------------------------------------------
    def mark(self):
        """Telemetry counts from here: call it right before the action under test."""
        self._do("mark")
        self._marked = True

    def _telemetry(self, what, command, *args):
        if not self._marked:
            raise self._error(f"{what}: call mark() first, right before the action under test (setup fires pixels too)")
        code, out = self._sh(command, *args)
        if code == 2:
            raise self._error(f"{what}: can't tell: {out[-600:]}")
        return self.check(what, code == 0, out[-600:])

    def expect_pixel(self, name, params=None, timeout=10):
        what = f"pixel {name} fired" + (f" with {params}" if params else "")
        return self._telemetry(what, "expect-pixel", name, *(f"{k}={v}" for k, v in (params or {}).items()),
                               "--timeout", timeout)

    def expect_no_pixel(self, name, within=3):
        return self._telemetry(f"pixel {name} not fired", "expect-no-pixel", name, "--within", within)

    def expect_wide_event(self, feature, status=None, timeout=10):
        what = f"wide event {feature}" + (f" status {status}" if status else "")
        return self._telemetry(what, "expect-wide-event", feature, *(["--status", status] if status else []),
                               "--timeout", timeout)

    # evidence ---------------------------------------------------------------
    def shot(self, name):
        """Screenshot of the app's window. One that can't be taken is a Problem, not a failed check."""
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name) or name == "final":
            raise self._error(f"shot({name!r}): use letters, digits, - and _; 'final' is taken by prove")
        code, out = self._sh("shot", name)
        if code:
            self.rec.problems.append(f"screenshot {name} not taken: {out[-300:]}")
        else:
            self.rec.shots.append(f"{name}.png")

    def note(self, text):
        self.rec.notes.append(text)

    def unverified(self, what, why):
        """Name behavior this proof could not verify, and why; it appears in the report."""
        self.rec.unverified.append((what, why))

    # setup only -------------------------------------------------------------
    def navigate(self, url):
        """Setup only, through the AutomationServer: a proof of navigation types in the address bar instead."""
        return self._do("web", "navigate", url)


def _trim(v, n=600):
    s = v if isinstance(v, str) or v is None else json.dumps(v, default=str)
    return s if s is None or len(s) <= n else s[:n] + "…"


# ---------------------------------------------------------------- check
def load(path):
    """Compile and import a proof without running it; return (module, problems). Touches no app or build."""
    try:
        with open(path) as f:
            compile(f.read(), path, "exec")
    except OSError as e:
        return None, [f"cannot read: {e.strerror}"]
    except SyntaxError as e:
        return None, [f"does not compile: {e.msg} (line {e.lineno})"]
    spec = importlib.util.spec_from_file_location(f"proof_{uuid.uuid4().hex[:8]}", path)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as e:
        return None, [f"import failed: {type(e).__name__}: {e}"]
    problems = []
    if not (mod.__doc__ or "").strip():
        problems.append("needs a docstring saying what it proves")
    fn = getattr(mod, "run", None)
    if not callable(fn) or len(inspect.signature(fn).parameters) != 1:
        problems.append("must define run(mac) taking exactly one argument")
    elif inspect.iscoroutinefunction(fn) or inspect.isgeneratorfunction(fn):
        problems.append("run(mac) must be a plain function")
    flags = getattr(mod, "FLAGS", {})
    if not isinstance(flags, dict) or not all(isinstance(k, str) and isinstance(v, bool) for k, v in flags.items()):
        problems.append("FLAGS must map FeatureFlag case names to True/False")
    elif flags:
        names, fixed = vhelp.feature_flags(ROOT)
        problems += [f"FLAGS: {k} is not a FeatureFlag case" for k in flags if k not in names]
        problems += [f"FLAGS: {k} has supportsLocalOverriding: false; the app would ignore it" for k in flags if k in fixed]
    live = getattr(mod, "LIVE", [])
    if not isinstance(live, list) or not all(isinstance(s, str) for s in live):
        problems.append("LIVE must be a list of service names")
    if not isinstance(getattr(mod, "AUTOMATION", False), bool):
        problems.append("AUTOMATION must be True or False")
    return mod, problems


# ---------------------------------------------------------------- evidence folders
ATTEMPT = re.compile(r"\d{8}-\d{6}-([a-z0-9-]+)-([0-9a-f]{4})")   # <stamp>-<name>-<id>


def topic_of(folder):
    """verify.sh's topic for an attempt folder: `<name>-<id>`, name cut to 9 characters, 14 at most.
    shortcut: the app is named "DuckDuckGo - verify-<topic>", and a Debug app named over 35 characters quits at
    launch (callingSymbol() misread stack lines whose module column is cut at 35); drop the cap once #8345 is in."""
    name, uid = ATTEMPT.fullmatch(os.path.basename(folder)).groups()
    return f"{name[:9].strip('-')}-{uid}"


def evidence_root(evidence_dir=None):
    """Where attempt folders go: the caller's --evidence-dir, or HOME. A directory inside a git checkout is refused,
    resolved through symlinks: this repo is public, and evidence there could be committed."""
    if not evidence_dir:
        return os.path.realpath(HOME)
    root = probe = os.path.realpath(evidence_dir)
    while not os.path.isdir(probe):
        probe = os.path.dirname(probe)
    top = subprocess.run(["git", "-C", probe, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if top.returncode == 0:
        raise Refused(f"--evidence-dir {evidence_dir} is inside the git checkout {top.stdout.strip()}: "
                      "pass a directory outside it")
    return root


def _new_attempt(stem, root):
    stem = re.sub(r"[^a-z0-9-]+", "-", stem.lower()).strip("-")[:24].strip("-") or "proof"
    d = os.path.join(root, f"{time.strftime('%Y%m%d-%H%M%S')}-{stem}-{uuid.uuid4().hex[:4]}")
    os.makedirs(d)   # never exist_ok: two attempts never share a folder
    return d


def new_proof(name, root):
    path = os.path.join(_new_attempt(name, root), "proof.py")
    with open(path, "w") as f:
        f.write(TEMPLATE)
    return path


def attempt_dir(path, root):
    """The proof's own folder if it is an untouched attempt folder in `root` (only the proof in it); otherwise a new
    attempt folder in `root` with a copy. A folder that holds anything else (a finished or crashed attempt), or whose
    name isn't an attempt name (like `_lead`, which has no valid topic), is never reused."""
    path = os.path.realpath(path)
    parent = os.path.dirname(path)
    if os.path.dirname(parent) == root and ATTEMPT.fullmatch(os.path.basename(parent)) \
            and os.listdir(parent) == [os.path.basename(path)]:
        return parent, path
    stem = re.sub(r"^\d{8}-\d{6}-|-[0-9a-f]{4}$", "", os.path.basename(parent)) \
        if os.path.basename(path) == "proof.py" else os.path.splitext(os.path.basename(path))[0]
    d = _new_attempt(stem, root)
    copy = os.path.join(d, "proof.py")
    with open(path) as src, open(copy, "w") as dst:
        dst.write(src.read())
    return d, copy


# ---------------------------------------------------------------- prove
def _on_signal(signum, _frame):
    raise _Stop(signal.Signals(signum).name)


def _alive(pid_file):
    try:
        os.kill(int(open(pid_file).read().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def prove(path, target, evidence_dir=None, video=True):
    """Run one proof: setup, the proof, capture, cleanup, report. Returns (exit code, summary).
    Raises Refused, before anything is written, for an --evidence-dir inside a git checkout."""
    root = evidence_root(evidence_dir)
    mod, problems = load(path)
    if problems:
        return 2, dict(proof=path, ok=False, problems=problems)
    if target not in TARGETS:
        return 2, dict(proof=path, ok=False, problems=[f"--target must be one of {TARGETS}"])
    evidence, proof = attempt_dir(path, root)
    topic = topic_of(evidence)
    rec = Record()
    rec.video = {} if video else None
    mac = Mac(topic, evidence, rec, automation=getattr(mod, "AUTOMATION", False))
    vm = None if target == "mac" else ("auto" if target == "vm" else target)
    shown_dir = root if evidence_dir else None
    rerun = rerun_command(proof, target, shown_dir, video)
    old = {s: signal.signal(s, _on_signal) for s in (signal.SIGINT, signal.SIGTERM)}
    running = None
    try:
        if vm:
            mac._do("vm", vm)
        for name, on in getattr(mod, "FLAGS", {}).items():
            mac._do("flag", name, "on" if on else "off")
        mac._do("build", ROOT, *(["--automation"] if mac.automation else []))
        doctor = mac._do("doctor")
        running = json.loads(re.search(r"^running_hashes=(.*)$", doctor, re.M).group(1))
        if video:
            _record(mac, rec, "start")
        rec.phase = "proof"
        mod.run(mac)
        if not rec.checks:
            rec.error = "proof: nothing was checked"
    except _Stop as e:
        rec.cancelled, rec.error = True, f"{rec.phase}: cancelled by {e}"
    except CheckFailed as e:
        rec.error = f"proof: check failed: {e}"
    except BaseException as e:   # SystemExit too: a proof's exit() must not skip cleanup and the report
        rec.error = f"{rec.phase}: {type(e).__name__}: {e}"
        if not isinstance(e, ProofError):
            with open(os.path.join(evidence, "traceback.txt"), "w") as f:
                f.write(traceback.format_exc())
    finally:
        for s in old:   # capture, cleanup and the report must not be interrupted
            signal.signal(s, signal.SIG_IGN)
    try:
        _finish(mac, rec, evidence)
        manifest = _manifest(evidence, rec, proof, rerun, running, getattr(mod, "LIVE", []), target, shown_dir)
        with open(os.path.join(evidence, "report.md"), "w") as f:
            f.write(report(mod.__doc__.strip(), rec, manifest, evidence))
    finally:
        for s, h in old.items():
            signal.signal(s, h)
    verdict, code = label(rec)
    return code, dict(ok=code == 0, verdict=verdict, reason=rec.error, problems=rec.problems, proof=proof,
                      evidence=evidence, report=os.path.join(evidence, "report.md"))


def rerun_command(proof, target, evidence_dir=None, video=True):
    """The report's rerun command: same checkout, proof, target, evidence directory and video setting; it works pasted
    into zsh."""
    return f"cd {_sh_path(ROOT)} && {_sh_path(os.path.join(SKILL, 'bin', 'verify-macos-browser'))} prove " \
           f"{_sh_path(proof)} --target {target}" + (f" --evidence-dir {_sh_path(evidence_dir)}" if evidence_dir else "") \
           + ("" if video else " --no-video")


def _record(mac, rec, step):
    """Start or stop the screen recording. A recording that fails is a Problem, never a failed check."""
    code, out = mac._sh("record", step)
    written = re.search(r"seconds=([\d.]+) bytes=(\d+)", out)
    if written:
        rec.video.update(path=VIDEO, seconds=float(written[1]), bytes=int(written[2]))
    if code:
        rec.video["error"] = f"screen recording {'not started' if step == 'start' else 'failed'}: {_line(out[-300:])}"
        rec.problems.append(rec.video["error"])


def _finish(mac, rec, evidence):
    """Final state, logs and cleanup, whatever happened; every failure here is a Problem."""
    started = rec.phase == "proof"
    rec.phase = "cleanup"
    if started:
        code, out = mac._sh("ax", "front")
        last = out.splitlines()[-1] if out else ""
        # Only ax's own answer decides; an ssh blip or other error leaves it unknown (INCONCLUSIVE, not FAIL).
        rec.app_running = True if last in ("yes", "no") else False if last.startswith("APP NOT RUNNING") else None
        if rec.app_running is not True:
            rec.notes.append(f"app {'not running' if rec.app_running is False else 'state unknown'} at the end: {out[-200:]}")
        code, out = mac._sh("shot", "final") if rec.app_running else (1, "app not running")
        if code:
            rec.problems.append(f"final screenshot not taken: {out[-300:]}")
        if rec.video is not None and "error" not in rec.video:
            _record(mac, rec, "stop")   # after the final screenshot, so the video ends on the final state
        if mac._marked and not _alive(os.path.join(evidence, "pixel_stream.pid")):
            rec.problems.append("pixel stream died during the run: telemetry checks after that can't be trusted")
        code, out = mac._sh("logs")
        if code:
            rec.problems.append(f"log.txt not written: {out[-300:]}")
    host = (open(os.path.join(evidence, "vm")).read().strip() if os.path.exists(os.path.join(evidence, "vm")) else None)
    code, out = mac._sh("cleanup")
    if code:
        rec.problems.append(f"cleanup failed (exit {code}): {out[-600:]}")
    lock = os.path.join(HOME, ".vm-locks", host or "-", "topic")
    if host and os.path.exists(lock) and open(lock).read().strip() == mac.topic:
        rec.problems.append(f"VM {host} not released: its lock still names this run")


def _manifest(evidence, rec, proof, rerun, running, live, target, evidence_dir=None):
    """Extend the manifest verify.sh cleanup wrote with the proof's own fields."""
    path = os.path.join(evidence, "manifest.json")
    try:
        with open(path) as f:
            m = json.load(f)
    except (OSError, ValueError) as e:
        rec.problems.append(f"manifest.json not written by cleanup: {e}")
        m = {}
    verdict, code = label(rec)
    m.update(proof=os.path.relpath(proof, evidence), target=target, evidence_dir=evidence_dir, rerun=rerun, running_hashes=running, live=live,
             verdict=verdict, exit=code, reason=rec.error, phase_reached=rec.phase,
             checks=[dict(check=n, ok=ok, detail=d) for n, ok, d in rec.checks], problems=rec.problems,
             unverified=[dict(what=w, why=y) for w, y in rec.unverified],
             video=dict(off=True) if rec.video is None else rec.video)
    with open(path, "w") as f:
        f.write(_tilde(json.dumps(m, indent=1)))
    return m
