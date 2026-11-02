"""Where things live for this worktree: state dir, ports, token, locks, and process identity.

Everything is keyed to the git worktree the caller runs from, so two worktrees never share simulators, ports,
build products, recorded pids or evidence.
"""
import contextlib, fcntl, hashlib, json, os, secrets, socket, subprocess

SKILL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
BUNDLE = "com.duckduckgo.mobile.ios"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
DEVICE_TYPES = {"iphone": "iPhone 17 Pro", "ipad": "iPad Pro 11-inch (M5)"}
PORT_OFFSET = {"iphone": (0, 1), "ipad": (2, 3)}   # (AutomationServer, runner) offsets from the worktree's base port
FIXTURE_OFFSET = 4
EXIT_BUSY = 75
# Remote feature flags pinned on every launch (through LaunchOptionsHandler's `-ff.<flag> true|false` arguments), so
# proofs never depend on the live privacy configuration. The iPhone ids in steps.py and the feature map assume these.
PINNED_FLAGS = {"newTabPageRedesign": True}


class Failed(Exception):
    """A check failed or an element wasn't found (exit 1)."""

    def __init__(self, msg, **extra):
        super().__init__(msg)
        self.extra = extra


class SetupFailed(Failed):
    """Setting up the device failed (launch, reset, a simulator setting), even when a proof asked for it: reported
    as an error (exit 2, INCONCLUSIVE), never as a product failure."""


class Unsupported(Exception):
    """Not something iOS or this driver can do (exit 3)."""


class Busy(Exception):
    """Another process holds this device's lock (exit 75)."""


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def git_root():
    p = run(["git", "rev-parse", "--show-toplevel"])
    return p.stdout.strip() if p.returncode == 0 else os.path.dirname(os.path.dirname(os.path.dirname(SKILL)))


ROOT = git_root()
KEY = os.path.basename(ROOT) + "-" + hashlib.sha1(ROOT.encode()).hexdigest()[:6]
HOME = os.path.join(os.path.expanduser(os.environ.get("VERIFY_IOS_HOME", "~/.ddg-verify-ios")), KEY)
STATE = f"{HOME}/state.json"
APP_DD = f"{HOME}/build/app"
RUNNER_DD = f"{HOME}/build/runner"
APP = f"{APP_DD}/Build/Products/Debug-iphonesimulator/DuckDuckGo.app"
EVIDENCE = f"{HOME}/evidence"
BASE_PORT = 20000 + int(hashlib.sha1(ROOT.encode()).hexdigest(), 16) % 1000 * 8


def ports(device):
    web, runner = PORT_OFFSET[device]
    return BASE_PORT + web, BASE_PORT + runner


def fixture_port():
    return BASE_PORT + FIXTURE_OFFSET


# ---------------------------------------------------------------- state
@contextlib.contextmanager
def _state_lock():
    os.makedirs(HOME, exist_ok=True)
    with open(f"{HOME}/state.lock", "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def update_state(change):
    """Read-modify-write under a lock: iPhone and iPad commands may update state at the same moment."""
    with _state_lock():
        st = load_state()
        result = change(st)
        tmp = STATE + ".tmp"
        with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:   # it holds the runner token
            json.dump(st, f, indent=1)
        os.replace(tmp, STATE)
        return result


def feature_flag_names():
    """The app's FeatureFlag case names, read from this checkout's source (a pinned flag must be one of them)."""
    import re
    path = os.path.join(ROOT, "iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift")
    with open(path) as f:
        source = f.read()
    body = source.split("public enum FeatureFlag", 1)[-1].split("\n}", 1)[0]
    return set(re.findall(r"^\s*case\s+(\w+)\s*$", body, re.M))


def source_stamp():
    """Fingerprint of the app source in this worktree: HEAD plus every uncommitted change outside .claude/.
    Recorded when the app is built and compared before a proof, so a proof can't pass against a stale build."""
    scope = ["--", ".", ":(exclude).claude"]
    head = run(["git", "-C", ROOT, "rev-parse", "HEAD"]).stdout.strip()
    h = hashlib.sha256(head.encode())
    h.update(subprocess.run(["git", "-C", ROOT, "diff", "HEAD", "--binary", *scope], capture_output=True).stdout)
    for path in sorted(run(["git", "-C", ROOT, "ls-files", "--others", "--exclude-standard", *scope]).stdout.splitlines()):
        h.update(path.encode())
        try:
            h.update(sha256(os.path.join(ROOT, path)).encode())
        except OSError:
            pass
    return dict(head=head, stamp=h.hexdigest())


def token():
    st = load_state()
    if st.get("token"):
        return st["token"]
    return update_state(lambda s: s.setdefault("token", secrets.token_hex(16)))


# ---------------------------------------------------------------- device lock
class DeviceLock:
    """One owner per device in this worktree: a proof or an exploring CLI command. Never broken, never waited on."""

    def __init__(self, device):
        os.makedirs(f"{HOME}/locks", exist_ok=True)
        self.path = f"{HOME}/locks/{device}.lock"
        self.device = device
        self.f = None

    def acquire(self, holder):
        self.f = open(self.path, "a+")
        try:
            fcntl.flock(self.f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.f.seek(0)
            who = self.f.read().strip() or "unknown"
            self.f.close()
            self.f = None
            raise Busy(f"{self.device} is busy ({who}). Let that run finish; never delete {self.path}.")
        self.f.seek(0)
        self.f.truncate()
        self.f.write(f"{holder} pid {os.getpid()}\n")
        self.f.flush()
        return self

    def release(self):
        if self.f:
            self.f.close()
            self.f = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.release()


# ---------------------------------------------------------------- processes and ports
def port_listening(port, host="127.0.0.1"):
    fam = socket.AF_INET6 if ":" in host else socket.AF_INET
    with socket.socket(fam, socket.SOCK_STREAM) as s:
        s.settimeout(0.3)
        return s.connect_ex((host, port)) == 0


def process_identity(pid):
    """Start time + command of a live pid, or None. Recorded at start and checked before any kill, so a pid that was
    reused by an unrelated process is never signalled."""
    p = run(["ps", "-o", "lstart=,command=", "-p", str(pid)])
    line = p.stdout.strip()
    if p.returncode or not line:
        return None
    return dict(pid=int(pid), lstart=line[:24], command=line[24:].strip()[:300])


def still_ours(recorded):
    now = process_identity(recorded["pid"])
    return bool(now) and now["lstart"] == recorded["lstart"] and now["command"] == recorded["command"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
