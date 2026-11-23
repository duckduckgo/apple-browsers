"""`verify-macos-browser selftest`: does verify-macos-browser work here, and if not, which step failed, why, and the fix.

Run it on a new Mac, a new checkout, after an Xcode or macOS update, or after setting up a VM. Steps run in order and
a target stops at its first failure:
  this Mac: Xcode, the build (incremental, into the DerivedData `build` picks), the unit tests;
  each VM: ssh without a prompt, its lock, the same macOS major as this Mac, an auto-login session, a display that
    never sleeps, an unlocked screen, the Accessibility and Screen Recording grants over ssh (`ax grants`), its
    Provisioning UDID in the built
    app's profile, a launch that shows a window; then the must-fail proof and the offline example through `prove`,
    nothing left running and the VM released;
  --target mac: the Accessibility and Screen Recording grants of the process that will drive (read only, never a
    prompt), then the same proofs ON YOUR SCREEN. `all` is vm-1 and vm-2, never your screen.
Nothing here changes a setting; a failure only names the fix.
"""
import json
import os
import plistlib
import re
import subprocess
import sys
import time

import harness

STEPS_DOC = "VM-SETUP.md"
TARGETS = ("mac", "vm-1", "vm-2", "all")
PROOFS = (os.path.join(harness.SKILL, "tests", "must_fail.py"), os.path.join(harness.SKILL, "examples", "t3_fixture_page.py"))
LEFT_RUNNING = "DuckDuckGo - verify-.*[.]app/Contents/MacOS"   # the app, on this Mac or in a VM
LOCAL_LEFT = "ServerAliveInterval=15|" + LEFT_RUNNING           # also verify.sh's ssh streams and tunnels

# The fix for each step: one string, or {marker in the why: fix} with "" as the default.
FIX = {
    "Xcode selected": "sudo xcode-select -s /Applications/Xcode.app && xcodebuild -runFirstLaunch",
    "build is current": {
        "BROKEN BUILD PRODUCT": "remove the app target's assetcatalog_output under DerivedData's Build/Intermediates.noindex, rerun",
        "": "fix the first error in host/build.log; after switching branches, 'has no member' for code that is there is a "
            "stale module: move DerivedData aside and rerun",
    },
    "unit tests": "python3 -I -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py' and fix what fails",
    "ssh without a prompt": f"{STEPS_DOC} section 3 (ssh config entry and key; `ssh <vm> true` must not prompt). In Claude "
                            "Code, ssh runs outside the sandbox",
    "VM free and reserved": "another run holds it: wait, or `verify.sh cleanup <topic>` for the topic named, or remove "
                            "~/.ddg-verify-macos/.vm-locks/<vm> if that run is gone",
    "same macOS major as this Mac": f"{STEPS_DOC} section 1 (create the VM with this Mac's macOS version)",
    "auto-login session up": f"{STEPS_DOC} section 2, Users & Groups: automatically log in as the VM user (FileVault off); "
                             "then restart the VM",
    "display never sleeps": f"{STEPS_DOC} section 2, Lock Screen: Turn display off → Never (`pmset -g` shows displaysleep 0)",
    "screen not locked": f"unlock it in the VM window, then {STEPS_DOC} section 2, Lock Screen: Require password → Never",
    "Accessibility grant over ssh": f"{STEPS_DOC} section 2, Accessibility: add /usr/libexec/sshd-keygen-wrapper",
    "Screen Recording grant over ssh": f"{STEPS_DOC} section 2, Screen & System Audio Recording: add /usr/libexec/sshd-keygen-wrapper",
    "Provisioning UDID in the app's profile": f"{STEPS_DOC} section 4 (register the UDID, rebuild with "
                                               "-allowProvisioningUpdates)",
    "app launches and shows a window": {
        "NOT LAUNCHED": f"AMFI rejected the app: {STEPS_DOC} section 4 (the VM's Provisioning UDID in the profile)",
        "NOT READY": f"a keychain dialog waits in the VM: {STEPS_DOC} section 5 (click Always Allow in the VM window)",
        "ONBOARDING NOT SKIPPED": f"the app wasn't frontmost or the screen is locked: open the VM window, unlock it, "
                                  f"{STEPS_DOC} section 2 Lock Screen",
        "": "read the last lines of <target>/build.log and transcript in the selftest folder",
    },
    "VM lock released at the end": "a proof's cleanup didn't release it: read its report.md; then remove "
                                   "~/.ddg-verify-macos/.vm-locks/<vm>",
    "VM released": "`verify.sh cleanup <topic>` for the selftest topic, or remove ~/.ddg-verify-macos/.vm-locks/<vm>",
    "Accessibility grant": "System Settings → Privacy & Security → Accessibility: add the app that runs the agent "
                           "(Terminal, Claude), restart it; or use a VM (VM-SETUP.md)",
    "Screen Recording grant": "System Settings → Privacy & Security → Screen & System Audio Recording: add the app that "
                              "runs the agent, restart it; or use a VM (VM-SETUP.md)",
    "proof": "open the report.md named; a setup failure there (NOT LAUNCHED, NOT READY, …) has the fix of the step above",
    "nothing left running": "kill the processes named (they belong to a verify run that didn't clean up)",
}


