from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import math
from pathlib import Path
import subprocess
import time
from urllib.parse import quote

import runtime

BROKER_ERRORS = frozenset({"httpError", "actionFailed"})
# A scan cut off by its job timeout, or by a dropped connection to the broker, says nothing about our code.
# Network errors are recorded by their system description, so they are matched by it.
TRANSIENT_ERRORS = frozenset({"Cancelled", "jobTimeout", "The network connection was lost.", "The request timed out.",
                              "The Internet connection appears to be offline.", "Could not connect to the server.",
                              "A server with the specified hostname could not be found."})
FINISHED = frozenset({"pass", "removed", "fail", "transient"})


class _DeadlineReached(Exception):
    pass


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
    platform: str = "macos"
    port: int = 8474
    brokers: tuple[str, ...] = ()


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


@dataclass(frozen=True)
class UpgradeRequest:
    platform: str
    brokers: tuple[str, ...]
    timeout: float
    simulator: str | None = None
    reset_delivery: bool = False
    port: int = 8474


def _brokers(args):
    brokers = tuple(getattr(args, "scheduler_brokers", None) or ())
    for broker in brokers:
        if (not broker or broker.strip() != broker or any(c.isspace() or ord(c) < 32 for c in broker)
                or "/" in broker or ":" in broker):
            raise ValueError("--broker takes a bare broker URL such as peoplefinders.com")
    if len(set(brokers)) != len(brokers):
        raise ValueError("--broker values must be unique")
    return brokers


def parse_upgrade(args):
    if any(value is not None for value in (args.scheduler_port, args.scheduler_since, args.scheduler_jobs, args.scheduler_profile)):
        raise ValueError("upgrade launches the existing DEBUG store; it takes no profile, port, cutoff or jobs")
    brokers = _brokers(args)
    if not brokers:
        raise ValueError("upgrade requires --broker for each broker to scan after the refresh")
    simulator = getattr(args, "scheduler_simulator", None)
    if (args.platform == "ios") != (simulator is not None):
        raise ValueError("upgrade takes --simulator on iOS, naming the simulator a seed kept, and only there")
    return UpgradeRequest(args.platform, brokers, _timeout(args.scheduler_timeout), simulator,
                          bool(getattr(args, "scheduler_reset_delivery", False)))


def _maintenance(client, path, body, deadline):
    started = client.request("POST", path, body)
    operation = started.get("id")
    if not isinstance(operation, str):
        raise RuntimeError(f"{path} did not start a maintenance operation")
    while time.monotonic() < deadline:
        state = client.request("GET", f"/api/debug/maintenance/{operation}")
        if state.get("status") == "succeeded":
            return state.get("result")
        if state.get("status") == "failed":
            raise RuntimeError(f"{path} failed in the app: {state.get('error')}")
        time.sleep(.5)
    raise RuntimeError(f"{path} did not finish before the timeout")


def listener_on(port):
    """Whether anything already listens on this loopback port."""
    result = subprocess.run(["/usr/sbin/lsof", "-nP", "-a", f"-iTCP@127.0.0.1:{port}", "-sTCP:LISTEN", "-t"],
                            capture_output=True, text=True, timeout=5)
    return bool(result.stdout.split())


def upgrade(context, client, request, expected_executable):
    """Refreshes broker JSON on a store an earlier build seeded, then scans the requested brokers now and observes them."""
    deadline = time.monotonic() + request.timeout
    while True:
        try:
            identity = _identity(request.platform, request.port, deadline)
            client.request("GET", "/api", timeout=5)
            break
        except (RuntimeError, OSError, ValueError) as error:
            if time.monotonic() >= deadline:
                raise RuntimeError("the upgraded build's debug server did not answer before the timeout") from error
            time.sleep(1)
    if Path(identity["executable"]).resolve() != Path(expected_executable).resolve():
        raise RuntimeError("The debug server is not the PIR app from this attempt's DEBUG build")
    client.owned = True
    brokers = _maintenance(client, "/api/debug/broker-json/refresh", dict(resetDelivery=request.reset_delivery), deadline)
    context.write("upgrade-refresh.json", brokers)
    since = datetime.now(timezone.utc).replace(microsecond=0) - timedelta(seconds=1)
    scans = _maintenance(client, "/api/debug/scans/immediate", dict(brokers=list(request.brokers)), deadline)
    context.write("upgrade-scans.json", scans)
    context.result["upgrade"] = dict(brokers=brokers, queued=scans.get("queued", []), notQueued=scans.get("notQueued", []))
    queued = scans.get("queued") or []
    if not queued:
        return dict(status="inconclusive", reason="no requested broker was queued: " + ", ".join(scans.get("notQueued", [])))
    scope = Scope(request.platform, request.port, since, _jobs((job.get("brokerURL"), job.get("profileQueryId")) for job in queued),
                  max(1, deadline - time.monotonic()), managed=True)
    outcome = observe(context, client, scope, expected_executable)
    if scans.get("notQueued"):
        outcome = dict(outcome, reason=f"{outcome.get('reason', '')}; not queued: {', '.join(scans['notQueued'])}")
    return outcome


def parse_seed(args):
    if any(value is not None for value in (args.scheduler_port, args.scheduler_since, args.scheduler_jobs)):
        raise ValueError("seed and reseed discover the agent, cutoff and jobs automatically")
    if args.scheduler_profile is None:
        raise ValueError("seed and reseed require --profile-file")
    brokers = _brokers(args)
    return SeedRequest(args.scheduler_mode, args.scheduler_profile.expanduser().resolve(), _timeout(args.scheduler_timeout),
                       args.platform, brokers=brokers)


