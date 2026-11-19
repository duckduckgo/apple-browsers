"""Every refusal in the harness, ax and doctor is refused, and no refused action changes the app: the trust contract.

Run it after changing harness.py, vhelp.py, verify.sh or ax.swift, in a VM (it quits and relaunches the app):
    bin/verify-macos-browser prove .claude/skills/verify-macos-browser/tests/must_fail.py --target vm-1
It passes only when every probe was refused as it should be; a probe that wasn't fails the run and names it. To trigger
doctor's refusals it edits README.md, adds an untracked file, and rewrites this run's build.json, launch.json and
pixel_stream.pid for a moment; each is restored in a finally block, so a failure or Ctrl-C leaves the checkout as it was.
"""
import contextlib
import json
import os
import subprocess
import time

import harness   # already loaded by bin/verify-macos-browser; its scripts folder is on sys.path
import vhelp

FLAGS = {}
LIVE = []
AUTOMATION = False


def refused(mac, what, fn, expect):
    """Record a check that `fn` was refused with `expect` in its message. The refusal is the outcome under test, so
    it is taken off the run's action errors."""
    try:
        out = fn()
    except harness.ProofError as e:
        mac.rec.action_errors.remove(str(e))
        return mac.check(f"refused: {what}", expect in str(e), str(e))
    return mac.check(f"refused: {what}", False, f"not refused: {out}")


@contextlib.contextmanager
def changed(path, change):
    """Apply `change(text) -> text` to a file, or create it when `change` is a string; restore bytes and mtime after."""
    old = st = None
    if os.path.exists(path):
        st = os.stat(path)
        with open(path, "rb") as f:
            old = f.read()
    try:
        with open(path, "w") as f:
            f.write(change if isinstance(change, str) else change(old.decode()))
        yield
    finally:
        if old is None:
            os.remove(path)
        else:
            with open(path, "wb") as f:
                f.write(old)
            os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns))


def json_change(**fields):
    def change(text):
        d = json.loads(text)
        for key, fn in fields.items():
            d[key] = fn(d[key])
        return json.dumps(d)
    return change


def read(path):
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return f.read()


def tabs(mac):
    """Every tab with its title, selection and frame: what a refused action must leave as it was."""
    return [line for line in mac.find("TabBarViewItem") if " id=TabBarViewItem " in line]


def doctor_ok(mac, what):
    mac.check(f"doctor accepts {what}", mac._do("doctor").splitlines()[-1] == "OK")


def run(mac):
    ev = mac.evidence
    refused(mac, "expect_pixel without a mark", lambda: mac.expect_pixel("m_mac_any"), "call mark() first")
    refused(mac, "expect_wide_event without a mark", lambda: mac.expect_wide_event("any"), "call mark() first")

    mac.key("cmd+t")
    mac.expect_tab_count(2)
    before = tabs(mac)
    refused(mac, "press an ambiguous target", lambda: mac.press("TabBarViewItem"), "AMBIGUOUS")
    refused(mac, "click an ambiguous target", lambda: mac.click("TabBarViewItem"), "AMBIGUOUS")
    refused(mac, "press a missing target", lambda: mac.press("verify.does-not-exist"), "NOT FOUND")
    refused(mac, "press a match that isn't there (nth)", lambda: mac.press("TabBarViewItem", nth=5), "NOT FOUND")
    refused(mac, "an unknown key", lambda: mac.key("cmd+nosuchkey"), "unknown key")
    mac.check("tabs unchanged by the refused actions", tabs(mac) == before, dict(before=before, after=tabs(mac)))

    flags = os.path.join(ev, "flags")
    pinned = read(flags)
    _, fixed = vhelp.feature_flags(mac.checkout)
    refused(mac, "a flag with supportsLocalOverriding: false", lambda: mac._do("flag", sorted(fixed)[0], "on"),
            "NOT OVERRIDABLE")
    refused(mac, "an unknown flag", lambda: mac._do("flag", "verifyNoSuchFlag", "on"), "UNKNOWN FLAG")
    mac.check("no flag pinned by the refused flags", read(flags) == pinned)

    doctor_ok(mac, "this build")
    with changed(os.path.join(mac.checkout, "README.md"), lambda t: t + "\n"):
        refused(mac, "stale build: a tracked file changed after the build", lambda: mac._do("doctor"), "STALE SOURCE")
    with changed(os.path.join(mac.checkout, f"verify-must-fail-{mac.topic}.txt"), "x\n"):
        refused(mac, "stale build: a file added after the build", lambda: mac._do("doctor"), "STALE SOURCE")
    with changed(os.path.join(ev, "build.json"), json_change(hashes=lambda h: {k: "0" * 64 for k in h})):
        refused(mac, "rebuilt binary", lambda: mac._do("doctor"), "REBUILT")
    # The process must start after the build (this Mac) or after this build's launch (VM): move both an hour later.
    with changed(os.path.join(ev, "build.json"), json_change(build_end=lambda t: t + 3600)), \
            changed(os.path.join(ev, "launch.json"), json_change(launched=lambda t: t + 3600)):
        refused(mac, "old process", lambda: mac._do("doctor"), "OLD PROCESS")
    doctor_ok(mac, "this build again once every file is restored")

    mac.mark()
    dead = subprocess.Popen(["/usr/bin/true"])
    dead.wait()
    with changed(os.path.join(ev, "pixel_stream.pid"), f"{dead.pid}\n"):
        refused(mac, "expect_pixel on a dead pixel stream", lambda: mac.expect_pixel("m_mac_any", timeout=1),
                "PIXEL STREAM DEAD")
        refused(mac, "expect_no_pixel on a dead pixel stream", lambda: mac.expect_no_pixel("m_mac_any", within=0),
                "PIXEL STREAM DEAD")
    mac.expect_no_pixel("m_mac_verify_no_such_pixel", within=1)   # the restored stream still answers

    # Last, as it relaunches the app: with the app gone nothing passes, and doctor refuses.
    launch = json.loads(read(os.path.join(ev, "launch.json")))
    vm = launch.get("vm")
    subprocess.run(["ssh", "-o", "BatchMode=yes", vm, "kill", str(launch["pid"])] if vm else ["kill", str(launch["pid"])],
                   check=True)
    for _ in range(20):
        if mac._sh("ax", "front")[1].startswith("APP NOT RUNNING"):
            break
        time.sleep(0.5)
    refused(mac, "a check after the app quit", lambda: mac.eventually("tabs closed", lambda: mac.tab_count() == 0,
                                                                       timeout=2), "APP NOT RUNNING")
    refused(mac, "doctor after the app quit", lambda: mac._do("doctor"), "NOT RUNNING")
    mac._do("build", mac.checkout)
    doctor_ok(mac, "the relaunched build")
