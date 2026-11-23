"""Every refusal in the harness, ax and doctor is refused, and no refused action changes the app: the trust contract.

Run it after changing harness.py, vhelp.py, verify.sh or ax.swift, in a VM (it quits and relaunches the app):
    bin/verify-macos-browser prove .agents/skills/verify-macos-browser/tests/must_fail.py --target vm-1
It passes only when every probe was refused as it should be; a probe that wasn't fails the run and names it. It brings
Finder to the front for a moment, and its report's Warnings must list the deliberate no-op click. To trigger
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
AUTOMATION = True   # for the fixture page and url()


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


def on_target(mac, *command):
    """Run a command where the app runs: in its VM over ssh, or on this Mac."""
    vm = json.loads(read(os.path.join(mac.evidence, "launch.json"))).get("vm")
    subprocess.run(["ssh", "-o", "BatchMode=yes", vm, *command] if vm else list(command), check=True)


def wait_front(mac, answer):
    """Wait until `ax front` answers `answer` ("yes", "no" or "APP NOT RUNNING")."""
    for _ in range(20):
        if mac._sh("ax", "front")[1].startswith(answer):
            return
        time.sleep(0.5)


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

    # The fixture page: targets the user couldn't act on, typing with nothing focused, and an action that changes nothing.
    token = mac.token("mf")
    mac.navigate(mac.fixture_url(token))
    mac.expect_url_contains(token)
    mac.eventually("the fixture page shows", lambda: mac.find("bottom marker"))

    def page():
        return mac.url(), tabs(mac), mac.find("status")
    before = page()
    refused(mac, "press a disabled button", lambda: mac.press("disabled button"), "DISABLED")
    refused(mac, "click a disabled button", lambda: mac.click("disabled button"), "DISABLED")
    refused(mac, "press an element scrolled out of the window", lambda: mac.press("bottom marker"), "OFF WINDOW")
    refused(mac, "click an element scrolled out of the window", lambda: mac.click("bottom marker"), "OFF WINDOW")
    mac.click("token")   # the page takes the focus from the address bar; nothing focused there takes text
    warned = len(mac.rec.warnings)
    mac.click("token")   # again: nothing changes, so it must be listed under Warnings
    mac.check("an action that changed nothing is listed under Warnings",
              len(mac.rec.warnings) == warned + 1 and "click('token') changed nothing" in mac.rec.warnings[-1],
              mac.rec.warnings)
    refused(mac, "type with nothing focused that takes text", lambda: mac.type("x"), "NOT FOCUSED")
    mac.check("the page unchanged by the refused actions", page() == before, dict(before=before, after=page()))

    # Another app in front: nothing is read or done, so a "gone" read can't pass on a closed popover or a lost focus.
    on_target(mac, "open", "-a", "Finder")
    wait_front(mac, "no")
    refused(mac, "press while another app is in front", lambda: mac.press("TabBarViewItem", nth=0), "NOT FRONTMOST")
    refused(mac, "type while another app is in front", lambda: mac.type("x"), "NOT FRONTMOST")
    refused(mac, "an AX read while another app is in front", lambda: mac.find("TabBarViewItem"), "NOT FRONTMOST")
    refused(mac, "a URL read while another app is in front", lambda: mac.url(), "NOT FRONTMOST")
    mac._do("ax", "activate")
    wait_front(mac, "yes")
    mac.check("tabs unchanged while another app was in front", tabs(mac) == before[1],
              dict(before=before[1], after=tabs(mac)))

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
    on_target(mac, "kill", str(json.loads(read(os.path.join(ev, "launch.json")))["pid"]))
    wait_front(mac, "APP NOT RUNNING")
    refused(mac, "a check after the app quit", lambda: mac.eventually("tabs closed", lambda: mac.tab_count() == 0,
                                                                       timeout=2), "APP NOT RUNNING")
    refused(mac, "doctor after the app quit", lambda: mac._do("doctor"), "NOT RUNNING")
    mac._do("build", mac.checkout, "--automation")
    doctor_ok(mac, "the relaunched build")
