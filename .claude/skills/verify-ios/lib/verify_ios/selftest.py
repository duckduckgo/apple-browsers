"""One command that checks verify-ios works on this Mac and checkout: the PR test, and a health check for anyone.

It runs the real commands a user runs, in order, and stops at the first failure with the reason:
  1. set up this checkout's simulators;
  2. build the app and the runner, unless the current build already matches the source;
  3. the tool's own tests (no simulator);
  4. the "must fail" trust checks and one worked proof (the Fire button) on each device;
  5. confirm nothing was left running and each proof deleted its simulator.
"""
import json, os, subprocess, sys, time

from . import env
from .device import Device

CLI = os.path.join(env.SKILL, "bin", "verify-ios")


def _say(text):
    print(text, file=sys.stderr, flush=True)


def _cli(*args, timeout=3600):
    p = subprocess.run([CLI, "--json", *args], capture_output=True, text=True, timeout=timeout)
    try:
        out = json.loads(p.stdout.strip().splitlines()[-1]) if p.stdout.strip() else {}
    except ValueError:
        out = {"raw": p.stdout[-500:]}
    return p.returncode, out, p.stderr[-1000:]


def run(devices):
    steps, reports, t0 = [], [], time.time()

    def step(name, ok, detail=None):
        steps.append(dict(step=name, ok=ok, **({"why": detail} if detail and not ok else {})))
        _say(f"{'ok  ' if ok else 'FAIL'} {name}" + (f": {detail}" if detail and not ok else ""))
        return ok

    def done():
        ok = all(s["ok"] for s in steps)
        return (0 if ok else 1), dict(ok=ok, devices=devices, minutes=round((time.time() - t0) / 60, 1), steps=steps,
                                      reports=reports, worktree=env.ROOT, stateDir=env.HOME)

    _say(f"verify-ios self-test for {env.ROOT} on {', '.join(devices)} (a first run takes about 10-25 minutes)")
    before = _running(devices)   # left running by earlier exploring: not this self-test's to report
    for d in devices:
        code, out, err = _cli("--device", d, "setup", timeout=600)
        if not step(f"{d} simulator ready", code == 0, out.get("message") or err):
            return done()

    try:
        Device.check_build_current()
        built = True
        step("app and runner builds are current (build skipped)", True)
    except env.Failed:
        built = False
    if not built:
        _say("building the app and the runner (a first build takes 3-20 minutes)...")
        code, out, err = _cli("--device", devices[0], "build", timeout=3600)
        if not step("app and runner built", code == 0, out.get("message") or err):
            return done()

    _say("running the tool's own tests...")
    p = subprocess.run([sys.executable, "-W", "ignore", "-m", "unittest", "discover", "-s", os.path.join(env.SKILL, "tests"),
                        "-p", "test_*.py"], capture_output=True, text=True, timeout=600)
    summary = (p.stderr.strip().splitlines() or ["?"])[-1]
    if not step("tool tests", p.returncode == 0, summary if p.returncode else None):
        return done()

    proofs = [os.path.join(env.SKILL, "tests", "must_fail.py"), os.path.join(env.SKILL, "examples", "t7_fire_button.py")]
    _say(f"proving the trust checks and the Fire button on {', '.join(devices)} (about 3 minutes per device)...")
    code, out, err = _cli("prove", *proofs, "--devices", ",".join(devices))
    for p_ in out.get("proofs", []):
        name = os.path.basename(p_.get("proof", "?"))
        if p_.get("report"):
            reports.append(p_["report"])
        for r in p_.get("results", []):
            step(f"{r['device']} {name}", r.get("status") == "pass" and not r.get("problems"),
                 f"{r.get('status')}: {r.get('reason') or r.get('problems')} (report: {p_.get('report')})")
    if code != 0 and not out.get("proofs"):
        step("prove", False, out.get("message") or out.get("preflight") or err)
    if not all(s["ok"] for s in steps):
        return done()

    left = sorted(_running(devices) - before)
    step("nothing left running", not left, f"still running: {left}")
    kept = {d: found["udid"] for d in devices if (found := Device(d)._find())}
    step("each proof deleted its simulator", not kept, f"still there: {kept}")
    return done()


def _running(devices):
    """Pids of the runner processes and fixture server recorded for these devices that are still ours."""
    st = env.load_state()
    pids = {p["pid"] for d in devices for s in st.get("devices", {}).get(d, {}).get("started", [])
            for p in s.get("processes", []) if env.still_ours(p)}
    fx = st.get("fixture")
    if fx and env.still_ours(fx):
        pids.add(fx["pid"])
    return pids
