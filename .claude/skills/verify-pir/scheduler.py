from dataclasses import dataclass
from datetime import datetime, timezone
import math
from pathlib import Path
import subprocess
import time
from urllib.parse import quote

import runtime


@dataclass(frozen=True)
class Job:
    broker_url: str
    query_id: int


@dataclass(frozen=True)
class Scope:
    platform: str
    port: int
    since: datetime
    jobs: tuple[Job, ...]
    timeout: float
    managed: bool = False


@dataclass(frozen=True)
class SeedRequest:
    mode: str
    profile_path: Path
    timeout: float
    port: int = 8474


def _date(value):
    if not isinstance(value, str):
        raise ValueError("scheduler dates must be timezone-qualified ISO8601 strings")
    parsed = datetime.fromisoformat(value[:-1] + "+00:00" if value.endswith("Z") else value)
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("scheduler dates require a timezone")
    return parsed.astimezone(timezone.utc)


def _timeout(value):
    timeout = 600 if value is None else value
    if (isinstance(timeout, bool) or not isinstance(timeout, (int, float))
            or not math.isfinite(timeout) or not 0 < timeout <= 3600):
        raise ValueError("scheduler timeout must be positive and no more than 3600 seconds")
    return float(timeout)


def _jobs(pairs):
    jobs = []
    for pair in pairs:
        if not isinstance(pair, (list, tuple)) or len(pair) != 2:
            raise ValueError("each scheduler job requires a broker URL and query ID")
        broker, raw_id = pair
        if (not isinstance(broker, str) or not broker or broker.strip() != broker
                or any(character.isspace() or ord(character) < 32 for character in broker)):
            raise ValueError("each scheduler job requires an exact nonempty broker URL")
        if isinstance(raw_id, bool) or not str(raw_id).isdecimal() or not 0 < int(raw_id) <= 2**63 - 1:
            raise ValueError("scheduler query IDs must be positive Int64 values")
        job = Job(broker, int(raw_id))
        if job in jobs:
            raise ValueError("scheduler jobs must be unique")
        jobs.append(job)
    if not jobs:
        raise ValueError("scheduler observation requires at least one exact job")
    return tuple(jobs)


def parse_scope(args):
    port = 8474 if args.scheduler_port is None else args.scheduler_port
    if type(port) is not int or not 1 <= port <= 65535:
        raise ValueError("scheduler port must be between 1 and 65535")
    return Scope(args.platform, port, _date(args.scheduler_since),
                 _jobs(args.scheduler_jobs or []), _timeout(args.scheduler_timeout))


def parse_seed(args):
    if any(value is not None for value in (args.scheduler_port, args.scheduler_since, args.scheduler_jobs)):
        raise ValueError("seed and reseed discover the agent, cutoff and jobs automatically")
    if args.scheduler_profile is None:
        raise ValueError("seed and reseed require --profile-file")
    return SeedRequest(args.scheduler_mode, args.scheduler_profile.expanduser().resolve(), _timeout(args.scheduler_timeout))


def receipt_scope(receipt, request, instance):
    if not isinstance(receipt, dict) or receipt.get("instanceID") != instance or receipt.get("mode") != request.mode:
        raise RuntimeError("The scheduler launch receipt does not match this attempt")
    if receipt.get("status") != "ready":
        error = receipt.get("errorCode")
        if error == "profileAlreadyExists":
            raise RuntimeError("The DEBUG PIR store already has a profile. Use observe or explicitly choose reseed.")
        if error == "authenticatedAccount":
            raise RuntimeError("Scheduler seeding requires a signed-out DEBUG account for Freemium scans")
        raise RuntimeError("The DEBUG browser did not complete scheduler setup; see scheduler-launch.json")
    jobs = _jobs((job.get("brokerURL"), job.get("profileQueryId")) for job in _rows(receipt, "jobs"))
    return Scope("macos", request.port, _date(receipt.get("since")), jobs, request.timeout, managed=True)


def _remaining(deadline):
    seconds = deadline - time.monotonic()
    if seconds <= 0:
        raise RuntimeError("expected scheduler scans did not complete before timeout")
    return seconds


def _identity(platform, port, deadline):
    try:
        result = subprocess.run(["/usr/sbin/lsof", "-nP", "-a", f"-iTCP@127.0.0.1:{port}",
                                 "-sTCP:LISTEN", "-t"], capture_output=True, text=True, timeout=min(5, _remaining(deadline)))
        pids = set(result.stdout.split())
        if result.returncode != 0 or len(pids) != 1 or not next(iter(pids)).isdecimal():
            raise RuntimeError("scheduler port does not identify one listening process")
        identity = runtime._process(int(next(iter(pids))), timeout=min(5, _remaining(deadline)))
        if not identity:
            raise RuntimeError("scheduler listener process is unavailable")
        executable = Path(identity["executable"]).resolve()
        bundle = next(parent for parent in executable.parents if parent.suffix == ".app")
        info = runtime._info(bundle, platform)
        executable_directory = bundle if platform == "ios" else bundle / "Contents/MacOS"
        if (info.get("CFBundleIdentifier") != runtime.BUNDLES[platform]
                or executable != (executable_directory / info["CFBundleExecutable"]).resolve()):
            raise RuntimeError(f"scheduler listener does not match the requested {platform} PIR app")
        if platform == "ios" and info.get("DTPlatformName") != "iphonesimulator":
            raise RuntimeError("iOS scheduler observation requires a direct simulator listener")
        return dict(identity, bundleId=info["CFBundleIdentifier"], bundlePath=str(bundle))
    except (OSError, subprocess.SubprocessError, StopIteration, KeyError, ValueError) as error:
        raise RuntimeError("unable to verify scheduler listener identity") from error


