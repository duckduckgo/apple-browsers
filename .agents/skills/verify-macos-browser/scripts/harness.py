"""The proof harness: the `mac` handle a proof receives, and `prove`, which runs a proof file and writes its evidence.

A proof is a short Python file written for one change, saved with its evidence, never committed. Its docstring is the
claim; it defines `run(mac)` and may set `FLAGS = {"caseName": True}` (FeatureFlag cases to pin), `LIVE = ["duck.ai"]`
(live services it depends on: any other non-local host the app loaded is flagged in the report) and
`AUTOMATION = True` (start the AutomationServer for `url()` and `navigate()`, and collect the hosts the app loaded;
it turns off popup blocking and the quit survey, so never use it to verify either) and `CONDITIONS` (what screenshots
depend on: set before the proof, undone after it; see CONDITION_KEYS).

Every action goes through verify.sh, the low-level layer. The harness keeps one run record (the checks in the order
they ran, problems, warnings, notes, unverified items, the phase reached); the verdict and report.md come from it alone.
"""
from __future__ import annotations

import contextlib
import functools
import http.server
import importlib.util
import inspect
import json
import os
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import traceback
import urllib.parse
import uuid

sys.dont_write_bytecode = True   # keep __pycache__ out of the skill directory
SCRIPTS = os.path.dirname(os.path.realpath(__file__))
SKILL = os.path.dirname(SCRIPTS)
ROOT = os.path.realpath(os.path.join(SKILL, "..", "..", ".."))   # the checkout this skill belongs to
VERIFY_SH = os.path.join(SCRIPTS, "verify.sh")
HOME = os.environ.get("VERIFY_MACOS_HOME", os.path.expanduser("~/.ddg-verify-macos"))
TARGETS = ("mac", "vm", "vm-1", "vm-2")
VIDEO = "recording.mp4"
FIXTURE = os.path.join(SKILL, "fixture")
LOCAL_HOSTS = ("127.0.0.1", "localhost", "::1")
SSH_OPTS = ("-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=15")   # as verify.sh
BASE_OUTCOMES = ("fail", "pass", "unchanged")
sys.path.insert(0, SCRIPTS)
import vhelp  # noqa: E402

