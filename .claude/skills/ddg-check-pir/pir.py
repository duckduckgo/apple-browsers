#!/usr/bin/env python3
"""Check live PIR broker flows or observe persisted scheduler scans."""
import argparse
import dataclasses
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

NATIVE_LOG_LIMIT = 5000  # The debug server's maximum for /api/logs.


class Failed(Exception):
    """The broker flow or an assertion failed."""


class BrokerOutcome(Exception):
    pass


class SetupFailed(Exception):
    """The requested flow could not be verified."""


def sha256(raw):
    return hashlib.sha256(raw).hexdigest()


def validate_profile(profile):
    if not isinstance(profile, dict) or not all(k in profile for k in ("names", "addresses", "birthYear")):
        raise ValueError("profileFile needs names, addresses, and birthYear")
    if (not isinstance(profile["names"], list) or not profile["names"]
            or not isinstance(profile["addresses"], list) or not profile["addresses"]
            or type(profile["birthYear"]) is not int
            or not 1900 <= profile["birthYear"] <= time.localtime().tm_year):
        raise ValueError("profileFile needs a name, address and valid birthYear")
    for field, required, optional in (("names", ("firstName", "lastName"), ("middleName", "suffix")),
                                      ("addresses", ("city", "state"), ("street", "zipCode"))):
        for entry in profile[field]:
            if (not isinstance(entry, dict) or any(not isinstance(entry.get(key), str) or not entry[key] for key in required)
                    or any(entry.get(key) is not None and not isinstance(entry[key], str) for key in optional)):
                raise ValueError(f"profileFile {field} must match the native profile fields")
    if profile.get("phones", []) != []:
        raise ValueError("profileFile phones are unsupported; leave them out")
    # The native profile decoder requires the key, though PIR never searches by phone.
    return {**profile, "phones": []}


def load_inputs(path, needs_auth=False):
    path = Path(path).expanduser().resolve()
    raw_config = path.read_bytes()
    config = json.loads(raw_config)
    allowed = {"brokerFile", "profileFile", "expectedFile", "optOut", "emailConfirmation",
               "subscriptionEnvironment", "pirEnvironment", "pirEndpoint", "activityTimeout", "emailTimeout"}
    if not isinstance(config, dict) or set(config) - allowed:
        raise ValueError("configuration must be an object containing only documented fields; keep credentials separate")
    raw = {}
    references = {"configuration": dict(reference=str(path), sha256=sha256(raw_config))}
    for field in ("brokerFile", "profileFile", "expectedFile"):
        if field not in config:
            if field == "expectedFile":
                continue
            raise ValueError(f"configuration requires {field}")
        if not isinstance(config[field], str) or not config[field]:
            raise ValueError(f"{field} must be a file path")
        source = (path.parent / config[field]).resolve()
        raw[field] = source.read_bytes()
        references[field] = dict(reference=str(source), sha256=sha256(raw[field]))
    broker, profile = json.loads(raw["brokerFile"]), json.loads(raw["profileFile"])
    expected = json.loads(raw["expectedFile"]) if "expectedFile" in raw else {}
    if not isinstance(broker, dict) or not all(broker.get(k) for k in ("name", "url", "version", "steps")):
        raise ValueError("brokerFile needs complete broker JSON including name, url, version, and steps")
    profile = validate_profile(profile)
    if not isinstance(expected, dict) or set(expected) - {"profileUrl"} or not isinstance(expected.get("profileUrl", ""), str):
        raise ValueError("expectedFile may only name the profileUrl of one scan result")
    if not isinstance(config.get("optOut"), bool):
        raise ValueError("optOut must explicitly be true or false")
    if config["optOut"] and not isinstance(config.get("emailConfirmation"), bool):
        raise ValueError("emailConfirmation must explicitly be true or false")
    if config["optOut"] or needs_auth or "pirEndpoint" in config:
        if not isinstance(config.get("pirEndpoint", ""), str):
            raise ValueError("pirEndpoint must be a URL string")
        try:
            endpoint = urllib.parse.urlsplit(config.get("pirEndpoint", ""))
        except ValueError:
            raise ValueError("pirEndpoint must be a valid URL") from None
        if (endpoint.scheme not in ("http", "https") or not endpoint.hostname or endpoint.username
                or endpoint.password or endpoint.query or endpoint.fragment):
            raise ValueError("pirEndpoint must name the expected credential-free PIR backend URL")
    for key in ("subscriptionEnvironment", "pirEnvironment"):
        if (config["optOut"] or needs_auth or key in config) and config.get(key) not in ("production", "staging"):
            raise ValueError(f"{key} must explicitly be production or staging")
    for key, default, maximum in (("activityTimeout", 600, 3600), ("emailTimeout", 300, 1800)):
        value = config.setdefault(key, default)
        if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or not 0 < value <= maximum:
            raise ValueError(f"{key} must be positive and no more than {maximum} seconds")
    return dict(config=config, broker=broker, profile=profile, expected=expected,
                brokerBytes=raw["brokerFile"], references=references,
                inputBytes=[raw_config, *raw.values()])


