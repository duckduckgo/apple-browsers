#!/usr/bin/env python3
"""Helpers for verify.sh: source fingerprint, flag check, telemetry, AutomationServer, manifest.

Every command prints one line or JSON and exits 0 (ok), 1 (a check failed) or 2 (error / can't tell).
"""
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

VERIFY_SH = ".agents/skills/verify-macos-browser/scripts/verify.sh"   # from the worktree root
FEATURE_FLAG_SWIFT = "macOS/LocalPackages/FeatureFlags-macOS/Sources/FeatureFlags/FeatureFlag.swift"
PIXEL = re.compile(r"👾\[(?P<frequency>.+?)-(?P<status>Fired\(dryRun\)|Fired|Skipped)\] (?P<name>\S+)(?: \[(?P<params>.*)\])?\s*$")
PARAM = re.compile(r'"((?:[^"\\]|\\.)*)": "((?:[^"\\]|\\.)*)"')


def die(msg, code=2):
    print(msg)
    sys.exit(code)


def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, check=True).stdout


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fingerprint(root):
    """HEAD plus every uncommitted change outside .claude/ and .agents/ (same as verify-ios source_stamp)."""
    scope = ["--", ".", ":(exclude).claude", ":(exclude).agents"]
    head = git(root, "rev-parse", "HEAD").decode().strip()
    h = hashlib.sha256(head.encode())
    h.update(git(root, "diff", "HEAD", "--binary", *scope))
    for path in sorted(git(root, "ls-files", "--others", "--exclude-standard", *scope).decode().splitlines()):
        h.update(path.encode())
        try:
            h.update(sha256_file(os.path.join(root, path)).encode())
        except OSError:
            pass
    dirty = bool(git(root, "status", "--porcelain", *scope).strip())
    return dict(head=head, dirty=dirty, stamp=h.hexdigest())


def feature_flags(root):
    with open(os.path.join(root, FEATURE_FLAG_SWIFT)) as f:
        source = f.read()
    body = source.split("public enum FeatureFlag", 1)[-1].split("\n}", 1)[0]
    names = set(re.findall(r"^\s*case\s+(\w+)\s*$", body, re.M))
    config = source.split("private var config: Config {", 1)[-1]
    fixed, current = set(), []
    for line in config.splitlines():
        case = re.match(r"^\s*case\s+(\.\w+(?:\s*,\s*\.\w+)*)\s*:", line)
        if case:
            current = re.findall(r"\.(\w+)", case.group(1))
        elif re.match(r"^\s*default\s*:", line):
            current = []
        if "supportsLocalOverriding: false" in line:
            fixed.update(current)
    return names, fixed


def parse_pixel(message):
    m = PIXEL.search(message or "")
    if not m:
        return None
    params = dict(PARAM.findall(m["params"] or ""))
    return dict(name=m["name"], status="Skipped" if m["status"] == "Skipped" else "Fired",
                frequency=m["frequency"], params=params)


def pixels_since(path, offset):
    out = []
    try:
        with open(path, "rb") as f:
            f.seek(offset)
            for raw in f:
                try:
                    event = json.loads(raw)
                except ValueError:
                    continue
                p = parse_pixel(event.get("eventMessage"))
                if p:
                    p["time"] = event.get("timestamp")
                    out.append(p)
    except FileNotFoundError:
        pass
    return out


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError):
        return False


def read_json(path):
    with open(path) as f:
        return json.load(f)


def cmd_fingerprint(root):
    print(json.dumps(fingerprint(root)))


def cmd_hash(*paths):
    out = {}
    for p in paths:
        try:
            out[os.path.basename(p)] = sha256_file(p)
        except OSError:
            out[os.path.basename(p)] = None
    print(json.dumps(out))