def fix_for(step, why):
    fix = FIX["proof" if step.startswith("prove ") else step]
    if isinstance(fix, dict):
        return next((f for marker, f in fix.items() if marker and marker in why), fix[""])
    return fix


def run_steps(steps, say):
    """Run (name, check) pairs in order and stop at the first failure. check() returns None when it passes, else why.
    A check that raises fails with its error. Returns [dict(step, ok[, why, fix])]."""
    out = []
    for name, check in steps:
        try:
            why = check()
        except Exception as e:   # a crashed check is that step's failure, named, never a traceback mid-run
            why = f"{type(e).__name__}: {e}"
        if why is None:
            out.append(dict(step=name, ok=True))
            say(f"ok   {name}")
            continue
        out.append(dict(step=name, ok=False, why=why, fix=fix_for(name, why)))
        say(f"FAIL {name}: {why}\n     fix: {out[-1]['fix']}")
        break
    return out


def result(host, targets, folder, seconds):
    """The JSON the command ends with: ok and the reports, or the first failed step (and its target)."""
    failed = next(([None, s] for s in host if not s["ok"]), None) or \
        next(([t, s] for t, r in targets.items() for s in r["steps"] if not s["ok"]), None)
    out = dict(ok=failed is None, host=host, targets=targets, evidence=folder, minutes=round(seconds / 60, 1),
               reports=[p for r in targets.values() for p in r["reports"]])
    if failed:
        out["failed"] = dict(target=failed[0], **failed[1])
    return out


# ---------------------------------------------------------------- judges: command output in, None or why out
def _last(text):
    lines = [line for line in (text or "").strip().splitlines() if line.strip()]
    return lines[-1].strip() if lines else ""


def judge_exit(code, out):
    return None if code == 0 else (_last(out) or f"exit {code}")


def judge_same_major(host_version, vm_version):
    if host_version.split(".")[0] == vm_version.split(".")[0]:
        return None
    return f"the VM runs macOS {vm_version or '?'}, this Mac {host_version}"


def console_sessions(ioreg_xml):
    """The console sessions in `ioreg -n Root -d1 -a` (IOConsoleUsers): who is logged in at the screen."""
    users = plistlib.loads(ioreg_xml.encode() if isinstance(ioreg_xml, str) else ioreg_xml).get("IOConsoleUsers", [])
    return [u for u in users if u.get("kCGSSessionOnConsoleKey")]


def judge_logged_in(ioreg_xml):
    names = [u.get("kCGSSessionUserNameKey") for u in console_sessions(ioreg_xml) if u.get("kCGSessionLoginDoneKey")]
    return None if any(n and n != "loginwindow" for n in names) else "no user logged in at the VM's screen (login window)"


def judge_unlocked(ioreg_xml):
    locked = [u.get("kCGSSessionUserNameKey") for u in console_sessions(ioreg_xml) if u.get("CGSSessionScreenIsLocked")]
    return f"the screen is locked (session of {', '.join(map(str, locked))})" if locked else None


def judge_display_sleep(pmset_out):
    m = re.search(r"^\s*displaysleep\s+(\d+)", pmset_out, re.M)
    if m and m[1] == "0":
        return None
    return f"display sleeps after {m[1]} min" if m else "pmset -g shows no displaysleep"


def profile_devices(profile_xml):
    return plistlib.loads(profile_xml.encode() if isinstance(profile_xml, str) else profile_xml).get("ProvisionedDevices", [])