def receipt_scope(receipt, request, instance):
    if not isinstance(receipt, dict) or receipt.get("instanceID") != instance or receipt.get("mode") != request.mode:
        raise RuntimeError("The scheduler launch receipt does not match this attempt")
    if receipt.get("status") != "ready":
        error = receipt.get("errorCode")
        if error == "profileAlreadyExists":
            raise RuntimeError("The DEBUG PIR store already has a profile. Use observe or explicitly choose reseed.")
        if error == "unknownBroker":
            reasons = ", ".join(f"{url} ({reason})" for url, reason in sorted((receipt.get("missingBrokers") or {}).items()))
            raise RuntimeError("A --broker value has no eligible Freemium scan in this build" + (f": {reasons}" if reasons else ""))
        if error == "authenticatedAccount":
            raise RuntimeError("Scheduler seeding found the DEBUG account still signed in")
        raise RuntimeError("The DEBUG app did not complete scheduler setup; see scheduler-launch.json")
    jobs = _jobs((job.get("brokerURL"), job.get("profileQueryId")) for job in _rows(receipt, "jobs"))
    return Scope(request.platform, request.port, _date(receipt.get("since")), jobs, request.timeout, managed=True)


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
    if detail.get("url") != job.broker_url:
        return dict(state, status="missing", reason="exact broker is missing")
    if detail.get("isRemoved") is True:
        return dict(state, status="removed", reason="broker removed by a broker update; removed brokers are not scanned")
    if detail.get("isRemoved") is not False:
        return dict(state, status="missing", reason="broker removal state is missing")
    matches = [query for query in _rows(detail, "profileQueries")
               if type(query.get("profileQueryId")) is int and query["profileQueryId"] == job.query_id]
    if len(matches) != 1:
        return dict(state, status="missing", reason="broker has no unique expected query")
    history = _rows(matches[0].get("scan"), "history")
    previous, start, starts, terminals = None, None, 0, []
    for event in history:
        date = _date(event.get("date"))
        if previous is not None and date < previous:
            return dict(state, status="ambiguous", reason="scan history is not chronological")
        previous = date
        if event.get("type") == "scanStarted":
            if date >= since if managed else date > since:
                start, starts = event, starts + 1
            else:
                start, starts, terminals = None, 0, []
        elif start is not None and event.get("type") in ("matchesFound", "noMatchFound", "error"):
            terminals.append(event)
    if start is None:
        return dict(state, reason="no persisted scan start after cutoff")
    state["startedAt"] = start["date"]
    if len(terminals) < starts:
        return dict(state, reason="latest fresh scan has no terminal event")
    if len(terminals) > starts:
        return dict(state, status="ambiguous", reason="fresh scans have more terminal events than starts")
    terminal = terminals[-1]
    state.update(terminal=terminal["type"], finishedAt=terminal["date"])
    if terminal["type"] != "error":
        return dict(state, status="pass")
    name = (terminal.get("error") or {}).get("name")
    if name in BROKER_ERRORS:
        return dict(state, status="pass", brokerError=name)
    if name in TRANSIENT_ERRORS:
        return dict(state, status="transient", reason=f"scan ended in a transient error: {name}")
    return dict(state, status="fail", reason=f"scan ended in a non-broker error: {name}")


def _read(client, path, timeout, deadline):
    try:
        value = client.request("GET", path, timeout=timeout)
    except Exception as error:
        if time.monotonic() >= deadline:
            raise _DeadlineReached from error
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
            raise RuntimeError("The scheduler listener is not the PIR app from this attempt's DEBUG build")
        while True:
            if _identity(scope.platform, scope.port, deadline) != summary["identity"]:
                raise RuntimeError("scheduler listener identity changed during observation")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                outcome = dict(status="fail", reason="expected scheduler scans did not complete before timeout")
                break
            snapshot = _read(client, "/api", min(10, remaining), deadline).get("snapshot", {})
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
                                                    min(10, remaining), deadline)
            states = [_job_state(job, snapshot, details[job.broker_url], scope.since, scope.managed) for job in scope.jobs]
            summary.update(observedAt=datetime.now(timezone.utc).isoformat(),
                           schedulerState=snapshot["schedulerState"], jobs=states, polls=summary["polls"] + 1)
            context.write("scheduler.json", summary)
            if _identity(scope.platform, scope.port, deadline) != summary["identity"]:
                raise RuntimeError("scheduler listener identity changed while collecting jobs")
            if time.monotonic() >= deadline:
                outcome = dict(status="fail", reason="scheduler observation timed out before completion")
                break
            if not all(state["status"] in FINISHED for state in states):
                time.sleep(min(2, max(0, deadline - time.monotonic())))
                continue
            failed = [state["brokerURL"] for state in states if state["status"] == "fail"]
            transient = [state["brokerURL"] for state in states if state["status"] == "transient"]
            if failed:
                outcome = dict(status="fail", reason="fresh scheduler scans ended in a non-broker error: " + ", ".join(failed))
                break
            if transient:
                outcome = dict(status="inconclusive",
                               reason="fresh scheduler scans ended in a transient error; rerun them: " + ", ".join(transient))
                break
            if all(state["status"] == "removed" for state in states):
                outcome = dict(status="inconclusive", reason="every expected broker was removed before it was scanned")
                break
            if all(state["status"] in ("pass", "removed") for state in states):
                reason = "every expected scheduler job has a fresh persisted scan that reached a terminal event"
                if any(state["status"] == "removed" for state in states):
                    reason += ", except brokers removed during the run"
                outcome = dict(status="pass", reason=reason)
                break
    except _DeadlineReached:
        outcome = dict(status="fail", reason="expected scheduler scans did not complete before timeout")
    except (RuntimeError, ValueError) as error:
        outcome = dict(status="inconclusive", reason=str(error))
        raise
    finally:
        summary.update(outcome)
        context.write("scheduler.json", summary)
    return outcome
