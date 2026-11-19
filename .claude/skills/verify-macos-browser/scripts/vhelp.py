#!/usr/bin/env python3
"""Helpers for verify.sh: source fingerprint, flag check, telemetry, AutomationServer, manifest.

Every command prints one line or JSON and exits 0 (ok), 1 (a check failed) or 2 (error / can't tell).
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

VERIFY_SH = ".claude/skills/verify-macos-browser/scripts/verify.sh"   # from the worktree root
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
    """HEAD plus every uncommitted change outside .claude/ (same as verify-ios source_stamp)."""
    scope = ["--", ".", ":(exclude).claude"]
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
        pid = open(os.path.join(run_dir, "pixel_stream.pid")).read().strip()
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


COMMANDS = {
    "fingerprint": cmd_fingerprint, "hash": cmd_hash, "flag": cmd_flag, "mark": cmd_mark,
    "expect-pixel": cmd_expect_pixel, "expect-no-pixel": cmd_expect_no_pixel,
    "expect-wide-event": cmd_expect_wide_event, "ready": cmd_ready, "web": cmd_web, "manifest": cmd_manifest,
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
