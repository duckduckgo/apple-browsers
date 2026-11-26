"""Delete verify-ios simulators that nobody will use again, from any worktree.

A proof deletes its own simulators when it ends, but `setup`, `launch`, exploring and `prove --keep` leave them booted,
and a run that is killed, or whose worktree is removed, never cleans up. So every command first reaps:

- orphans: the worktree that made the simulator no longer exists;
- idle simulators: nobody used them for VERIFY_IOS_IDLE_HOURS (default 2; 0 turns this off).

A simulator is matched to its worktree by name (`verify-ios-<key>-<device>`, see Device.name) and the worktree's state
folder BASE/<key>, which records the worktree's path and when each device was last used (env.touch). A device whose
lock another process holds is never touched, and nothing whose name doesn't start with `verify-ios-` ever is.
"""
import fcntl, json, os, shutil, signal, time

from . import env
from .env import run

PREFIX = "verify-ios-"
# What a worktree's state folder holds besides evidence (pull requests link to it) and `prove --base` worktrees.
STATE_ENTRIES = ("state.json", "state.json.tmp", "state.lock", "fixture.lock", "locks", "logs")
SIM_DEVICES = os.path.expanduser("~/Library/Developer/CoreSimulator/Devices")


def idle_limit():
    """Seconds of disuse after which a simulator is reaped, or None when idle reaping is off."""
    try:
        hours = float(os.environ.get("VERIFY_IOS_IDLE_HOURS", "2"))
    except ValueError:
        hours = 2
    return hours * 3600 if hours > 0 else None


def parse_name(name):
    """(worktree key, device) for a verify-ios simulator name, or None for any other simulator."""
    if not name.startswith(PREFIX):
        return None
    key, _, device = name[len(PREFIX):].rpartition("-")
    return (key, device) if key and device in env.PORT_OFFSET else None


def owner(key, device, udid, base=None):
    """What the reaper knows about who uses a simulator: its worktree's path (None when not recorded, by state from
    before this was recorded or with no state folder at all) and when it was last used (epoch seconds)."""
    home = os.path.join(base or env.BASE, key)
    st = env.load_state(home)
    used = st.get("devices", {}).get(device, {}).get("lastUsed")
    if used is None:   # not recorded: when the worktree last took this device's lock or wrote its state, else when
        # the simulator was last booted or shut down
        paths = [f"{home}/locks/{device}.lock", f"{home}/state.json", f"{SIM_DEVICES}/{udid}/device.plist"]
        used = max((os.path.getmtime(p) for p in paths if os.path.exists(p)), default=0)
    return dict(home=home, root=st.get("root"), lastUsed=used)


def verdict(root, last_used, now, limit):
    """Why a simulator should go ("orphan" or "idle"), or None to keep it."""
    if root and _gone(root):
        return "orphan"
    if limit is not None and now - last_used > limit:
        return "idle"
    return None


def _gone(root):
    """True only when the worktree was removed: its .git is missing and the folder that held it is still readable.
    A worktree the reaper can't see (no permission, an unmounted volume) is not gone."""
    try:
        os.stat(os.path.join(root, ".git"))
        return False
    except FileNotFoundError:
        return os.access(os.path.dirname(root), os.R_OK | os.X_OK)
    except OSError:
        return False


def candidates(sims, now=None, limit=None, spare=()):
    """The simulators to reap, each with its key, device, owner and reason. `spare` is a set of (key, device) this
    command is about to use."""
    now = time.time() if now is None else now
    out = []
    for sim in sims:
        parsed = parse_name(sim["name"])
        if not parsed or parsed in spare:
            continue
        key, device = parsed
        who = owner(key, device, sim["udid"])
        why = verdict(who["root"], who["lastUsed"], now, limit)
        if why:
            out.append(dict(sim=sim, key=key, device=device, why=why, **who))
    return out


def try_lock(home, device):
    """(free, handle): take the device's lock without waiting. A lock file nobody ever took is free with no handle."""
    try:
        f = open(f"{home}/locks/{device}.lock", "r+")
    except FileNotFoundError:
        return True, None
    try:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        f.close()
        return False, None
    return True, f


def simulators():
    devs = json.loads(run(["xcrun", "simctl", "list", "devices", "-j"]).stdout)["devices"]
    return [d for ds in devs.values() for d in ds]


def reap(spare=(), now=None):
    """Reap orphaned and idle simulators. Returns one entry per simulator acted on, with any problems."""
    if os.environ.get("VERIFY_IOS_REAP") == "0":
        return []
    sims = simulators()
    now, limit = time.time() if now is None else now, idle_limit()
    done = [d for d in (_reap_one(c, now, limit) for c in candidates(sims, now, limit, spare)) if d]
    for home in {d["home"] for d in done if d["why"] == "orphan" and d.get("deleted")}:
        left = [s for s in simulators() if (parse_name(s["name"]) or ("",))[0] == os.path.basename(home)]
        if not left:
            _forget(home)
    return [{k: d[k] for k in ("name", "why", "deleted", "busy", "problems") if k in d} for d in done]


def _reap_one(c, now, limit):
    """Reap one candidate, or return None when it turns out to be in use again."""
    from .driver import XCUITestRunner
    sim, home, device = c["sim"], c["home"], c["device"]
    res = dict(name=sim["name"], why=c["why"], home=home, deleted=False)
    free, lock = try_lock(home, device)
    if not free:
        return dict(res, busy=True)   # another process holds it: a live proof or command; exit-75 rules apply
    problems = []
    try:
        who = owner(c["key"], device, sim["udid"])   # again, under the lock: a lockless command may have used it since
        res["why"] = verdict(who["root"], who["lastUsed"], now, limit)
        if not res["why"]:
            return None
        st = env.load_state(home)
        survivors = []
        for s in st.get("devices", {}).get(device, {}).get("started", []):   # the runner it left, by recorded identity
            left = XCUITestRunner(sim["udid"], s["port"], st.get("token", "")).stop(s.get("processes", [])).get("left")
            if left:
                survivors.append(dict(processes=left, port=s["port"]))
                problems.append(f"left running: {[p['pid'] for p in left]}")
        if os.path.isdir(home):
            env.update_state(lambda st: st.setdefault("devices", {}).__setitem__(device, {"started": survivors}), home)
        run(["xcrun", "simctl", "shutdown", sim["udid"]])
        p = run(["xcrun", "simctl", "delete", sim["udid"]])
        if p.returncode:
            problems.append(f"simctl delete failed: {p.stderr.strip()}")
        else:
            res["deleted"] = True
    finally:
        if lock:
            lock.close()
    if problems:
        res["problems"] = problems
    return res


def _forget(home):
    """Remove an orphaned worktree's state (its fixture server too), keeping its evidence and base worktrees."""
    fx = env.load_state(home).get("fixture")
    if fx and env.still_ours(fx):
        os.kill(fx["pid"], signal.SIGTERM)
    for name in STATE_ENTRIES:
        path = os.path.join(home, name)
        if os.path.isdir(path):
            shutil.rmtree(path, ignore_errors=True)
        elif os.path.exists(path):
            os.remove(path)
    try:
        os.rmdir(home)   # only when nothing (evidence) is left in it
    except OSError:
        pass