def cmd_flag(root, name):
    names, fixed = feature_flags(root)
    if name not in names:
        die(f"UNKNOWN FLAG: {name} is not a FeatureFlag case (see {FEATURE_FLAG_SWIFT})")
    if name in fixed:
        die(f"NOT OVERRIDABLE: {name} has supportsLocalOverriding: false; the app would ignore the override")
    print("localOverride" + name[0].upper() + name[1:])


def cmd_mark(run_dir):
    pix = os.path.join(run_dir, "pixels.ndjson")
    wide = wide_event_log()
    mark = dict(time=time.time(),
                pixels_offset=os.path.getsize(pix) if os.path.exists(pix) else 0,
                wide_path=wide, wide_offset=os.path.getsize(wide) if wide else 0)
    with open(os.path.join(run_dir, "mark.json"), "w") as f:
        json.dump(mark, f)
    print("marked")


def load_mark(run_dir):
    try:
        return read_json(os.path.join(run_dir, "mark.json"))
    except FileNotFoundError:
        die("NO MARK: run `verify.sh mark <topic>` right before the action under test")


def stream_ok(run_dir):
    try:
        pid = open(os.path.join(run_dir, "pixel_stream.pid")).readline().strip()   # then its identity (verify.sh)
    except FileNotFoundError:
        return False
    return alive(pid)


def save_pixels(run_dir, mark):
    seen = pixels_since(os.path.join(run_dir, "pixels.ndjson"), mark["pixels_offset"])
    with open(os.path.join(run_dir, "pixels.json"), "w") as f:
        json.dump(seen, f, indent=1)
    return seen


def cmd_expect_pixel(run_dir, name, *args):
    mark = load_mark(run_dir)
    timeout, want = 10.0, {}
    it = iter(args)
    for a in it:
        if a == "--timeout":
            timeout = float(next(it))
        elif "=" in a:
            k, v = a.split("=", 1)
            want[k] = v
        else:
            die(f"bad argument: {a}")
    deadline = time.time() + timeout
    while True:
        if not stream_ok(run_dir):
            die("PIXEL STREAM DEAD: can't tell; rebuild/relaunch with verify.sh build")
        seen = save_pixels(run_dir, mark)
        hits = [p for p in seen if p["name"] == name and p["status"] == "Fired"]
        if hits:
            p = hits[0]
            bad = {k: (v, p["params"].get(k)) for k, v in want.items() if p["params"].get(k) != v}
            if bad:
                die(f"FAIL pixel {name} fired with different params: {bad}", 1)
            print(f"PASS pixel {name} fired ({p['frequency']}) params={p['params']}")
            return
        if time.time() > deadline:
            skipped = [p for p in seen if (p["name"] in name or name in p["name"]) and p["status"] == "Skipped"]
            extra = f"; skipped by frequency rule: {[s['name'] for s in skipped]}" if skipped else ""
            die(f"FAIL pixel {name} not fired within {timeout:g}s after mark{extra}", 1)
        time.sleep(0.5)


def cmd_expect_no_pixel(run_dir, name, *args):
    mark = load_mark(run_dir)
    within = float(args[1]) if len(args) == 2 and args[0] == "--within" else 3.0
    time.sleep(within)
    if not stream_ok(run_dir):
        die("PIXEL STREAM DEAD: can't tell")
    hits = [p for p in save_pixels(run_dir, mark) if p["name"] == name and p["status"] == "Fired"]
    if hits:
        die(f"FAIL pixel {name} fired: {hits[0]['params']}", 1)
    print(f"PASS pixel {name} not fired within {within:g}s after mark")


def wide_event_log():
    # In a VM, verify.sh mirrors the VM's log to a local file (tail -F over ssh) and names it here.
    mirrored = os.environ.get("VERIFY_WIDE_LOG")
    if mirrored:
        return mirrored if os.path.exists(mirrored) else None
    bundle = "com.duckduckgo.macos.browser.debug"
    for p in (os.path.expanduser(f"~/Library/Containers/{bundle}/Data/Library/Caches/wide-event-validation-log.jsonl"),
              os.path.expanduser("~/Library/Caches/wide-event-validation-log.jsonl")):
        if os.path.exists(p):
            return p
    return None


