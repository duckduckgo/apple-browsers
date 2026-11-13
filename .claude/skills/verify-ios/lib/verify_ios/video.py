"""Screen recording of one device's proof run: `xcrun simctl io <udid> recordVideo`, h264 so browsers and GitHub play it.

The recorder runs in its own session so a Ctrl-C at the terminal can't stop it early, and it is stopped with SIGINT,
the signal simctl finalizes the movie on. A recording that fails is reported as an evidence problem, never as a failed
proof.
"""
import os, signal, subprocess, time


class Video:
    FILE = "recording.mp4"
    START_TIMEOUT = 15
    STOP_TIMEOUT = 30

    def __init__(self, udid, path):
        self.udid, self.path = udid, path
        self.log = f"{os.path.splitext(path)[0]}.log"
        self.proc, self.ok = None, False

    def start(self):
        """Start recording and wait until simctl says it is recording, so the first actions are on the video."""
        with open(self.log, "w") as log:
            self.proc = subprocess.Popen(["xcrun", "simctl", "io", self.udid, "recordVideo", "--codec=h264", "--force",
                                          self.path], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.time() + self.START_TIMEOUT
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"recordVideo exited {self.proc.returncode}: {self._said()}")
            if "Recording started" in self._said():
                return self
            time.sleep(0.2)
        return self   # still running without saying so: keep it, stop() checks the file

    def stop(self):
        """Stop with SIGINT so the movie is finalized; return problems (never raises)."""
        problems = []
        try:
            if self.proc.poll() is None:
                self.proc.send_signal(signal.SIGINT)
                try:
                    self.proc.wait(self.STOP_TIMEOUT)
                except subprocess.TimeoutExpired:
                    self.proc.kill()
                    self.proc.wait()
                    problems.append(f"screen recording did not stop within {self.STOP_TIMEOUT} s and was killed; "
                                    f"{self.FILE} may be unplayable")
            elif self.proc.returncode != 0:
                problems.append(f"screen recording stopped early (exit {self.proc.returncode}): {self._said()}")
            if not os.path.isfile(self.path) or os.path.getsize(self.path) == 0:
                problems.append(f"screen recording wrote no {self.FILE}: {self._said()}")
            self.ok = not problems
        except Exception as e:
            problems.append(f"could not stop the screen recording: {type(e).__name__}: {e}")
        return problems

    def _said(self):
        try:
            with open(self.log) as f:
                return f.read().strip()[-300:]
        except OSError:
            return ""
