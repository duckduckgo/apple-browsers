#!/usr/bin/env python3
"""Observe one selected simulator while running a command; preserve its exit status."""

import datetime
import json
import os
import re
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

simulator, output_path, *command = sys.argv[1:]
output = Path(output_path)
output.mkdir(parents=True, exist_ok=True)
status = (output / "capture-status.jsonl").open("w", buffering=1)
status_lock = threading.RLock()


def record(event, **values):
    with status_lock:
        status.write(json.dumps(dict(event=event, wall=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                     monotonic=time.monotonic(), simulator=simulator, **values)) + "\n")


def snapshot(phase):
    # launchctl binds simulator service labels to PIDs; ps adds process start times for PID reuse.
    initial_hosts = None
    try:
        result = subprocess.run(["xcrun", "simctl", "spawn", simulator, "launchctl", "list"],
                                capture_output=True, text=True, timeout=15)
        if result.returncode == 0:
            initial_hosts = {int(row.split()[0]) for row in result.stdout.splitlines()
                             if len(row.split()) == 3 and row.split()[2] == "com.apple.LocalAuthenticationUIService"
                             and row.split()[0].isdigit()}
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
    return initial_hosts


def host_identity(pid, phase):
    try:
        services = subprocess.run(["xcrun", "simctl", "spawn", simulator, "launchctl", "list"],
                                  capture_output=True, text=True, timeout=1)
        selected = any(len(row.split()) == 3 and row.split()[0] == str(pid)
                       and row.split()[2] == "com.apple.LocalAuthenticationUIService"
                       for row in services.stdout.splitlines())
        process = subprocess.run(["ps", "-p", str(pid), "-o", "pid=,lstart=,comm="],
                                 capture_output=True, text=True, timeout=1)
        parts = process.stdout.strip().split(maxsplit=6)
        identity = dict(pid=pid, start=" ".join(parts[1:6]), path=parts[6]) if len(parts) == 7 else None
        valid = (services.returncode == 0 and selected and process.returncode == 0 and identity is not None
                 and parts[0] == str(pid) and Path(identity["path"]).name == "LocalAuthenticationUIService"
                 and ".simruntime/Contents/Resources/RuntimeRoot/" in identity["path"])
        record("sample_identity", phase=phase, selected_service=selected, valid=valid, identity=identity,
               service_exit=services.returncode, ps_exit=process.returncode,
               errors=services.stderr + process.stderr)
        return identity if valid else None
    except (OSError, subprocess.TimeoutExpired) as error:
        record("sample_identity_unavailable", phase=phase, pid=pid, error=str(error))
        return None


def observe_new_host(initial_hosts):
    # Tail the existing file independently; neither event parsing nor sampling blocks the test command.
    pending = ""
    attempted = False
    try:
        with (output / "simulator.log").open() as timeline:
            while not sample_stop.is_set() and timeline.tell() < 64 * 1024 * 1024:
                pending += timeline.read(65536)
                lines = pending.split("\n")
                pending = lines.pop()
                for line in lines:
                    try:
                        event = json.loads(line)
                    except ValueError:
                        continue
                    if Path(event.get("processImagePath", "")).name != "runningboardd":
                        continue
                    match = re.fullmatch(r"\[osservice<com\.apple\.LocalAuthenticationUIService>:([1-9]\d*)\] reported to RB as running",
                                         event.get("eventMessage", ""))
                    if match is None:
                        continue
                    pid = int(match[1])
                    if initial_hosts is not None and pid in initial_hosts:
                        record("sample_preexisting_host_ignored", pid=pid, event_timestamp=event.get("timestamp"))
                        continue
                    attempted = True
                    detected = time.time()
                    try:
                        event_time = datetime.datetime.fromisoformat(event["timestamp"]).timestamp()
                    except (KeyError, ValueError):
                        event_time = None
                    record("sample_trigger", pid=pid, event_timestamp=event.get("timestamp"),
                           event_mach_timestamp=event.get("machTimestamp"), source_process_id=event.get("processID"),
                           source_process_path=event.get("processImagePath"), detected_epoch=detected, detection_age_seconds=None if event_time is None else detected - event_time)
                    if initial_hosts is None:
                        record("sample_refused", pid=pid, reason="initial selected-simulator identity unavailable")
                        return
                    before = host_identity(pid, "before")
                    if before is None or sample_stop.is_set():
                        record("sample_refused", pid=pid, reason="selected-simulator identity unconfirmed or capture ended")
                        return
                    started = time.time()
                    record("sample_start", pid=pid, event_timestamp=event.get("timestamp"), start_epoch=started,
                           age_seconds=None if event_time is None else started - event_time,
                           timing_assessment="requires offline overlap review; late samples are inconclusive")
                    sample_exit = None
                    interrupted_sample = False
                    try:
                        with (output / "host-sample.stdout").open("wb") as stdout, (output / "host-sample.stderr").open("wb") as stderr:
                            sample = subprocess.Popen(["/usr/bin/sample", str(pid), "1", "-file", str(output / "host-sample.txt")],
                                                      stdout=stdout, stderr=stderr)
                            deadline = time.monotonic() + 3
                            while sample.poll() is None and time.monotonic() < deadline and not sample_stop.wait(.05):
                                pass
                            interrupted_sample = sample.poll() is None
                            if interrupted_sample:
                                sample.terminate()
                                try:
                                    sample.wait(timeout=1)
                                except subprocess.TimeoutExpired:
                                    sample.kill()
                                    sample.wait()
                            sample_exit = sample.returncode
                            record("sample_end", pid=pid, owned_sample_pid=sample.pid, exit_code=sample_exit,
                                   interrupted=interrupted_sample)
                    except OSError as error:
                        record("sample_unavailable", pid=pid, error=str(error))
                        record("sample_end", pid=pid, owned_sample_pid=None, exit_code=None, error=str(error))
                    after = host_identity(pid, "after")
                    record("sample_disposition", pid=pid, same_lifetime=before == after,
                           attachment_valid=not interrupted_sample and sample_exit == 0 and before == after,
                           conclusion="inconclusive until timing overlap and a matching sampled control are assessed")
                    return  # One new-host attempt per wrapper, including refusal or attachment failure.
                sample_stop.wait(.05)
    except (OSError, ValueError, TypeError) as error:
        record("sample_observer_unavailable", error=str(error))
    finally:
        record("sample_observer_end", attempted=attempted, stop_requested=sample_stop.is_set())


stream = None
child = None
sample_stop = threading.Event()
sample_observer = None


def interrupted(signum, _frame):
    record("interrupted", signal=signum)
    if child is not None and child.poll() is None:
        child.terminate()
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
record("capture_start", limits="35 minutes or 64 MiB; filtered, dropped, or missing events do not establish absence")
initial_hosts = snapshot("start")
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
        sample_observer = threading.Thread(target=observe_new_host, args=(initial_hosts,))
        sample_observer.start()
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
    sample_stop.set()
    if sample_observer is not None:
        sample_observer.join()
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