TEMPLATE = '''"""What this proves, in one sentence: what the user sees, under which conditions."""
FLAGS = {}          # FeatureFlag cases to pin, e.g. {"someFlag": True}; every flag the behavior depends on
LIVE = []           # live services this proof depends on, e.g. ["duck.ai"]
AUTOMATION = False  # True for url()/navigate(); turns off popup blocking and the quit survey
CONDITIONS = {}     # what screenshots depend on, e.g. dict(appearance="dark", window=(40, 60, 1280, 800), language="en")


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


# CONDITIONS a proof may declare, so screenshots compare between runs and with a base build. Each is set before the proof,
# read back, recorded in the manifest and report, and undone after it. Undeclared ones are recorded too: the appearance
# (a VM starts light; on this Mac the app's own setting, never the system's), the window the app opened, en/en_US.
CONDITION_KEYS = dict(appearance="light or dark", window="(x, y, width, height) in points, top-left origin, below the "
                  "menu bar", language="e.g. en, pt-BR, zh-Hans", locale="e.g. en_US, de_DE")
LANGUAGE, LOCALE = re.compile(r"[a-z]{2,3}(-[A-Za-z0-9]{2,8})*"), re.compile(r"[a-z]{2,3}(_[A-Za-z0-9]{2,8})*")


def condition_problems(c):
    """What is wrong with a proof's CONDITIONS; [] when nothing is. `check` and `prove` refuse a proof with any."""
    if not isinstance(c, dict):
        return ["CONDITIONS must be a dict, e.g. dict(appearance=\"dark\")"]
    problems = [f"CONDITIONS: unknown {k!r} (one of {', '.join(CONDITION_KEYS)})" for k in c if k not in CONDITION_KEYS]
    if "appearance" in c and c["appearance"] not in ("light", "dark"):
        problems.append("CONDITIONS: appearance must be \"light\" or \"dark\"")
    w = c.get("window", (0, 0, 1, 1))
    if not (isinstance(w, (tuple, list)) and len(w) == 4 and all(type(n) is int for n in w)
            and min(w) >= 0 and min(w[2:]) > 0):
        problems.append("CONDITIONS: window must be (x, y, width, height) in whole points, width and height above 0")
    for key, pattern in (("language", LANGUAGE), ("locale", LOCALE)):
        if key in c and not (isinstance(c[key], str) and pattern.fullmatch(c[key])):
            problems.append(f"CONDITIONS: {key} must look like {CONDITION_KEYS[key][5:]}")
    return problems


def conditions_line(m):
    """The conditions a run's screenshots were taken under, as report.md shows them; declared ones are marked."""
    c, declared = m.get("conditions") or {}, m.get("conditions_declared") or []
    shown = [f"{k} {c[k]}" + (" (declared)" if k in declared else "") for k in CONDITION_KEYS if k in c]
    return ", ".join(shown) or "(not recorded)"


def conditions_differ(a, b):
    """The conditions that differ between two runs' manifests: every recorded one, except a window neither run
    declared (the app picks it, and the change under proof may move it)."""
    ca, cb = a.get("conditions") or {}, b.get("conditions") or {}
    declared = set(a.get("conditions_declared") or []) | set(b.get("conditions_declared") or [])
    return [k for k in CONDITION_KEYS if (k != "window" or k in declared) and ca.get(k) != cb.get(k)]


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
        self.checks = []        # (name, ok, detail, what the base build should do) in the order they ran
        self.problems = []      # cleanup or evidence failures: never dropped
        self.warnings = []
        self.notes = []
        self.unpinned = []      # FLAGS the base revision doesn't define, so its run of prove --base didn't pin them
        self.unverified = []    # (what, why)
        self.shots = []         # screenshot files the proof took, in order
        self.phase = "setup"    # setup | proof | cleanup: how far the run got
        self.error = None       # why the run stopped early, prefixed with the phase it stopped in
        self.action_errors = []  # actions or reads that failed, even if the proof caught the error
        self.app_running = None  # at the end of the proof; None when the proof never started
        self.cancelled = False
        self.video = {}         # None when off (--no-video); else path, seconds, bytes once written, error if it failed
        self.hosts = None       # hosts the app loaded pages or resources from; None when not collected (AUTOMATION off)
        self.conditions = {}    # appearance and window as read back from the target, for the manifest
        self.tokens = []        # (token, prefix) issued this run, left out of prove --base's match keys


# ---------------------------------------------------------------- hosts the app loaded
URL = re.compile(r"(?:https?|wss?)://[^\s\"'\\,\]]+")


def host_of(url):
    """The network host `url` loads from; None for URLs that load nothing from the network (duck://, about:, data:)."""
    try:
        p = urllib.parse.urlparse(url.strip())
        return p.hostname if p.scheme in ("http", "https", "ws", "wss") else None
    except ValueError:
        return None


def undeclared(hosts, live):
    """The non-local hosts no LIVE entry covers; an entry covers its own host and its subdomains."""
    return sorted(h for h in hosts or () if h not in LOCAL_HOSTS
                  and not any(h == s or h.endswith("." + s) for s in live))


def evidence_kind(live, hosts):
    """What the evidence rests on: declared or undeclared live services, none observed, or unknown. Hosts are read from
    navigate(), url() and the last page, so a live page opened and left in between goes unseen."""
    services = list(live) + undeclared(hosts, live)
    if services:
        return "live: " + ", ".join(services)
    return "no live hosts observed" if hosts is not None else "unknown: hosts not collected (AUTOMATION is off)"


def label(rec):
    """(label, exit code), by fixed rules. Never a pass by default."""
    if rec.cancelled:
        return "INCONCLUSIVE", 130
    if any(not ok for _, ok, *_ in rec.checks):
        return "FAIL", 1
    if rec.app_running is False:
        return "FAIL", 1
    if rec.error or rec.action_errors or not any(ok for _, ok, *_ in rec.checks) or rec.app_running is not True:
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
    passed = [name for name, ok, *_ in rec.checks if ok]
    failed = [f"{name}" + (f": {_line(detail)}" if detail else "") for name, ok, detail, *_ in rec.checks if not ok]
    if rec.app_running is not None:
        (passed if rec.app_running else failed).append("app still running at the end")
    lines += ["Passed:"] + [f"- {c}" for c in passed or ["(none)"]]
    lines += ["", "Failed:"] + [f"- {c}" for c in failed or (["(the run stopped: see above)"] if verdict != "PASS" else ["(none)"])]
    lines += ["", "Problems (cleanup or evidence):"] + [f"- {p}" for p in rec.problems or ["(none)"]]
    if rec.action_errors:
        lines += ["", "Actions or reads that failed (the run can't tell):"] + [f"- {_line(e)}" for e in rec.action_errors]
    live = m.get("live") or []
    warnings = [f"**Undeclared live host: {h}** (not in LIVE)" for h in undeclared(rec.hosts, live)] + rec.warnings
    if warnings:
        lines += ["", "Warnings:"] + [f"- {w}" for w in warnings]
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
              f"- Conditions: {conditions_line(m)}; automation " + ("on" if launch.get("automation_port") else "off"),
              f"- Evidence: {evidence_kind(live, rec.hosts)}",
              "- Hosts the app loaded: " + ((", ".join(sorted(rec.hosts)) or "(none)") if rec.hosts is not None
                                            else "(not collected: AUTOMATION is off)"),
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

    def __init__(self, topic, evidence, rec, automation=False, checkout=ROOT, as_base=False):
        self.topic, self.evidence, self.rec, self.automation = topic, evidence, rec, automation
        self.checkout = checkout   # the checkout built and proved: this one, or another (prove --checkout)
        self.as_base = as_base     # the base run of prove --base
        self.reset = False         # this Mac, prove --base: park the Debug app's data around the run (verify.sh reset)
        self.base_outcome = "unchanged"   # what checks made now should do on the base build (on_base)
        self._marked = False
        self._fixture = None
        self.undo = []           # (what, verify.sh args) per condition set: run last first after the proof, always
        if automation:
            rec.hosts = set()

    def _sh(self, command, *args):
        """Run `verify.sh <command> <topic> args`; return (exit code, output). Logged to transcript.jsonl."""
        t0 = time.time()
        p = subprocess.run([VERIFY_SH, command, self.topic, *map(str, args)], cwd=self.checkout, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           env={**os.environ, "VERIFY_WORKTREE": self.checkout, "VERIFY_RUN_DIR": self.evidence,
                                "VERIFY_OWNER_PID": str(os.getpid())})
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
    def _act(self, what, *args):
        """One action through ax. Its last line says whether the accessibility tree changed; one that changed nothing
        is a Warning, not a failure: the proof's own reads must then show the effect."""
        out = self._do("ax", *args)
        if out.splitlines()[-1:] == ["changed=no"]:
            self.rec.warnings.append(f"{what} changed nothing in the accessibility tree: the proof's own reads must "
                                     "show its effect")
        return out

    def press(self, target, nth=None):
        """AX press on the one element `target` names (id, then title); several matches are refused unless nth=, and
        a disabled or off-window target is refused."""
        return self._act(f"press({target!r})", "press", target, *([f"nth={nth}"] if nth is not None else []))

    def click(self, target, nth=None):
        """A real mouse click at the element's center."""
        return self._act(f"click({target!r})", "clickel", target, *([f"nth={nth}"] if nth is not None else []))

    def type(self, text):
        """Typed into the focused text element; refused when nothing that takes text has keyboard focus."""
        return self._act(f"type({text!r})", "type", text)

    def key(self, combo):
        """A key with modifiers, e.g. "cmd+t", "escape", "cmd+shift+n"."""
        *mods, key = combo.lower().split("+")
        if key not in KEYS or any(m not in MODIFIERS for m in mods):
            raise self._error(f"key({combo!r}): unknown key or modifier (keys: {sorted(KEYS)}, modifiers: {MODIFIERS})")
        return self._act(f"key({combo!r})", "key", KEYS[key], *mods)

    # read -------------------------------------------------------------------
    def find(self, target):
        """Every element matching `target` (id, title, description or value), one description per line."""
        return [line for line in self._do("ax", "find", target).splitlines() if line.strip()]

    def tab_count(self):
        """Tabs in the front window; other windows' tabs don't count."""
        # The id alone: each tab's close button is TabBarViewItem.closeButton.
        return sum(" id=TabBarViewItem " in line for line in self._do("ax", "findmain", "TabBarViewItem").splitlines())

    def url(self):
        """The current tab's URL, through the AutomationServer (AUTOMATION = True)."""
        url = self._do("web", "url")
        self._saw(url)
        return url

    def _saw(self, *urls):
        if self.rec.hosts is not None:
            self.rec.hosts.update(h for h in map(host_of, urls) if h)

    def _sweep_hosts(self):
        """Add the hosts of the front tab's page and every resource it loaded; a read that fails is a Problem."""
        code, out = self._sh("web", "eval", "return [location.href, ...performance.getEntriesByType('resource')"
                                            ".map(e => e.name)].join(' ')")
        if code:
            self.rec.problems.append(f"hosts of the last page not read: {_line(out[-300:])}")
        else:
            self._saw(*URL.findall(out.replace("\\/", "/")))   # the server JSON-escapes "/" as "\/"

    # assert -----------------------------------------------------------------
    def check(self, what, ok, detail=None):
        """Record a named check; stop the proof if it is false."""
        self.rec.checks.append((what, bool(ok), None if ok else _trim(detail), self.base_outcome))
        if not ok:
            if self.as_base and self.base_outcome == "fail":
                return False   # the bug, as the proof declared: record it and carry on
            raise CheckFailed(what)
        return True

    @contextlib.contextmanager
    def on_base(self, outcome):
        """Checks made inside this block should `outcome` ("fail", "pass" or "unchanged") on the base build, for
        `prove --base`; checks outside any block should be unchanged. On the base run a check expected to fail is
        recorded and the proof carries on; that check returns False."""
        if outcome not in BASE_OUTCOMES:
            raise ValueError(f"on_base takes one of {BASE_OUTCOMES}, got {outcome!r}")
        outer, self.base_outcome = self.base_outcome, outcome
        try:
            yield
        finally:
            self.base_outcome = outer

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
                return self.check(what, False, f"not true within {timeout}s (last: {last})")
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

    # fixture pages ----------------------------------------------------------
    def token(self, prefix="t"):
        """A fresh token for this run, e.g. "t-1a2b3c4d"; never reuse one."""
        token = f"{prefix}-{uuid.uuid4().hex[:8]}"
        self.rec.tokens.append((token, prefix))
        return token

    def fixture_url(self, token):
        """The skill's fixture page showing `token`, served for this run only at 127.0.0.1, for the app on this Mac
        or in the VM. It links to target.html."""
        if not self._fixture:
            vm_file = os.path.join(self.evidence, "vm")
            vm = open(vm_file).read().strip() if os.path.exists(vm_file) else None
            try:
                self._fixture = Fixture(os.path.join(self.evidence, "fixture.log"), vm)
            except OSError as e:
                raise self._error(f"fixture pages not served: {e}")
            self.rec.notes.append(f"fixture pages served at 127.0.0.1:{self._fixture.port} for this run"
                                  + (f" (in {vm} through an ssh reverse tunnel to its loopback)" if vm else ""))
        return f"http://127.0.0.1:{self._fixture.port}/index.html?token={urllib.parse.quote(token)}"

    # setup only -------------------------------------------------------------
    def navigate(self, url):
        """Setup only, through the AutomationServer: a proof of navigation types in the address bar instead."""
        self._saw(url)
        return self._do("web", "navigate", url)


class _FixtureHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):   # to fixture.log in the evidence, not the terminal
        with open(self.server.log_path, "a") as f:
            f.write(f"{self.log_date_time_string()} {fmt % args}\n")


class Fixture:
    """The fixture pages, served for one run on this Mac's loopback only. For a VM, an ssh reverse tunnel binds the
    same port on the VM's loopback: the URL is the same on both, and nothing else on either network can reach it."""

    def __init__(self, log_path, vm=None):
        self.vm, self.tunnel = vm, None
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
                                                      functools.partial(_FixtureHandler, directory=FIXTURE))
        self.server.log_path = log_path
        self.port = self.server.server_address[1]
        # A daemon thread: if the harness dies, the listener dies with it.
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        if vm:
            self.tunnel = subprocess.Popen(["ssh", *SSH_OPTS, "-N", "-o", "ExitOnForwardFailure=yes", "-R",
                                            f"127.0.0.1:{self.port}:127.0.0.1:{self.port}", vm],
                                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            for _ in range(40):   # up once the VM fetches the page through it
                if self.tunnel.poll() is not None:
                    break
                if subprocess.run(["ssh", *SSH_OPTS, vm, f"curl -fsS -o /dev/null http://127.0.0.1:{self.port}/index.html"],
                                  capture_output=True).returncode == 0:
                    return
                time.sleep(0.25)
            err = self.tunnel.stderr.read().decode()[-300:] if self.tunnel.poll() is not None else "timed out"
            self.stop()
            raise OSError(f"the tunnel to {vm} did not come up: {_line(err)}")

    def stop(self):
        """Stop serving, here and in the VM; return problems: a listener still there afterwards."""
        if self.tunnel:
            self.tunnel.terminate()
            try:
                self.tunnel.wait(5)
            except subprocess.TimeoutExpired:
                self.tunnel.kill()
                self.tunnel.wait()
        self.server.shutdown()
        self.server.server_close()
        problems = []
        with socket.socket() as s:
            if s.connect_ex(("127.0.0.1", self.port)) == 0:
                problems.append(f"fixture server still listening on 127.0.0.1:{self.port}")
        if self.vm:
            for _ in range(12):   # sshd drops the forwarded port when the session closes, not always at once
                p = subprocess.run(["ssh", *SSH_OPTS, self.vm, f"nc -z 127.0.0.1 {self.port}"], capture_output=True)
                if p.returncode == 1:
                    break
                time.sleep(0.25)
            else:
                problems.append(f"fixture port {self.port} still open in {self.vm}, or it couldn't tell "
                                f"(ssh exit {p.returncode})")
        return problems


def _trim(v, n=600):
    s = v if isinstance(v, str) or v is None else json.dumps(v, default=str)
    return s if s is None or len(s) <= n else s[:n] + "…"


# ---------------------------------------------------------------- check
def load(path, checkout=ROOT):
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
        names, fixed = vhelp.feature_flags(checkout)
        problems += [f"FLAGS: {k} is not a FeatureFlag case" for k in flags if k not in names]
        problems += [f"FLAGS: {k} has supportsLocalOverriding: false; the app would ignore it" for k in flags if k in fixed]
    live = getattr(mod, "LIVE", [])
    if not isinstance(live, list) or not all(isinstance(s, str) for s in live):
        problems.append("LIVE must be a list of service names")
    if not isinstance(getattr(mod, "AUTOMATION", False), bool):
        problems.append("AUTOMATION must be True or False")
    problems += condition_problems(getattr(mod, "CONDITIONS", {}))
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


def _ignore(_signum, _frame):
    pass


def _alive(pid_file):
    try:
        os.kill(int(open(pid_file).readline()), 0)   # the first line; the rest is its identity (verify.sh)
        return True
    except (OSError, ValueError):
        return False


def checkout_of(path):
    """--checkout: another checkout of this repo to build and prove with this skill, such as a base revision."""
    d = os.path.realpath(path)
    if not os.path.isdir(os.path.join(d, "DuckDuckGo.xcworkspace")):
        raise Refused(f"--checkout {path} is not a checkout of this repo (no DuckDuckGo.xcworkspace)")
    return d


def prove(path, target, evidence_dir=None, video=True, checkout=ROOT):
    """Run one proof: setup, the proof, capture, cleanup, report. Returns (exit code, summary).
    Raises Refused, before anything is written, for an --evidence-dir inside a git checkout.
    Without --evidence-dir, a proof in an attempt folder outside HOME (from new-proof --evidence-dir) runs there."""
    parent = os.path.dirname(os.path.realpath(path))
    if not evidence_dir and ATTEMPT.fullmatch(os.path.basename(parent)) \
            and os.path.dirname(parent) != os.path.realpath(HOME):
        evidence_dir = os.path.dirname(parent)
    root = evidence_root(evidence_dir)
    mod, problems = load(path, checkout)
    if problems:
        return 2, dict(proof=path, ok=False, problems=problems)
    if target not in TARGETS:
        return 2, dict(proof=path, ok=False, problems=[f"--target must be one of {TARGETS}"])
    evidence, proof = attempt_dir(path, root)
    shown_dir = root if evidence_dir else None
    rec, _ = run_one(mod, proof, evidence, topic_of(evidence), target, video, checkout,
                     rerun_command(proof, target, shown_dir, video, checkout), shown_dir)
    verdict, code = label(rec)
    return code, dict(ok=code == 0, verdict=verdict, reason=rec.error, problems=rec.problems, proof=proof,
                      evidence=evidence, report=os.path.join(evidence, "report.md"))


def flags_to_pin(flags, checkout, as_base):
    """(FLAGS to pin, FLAGS skipped). The base run of prove --base skips a flag its revision doesn't define, since the
    change may add it; every other run pins them all, and check refuses one this checkout doesn't define."""
    if not (as_base and flags):
        return flags, []
    names = vhelp.feature_flags(checkout)[0]
    return {k: v for k, v in flags.items() if k in names}, [k for k in flags if k not in names]


def run_one(mod, proof, evidence, topic, target, video, checkout, rerun, shown_dir, as_base=False, reset=False,
            prefer_vm=None):
    """One run of a loaded proof on `checkout`, with its evidence in `evidence`: setup, the proof, capture, cleanup,
    report.md and manifest.json. Returns (record, manifest). A VM is always reset when reserved (`prefer_vm` first for
    --target vm); `reset` resets this Mac around the run too (prove --base)."""
    rec = Record()
    rec.video = {} if video else None
    if as_base:
        rec.notes.append("the base run of prove --base: a check the proof expects to fail here is recorded and the "
                         "proof carries on; the comparison is ../report.md")
    mac = Mac(topic, evidence, rec, getattr(mod, "AUTOMATION", False), checkout, as_base)
    mac.reset = reset and target == "mac"
    vm = None if target == "mac" else ("auto" if target == "vm" else target)
    old = {s: signal.signal(s, _on_signal) for s in (signal.SIGINT, signal.SIGTERM)}
    running = None
    conditions = getattr(mod, "CONDITIONS", {})
    try:
        if vm:
            mac._do("vm", vm, *([prefer_vm] if vm == "auto" and prefer_vm else []))
        else:   # without both grants a run on this Mac can only end in NOT READY, after the whole build
            grants = mac._do("ax", "grants")
            missing = [g for g in ("Accessibility", "Screen Recording") if f"{g.lower().replace(' ', '-')}=true" not in grants]
            if missing:
                raise ProofError(f"NO GRANT: the process running prove has no {' or '.join(missing)} grant ({_line(grants)}); "
                                 "turn it on in System Settings > Privacy & Security for the app it runs under, or "
                                 "prove in a VM")
        if mac.reset:   # a failed reset stops the run: it would run on the engineer's own Debug data
            code, out = mac._sh("reset", "begin")
            failed = re.findall(r"^check\t(.*)\tfail$", out, re.M)
            if code or failed:
                raise ProofError("reset before the run failed, so the run stopped before launching: "
                                 + ("; ".join(failed) if failed else f"exit {code}: {_line(out[-300:])}"))
        set_conditions(mac, conditions, target, launched=False)
        flags, rec.unpinned = flags_to_pin(getattr(mod, "FLAGS", {}), checkout, as_base)
        for name in rec.unpinned:
            rec.notes.append(f"FLAGS: {name} is not defined on the base revision, so this run doesn't pin it")
        for name, on in flags.items():
            mac._do("flag", name, "on" if on else "off")
        mac._do("build", checkout, *(["--automation"] if mac.automation else []),
                "--language", conditions.get("language", "en"), "--locale", conditions.get("locale", "en_US"))
        doctor = mac._do("doctor")
        running = json.loads(re.search(r"^running_hashes=(.*)$", doctor, re.M).group(1))
        set_conditions(mac, conditions, target, launched=True)
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
            # A no-op handler, not SIG_IGN: children (ssh, log show) get the default back, so they stay killable.
            signal.signal(s, _ignore)
    try:
        _finish(mac, rec, evidence)
        manifest = _manifest(evidence, rec, proof, rerun, running, getattr(mod, "LIVE", []), target, shown_dir,
                             sorted(conditions))
        with open(os.path.join(evidence, "report.md"), "w") as f:
            f.write(report(mod.__doc__.strip(), rec, manifest, evidence))
    finally:
        for s, h in old.items():
            signal.signal(s, h)
    return rec, manifest


def rerun_command(proof, target, evidence_dir=None, video=True, checkout=ROOT):
    """The report's rerun command: it starts in the checkout it proved and names the same proof, target, evidence
    directory and video setting; it works pasted into zsh."""
    return f"cd {_sh_path(checkout)} && {_sh_path(os.path.join(SKILL, 'bin', 'verify-macos-browser'))} prove " \
           f"{_sh_path(proof)} --target {target}" + (f" --checkout {_sh_path(checkout)}" if checkout != ROOT else "") \
           + (f" --evidence-dir {_sh_path(evidence_dir)}" if evidence_dir else "") + ("" if video else " --no-video")


def _readback(out, key):
    """The value verify.sh read back, from its last `key=value` line."""
    return re.findall(rf"^{key}=(.*)$", out, re.M)[-1]


def set_conditions(mac, conditions, target, launched):
    """Before launch: put the appearance back to the default (whatever a killed run left), then set a declared one, so
    the app starts in it. After launch: set a declared window. Each is read back and recorded, and its undo is
    registered before the change, so a change that fails halfway is still undone."""
    rec = mac.rec
    if not launched:
        if "appearance" not in conditions:   # nothing declared: a restore that fails can't spoil the proof
            code, out = mac._sh("appearance", "restore")
            if code:
                rec.problems.append(f"appearance not restored (exit {code}): {_line(out[-300:])}")
            else:
                rec.conditions["appearance"] = _readback(out, "appearance")
            return
        mac._do("appearance", "restore")
        mac.undo.append(("appearance", ("appearance", "restore")))
        rec.conditions["appearance"] = _readback(mac._do("appearance", conditions["appearance"]), "appearance")
        return
    if "window" in conditions:
        if target == "mac":   # this Mac's Debug app keeps its window frame; a VM's app data is wiped at reservation
            mac.undo.append(("window", ("window", *mac._do("ax", "winrect").split(","))))
        mac._do("window", *conditions["window"])
    rec.conditions["window"] = mac._do("ax", "winrect")


def undo_conditions(mac, rec):
    """Undo every condition set, last first. One that fails is a Problem, and the rest still run."""
    while mac.undo:
        what, args = mac.undo.pop()
        code, out = mac._sh(*args)
        if code:
            rec.problems.append(f"{what} not undone (exit {code}): {_line(out[-300:])}")


def _record(mac, rec, step):
    """Start or stop the screen recording. A recording that fails is a Problem, never a failed check."""
    code, out = mac._sh("record", step)
    written = re.search(r"seconds=([\d.]+) bytes=(\d+)", out)
    if written:
        rec.video.update(path=VIDEO, seconds=float(written[1]), bytes=int(written[2]))
    if code:
        outcome = "not started" if step == "start" else "cut short" if "CUT:" in out else "failed"
        rec.video["error"] = f"screen recording {outcome}: {_line(out[-300:])}"
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
        if rec.hosts is not None and rec.app_running:
            mac._sweep_hosts()
        if mac._marked and not _alive(os.path.join(evidence, "pixel_stream.pid")):
            rec.problems.append("pixel stream died during the run: telemetry checks after that can't be trusted")
        code, out = mac._sh("logs")
        if code:
            rec.problems.append(f"log.txt not written: {out[-300:]}")
    undo_conditions(mac, rec)   # after the final screenshot and recording; before cleanup quits the app and frees the VM
    if mac._fixture:   # before cleanup releases the VM
        rec.problems += mac._fixture.stop()
    host = (open(os.path.join(evidence, "vm")).read().strip() if os.path.exists(os.path.join(evidence, "vm")) else None)
    code, out = mac._sh("cleanup")
    if code:
        rec.problems.append(f"cleanup failed (exit {code}): {out[-600:]}")
    if mac.reset:   # after cleanup quit the app
        code, out = mac._sh("reset", "end")
        if code:
            rec.problems.append(f"reset after the run failed (exit {code}): {_line(out[-300:])}")
    rec.problems += reset_problems(_read_json(os.path.join(evidence, "reset.json")),
                                   expected=bool(host) or mac.reset)
    lock = os.path.join(HOME, ".vm-locks", host or "-", "topic")
    if host and os.path.exists(lock) and open(lock).read().strip() == mac.topic:
        rec.problems.append(f"VM {host} not released: its lock still names this run")


def _read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def reset_problems(reset, expected):
    """Problems for a run's reset.json: a state not reset, or no record of a reset the run should have had."""
    if reset is None:
        return ["start state not reset: no reset.json"] if expected else []
    return [f"reset: {what}: failed" for what, ok in reset.get("checks", {}).items() if not ok]


def _manifest(evidence, rec, proof, rerun, running, live, target, evidence_dir=None, declared=()):
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
             hosts=None if rec.hosts is None else sorted(rec.hosts), undeclared_hosts=undeclared(rec.hosts, live),
             evidence_kind=evidence_kind(live, rec.hosts),
             verdict=verdict, exit=code, reason=rec.error, phase_reached=rec.phase,
             checks=[dict(check=n, ok=ok, detail=d, base=b) for n, ok, d, b in rec.checks], problems=rec.problems,
             unverified=[dict(what=w, why=y) for w, y in rec.unverified],
             video=dict(off=True) if rec.video is None else rec.video, conditions_declared=list(declared),
             reset=_read_json(os.path.join(evidence, "reset.json")),
             conditions={**rec.conditions, **{k: v for k, v in (m.get("launch") or {}).items()
                                              if k in ("language", "locale")}})
    with open(path, "w") as f:
        f.write(_tilde(json.dumps(m, indent=1)))
    return m