def _rows(value, key):
    rows = value.get(key) if isinstance(value, dict) else None
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise ValueError(f"scheduler API field {key} must be an array of objects")
    return rows


def _job_state(job, snapshot, detail, since, managed):
    state = dict(brokerURL=job.broker_url, profileQueryId=job.query_id, status="pending")
    queries = _rows(snapshot, "profileQueries")
    active = [query for query in queries if type(query.get("id")) is int and query["id"] == job.query_id]
    if len(active) != 1 or active[0].get("deprecated") is not False:
        return dict(state, status="missing", reason="expected profile query is missing or inactive")
    if detail.get("url") != job.broker_url or detail.get("isRemoved") is not False:
        return dict(state, status="missing", reason="exact broker is missing or removed")
    matches = [query for query in _rows(detail, "profileQueries")
               if type(query.get("profileQueryId")) is int and query["profileQueryId"] == job.query_id]
    if len(matches) != 1:
        return dict(state, status="missing", reason="broker has no unique expected query")
    history = _rows(matches[0].get("scan"), "history")
    previous, start, terminals = None, None, []
    for event in history:
        date = _date(event.get("date"))
        if previous is not None and date < previous:
            return dict(state, status="ambiguous", reason="scan history is not chronological")
        previous = date
        if event.get("type") == "scanStarted":
            fresh = date >= since if managed else date > since
            start, terminals = event if fresh else None, []
        elif start is not None and event.get("type") in ("matchesFound", "noMatchFound", "error"):
            terminals.append(event)
    if start is None:
        return dict(state, reason="no persisted scan start after cutoff")
    state["startedAt"] = start["date"]
    if not terminals:
        return dict(state, reason="latest fresh scan has no terminal event")
    if len(terminals) != 1:
        return dict(state, status="ambiguous", reason="latest scan has multiple terminal events")
    terminal = terminals[0]
    return dict(state, status="pass", terminal=terminal["type"], finishedAt=terminal["date"])


def _read(client, path, timeout):
    try:
        value = client.request("GET", path, timeout=timeout)
    except Exception as error:
        raise RuntimeError("scheduler HTTP read failed; see request evidence") from error
    if not isinstance(value, dict):
        raise ValueError("scheduler API response must be an object")
    return value


def observe(context, client, scope, expected_executable=None):
    if not scope.jobs:
        raise ValueError("scheduler observation requires at least one exact job")
    summary = dict(platform=scope.platform, port=scope.port, since=scope.since.isoformat(), timeout=scope.timeout,
                   jobs=[dict(brokerURL=job.broker_url, profileQueryId=job.query_id) for job in scope.jobs], polls=0)
    context.result["scheduler"] = summary
    context.unverified("recurring scheduler", "one observation does not prove future scheduling")
    context.unverified("scheduler opt-outs", "this mode verifies persisted scan completion only")
    if not scope.managed:
        context.unverified("scan trigger", "persisted history does not identify what triggered these scans")
        context.unverified("fixture identity", "the caller supplies the cutoff and expected query IDs")
    deadline = time.monotonic() + scope.timeout
    outcome = dict(status="inconclusive", reason="scheduler observation did not complete")
    try:
        summary["identity"] = _identity(scope.platform, scope.port, deadline)
        if expected_executable and Path(summary["identity"]["executable"]).resolve() != Path(expected_executable).resolve():
            raise RuntimeError("The normal PIR listener is not the agent embedded in this attempt's DEBUG build")
        while True:
            if _identity(scope.platform, scope.port, deadline) != summary["identity"]:
                raise RuntimeError("scheduler listener identity changed during observation")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                outcome = dict(status="inconclusive", reason="expected scheduler scans did not complete before timeout")
                break
            snapshot = _read(client, "/api", min(10, remaining)).get("snapshot", {})
            if not isinstance(snapshot, dict):
                raise ValueError("scheduler snapshot must be an object")
            if snapshot.get("schedulerState") not in ("idle", "running"):
                raise RuntimeError("attached endpoint does not expose the production scheduler")
            details = {}
            for job in scope.jobs:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError("scheduler observation timed out while collecting jobs")
                if job.broker_url not in details:
                    details[job.broker_url] = _read(client, "/api/brokers/" + quote(job.broker_url, safe=""),
                                                    min(10, remaining))
            states = [_job_state(job, snapshot, details[job.broker_url], scope.since, scope.managed) for job in scope.jobs]
            summary.update(observedAt=datetime.now(timezone.utc).isoformat(),
                           schedulerState=snapshot["schedulerState"], jobs=states, polls=summary["polls"] + 1)
            context.write("scheduler.json", summary)
            if _identity(scope.platform, scope.port, deadline) != summary["identity"]:
                raise RuntimeError("scheduler listener identity changed while collecting jobs")
            if time.monotonic() >= deadline:
                outcome = dict(status="inconclusive", reason="scheduler observation timed out before completion")
                break
            if all(state["status"] == "pass" for state in states):
                outcome = dict(status="pass", reason="every expected scheduler job has a fresh persisted scan that reached a terminal event")
                break
            time.sleep(min(2, max(0, deadline - time.monotonic())))
    except (RuntimeError, ValueError) as error:
        outcome = dict(status="inconclusive", reason=str(error))
        raise
    finally:
        summary.update(outcome)
        context.write("scheduler.json", summary)
    return outcome
