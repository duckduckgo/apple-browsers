#!/usr/bin/env python3
"""Observe one selected simulator while running a command; preserve its exit status."""

import datetime
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

simulator, output_path, *command = sys.argv[1:]
output = Path(output_path)
output.mkdir(parents=True, exist_ok=True)
status = (output / "capture-status.jsonl").open("w", buffering=1)


def record(event, **values):
    status.write(json.dumps(dict(event=event, wall=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                 monotonic=time.monotonic(), simulator=simulator, **values)) + "\n")


def snapshot(phase):
    # launchctl binds simulator service labels to PIDs; ps adds process start times for PID reuse.
    try:
        result = subprocess.run(["xcrun", "simctl", "spawn", simulator, "launchctl", "list"],
                                capture_output=True, text=True, timeout=15)
        rows = [line for line in result.stdout.splitlines()
                if any(term in line.lower() for term in ("auth", "springboard", "duckduckgo", "runningboard", "frontboard"))]
        record("processes", phase=phase, exit_code=result.returncode, services=rows, error=result.stderr)
        pids = [row.split()[0] for row in rows if row.split()[0].isdigit()]
        if pids:
            details = subprocess.run(["ps", "-p", ",".join(pids), "-o", "pid=,ppid=,lstart=,command="],
                                     capture_output=True, text=True, timeout=10)
            record("process_start_identities", phase=phase, exit_code=details.returncode,
                   identities=details.stdout, error=details.stderr)
    except (OSError, subprocess.TimeoutExpired) as error:
        record("process_snapshot_unavailable", phase=phase, error=str(error))
    # Metadata only, never crash contents. Start/end inventories distinguish pre-existing reports.
    directories = [Path.home() / "Library/Logs/DiagnosticReports",
                   Path.home() / "Library/Developer/CoreSimulator/Devices" / simulator / "data/Library/Logs/CrashReporter"]
    for directory in directories:
        try:
            reports = [dict(name=path.name, modified=path.stat().st_mtime, size=path.stat().st_size)
                       for path in directory.iterdir() if path.is_file()
                       and any(term in path.name.lower() for term in ("auth", "springboard", "duckduckgo", "runningboard", "frontboard"))]
            record("crash_metadata", phase=phase, directory=str(directory), reports=reports,
                   scope="host inventory is not proof of selected-simulator origin")
        except OSError as error:
            record("crash_metadata_unavailable", phase=phase, directory=str(directory), error=str(error))


stream = None
child = None


def interrupted(signum, _frame):
    record("interrupted", signal=signum)
    if child is not None and child.poll() is None:
        child.terminate()
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
record("capture_start", limits="35 minutes or 64 MiB; filtered, dropped, or missing events do not establish absence")
snapshot("start")
predicate = ('process CONTAINS[c] "auth" OR '
             '(process == "DuckDuckGo" AND eventMessage CONTAINS "Application Lock UI test:") OR '
             '((process == "SpringBoard" OR process == "runningboardd" OR process == "frontboardd") AND '
             '(eventMessage CONTAINS[c] "auth" OR eventMessage CONTAINS[c] "duckduckgo" '
             'OR eventMessage CONTAINS[c] "scene" OR eventMessage CONTAINS[c] "activation"))')
try:
    with (output / "simulator.log").open("wb") as events, (output / "stream.stderr").open("wb") as errors:
        try:
            stream = subprocess.Popen(["xcrun", "simctl", "spawn", simulator, "log", "stream",
                                       "--style", "ndjson", "--level", "debug", "--timeout", "35m", "--predicate", predicate],
                                      stdout=events, stderr=errors)
            record("stream_started", pid=stream.pid, predicate=predicate)
        except OSError as error:
            record("stream_unavailable", error=str(error))
        child = subprocess.Popen(command)
        started = time.monotonic()
        while child.poll() is None:
            if stream is not None:
                if stream.poll() is not None:
                    record("stream_exited", exit_code=stream.returncode, bytes=events.tell())
                    stream = None
                elif time.monotonic() - started >= 2100 or events.tell() >= 64 * 1024 * 1024:
                    record("capture_limit_reached", bytes=events.tell())
                    stream.terminate()
                    try:
                        stream.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        stream.kill()
                        stream.wait()
                    stream = None
            time.sleep(1)
        record("command_completed", exit_code=child.returncode)
        sys.exit(child.returncode if child.returncode >= 0 else 128 - child.returncode)
finally:
    if stream is not None and stream.poll() is None:
        stream.terminate()
        try:
            stream.wait(timeout=10)
        except subprocess.TimeoutExpired:
            stream.kill()
            stream.wait()
        record("owned_stream_stopped", pid=stream.pid, exit_code=stream.returncode)
    elif stream is not None:
        record("stream_exited", exit_code=stream.returncode)
    snapshot("end")
    record("capture_end", stream_errors="stream.stderr", events="simulator.log")
    status.close()
