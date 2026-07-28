#!/usr/bin/env python3

import importlib.util
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROGRAM = ROOT / "run-with-watchdog.py"
SPEC = importlib.util.spec_from_file_location("run_with_watchdog", PROGRAM)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class RunWithWatchdogTests(unittest.TestCase):
    def test_sigterm_race_is_treated_as_already_exited(self) -> None:
        class Process:
            pid = 123

            @staticmethod
            def poll() -> None:
                return None

        original_exists = MODULE.process_group_exists
        original_killpg = MODULE.os.killpg
        try:
            MODULE.process_group_exists = lambda _pid: True

            def process_gone(_pid: int, _signal: int) -> None:
                raise ProcessLookupError

            MODULE.os.killpg = process_gone
            self.assertEqual(
                MODULE.terminate_process_group(Process(), 1),
                "already_exited",
            )
        finally:
            MODULE.process_group_exists = original_exists
            MODULE.os.killpg = original_killpg

    def test_non_timeout_preserves_exit_status_and_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status = Path(directory) / "status.tsv"
            result = subprocess.run(
                [
                    "python3", str(PROGRAM),
                    "--timeout-seconds", "5",
                    "--term-grace-seconds", "1",
                    "--status-file", str(status),
                    "--", "/bin/sh", "-c", "echo retained; exit 7",
                ],
                text=True,
                capture_output=True,
                timeout=10,
            )

            self.assertEqual(result.returncode, 7)
            self.assertEqual(result.stdout, "retained\n")
            self.assertEqual(status.read_text(), "completed\t7\tnot_needed\n")

    def test_timeout_kills_only_launched_process_group(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            status = root / "status.tsv"
            child_pid_file = root / "child.pid"
            script = root / "hang.sh"
            script.write_text(
                "#!/bin/sh\n"
                "trap '' TERM\n"
                "sleep 1000 &\n"
                f"echo $! > {child_pid_file}\n"
                "wait\n"
            )
            script.chmod(0o755)
            unrelated = subprocess.Popen(["sleep", "30"])
            try:
                result = subprocess.run(
                    [
                        "python3", str(PROGRAM),
                        "--timeout-seconds", "1",
                        "--term-grace-seconds", "1",
                        "--status-file", str(status),
                        "--", str(script),
                    ],
                    text=True,
                    capture_output=True,
                    timeout=10,
                )

                self.assertEqual(result.returncode, 124)
                state, code, cleanup = status.read_text().strip().split("\t")
                self.assertEqual((state, code), ("timed_out", "124"))
                self.assertIn(cleanup, {"terminated", "killed"})
                self.assertIsNone(unrelated.poll())
                child_pid = int(child_pid_file.read_text())
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    try:
                        os.kill(child_pid, 0)
                    except ProcessLookupError:
                        break
                    time.sleep(0.05)
                else:
                    self.fail(
                        "watchdog left a child in its launched process group"
                    )
            finally:
                unrelated.terminate()
                unrelated.wait()


if __name__ == "__main__":
    unittest.main()
