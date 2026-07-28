#!/usr/bin/env python3
"""Run one command in its own process group with a bounded wall-clock timeout."""

import argparse
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import BinaryIO


def positive_integer(value: str) -> int:
    try:
        parsed = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("must be an integer") from error
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return parsed


def copy_output(source: BinaryIO) -> None:
    while chunk := source.read(64 * 1024):
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()


def process_group_exists(process_group: int) -> bool:
    try:
        os.killpg(process_group, 0)
    except ProcessLookupError:
        return False
    return True


def terminate_process_group(process: subprocess.Popen[bytes], grace: int) -> str:
    process.poll()
    if not process_group_exists(process.pid):
        return "already_exited"
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return "already_exited"
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        process.poll()
        if not process_group_exists(process.pid):
            return "terminated"
        time.sleep(0.05)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return "terminated"
    try:
        process.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        pass
    return "killed"


def write_status(path: Path, state: str, return_code: int, cleanup: str) -> None:
    path.write_text(
        f"{state}\t{return_code}\t{cleanup}\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout-seconds", type=positive_integer, required=True)
    parser.add_argument("--term-grace-seconds", type=positive_integer, required=True)
    parser.add_argument("--status-file", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("a command is required after --")

    args.status_file.unlink(missing_ok=True)
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    assert process.stdout is not None
    output_thread = threading.Thread(
        target=copy_output,
        args=(process.stdout,),
        daemon=True,
    )
    output_thread.start()

    forwarded_signal = 0

    def handle_signal(signum: int, _frame: object) -> None:
        nonlocal forwarded_signal
        forwarded_signal = signum

    original_handlers = {
        signum: signal.signal(signum, handle_signal)
        for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)
    }
    deadline = time.monotonic() + args.timeout_seconds
    state = "completed"
    cleanup = "not_needed"
    try:
        while process.poll() is None:
            if forwarded_signal:
                cleanup = terminate_process_group(
                    process,
                    args.term_grace_seconds,
                )
                write_status(
                    args.status_file,
                    "interrupted",
                    128 + forwarded_signal,
                    cleanup,
                )
                return 128 + forwarded_signal
            if time.monotonic() >= deadline:
                state = "timed_out"
                cleanup = terminate_process_group(
                    process,
                    args.term_grace_seconds,
                )
                break
            time.sleep(0.1)
        output_thread.join(timeout=5)
        if state == "timed_out":
            write_status(args.status_file, state, 124, cleanup)
            return 124
        return_code = process.returncode
        write_status(args.status_file, state, return_code, cleanup)
        return return_code
    finally:
        for signum, handler in original_handlers.items():
            signal.signal(signum, handler)
        if process.poll() is None:
            terminate_process_group(process, args.term_grace_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
