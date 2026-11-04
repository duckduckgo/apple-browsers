"""Pixels and wide events, read from a Debug build on the simulator. Debug builds send nothing:

- Pixels: PixelKit runs in dry-run mode and logs every pixel at debug level on subsystem "PixelKit":
  `👾[<frequency>-Fired(dryRun)] <name> ["key": "value", ...]`, or `-Skipped` when its frequency rule suppressed it
  (a daily pixel that already fired, a sample that wasn't picked). Debug messages are only visible to a live stream,
  so the stream must start before the action.
- Wide events: the POST is mocked in Debug, and its log line is truncated at ~1 KB, so read the complete events from
  `<app data>/Library/Caches/wide-event-validation-log.jsonl` (DefaultWideEventSender, Debug only; cleared on the
  first event of each app launch).
"""
import json, os, re, subprocess, time

from .env import Failed

PIXEL = re.compile(r"👾\[(?P<frequency>.+?)-(?P<status>Fired\(dryRun\)|Fired|Skipped)\] (?P<name>\S+)(?: \[(?P<params>.*)\])?\s*$")
PARAM = re.compile(r'"((?:[^"\\]|\\.)*)": "((?:[^"\\]|\\.)*)"')
SUFFIX = re.compile(r"_ios_(phone|tablet)$")


def _tail(path, n=500):
    try:
        with open(path) as f:
            return f.read()[-n:]
    except OSError:
        return ""


def parse_pixel(message):
    m = PIXEL.search(message.strip())
    if not m:
        return None
    params = dict(PARAM.findall(m["params"] or ""))
    return dict(name=m["name"], status="Skipped" if m["status"] == "Skipped" else "Fired", frequency=m["frequency"], params=params)


class Pixels:
    """Captures PixelKit log lines for one proof run. Selection is by name and emission order, never by expected params."""

    ATTACHED = "Filtering the log data"   # `log stream` prints this header once it is attached

    def __init__(self, udid, path):
        self.udid, self.path = udid, path
        self.proc = None
        self.since = None   # index into all() set by mark(); assertions only count emissions after it

    def start(self, timeout=15):
        """Start the stream; on any failure the child is stopped before raising (the caller may not get the object)."""
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path, "w") as out, open(self.path + ".stderr", "w") as err:
            self.proc = subprocess.Popen(["xcrun", "simctl", "spawn", self.udid, "log", "stream", "--level", "debug", "--style", "ndjson",
                                          "--predicate", 'subsystem == "PixelKit"'], stdout=out, stderr=err, start_new_session=True)
        end = time.time() + timeout
        try:
            while time.time() < end:
                with open(self.path) as f:
                    if self.ATTACHED in f.read(4096):   # pixels fired before this would be missed
                        return self
                if self.proc.poll() is not None:
                    raise Failed("pixel log stream exited", stderr=open(self.path + ".stderr").read()[-500:])
                time.sleep(0.1)
            raise Failed("pixel log stream never attached")
        except BaseException:
            self.stop()
            raise

    def healthy(self):
        """Fail if the stream has died: a dead stream sees no pixels, which would make "not fired" pass vacuously."""
        if not self.proc or self.proc.poll() is not None:
            raise Failed("the pixel log stream is not running; pixel results would be meaningless",
                         stderr=_tail(self.path + ".stderr"))

    def mark(self):
        """Count only pixels emitted from now on (call it just before the action under test)."""
        self.healthy()
        self.since = len(self.all())

    def _after_mark(self):
        if self.since is None:
            raise Failed("call ios.mark() just before the action under test: without it, pixels fired during setup would count")
        return self.all()[self.since:]

    def stop(self):
        """Stop our `simctl spawn` child; that also ends the `log stream` it started inside the simulator.

        No identity check here: this is our own unreaped child, so its pid can't have been reused. (Its recorded
        command would not match anyway: xcrun replaces itself with simctl right after starting.)
        """
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(5)
        self.proc = None

    def all(self):
        """Every pixel line seen so far, in order: {name, status Fired|Skipped, frequency, params, time}."""
        out = []
        try:
            with open(self.path) as f:
                for line in f:
                    try:
                        ev = json.loads(line)
                    except ValueError:
                        continue
                    px = parse_pixel(ev.get("eventMessage", ""))
                    if px:
                        px["time"] = ev.get("timestamp")
                        out.append(px)
        except OSError:
            pass
        return out

    def fired(self, name, occurrence=0, timeout=10):
        """Wait until pixel `name` has fired `occurrence`+1 times since the mark; return that emission.
        Skipped emissions don't count; PixelKit logs them without the _ios_phone/_ios_tablet suffix."""
        base = SUFFIX.sub("", name)
        end = time.time() + timeout
        while True:
            self.healthy()
            seen = self._after_mark()
            hits = [p for p in seen if p["name"] == name and p["status"] == "Fired"]
            if len(hits) > occurrence:
                return hits[occurrence]
            if time.time() > end:
                raise Failed(f"pixel {name} not fired (occurrence {occurrence}) within {timeout}s of the mark",
                             skipped=[p for p in seen if p["name"] in (name, base) and p["status"] == "Skipped"],
                             similar=sorted({p["name"] for p in seen if base.split("_")[0] in p["name"]})[:20])
            time.sleep(0.25)

    def not_fired(self, name, within=3):
        """Fail if `name` fires between the mark and `within` seconds from now; fail too if the stream isn't running."""
        end = time.time() + within
        while time.time() < end:
            self.healthy()
            hits = [p for p in self._after_mark() if p["name"] == name and p["status"] == "Fired"]
            if hits:
                raise Failed(f"pixel {name} fired but should not have", pixel=hits[0])
            time.sleep(0.25)
        self.healthy()


class WideEvents:
    """Complete wide events written by a Debug build during this proof run."""

    FILE = "Library/Caches/wide-event-validation-log.jsonl"

    def __init__(self, data_container):
        """`data_container` is a callable: a reinstall (reset) moves the app to a new data container."""
        self.container = data_container
        self.baseline = (self._path(), self._lines(self._path()))
        self.marked = False

    def mark(self):
        """Count only events written from now on (call it just before the action under test)."""
        path = self._path()
        self.baseline = (path, self._lines(path))
        self.marked = True

    def _path(self):
        try:
            return os.path.join(self.container(), self.FILE)
        except Failed:   # app not installed yet
            return None

    @staticmethod
    def _lines(path):
        try:
            with open(path) as f:
                return [line for line in f.read().splitlines() if line.strip()]
        except (OSError, TypeError):
            return []

    def all(self):
        path = self._path()
        lines = self._lines(path)
        base_path, base = self.baseline
        # Only events written after the proof started: a new container (reset) has none from before; in the same
        # container the app clears the file on its first event after a launch, until then skip what was there.
        if path == base_path and lines[:len(base)] == base:
            lines = lines[len(base):]
        return [json.loads(line) for line in lines]

    def wait(self, feature, occurrence=0, timeout=10):
        """Wait for the `occurrence`th wide event of `feature` (e.g. "data-clearing") since the mark; return the payload."""
        if not self.marked:
            raise Failed("call ios.mark() just before the action under test: without it, events from setup would count")
        end = time.time() + timeout
        while True:
            hits = [e for e in self.all() if e.get("feature", {}).get("name") == feature]
            if len(hits) > occurrence:
                return hits[occurrence]
            if time.time() > end:
                raise Failed(f"wide event {feature} not written (occurrence {occurrence}) within {timeout}s",
                             seen=[e.get("feature", {}).get("name") for e in self.all()])
            time.sleep(0.25)