def judge_udid(udid, devices):
    if udid and udid.lower() in {d.lower() for d in devices}:
        return None
    return f"Provisioning UDID {udid or '(unknown)'} is not among the {len(devices)} devices in the built app's profile"


def judge_grant(out, grant):
    m = re.search(rf"\b{grant}=(true|false)\b", out)
    if m and m[1] == "true":
        return None
    return f"the process that drives has no {grant} grant" if m else f"ax grants: {_last(out) or 'no answer'}"


def judge_proof(code, out):
    if code == 0:
        return None
    return f"{out.get('verdict', 'INCONCLUSIVE')}: {out.get('reason') or out.get('problems')} (report: {out.get('report')})"


def judge_left(pids_text):
    return f"still running: {' | '.join(pids_text.strip().splitlines())}" if pids_text.strip() else None


# ---------------------------------------------------------------- running it
def _say(text):
    print(text, file=sys.stderr, flush=True)


def _run(argv, env=None, timeout=3600):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, cwd=harness.ROOT,
                       env={**os.environ, **(env or {})})
    return p.returncode, p.stdout + p.stderr


class Run:
    """One selftest: its folder, the topic verify.sh runs under, and the facts later steps read."""

    def __init__(self, folder):
        self.folder, self.topic, self.info = folder, harness.topic_of(folder), {}

    def sh(self, where, *args, timeout=3600):
        """verify.sh with its run folder in <selftest>/<where>/: build.log, transcript, vm, launch state."""
        os.makedirs(os.path.join(self.folder, where), exist_ok=True)
        return _run([harness.VERIFY_SH, args[0], self.topic, *args[1:]],
                    dict(VERIFY_RUN_DIR=os.path.join(self.folder, where)), timeout)

    def ssh(self, host, script, timeout=120):
        return _run(["ssh", *harness.SSH_OPTS, host, script], timeout=timeout)

    def lock(self, host):
        return os.path.join(harness.HOME, ".vm-locks", host)

    # this Mac, once
    def host_steps(self):
        def build():
            code, out = self.sh("host", "build", harness.ROOT, "--no-launch")
            if code:
                return _last(out) if "BROKEN BUILD PRODUCT" not in out else out[out.index("BROKEN"):].splitlines()[0]
            with open(os.path.join(self.folder, "host", "build.json")) as f:
                self.info["app"] = json.load(f)["app"]
            self.info["derived_data"] = re.search(r"^DerivedData: (.*)$", out, re.M)[1]
            _say(f"     DerivedData: {self.info['derived_data']}")
            return None

        def unit_tests():
            code, out = _run([sys.executable, "-I", "-m", "unittest", "discover", "-s",
                              os.path.join(harness.SKILL, "tests"), "-p", "test_*.py"], timeout=900)
            self.info["unit_tests"] = (re.findall(r"^Ran \d+ tests.*$", out, re.M) or ["?"])[-1] + " " + _last(out)
            return None if code == 0 else _last(out)

        return [("Xcode selected", lambda: judge_exit(*_run(["xcodebuild", "-version"], timeout=120))),
                ("build is current", build),
                ("unit tests", unit_tests)]

    # one target
    def proof_steps(self, target, reports):
        def prove(path):
            def check():
                code, out = harness.prove(path, target, self.folder)
                if out.get("report"):
                    reports.append(out["report"])
                return judge_proof(code, out)
            return check
        return [(f"prove {os.path.basename(path)}", prove(path)) for path in PROOFS]

    def mac_steps(self, reports, before):
        def grant(name):
            return lambda: judge_grant(self.sh("host", "ax", "grants", timeout=300)[1], name)

        def left():
            return judge_left("\n".join(sorted(set(_pgrep(LOCAL_LEFT).splitlines()) - before)))

        return [("Accessibility grant", grant("accessibility")), ("Screen Recording grant", grant("screen-recording")),
                *self.proof_steps("mac", reports), ("nothing left running", left)]

    def vm_steps(self, host, reports, before):
        state = {}

        def ssh_ok():
            return judge_exit(*self.ssh(host, "true", timeout=30))

        def reserve():
            code, out = self.sh(host, "vm", host, timeout=300)
            if code:
                return " ".join(line.strip() for line in out.strip().splitlines()[-3:])
            with open(os.path.join(self.folder, host, "vm.json")) as f:
                state.update(json.load(f))
            return None

        def remote(name, script):
            code, out = self.ssh(host, script)
            state[name] = out
            return code, out

        def ioreg():
            if "ioreg" not in state:
                code, out = remote("ioreg", "ioreg -n Root -d1 -a")
                if code:
                    raise RuntimeError(f"ioreg over ssh: {_last(out)}")
            return state["ioreg"]

        def grants():
            if "grants" not in state:
                remote("grants", "cd ~/verify && ./ax grants")
            return state["grants"]

        def udid():
            code, out = _run(["security", "cms", "-D", "-i", os.path.join(self.info["app"], "Contents", "embedded.provisionprofile")])
            if code:
                return f"no embedded profile in the built app: {_last(out)}"
            return judge_udid(state.get("provisioning_udid"), profile_devices(out[out.index("<?xml"):]))

        def launch():
            code, out = self.sh(host, "build", harness.ROOT, timeout=3600)
            return None if code == 0 else _last(out)

        def release():
            state["released"] = True
            code, out = self.sh(host, "cleanup", timeout=600)
            if os.path.exists(self.lock(host)):
                return f"its lock is still held: {self.lock(host)}"
            return None if code == 0 else f"cleanup exited {code}: {_last(out)}"

        def left():
            code, out = self.ssh(host, f"pgrep -fl '{LEFT_RUNNING}'; pgrep -lx screencapture; true")
            local = "\n".join(sorted(set(_pgrep(LOCAL_LEFT).splitlines()) - before))
            return judge_left("\n".join(filter(None, [out.strip() and f"in {host}: {out.strip()}", local])))

        def unlocked_after():
            return f"its lock is held: {self.lock(host)}" if os.path.exists(self.lock(host)) else None

        steps = [
            ("ssh without a prompt", ssh_ok),
            ("VM free and reserved", reserve),
            ("same macOS major as this Mac", lambda: judge_same_major(_run(["sw_vers", "-productVersion"])[1].strip(),
                                                                      state.get("macos", ""))),
            ("auto-login session up", lambda: judge_logged_in(ioreg())),
            ("display never sleeps", lambda: judge_display_sleep(remote("pmset", "pmset -g")[1])),
            ("screen not locked", lambda: judge_unlocked(ioreg())),
            # the grants themselves: a screencapture without Screen Recording still writes the wallpaper
            ("Accessibility grant over ssh", lambda: judge_grant(grants(), "accessibility")),
            ("Screen Recording grant over ssh", lambda: judge_grant(grants(), "screen-recording")),
            ("Provisioning UDID in the app's profile", udid),
            ("app launches and shows a window", launch),
            ("VM released", release),
        ]
        return steps, state, [*self.proof_steps(host, reports), ("nothing left running", left),
                              ("VM lock released at the end", unlocked_after)]

    def target(self, name):
        reports, before = [], set(_pgrep(LOCAL_LEFT).splitlines())
        _say(f"== {name}")
        if name == "mac":
            _say("     the proofs drive this Mac's screen")
            return dict(steps=run_steps(self.mac_steps(reports, before), _say), reports=reports)
        setup, state, rest = self.vm_steps(name, reports, before)
        try:
            steps = run_steps(setup, _say)
        finally:
            if os.path.exists(os.path.join(self.folder, name, "vm")) and not state.get("released"):
                self.sh(name, "cleanup", timeout=600)   # release the VM whatever failed
        if all(s["ok"] for s in steps):
            steps += run_steps(rest, _say)
        return dict(steps=steps, reports=reports)


def _pgrep(pattern):
    return subprocess.run(["pgrep", "-fl", pattern], capture_output=True, text=True).stdout


def selftest(target="all", evidence_dir=None):
    """Returns (exit code, result). 0 everything passed, 1 a step failed."""
    t0 = time.time()
    folder = harness._new_attempt("selftest", harness.evidence_root(evidence_dir))
    run = Run(folder)
    _say(f"verify-macos-browser selftest of {harness.ROOT} → {folder}")
    host = run_steps(run.host_steps(), _say)
    targets = {}
    if all(s["ok"] for s in host):
        for name in ("vm-1", "vm-2") if target == "all" else (target,):
            targets[name] = run.target(name)
    out = result(host, targets, folder, time.time() - t0)
    out.update(run.info)
    with open(os.path.join(folder, "selftest.json"), "w") as f:
        json.dump(out, f, indent=1)
    return (0 if out["ok"] else 1), out