class Redactor:
    def __init__(self, token=None):
        self.forms = sorted({token, json.dumps(token, ensure_ascii=True)[1:-1],
                             json.dumps(token, ensure_ascii=False)[1:-1]} - {None, ""}, key=len, reverse=True) if token else []

    def text(self, text):
        for form in self.forms:
            text = text.replace(form, "[REDACTED]")
        return text

    def value(self, value):
        if isinstance(value, str):
            return self.text(value)
        if isinstance(value, dict):
            return {self.text(key): self.value(item) for key, item in value.items()}
        if isinstance(value, list):
            return [self.value(item) for item in value]
        return value


class Context:
    def __init__(self, evidence, redactor=None):
        self.evidence = Path(evidence)
        self.redactor = redactor or Redactor()
        self.result = dict(status="inconclusive", checks=[], unverified=[], cleanup={}, evidenceErrors=[])

    def write(self, name, value):
        (self.evidence / name).write_text(json.dumps(self.redactor.value(value), indent=2) + "\n")

    def check(self, description, condition):
        self.result["checks"].append(dict(check=description, passed=bool(condition)))
        if not condition:
            raise Failed(description)

    def unverified(self, what, reason):
        self.result["unverified"].append(dict(what=what, reason=reason))


class Client:
    def __init__(self, evidence, port, instance, redactor=None):
        self.evidence, self.port, self.instance = Path(evidence), port, instance
        self.redactor = redactor or Redactor()
        self.number, self.owned = 0, False
        self.last_get, self.reported = {}, set()
        self.last_run = None
        self.last_status = None
        self.collect_snapshots = None
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def request(self, method, path, body=None, timeout=10):
        # A seed or upgrade owns an instance-less listener once it has checked the listener's executable.
        if method != "GET" and not self.owned:
            raise SetupFailed("PIR endpoint ownership has not been verified")
        headers = {"Content-Type": "application/json"}
        if self.instance is not None:
            headers["X-PIR-Debug-Instance"] = self.instance
        request = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", method=method,
                                         headers=headers,
                                         data=json.dumps(body).encode() if body is not None else None)
        try:
            with self.opener.open(request, timeout=timeout) as response:
                status, raw = response.status, response.read().decode(errors="replace")
        except urllib.error.HTTPError as error:
            with error:
                status, raw = error.code, error.read().decode(errors="replace")
        except OSError as error:
            if method != "GET":
                raise Failed("PIR mutation response was lost; outcome is ambiguous and was not retried") from error
            raise
        try:
            result = json.loads(raw)
        except ValueError:
            result = {"text": raw}
        self.last_status = status
        safe_result = self.redactor.value(result)
        if method != "GET" or self.last_get.get(path) != (status, safe_result):
            self.number += 1
            record = dict(method=method, path=path, status=status, response=safe_result)
            (self.evidence / f"pir-http-{self.number:04d}.json").write_text(json.dumps(record, indent=2) + "\n")
        if method == "GET":
            self.last_get[path] = (status, safe_result)
        if status not in (200, 202):
            raise Failed(f"PIR HTTP {status}; see pir-http-{self.number:04d}.json")
        if method == "GET" and urllib.parse.urlsplit(path).path == "/api/logs":
            if not isinstance(result, list):
                raise Failed("PIR logs response is not a JSON array")
        elif not isinstance(result, dict):
            raise Failed("PIR response is not a JSON object")
        if path.startswith("/api/debug/runs/") or path == "/api/debug/scans":
            self.last_run = safe_result
        return result

    def prerequisite(self, timeout=35):
        check_id = str(uuid.uuid4())
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                result = self.request("GET", f"/api/debug/prerequisites?checkID={check_id}",
                                      timeout=min(5, max(.01, deadline - time.monotonic())))
            except OSError:
                time.sleep(min(.25, max(0, deadline - time.monotonic())))
                continue
            if result.get("instanceID") != self.instance or result.get("checkID") != check_id:
                raise SetupFailed("PIR endpoint belongs to another launch or returned an uncorrelated prerequisite")
            self.owned = True
            if result.get("result", {}).get("status") != "pending":
                if not result.get("checkedAt") or result.get("debugRunnerReady") is not True:
                    raise SetupFailed("PIR debug runner is not ready")
                return result
            time.sleep(min(.25, max(0, deadline - time.monotonic())))
        raise SetupFailed("PIR prerequisite did not complete within its deadline")

    def idle(self, run_id, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            run = self.request("GET", f"/api/debug/runs/{run_id}", timeout=min(10, max(.01, deadline - time.monotonic())))
            if run.get("id") != run_id:
                raise Failed("PIR returned a different run")
            if self.collect_snapshots:
                self.collect_snapshots()
            for event in run.get("events", []):
                key = (event.get("timestamp"), event.get("summary"), event.get("profileQuery"))
                if event.get("kind") == "History" and key not in self.reported:
                    self.reported.add(key)
                    print(self.redactor.text(f"PIR {event.get('timestamp')}: {event.get('summary')}"), flush=True)
            assert_clean(run)
            if self.last_status == 200 and not run.get("activity"):
                return run
            time.sleep(min(.5, max(0, deadline - time.monotonic())))
        raise Failed("PIR activity timed out; cleanup must stop the owned runtime")
def assert_clean(run):
    from scheduler import BROKER_ERRORS
    summaries = [event.get("summary", "") for event in run.get("events", [])]
    if "Email confirmation check failed" in summaries:
        raise Failed("PIR run contains an error event; see raw responses")
    errors = [summary for summary in summaries if summary.startswith("Error:")]
    if any(summary.removeprefix("Error: ").split(" - ", 1)[0] not in BROKER_ERRORS for summary in errors):
        raise Failed("PIR run contains an error event; see raw responses")
    if errors:
        raise BrokerOutcome(errors[0])
    if run.get("scanErrors") or any(r.get("optOutError") or r.get("optOutStatus") == "failed" for r in run.get("results", [])):
        raise Failed("PIR run contains scan or opt-out errors; see raw responses")


def selected(run, profile_url=None, result_id=None):
    results = run.get("results", [])
    if result_id is not None:
        matches = [r for r in results if r.get("id") == result_id]
    elif profile_url:
        matches = [r for r in results if r.get("profileUrl") == profile_url]
    else:
        matches = results
    if len(matches) != 1:
        hint = "; set profileUrl in expectedFile to choose one" if result_id is None and not profile_url else ""
        raise Failed(f"expected exactly one record to opt out, found {len(matches)}{hint}")
    result = matches[0]
    if not result.get("id") or sum(r.get("id") == result["id"] for r in results) != 1:
        raise Failed("selected result ID is ambiguous across the run; refusing opt-out")
    return result


def history(run, summary, query=None):
    return any(e.get("kind") == "History" and e.get("summary") == summary
               and (query is None or e.get("profileQuery") == query) for e in run.get("events", []))



def verify_auth(snapshot, config, *, provided):
    result = snapshot.get("result", {})
    backend, status, entitled = (("provided-token", "credentialProvided", None) if provided
                                 else ("subscription-auth-v2", "ready", True))
    valid = (result.get("authenticated") is True
             and result.get("backend") == backend
             and result.get("status") == status
             and result.get("entitled") is entitled
             and result.get("environment") == config["subscriptionEnvironment"]
             and result.get("pirEnvironment") == config["pirEnvironment"]
             and result.get("pirEndpoint") == config["pirEndpoint"])
    if valid:
        return
    if provided:
        raise SetupFailed("authentication diagnostics or configured backend do not match; see pir-prerequisites.json")
    raise SetupFailed("saved subscription is not ready for the configured PIR backend; "
                      "supply --token-file or --token-env; see pir-prerequisites.json")


def workflow(context, inputs, client, token):
    config, broker, profile, expected = (inputs[k] for k in ("config", "broker", "profile", "expected"))
    snapshot = client.prerequisite()
    context.write("pir-prerequisites.json", {"before": snapshot})
    if token:
        verify_auth(snapshot, config, provided=True)
        context.check("launch credential supplied for configured backend", True)
        context.unverified("subscription entitlement", "credentialProvided confirms injection; backend acceptance is exercised by broker work")
    elif config["optOut"]:
        verify_auth(snapshot, config, provided=False)
        context.check("saved subscription has PIR entitlement for the configured backend", True)
    context.unverified("PIR UI and production scheduler", "debug jobs run directly through the PIR debug server")
    context.unverified("PIR worker and backend traffic", "this workflow records debug-server responses and application logs, without network interception")
    started = client.request("POST", "/api/debug/scans", dict(broker=broker, profile=profile, hidesWebView=True))
    run_id = started.get("id")
    if not isinstance(run_id, str) or not re.fullmatch(r"[A-Za-z0-9-]+", run_id):
        raise Failed("scan did not return a valid run ID")
    context.result["runID"] = run_id
    scan = client.idle(run_id, config["activityTimeout"])
    context.check("scan emitted Scan Started", history(scan, "Scan Started"))
    if not scan.get("results"):
        context.check("empty scan emitted No Match", history(scan, "No Match"))
        context.unverified("PIR opt-out and email flow", "the app matched no records; no opt-out was submitted")
        raise SetupFailed("no match: broker flow remains inconclusive")
    if not config["optOut"]:
        context.check(f"scan found {len(scan['results'])} record(s) the app matched to the profile", True)
        if expected.get("profileUrl"):
            context.check("scan found the expected profileUrl", any(r.get("profileUrl") == expected["profileUrl"] for r in scan["results"]))
        context.unverified("PIR opt-out", "scan-only run, optOut is false")
        return
    result = selected(scan, expected.get("profileUrl"))
    result_id = result["id"]
    if not isinstance(result_id, str) or not re.fullmatch(r"[A-Za-z0-9-]+", result_id):
        raise Failed("invalid result ID")
    context.check("scan selected one record to opt out", True)
    path = f"/api/debug/runs/{run_id}"
    client.request("POST", f"{path}/optouts/{result_id}")
    opted = client.idle(run_id, config["activityTimeout"])
    result = selected(opted, result_id=result_id)
    if result.get("optOutStatus") == "optsOutInParent":
        context.check("app skipped the opt-out because the broker opts out in its parent",
                      not history(opted, "Opt-out Started", result.get("profileQuery")))
        context.unverified("PIR opt-out", f"{broker['name']} opts out in its parent {broker.get('parent') or 'site'}; "
                           "run the opt-out against the parent broker")
        context.result["reason"] = "Scan completed; the app skipped the opt-out because the broker opts out in its parent."
        return
    context.check("selected record emitted Opt-out Started", history(opted, "Opt-out Started", result.get("profileQuery")))
    if config["emailConfirmation"]:
        context.check("selected record awaits email confirmation", result.get("optOutStatus") == "awaitingEmailConfirmation")
        deadline = time.monotonic() + config["emailTimeout"]
        while not result.get("hasEmailConfirmationLink"):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise Failed("email confirmation link not available within deadline")
            client.request("POST", f"{path}/email-confirmation/check", timeout=min(10, remaining))
            remaining = deadline - time.monotonic()
            opted = client.idle(run_id, min(config["activityTimeout"], max(0, remaining)))
            result = selected(opted, result_id=result_id)
            if not result.get("hasEmailConfirmationLink"):
                time.sleep(min(2, max(0, deadline - time.monotonic())))
        context.check("selected record has an email confirmation link", result["hasEmailConfirmationLink"])
        client.request("POST", f"{path}/optouts/{result_id}/continue")
        opted = client.idle(run_id, config["activityTimeout"])
        result = selected(opted, result_id=result_id)
    context.check("selected record opt-out flow confirmed", result.get("optOutStatus") == "confirmed")
    context.check("selected record emitted Opt-out Confirmed", history(opted, "Opt-out Confirmed", result.get("profileQuery")))
    context.unverified("broker removal", "confirmed proves submission and confirmation; removal needs a later scan")


def selftest(context, client):
    snapshot = client.prerequisite()
    context.write("pir-prerequisites.json", snapshot)
    verify_auth(snapshot, dict(subscriptionEnvironment="staging", pirEnvironment="staging",
                               pirEndpoint="https://dbp-staging.duckduckgo.com"), provided=True)
    context.check("native runner reports the launch credential and staging endpoint", True)
    context.result["brokerRequests"] = 0
    context.unverified("PIR broker execution and subscription entitlement",
                       "selftest uses a dummy launch credential and only reads local debug endpoints")


def load_launch_profile(value):
    """Returns the user's launch profile and a reference to record, after checking it merges with the base profile."""
    from runtime import ios_launch_profile
    if value.strip().startswith("{"):
        profile = json.loads(value)
        source = dict(inline=profile)
    else:
        path = Path(value).expanduser().resolve()
        raw = path.read_bytes()
        profile = json.loads(raw)
        source = dict(reference=str(path), sha256=sha256(raw))
    ios_launch_profile(profile)
    return profile, source


def record_launch(context, launch, launch_profile_source):
    if launch_profile_source:
        launch["launchProfile"] = dict(source=launch_profile_source, **launch.get("launchProfile", {}))
    context.result["launch"] = launch
    context.write("launch.json", launch)


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("command", choices=("build", "run", "selftest", "scheduler"))
    cli.add_argument("scheduler_mode", nargs="?", choices=("observe", "seed", "reseed", "upgrade"),
                     help="attach, seed an empty DEBUG store, or replace the DEBUG profile and history")
    cli.add_argument("--platform", choices=("ios", "macos"), required=True)
    cli.add_argument("--config", type=Path, help="scenario JSON, required for run")
    cli.add_argument("--device", choices=("iphone", "ipad"), default="iphone")
    cli.add_argument("--evidence-dir", type=Path, default=Path.home() / "pir-evidence", help="parent directory outside checkout; each attempt gets a unique child")
    token = cli.add_mutually_exclusive_group()
    token.add_argument("--token-file", type=Path, help="read token from this file; never place credentials in config")
    token.add_argument("--token-env", metavar="NAME", help="read token from this environment variable")
    cli.add_argument("--check-config", action="store_true", help="validate inputs without building or launching")
    cli.add_argument("--keep", action="store_true", help="retain simulator after stopping owned app and agent")
    cli.add_argument("--launch-profile", metavar="JSON_OR_PATH",
                     help="iOS run, selftest, seed, reseed or upgrade: launch profile JSON or .json file merged over the base PIR profile")
    cli.add_argument("--scenario", help="title of the scenario this attempt runs; recorded in result.json")
    cli.add_argument("--expect", choices=("pass", "fail", "inconclusive"),
                     help="verdict the scenario expects; recorded in result.json (default: pass)")
    scheduler = cli.add_argument_group("scheduler")
    scheduler.add_argument("--profile-file", dest="scheduler_profile", type=Path, help="profile JSON for seed or reseed")
    scheduler.add_argument("--port", dest="scheduler_port", type=int, help="observe: local PIR debug server port (default: 8474)")
    scheduler.add_argument("--since", dest="scheduler_since", help="observe: ISO 8601 timestamp before the scan trigger")
    scheduler.add_argument("--job", dest="scheduler_jobs", nargs=2, action="append", metavar=("BROKER_URL", "QUERY_ID"),
                           help="persisted scan to verify, repeat for each broker and profile query pair")
    scheduler.add_argument("--timeout", dest="scheduler_timeout", type=float, help="observation timeout in seconds (default: 600)")
    scheduler.add_argument("--broker", dest="scheduler_brokers", action="append", metavar="BROKER_URL",
                           help="seed or reseed: scan only this eligible broker; upgrade: scan it now; repeat for each")
    scheduler.add_argument("--simulator", dest="scheduler_simulator", metavar="UDID",
                           help="iOS upgrade: the simulator an earlier seed kept with --keep")
    scheduler.add_argument("--reset-delivery", dest="scheduler_reset_delivery", action="store_true",
                           help="upgrade: also clear stored broker delivery data so the remote update re-downloads every broker")
    cli.add_argument("--step", help="with --scenario: this attempt is one step of that scenario, not its whole run")
    return cli


def read_token(args):
    if args.token_file:
        token = args.token_file.expanduser().resolve().read_text().strip()
    elif args.token_env:
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", args.token_env):
            raise ValueError("--token-env requires an environment variable name")
        token = os.environ.get(args.token_env, "").strip()
    else:
        return None
    if not token or len(token.encode("utf-8")) > 65_536 or any(c.isspace() or ord(c) < 32 or 127 <= ord(c) <= 159 for c in token):
        raise ValueError("token source must contain one nonempty credential of at most 65536 bytes without whitespace or control characters")
    return token


def rerun_command(args):
    command = ["python3", str(Path(__file__).resolve()), args.command]
    if args.scheduler_mode:
        command.append(args.scheduler_mode)
    command += ["--platform", args.platform]
    if args.platform == "ios":
        command += ["--device", args.device]
    command += ["--evidence-dir", str(args.evidence_dir.expanduser().resolve())]
    if args.config:
        command += ["--config", str(args.config.expanduser().resolve())]
    if args.token_file:
        command += ["--token-file", str(args.token_file.expanduser().resolve())]
    if args.token_env:
        command += ["--token-env", args.token_env]
    if args.keep:
        command += ["--keep"]
    if args.launch_profile is not None:
        value = args.launch_profile
        command += ["--launch-profile", value if value.strip().startswith("{") else str(Path(value).expanduser().resolve())]
    if args.scenario:
        command += ["--scenario", args.scenario]
    if args.expect:
        command += ["--expect", args.expect]
    if args.step:
        command += ["--step", args.step]
    if args.command == "scheduler":
        if args.scheduler_mode == "observe":
            command += ["--since", args.scheduler_since]
            for broker, query in args.scheduler_jobs:
                command += ["--job", broker, query]
        else:
            if args.scheduler_profile is not None:
                command += ["--profile-file", str(args.scheduler_profile.expanduser().resolve())]
            for broker in args.scheduler_brokers or []:
                command += ["--broker", broker]
            if args.scheduler_simulator:
                command += ["--simulator", args.scheduler_simulator]
            if args.scheduler_reset_delivery:
                command += ["--reset-delivery"]
        if args.scheduler_port is not None:
            command += ["--port", str(args.scheduler_port)]
        if args.scheduler_timeout is not None:
            command += ["--timeout", str(args.scheduler_timeout)]
    return shlex.join(command)


def finish(context, include_manifest=True):
    result = context.result
    result["finishedAt"] = time.time()
    snapshot_files = []
    if "snapshots" in result:
        snapshot_files = sorted(p for p in (context.evidence / "snapshots").glob("*")
                                if p.is_file() and p.suffix in (".png", ".unavailable"))
        result["snapshots"]["captured"] = sum(p.suffix == ".png" for p in snapshot_files)
        result["snapshots"]["unavailable"] = sum(p.suffix == ".unavailable" for p in snapshot_files)
    context.write("result.json", result)
    lines = [f"# PIR {result['status']}", "", f"Platform: {result['platform']}", "",
             result.get("reason", "Requested broker flow completed.")]
    if observed := result.get("scheduler"):
        lines += ["", "## Persisted scans", "", f"Cutoff: {observed['since']}", ""]
        lines += [f"- {job['brokerURL']} / query {job['profileQueryId']}: "
                  f"{job.get('terminal') or job.get('reason') or 'not observed yet'}" for job in observed["jobs"]]
    else:
        lines += ["", "## Checks", ""]
        lines += [f"- {'PASS' if c['passed'] else 'FAIL'}: {c['check']}" for c in result["checks"]] or ["No checks completed."]
    if "snapshots" in result:
        lines += ["", "## Web view snapshots", ""]
        lines += [f"- [{p.name}](snapshots/{p.name})" for p in snapshot_files] or ["No snapshots collected."]
        if error := result["snapshots"].get("collectionError"):
            lines += ["", f"Snapshot collection error: {error}"]
    lines += ["", "## Unverified", ""]
    lines += [f"- {u['what']}: {u['reason']}" for u in result["unverified"]] or ["None recorded."]
    lines += ["", "## Cleanup", "", "```json", json.dumps(result["cleanup"], indent=2), "```"]
    if result["evidenceErrors"]:
        lines += ["", "## Evidence errors", ""] + [f"- {e}" for e in result["evidenceErrors"]]
    lines += ["", "## Rerun", "", "```sh", result["rerun"], "```", ""]
    report = context.redactor.text("\n".join(lines)).encode()
    if include_manifest:
        artifacts = [p for p in context.evidence.iterdir() if p.is_file() and p.name not in ("manifest.json", "report.md")]
        files = {str(p.relative_to(context.evidence)): dict(sha256=sha256(p.read_bytes()), bytes=p.stat().st_size)
                 for p in sorted(artifacts + snapshot_files)}
        files["report.md"] = dict(sha256=sha256(report), bytes=len(report))
        context.write("manifest.json", dict(status=result["status"], files=files))
    (context.evidence / "report.md").write_bytes(report)


def execute(args, runtime_factory=None):
    is_selftest = args.command == "selftest"
    scope, seed = None, None
    if args.scenario is not None and args.command not in ("run", "scheduler"):
        raise ValueError("--scenario applies only to run and scheduler")
    if args.expect is not None and args.scenario is None:
        raise ValueError("--expect applies only with --scenario")
    if args.step is not None and args.scenario is None:
        raise ValueError("--step applies only with --scenario")
    if args.launch_profile is not None:
        if args.platform != "ios":
            raise ValueError("--launch-profile applies only to iOS")
        if args.command == "build" or args.scheduler_mode == "observe":
            raise ValueError("--launch-profile applies only to run, selftest and scheduler seed, reseed or upgrade")
    upgrade = None
    if args.command == "scheduler":
        if args.config or args.token_file or args.token_env or args.check_config:
            raise ValueError("scheduler commands do not accept scenario, credential or check-config options")
        if args.keep and (args.platform != "ios" or args.scheduler_mode not in ("seed", "reseed")):
            raise ValueError("--keep applies only to iOS scheduler seed and reseed")
        import scheduler
        if args.scheduler_mode == "observe":
            if args.scheduler_profile is not None or args.scheduler_brokers:
                raise ValueError("scheduler observe does not take a profile file or brokers")
            scope = scheduler.parse_scope(args)
        elif args.scheduler_mode in ("seed", "reseed"):
            if args.scheduler_simulator is not None or args.scheduler_reset_delivery:
                raise ValueError("--simulator and --reset-delivery apply only to scheduler upgrade")
            seed = scheduler.parse_seed(args)
        elif args.scheduler_mode == "upgrade":
            upgrade = scheduler.parse_upgrade(args)
        else:
            raise ValueError("Choose scheduler observe, seed, reseed or upgrade")
    elif any(option is not None for option in (args.scheduler_mode, args.scheduler_profile, args.scheduler_port,
                                               args.scheduler_since, args.scheduler_jobs, args.scheduler_timeout,
                                               args.scheduler_brokers, args.scheduler_simulator)) or args.scheduler_reset_delivery:
        raise ValueError("scheduler mode and options apply only to the scheduler command")
    if is_selftest and (args.config or args.token_file or args.token_env or args.check_config or args.keep):
        raise ValueError("selftest does not accept scenario, credential, check-config or keep options")
    token = None
    if is_selftest:
        token = "ddg-check-pir-selftest-dummy-credential"
    elif args.command != "scheduler":
        token = read_token(args)
    if args.command == "run" and not args.config:
        raise ValueError("run requires --config")
    if args.command == "build" and (args.token_file or args.token_env):
        raise ValueError("authentication options apply only to run")
    inputs = load_inputs(args.config, needs_auth=bool(token)) if args.config else None
    if token and inputs and inputs["config"]["subscriptionEnvironment"] != inputs["config"]["pirEnvironment"]:
        raise ValueError("provided-token subscriptionEnvironment and pirEnvironment must match")
    redactor = Redactor(token)
    if inputs and token and any(any(form.encode() in raw for form in redactor.forms) for raw in inputs["inputBytes"]):
        raise ValueError("credential occurs in scenario inputs; keep it only in the token source")
    launch_profile, launch_profile_source = (load_launch_profile(args.launch_profile) if args.launch_profile is not None
                                             else (None, None))
    root = Path(__file__).resolve().parents[3]
    parent = args.evidence_dir.expanduser().resolve()
    if parent == root or root in parent.parents:
        raise ValueError("--evidence-dir must be outside this checkout")
    if args.check_config:
        if inputs is None:
            raise ValueError("--check-config requires --config")
        valid = dict(status="valid", inputs=inputs["references"])
        if launch_profile_source:
            valid["launchProfile"] = launch_profile_source
        return valid
    parent.mkdir(parents=True, exist_ok=True)
    evidence = Path(tempfile.mkdtemp(prefix=f"{args.platform}-{args.command}-", dir=parent))
    context = Context(evidence, redactor)
    if scope:
        instance, port = None, scope.port
    elif seed and seed.platform == "macos":
        instance, port = str(uuid.uuid4()), seed.port
    elif upgrade and upgrade.platform == "macos":
        instance, port = str(uuid.uuid4()), upgrade.port
    else:
        instance = str(uuid.uuid4())
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0))
            port = reserved.getsockname()[1]
        if seed:
            seed = dataclasses.replace(seed, port=port)
        if upgrade:
            upgrade = dataclasses.replace(upgrade, port=port)
    context.result.update(platform=args.platform, command=args.command, instanceID=instance, port=port,
                          startedAt=time.time(), rerun=rerun_command(args), evidence=str(evidence))
    if args.scenario:
        context.result.update(scenario=args.scenario, expected=args.expect or "pass")
    if args.step:
        context.result["step"] = args.step
    runtime, client = None, None

    def collect_snapshots():
        try:
            runtime.collect_snapshots()
        except Exception as error:
            context.result["snapshots"]["collectionError"] = f"{type(error).__name__}: {error}"

    try:
        if seed:
            context.result["schedulerMode"] = seed.mode
            if seed.brokers:
                context.result["schedulerBrokers"] = list(seed.brokers)
            context.result["cleanup"] = {"mode": "managed-browser" if seed.platform == "macos" else "managed-simulator"}
            with seed.profile_path.open("rb") as profile_file:
                profile = profile_file.read(65_537)
            if len(profile) > 65_536:
                raise ValueError("scheduler profile JSON must be at most 65536 bytes")
            profile_json = json.dumps(validate_profile(json.loads(profile.decode())))
            context.write("pir-inputs.json", dict(profile=dict(reference=str(seed.profile_path), sha256=sha256(profile))))
            if runtime_factory is None:
                from runtime import Runtime
                runtime_factory = Runtime
            options = {} if seed.platform == "macos" else dict(device=args.device, keep=args.keep, launch_profile=launch_profile)
            runtime = runtime_factory(seed.platform, evidence, instance, port, **options)
            launch = runtime.launch_scheduler(seed.mode, profile_json, seed.brokers)
            record_launch(context, launch, launch_profile_source)
            scope = scheduler.receipt_scope(runtime.scheduler_receipt(), seed, instance)
            client = Client(evidence, port, None, redactor)
            listener = launch["product"] if seed.platform == "macos" else launch["process"]
            context.result.update(scheduler.observe(context, client, scope, expected_executable=listener["executable"]))
        elif upgrade:
            context.result.update(schedulerMode="upgrade", schedulerBrokers=list(upgrade.brokers))
            context.result["cleanup"] = {"mode": "managed-browser" if upgrade.platform == "macos" else "kept-simulator"}
            if runtime_factory is None:
                from runtime import Runtime
                runtime_factory = Runtime
            options = {} if upgrade.platform == "macos" else dict(device=args.device, keep=True, launch_profile=launch_profile)
            if upgrade.platform == "macos" and scheduler.listener_on(port):
                raise SetupFailed(f"A PIR agent from an earlier launch is listening on port {port}. A seed leaves its agent "
                                  f"registered; stop it with `launchctl bootout gui/{os.getuid()}/"
                                  "com.duckduckgo.macos.DBP.backgroundAgent.debug` and rerun the upgrade.")
            runtime = runtime_factory(upgrade.platform, evidence, instance, port, **options)
            launch = runtime.launch_existing(upgrade.simulator)
            record_launch(context, launch, launch_profile_source)
            client = Client(evidence, port, instance if upgrade.platform == "ios" else None, redactor)
            listener = launch["product"] if upgrade.platform == "macos" else launch["process"]
            context.result.update(scheduler.upgrade(context, client, upgrade, listener["executable"]))
        elif scope:
            context.result["schedulerMode"] = "observe"
            context.result["cleanup"] = {"mode": "attached"}
            client = Client(evidence, port, instance, redactor)
            context.result.update(scheduler.observe(context, client, scope))
        else:
            if inputs:
                context.result["inputs"] = inputs["references"]
                opt_out = inputs["config"]["optOut"]
                authentication = "saved-subscription" if opt_out else "none"
                if token:
                    authentication = "provided-token"
                context.write("pir-inputs.json", dict(references=inputs["references"], policy=opt_out,
                                                     authentication=authentication))
                (evidence / "pir-broker.json").write_bytes(inputs["brokerBytes"])
            if runtime_factory is None:
                from runtime import Runtime
                runtime_factory = Runtime
            environment = "staging" if is_selftest else inputs["config"].get("pirEnvironment", "production") if inputs else "production"
            runtime = runtime_factory(args.platform, evidence, instance, port, device=args.device, keep=args.keep,
                                      pir_environment=environment, launch_profile=launch_profile)
            runtime.snapshots_enabled = args.command == "run"
            if runtime.snapshots_enabled:
                context.result["snapshots"] = {"directory": "snapshots"}
                print(f"PIR live web view snapshots: {evidence / 'snapshots'}", flush=True)
            if args.command == "build":
                context.result["build"] = runtime.build()
                context.write("build.json", context.result["build"])
            else:
                record_launch(context, runtime.launch(access_token=token), launch_profile_source)
                client = Client(evidence, port, instance, redactor)
                if is_selftest:
                    selftest(context, client)
                else:
                    client.collect_snapshots = collect_snapshots
                    workflow(context, inputs, client, token)
            context.result["status"] = "pass"
    except KeyboardInterrupt:
        context.result.update(status="inconclusive", reason="scheduler attempt interrupted" if args.command == "scheduler" else
                              "cancelled; submitted broker requests cannot be undone")
    except BrokerOutcome as outcome:
        context.result["checks"].append(dict(check=f"broker ended the job with a terminal error: {outcome}", passed=True))
        context.result.update(status="pass", brokerError=str(outcome),
                              reason=f"The broker ended the job with {outcome}; later steps didn't run.")
    except Failed as error:
        context.result.update(status="fail", reason=str(error))
    except Exception as error:
        context.result.update(status="inconclusive", reason=f"{type(error).__name__}: {error}")
    finally:
        try:
            if args.command == "run" and client and client.last_run is not None:
                try:
                    context.write("pir-final-run.json", client.last_run)
                except (Exception, KeyboardInterrupt) as error:
                    context.result["evidenceErrors"].append(f"final run: {type(error).__name__}: {error}")
            if runtime and args.command in ("run", "selftest", "scheduler"):
                try:
                    if client and (args.command == "scheduler" or client.owned):
                        since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(context.result["startedAt"]))
                        logs = client.request("GET", f"/api/logs?since={urllib.parse.quote(since)}&limit={NATIVE_LOG_LIMIT}")
                        context.write("pir-native-logs.json", logs)
                        if len(logs) >= NATIVE_LOG_LIMIT:
                            context.result["evidenceErrors"].append(
                                f"debug logs: reached the {NATIVE_LOG_LIMIT}-line limit; earlier lines of the attempt are missing")
                        if is_selftest:
                            context.check("native debug logs returned a JSON array", isinstance(logs, list))
                except (Exception, KeyboardInterrupt) as error:
                    context.result["evidenceErrors"].append(f"debug logs: {type(error).__name__}: {error}")
            if args.command == "run" and client and client.collect_snapshots:
                try:
                    collect_snapshots()
                except KeyboardInterrupt:
                    context.result["snapshots"]["collectionError"] = "interrupted"
        finally:
            if runtime:
                try:
                    context.result["cleanup"].update(runtime.stop())
                except (Exception, KeyboardInterrupt) as error:
                    context.result["cleanup"] = dict(status="unverified", error=f"{type(error).__name__}: {error}")
                    context.result["evidenceErrors"].append("owned runtime cleanup failed")
        if context.result["evidenceErrors"] and context.result["status"] == "pass":
            context.result.update(status="inconclusive", reason="evidence collection or owned runtime cleanup failed")
        try:
            finish(context)
        except (Exception, KeyboardInterrupt) as error:
            context.result["evidenceErrors"].append(f"report: {type(error).__name__}: {error}")
            if context.result["status"] == "pass":
                context.result.update(status="inconclusive", reason="report or evidence manifest could not be written")
            try:
                (context.evidence / "manifest.json").unlink(missing_ok=True)
            except (Exception, KeyboardInterrupt):
                pass
            try:
                finish(context, include_manifest=False)
            except (Exception, KeyboardInterrupt):
                pass
    return redactor.value(context.result)


def main(argv=None):
    cli = parser()
    args = cli.parse_args(argv)
    try:
        result = execute(args)
    except (OSError, json.JSONDecodeError) as error:
        print(f"Invalid inputs: {type(error).__name__}: could not read or parse input files", file=sys.stderr)
        return 2
    except ValueError as error:
        print(f"Invalid inputs: {type(error).__name__}: {error}", file=sys.stderr)
        return 2
    print(f"PIR {result['status']}" + (f"\n{result['evidence']}/report.md" if "evidence" in result else ""))
    refresh_batch_report(args, result)
    return {"pass": 0, "valid": 0, "fail": 1, "inconclusive": 2}[result["status"]]


def refresh_batch_report(args, result):
    """A scenario attempt inside a batch's evidence/ folder rewrites that batch's report, so it can be reloaded."""
    if not args.scenario or "evidence" not in result:
        return
    evidence = Path(result["evidence"]).parent
    if evidence.name != "evidence":
        return
    try:
        import report
        print(f"PIR batch report: {report.refresh(evidence.parent)}")
    except Exception as error:  # The attempt's verdict stands even when the report can't be written.
        print(f"PIR batch report not refreshed: {type(error).__name__}: {error}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