def cmd_expect_wide_event(run_dir, feature, *args):
    mark = load_mark(run_dir)
    status, timeout = None, 10.0
    it = iter(args)
    for a in it:
        if a == "--status":
            status = next(it)
        elif a == "--timeout":
            timeout = float(next(it))
        else:
            die(f"bad argument: {a}")
    deadline = time.time() + timeout
    while True:
        path = mark.get("wide_path") or wide_event_log()
        offset = mark["wide_offset"] if mark.get("wide_path") == path else 0
        events = []
        if path:
            with open(path, "rb") as f:
                f.seek(offset)
                for raw in f:
                    try:
                        events.append(json.loads(raw))
                    except ValueError:
                        pass
        with open(os.path.join(run_dir, "wide-events.json"), "w") as f:
            json.dump(events, f, indent=1)
        hits = [e for e in events if feature in json.dumps(e)]
        if hits:
            e = hits[0]
            got = json.dumps(e)
            if status and f'"{status}"' not in got:
                die(f"FAIL wide event {feature} written without status {status}: {got[:300]}", 1)
            print(f"PASS wide event {feature}" + (f" status {status}" if status else ""))
            return
        if time.time() > deadline:
            where = path or "no wide-event-validation-log.jsonl found"
            die(f"FAIL wide event {feature} not written within {timeout:g}s after mark ({where})", 1)
        time.sleep(0.5)


def server_request(run_dir, method, path, params=None, timeout=30):
    launch = read_json(os.path.join(run_dir, "launch.json"))
    if not launch.get("automation_port"):
        die("NO AUTOMATION: rebuild with `verify.sh build <topic> <worktree> --automation`")
    token = open(os.path.join(run_dir, "automation_token")).read().strip()
    query = urllib.parse.urlencode(params or {}, quote_via=urllib.parse.quote)
    url = f"http://[::1]:{launch['automation_port']}{path}" + (f"?{query}" if query else "")
    req = urllib.request.Request(url, data=b"" if method == "POST" else None, method=method)
    req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r).get("message")


def cmd_ready(run_dir, timeout="60"):
    deadline = time.time() + float(timeout)
    last = None
    while time.time() < deadline:
        try:
            last = server_request(run_dir, "GET", "/contentBlockerReady", timeout=5)
            if last == "true":
                print("READY content blocker")
                return
        except OSError as e:
            last = str(e)
        time.sleep(1)
    die(f"NOT READY: /contentBlockerReady never returned true ({last})")


def cmd_web(run_dir, what, *rest):
    if what == "url":
        print(server_request(run_dir, "GET", "/getUrl"))
    elif what == "eval":
        print(server_request(run_dir, "POST", "/execute", {"script": rest[0]}))
    elif what == "navigate":
        print(server_request(run_dir, "POST", "/navigate", {"url": rest[0]}))
    else:
        die("web: url | eval '<js returning a value>' | navigate <url> (setup only)")


def cmd_manifest(run_dir, skill_dir, topic):
    def maybe(name):
        try:
            return read_json(os.path.join(run_dir, name))
        except (FileNotFoundError, ValueError):
            return None

    def lines(name):
        try:
            return [l for l in open(os.path.join(run_dir, name)).read().splitlines() if l]
        except FileNotFoundError:
            return []

    build, launch, vm = maybe("build.json") or {}, maybe("launch.json") or {}, maybe("vm.json")
    skill = hashlib.sha256()
    for top, dirs, files in os.walk(skill_dir):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        for n in sorted(files):
            skill.update(n.encode())
            skill.update(sha256_file(os.path.join(top, n)).encode())

    def cmd(*a):
        try:
            return subprocess.run(a, capture_output=True, text=True, timeout=20).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return None

    manifest = dict(
        topic=topic,
        worktree=build.get("worktree"),
        revision=build.get("source", {}).get("head"),
        dirty=build.get("source", {}).get("dirty"),
        source_fingerprint=build.get("source", {}).get("stamp"),
        build_hashes=build.get("hashes"),
        build_end=build.get("build_end"),
        launch=launch,
        defaults_written=lines("defaults_written"),
        flags=lines("flags"),
        mark=maybe("mark.json"),
        macos=cmd("sw_vers", "-productVersion"),
        xcode=(cmd("xcodebuild", "-version") or "").splitlines()[:1],
        vm=vm,
        skill_sha256=skill.hexdigest(),
        rerun=f"cd {build.get('worktree')} && "
              + (f"{VERIFY_SH} vm {topic} {vm['host']} && " if vm else "")
              + f"{VERIFY_SH} build {topic} ."
              + (" --automation" if launch.get("automation_port") else ""),
    )
    with open(os.path.join(run_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print(os.path.join(run_dir, "manifest.json"))


# ---------------------------------------------------------------- reset: each run starts from the same state
BUNDLE = "com.duckduckgo.macos.browser.debug"


def parse_checks(text):
    """{what: ok} from the "check<TAB>what<TAB>ok|fail" lines a reset prints; other lines are ignored."""
    return {p[1]: p[2] == "ok" for p in (line.split("\t") for line in text.splitlines()) if len(p) == 3 and p[0] == "check"}


def write_reset(run_dir, where, checks, kept=()):
    """reset.json: where the run was reset, each state read back after it (`checks`), and what was deliberately kept."""
    path = os.path.join(run_dir, "reset.json")
    old = read_json(path) if os.path.exists(path) else {}
    with open(path, "w") as f:
        json.dump(dict(where=where, checks={**old.get("checks", {}), **checks}, kept=list(kept) or old.get("kept", [])),
                  f, indent=1)


def cmd_reset_record(run_dir, where):
    """reset.json for a VM, from the reset's output on stdin."""
    write_reset(run_dir, where, parse_checks(sys.stdin.read()))


# The Debug app's own app groups (DeveloperID.xcconfig gives Debug `.debug` ones): the downloaded privacy config and its
# ETags, internal-user and remote-messaging state, the subscription. Not network-protection or dbp: the Debug VPN
# extension and DBP agent can run without the app and keep using them.
DEBUG_GROUPS = ("app-configuration", "subscription")


def app_data(home, temp, cache, bundle=BUNDLE):
    """The Debug app's own data on this Mac that exists now, its own .debug group containers included.
    Not WebKit's <temp>/com.apple.WebKit.*+<bundle> folders: macOS refuses to move them (seen in a VM)."""
    lib = os.path.join(home, "Library")
    paths = [os.path.join(lib, d, bundle) for d in ("Application Support", "Caches", "Containers", "WebKit", "HTTPStorages")]
    groups = glob.escape(os.path.join(lib, "Group Containers"))
    paths += sorted(p for g in DEBUG_GROUPS for p in glob.glob(os.path.join(groups, f"*.com.duckduckgo.macos.browser.{g}.debug")))
    paths += [os.path.join(lib, "Saved Application State", bundle + ".savedState"), os.path.join(temp, bundle),
              os.path.join(cache, bundle)] + sorted(glob.glob(os.path.join(glob.escape(cache), "*+" + bundle)))
    return [p for p in paths if os.path.lexists(p)]


def listing(folder):
    """{name: mtime} of a folder's entries."""
    try:
        return {e.name: e.stat(follow_symlinks=False).st_mtime for e in os.scandir(folder)}
    except FileNotFoundError:
        return {}


def created_since(before, after, since):
    """The entries a run created: names that weren't there at its start, modified since. A name that was there is the
    user's, whatever happened to it."""
    return sorted(n for n, mtime in after.items() if n not in before and mtime >= since)


def _sh(*args):
    return subprocess.run(args, capture_output=True, text=True)


class MacReset:
    """prove --base on this Mac: each run starts with no Debug app data and puts the engineer's back after it.

    begin parks the Debug app's own data (app_data, and its defaults domain exported then deleted) under
    <verify home>/.mac-park and snapshots ~/Downloads; end moves the run's new Downloads files to the Trash, deletes what
    the run created and moves the parked data back. Nothing is deleted unless it was parked first, a park left by a run
    that died is put back first, and nothing is parked while another Debug app is open, another worktree's verify app
    included (it would write into the moved folders). Only this run's own app is ever quit."""

    def __init__(self, run_dir, verify_home, app_name, home=os.path.expanduser("~"), owner=None, sh=_sh):
        self.run_dir, self.home, self.sh = run_dir, home, sh
        self.app = re.escape(app_name) + r"\.app/Contents/MacOS"
        self.park = os.path.join(verify_home, ".mac-park")
        self.owner = int(owner or os.environ.get("VERIFY_OWNER_PID") or os.getppid())
        self.temp, self.cache = (sh("getconf", v).stdout.strip() for v in ("DARWIN_USER_TEMP_DIR", "DARWIN_USER_CACHE_DIR"))
        self.downloads = os.path.join(home, "Downloads")

    def data(self):
        return app_data(self.home, self.temp, self.cache)

    def _park_owner(self):
        try:
            return read_json(os.path.join(self.park, "owner.json"))["pid"]
        except (OSError, ValueError, KeyError):
            return None

    def _defaults_empty(self):
        read = self.sh("defaults", "read", BUNDLE)   # after `defaults delete`, macOS 27 reads back `{}` with exit 0
        return read.returncode != 0 or "".join(read.stdout.split()) in ("", "{}")

    def begin(self):
        checks = {}
        if os.path.isdir(self.park):
            holder = self._park_owner()
            if holder and holder != self.owner and alive(holder):
                checks["Debug app data free (another run holds it)"] = False
            else:
                self.restore()   # left by a run that died
        for _ in range(10):
            if self.sh("pkill", "-f", self.app).returncode:
                break
            time.sleep(1)
        checks["app stopped"] = self.sh("pgrep", "-f", self.app).returncode != 0
        other = f'bundleID="{BUNDLE}"' in self.sh("lsappinfo", "list").stdout
        checks["no other Debug app open (another worktree's verify app counts)"] = not other
        if all(checks.values()) and not os.path.isdir(self.park):
            items = os.path.join(self.park, "items")
            os.makedirs(items)
            moved = {str(i): path for i, path in enumerate(self.data())}
            with open(os.path.join(self.park, "owner.json"), "w") as f:   # before any move: restore needs the plan
                json.dump(dict(pid=self.owner, moved=moved), f, indent=1)
            plist = os.path.join(self.park, "defaults.plist")
            had = not self._defaults_empty()
            if not had or self.sh("defaults", "export", BUNDLE, plist).returncode == 0:
                with open(os.path.join(self.park, "defaults.parked"), "w") as f:   # restore may now replace the domain
                    f.write("exported" if had else "absent")
                self.sh("defaults", "delete", BUNDLE)
            for i, path in moved.items():
                try:   # rename: all or nothing; a folder macOS refuses to move stays, and the check below fails
                    os.rename(path, os.path.join(items, i))
                except OSError:
                    pass
        left = self.data()
        checks["app data and temp files removed"] = not left
        if left:   # seen on a real Mac: other apps' containers are protected from a shell without Full Disk Access
            names = ", ".join(os.path.basename(p) for p in left)
            checks[f"macOS refused to move {names}: give the app that runs prove Full Disk Access, or prove in a VM"] = False
        checks["app defaults and pinned flags removed"] = self._defaults_empty()
        with open(os.path.join(self.run_dir, "downloads-before.json"), "w") as f:
            json.dump(dict(since=time.time(), entries=listing(self.downloads)), f)
        write_reset(self.run_dir, "mac", checks, kept=[
            "the engineer's Downloads files", "the pasteboard",
            "the Debug network-protection and dbp group containers (the VPN extension and DBP agent run without the app)",
            "wide-event storage (defaults domain com.duckduckgo.wide-pixel.storage, shared with the release app)"])

    def end(self):
        checks = {}
        try:
            before = read_json(os.path.join(self.run_dir, "downloads-before.json"))
        except (OSError, ValueError):
            before = None
        if before:
            new = created_since(before["entries"], listing(self.downloads), before["since"])
            trash = os.path.join(self.home, ".Trash")
            for name in new:
                stamp = time.strftime("%H.%M.%S")
                dest = os.path.join(trash, name if not os.path.lexists(os.path.join(trash, name)) else f"{name} {stamp}")
                try:
                    shutil.move(os.path.join(self.downloads, name), dest)
                except OSError:
                    pass
            checks["the run's Downloads files moved to the Trash"] = not any(
                os.path.lexists(os.path.join(self.downloads, n)) for n in new)
        else:
            checks["the run's Downloads files moved to the Trash (no snapshot at its start)"] = False
        if self._park_owner() == self.owner:
            checks["the engineer's Debug app data put back"] = self.restore()
        write_reset(self.run_dir, "mac", checks)

    def restore(self):
        """Delete the Debug app data a run created and move the parked data back; True when the park is gone."""
        try:
            moved = read_json(os.path.join(self.park, "owner.json"))["moved"]
        except (OSError, ValueError, KeyError):
            moved = None
        if moved is None:   # no plan written: nothing was moved yet, so nothing here is the engineer's to put back
            shutil.rmtree(self.park)
            return True
        for _ in range(10):
            if self.sh("pkill", "-f", self.app).returncode:
                break
            time.sleep(1)
        items = os.path.join(self.park, "items")
        for path in self.data():
            parked = [i for i, p in moved.items() if p == path]
            if parked and not os.path.lexists(os.path.join(items, parked[0])):
                continue   # never moved (begin died first): it is the engineer's own
            shutil.rmtree(path) if os.path.isdir(path) and not os.path.islink(path) else os.remove(path)
        for i, path in moved.items():
            if os.path.lexists(os.path.join(items, i)):
                os.makedirs(os.path.dirname(path), exist_ok=True)
                os.rename(os.path.join(items, i), path)
        if os.path.exists(os.path.join(self.park, "defaults.parked")):
            self.sh("defaults", "delete", BUNDLE)
            plist = os.path.join(self.park, "defaults.plist")
            if os.path.exists(plist):
                self.sh("defaults", "import", BUNDLE, plist)
        shutil.rmtree(self.park)
        return not os.path.exists(self.park) and all(os.path.lexists(p) for p in moved.values())


def cmd_reset(step, run_dir, verify_home, app_name):
    if step not in ("begin", "end"):
        die("reset: begin or end")
    getattr(MacReset(run_dir, verify_home, app_name), step)()
    checks = read_json(os.path.join(run_dir, "reset.json"))["checks"]
    for what, ok in checks.items():
        print(f"check\t{what}\t{'ok' if ok else 'fail'}")


COMMANDS = {
    "fingerprint": cmd_fingerprint, "hash": cmd_hash, "flag": cmd_flag, "mark": cmd_mark,
    "expect-pixel": cmd_expect_pixel, "expect-no-pixel": cmd_expect_no_pixel,
    "expect-wide-event": cmd_expect_wide_event, "ready": cmd_ready, "web": cmd_web, "manifest": cmd_manifest,
    "reset": cmd_reset, "reset-record": cmd_reset_record,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        die("usage: vhelp.py " + "|".join(COMMANDS))
    try:
        COMMANDS[sys.argv[1]](*sys.argv[2:])
    except TypeError as e:
        die(f"{sys.argv[1]}: wrong arguments ({e})")
    except subprocess.CalledProcessError as e:
        die(f"{sys.argv[1]}: {' '.join(map(str, e.cmd))} failed: {e.stderr.decode(errors='replace').strip()}")
