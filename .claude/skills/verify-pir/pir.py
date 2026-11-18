#!/usr/bin/env python3
"""Run one live PIR broker scan and an explicitly configured opt-out."""
import argparse
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


class Failed(Exception):
    """The broker flow or an assertion failed."""


class SetupFailed(Exception):
    """The requested flow could not be verified."""


def sha256(raw):
    return hashlib.sha256(raw).hexdigest()


def load_inputs(path, needs_auth=False):
    path = Path(path).expanduser().resolve()
    raw_config = path.read_bytes()
    config = json.loads(raw_config)
    allowed = {"brokerFile", "profileFile", "expectedFile", "optOut", "emailConfirmation",
               "subscriptionEnvironment", "pirEnvironment", "pirEndpoint", "checkpointTimeout",
               "activityTimeout", "emailTimeout"}
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
    if not isinstance(profile, dict) or not all(k in profile for k in ("names", "addresses", "phones", "birthYear")):
        raise ValueError("profileFile needs names, addresses, phones, and birthYear")
    if (not isinstance(profile["names"], list) or not profile["names"]
            or not isinstance(profile["addresses"], list) or not profile["addresses"]
            or not isinstance(profile["phones"], list) or type(profile["birthYear"]) is not int
            or not 1900 <= profile["birthYear"] <= time.localtime().tm_year):
        raise ValueError("profileFile needs a name, address, phones array and valid birthYear")
    for field, required, optional in (("names", ("firstName", "lastName"), ("middleName", "suffix")),
                                      ("addresses", ("city", "state"), ("street", "zipCode"))):
        for entry in profile[field]:
            if (not isinstance(entry, dict) or any(not isinstance(entry.get(key), str) or not entry[key] for key in required)
                    or any(entry.get(key) is not None and not isinstance(entry[key], str) for key in optional)):
                raise ValueError(f"profileFile {field} must match the native profile fields")
    if any(not isinstance(phone, str) for phone in profile["phones"]):
        raise ValueError("profileFile phones must contain strings")
    if not isinstance(expected, dict) or set(expected) - {"profileUrl"} or not isinstance(expected.get("profileUrl", ""), str):
        raise ValueError("expectedFile may only name the profileUrl of one scan result")
    if not isinstance(config.get("optOut"), bool):
        raise ValueError("optOut must explicitly be true or false")
    if config["optOut"] and not isinstance(config.get("emailConfirmation"), bool):
        raise ValueError("emailConfirmation must explicitly be true or false")
    if config["optOut"] or needs_auth or "pirEndpoint" in config:
        if not isinstance(config.get("pirEndpoint", ""), str):
            raise ValueError("pirEndpoint must be a URL string")
        endpoint = urllib.parse.urlsplit(config.get("pirEndpoint", ""))
        if (endpoint.scheme not in ("http", "https") or not endpoint.hostname or endpoint.username
                or endpoint.password or endpoint.query or endpoint.fragment):
            raise ValueError("pirEndpoint must name the expected credential-free PIR backend URL")
    for key in ("subscriptionEnvironment", "pirEnvironment"):
        if (config["optOut"] or needs_auth or key in config) and config.get(key) not in ("production", "staging"):
            raise ValueError(f"{key} must explicitly be production or staging")
    for key, default, maximum in (("checkpointTimeout", 900, 3600), ("activityTimeout", 600, 3600), ("emailTimeout", 300, 1800)):
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
        self.result = dict(status="inconclusive", checks=[], unverified=[], cleanup={}, evidenceErrors=[], humanSteps=[])

    def write(self, name, value):
        (self.evidence / name).write_text(json.dumps(self.redactor.value(value), indent=2) + "\n")

    def check(self, description, condition):
        self.result["checks"].append(dict(check=description, passed=bool(condition)))
        if not condition:
            raise Failed(description)

    def unverified(self, what, reason):
        self.result["unverified"].append(dict(what=what, reason=reason))


def checkpoint(context, instruction, timeout):
    checkpoint_id = uuid.uuid4().hex
    ack = context.evidence / f"ack-{checkpoint_id}"
    cancel = context.evidence / f"cancel-{checkpoint_id}"
    record = dict(instruction=instruction, id=checkpoint_id, acknowledge=str(ack), cancel=str(cancel),
                  timeout=timeout, status="pending")
    context.result["humanSteps"].append(record)
    context.write("checkpoint.json", record)
    print(f"{instruction}\nAcknowledge: touch {shlex.quote(str(ack))}\nCancel: touch {shlex.quote(str(cancel))}", flush=True)
    deadline = time.monotonic() + timeout
    try:
        while True:
            if cancel.exists():
                record["status"] = "cancelled"
                raise SetupFailed("manual checkpoint cancelled")
            if ack.exists():
                record.update(status="acknowledged", acknowledgedAt=time.time())
                return checkpoint_id
            if time.monotonic() >= deadline:
                record["status"] = "timedOut"
                raise SetupFailed("manual checkpoint timed out")
            time.sleep(.2)
    finally:
        if record["status"] == "pending":
            record["status"] = "interrupted"
        record["finishedAt"] = time.time()
        context.write("checkpoint.json", record)


class Client:
    def __init__(self, evidence, port, instance, redactor=None):
        self.evidence, self.port, self.instance = Path(evidence), port, instance
        self.redactor = redactor or Redactor()
        self.number, self.owned = 0, False
        self.last_get, self.reported = {}, set()
        self.last_run = None
        self.last_status = None
        # Redirects could forward the credential header or auth body to another server.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def request(self, method, path, body=None, timeout=10):
        if method != "GET" and not self.owned:
            raise SetupFailed("PIR endpoint ownership has not been verified")
        request = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", method=method,
                                         headers={"Content-Type": "application/json", "X-PIR-Debug-Instance": self.instance},
                                         data=json.dumps(body).encode() if body is not None else None)
        try:
            with self.opener.open(request, timeout=timeout) as response:
                status, raw = response.status, response.read().decode(errors="replace")
        except urllib.error.HTTPError as error:
            with error:
                status, raw = error.code, error.read().decode(errors="replace")
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as error:
            # In particular, never resend a POST whose response was lost.
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
        if not isinstance(result, dict):
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
            except (urllib.error.URLError, TimeoutError, ConnectionError, OSError):
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
    if run.get("scanErrors") or any(r.get("optOutError") or r.get("optOutStatus") == "failed" for r in run.get("results", [])):
        raise Failed("PIR run contains scan or opt-out errors; see raw responses")
    for event in run.get("events", []):
        summary = event.get("summary", "")
        if summary.startswith("Error:") or summary == "Email confirmation check failed":
            raise Failed("PIR run contains an error event; see raw responses")


def selected(run, profile_url=None, result_id=None):
    """The one result to opt out: by ID once chosen, else by profileUrl, else the only result."""
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



def verify_auth(snapshot, config, provided):
    result = snapshot.get("result", {})
    valid = (result.get("authenticated") is True
             and result.get("environment") == config["subscriptionEnvironment"]
             and result.get("pirEnvironment") == config["pirEnvironment"]
             and result.get("pirEndpoint") == config["pirEndpoint"])
    if provided:
        valid = valid and (result.get("backend") == "provided-token" and result.get("status") == "credentialProvided"
                           and result.get("entitled") is None)
    else:
        valid = valid and result.get("status") == "ready" and result.get("entitled") is True
    if not valid:
        raise SetupFailed("authentication diagnostics or configured backend do not match; see pir-prerequisites.json")


def workflow(context, inputs, client, token=None, interactive=False):
    config, broker, profile, expected = (inputs[k] for k in ("config", "broker", "profile", "expected"))
    snapshots = {"before": client.prerequisite()}
    context.write("pir-prerequisites.json", snapshots)
    if token:
        client.request("POST", "/api/debug/auth", dict(token=token, environment=config["subscriptionEnvironment"]))
        snapshots["after"] = client.prerequisite()
        context.write("pir-prerequisites.json", snapshots)
        verify_auth(snapshots["after"], config, provided=True)
        context.check("run-scoped credential supplied for configured backend", True)
        context.unverified("subscription entitlement", "credentialProvided confirms injection; backend acceptance is exercised by broker work")
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
    if not token:
        if not interactive:
            raise SetupFailed("opt-out requires a token source or --interactive-subscription")
        checkpoint(context, "Activate or restore the authorized test subscription in the running app. "
                   "Do not reset or relaunch. Acknowledge when ready.", config["checkpointTimeout"])
        snapshots["after"] = client.prerequisite()
        context.write("pir-prerequisites.json", snapshots)
        verify_auth(snapshots["after"], config, provided=False)
    path = f"/api/debug/runs/{run_id}"
    client.request("POST", f"{path}/optouts/{result_id}")
    opted = client.idle(run_id, config["activityTimeout"])
    result = selected(opted, result_id=result_id)
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


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("command", choices=("build", "run"))
    cli.add_argument("--platform", choices=("ios", "macos"), required=True)
    cli.add_argument("--config", type=Path, help="scenario JSON, required for run")
    cli.add_argument("--device", choices=("iphone", "ipad"), default="iphone")
    cli.add_argument("--evidence-dir", type=Path, default=Path.home() / "pir-evidence", help="parent directory outside checkout; each attempt gets a unique child")
    token = cli.add_mutually_exclusive_group()
    token.add_argument("--token-file", type=Path, help="read token from this file; never place credentials in config")
    token.add_argument("--token-env", metavar="NAME", help="read token from this environment variable")
    cli.add_argument("--interactive-subscription", action="store_true", help="explicitly allow a manual subscription checkpoint without a token")
    cli.add_argument("--check-config", action="store_true", help="validate inputs without building or launching")
    cli.add_argument("--keep", action="store_true", help="retain simulator after stopping owned app and agent")
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
    if not token or any(c.isspace() for c in token):
        raise ValueError("token source must contain one nonempty credential without whitespace")
    return token


def rerun_command(args):
    command = ["python3", str(Path(__file__).resolve()), args.command, "--platform", args.platform,
               "--device", args.device, "--evidence-dir", str(args.evidence_dir.expanduser().resolve())]
    if args.config:
        command += ["--config", str(args.config.expanduser().resolve())]
    if args.token_file:
        command += ["--token-file", str(args.token_file.expanduser().resolve())]
    if args.token_env:
        command += ["--token-env", args.token_env]
    if args.interactive_subscription:
        command += ["--interactive-subscription"]
    if args.keep:
        command += ["--keep"]
    return shlex.join(command)


def finish(context, include_manifest=True):
    result = context.result
    result["finishedAt"] = time.time()
    context.write("result.json", result)
    lines = [f"# PIR {result['status']}", "", f"Platform: {result['platform']}", "",
             result.get("reason", "Requested broker flow completed."), "", "## Checks", ""]
    lines += [f"- {'PASS' if c['passed'] else 'FAIL'}: {c['check']}" for c in result["checks"]] or ["No broker assertions completed."]
    lines += ["", "## Unverified", ""]
    lines += [f"- {u['what']}: {u['reason']}" for u in result["unverified"]] or ["None recorded."]
    lines += ["", "## Cleanup", "", "```json", json.dumps(result["cleanup"], indent=2), "```"]
    if result["evidenceErrors"]:
        lines += ["", "## Evidence errors", ""] + [f"- {e}" for e in result["evidenceErrors"]]
    lines += ["", "## Rerun", "", "```sh", result["rerun"], "```", ""]
    report = context.redactor.text("\n".join(lines)).encode()
    if include_manifest:
        files = {p.name: dict(sha256=sha256(p.read_bytes()), bytes=p.stat().st_size)
                 for p in sorted(context.evidence.iterdir()) if p.is_file() and p.name not in ("manifest.json", "report.md")}
        files["report.md"] = dict(sha256=sha256(report), bytes=len(report))
        context.write("manifest.json", dict(status=result["status"], files=files))
    # Publish the report only after its required evidence manifest is complete.
    (context.evidence / "report.md").write_bytes(report)


def execute(args, runtime_factory=None):
    token = read_token(args)
    if args.command == "run" and not args.config:
        raise ValueError("run requires --config")
    if args.command == "build" and (args.token_file or args.token_env or args.interactive_subscription):
        raise ValueError("authentication options apply only to run")
    inputs = load_inputs(args.config, needs_auth=bool(token)) if args.config else None
    if inputs and inputs["config"]["optOut"] and not token and not args.interactive_subscription:
        raise ValueError("opt-out requires --token-file, --token-env or explicit --interactive-subscription")
    if token and inputs["config"]["subscriptionEnvironment"] != inputs["config"]["pirEnvironment"]:
        raise ValueError("provided-token subscriptionEnvironment and pirEnvironment must match")
    redactor = Redactor(token)
    if inputs and token and any(any(form.encode() in raw for form in redactor.forms) for raw in inputs["inputBytes"]):
        raise ValueError("credential occurs in scenario inputs; keep it only in the token source")
    root = Path(__file__).resolve().parents[3]
    parent = args.evidence_dir.expanduser().resolve()
    if parent == root or root in parent.parents:
        raise ValueError("--evidence-dir must be outside this checkout")
    if args.check_config:
        if inputs is None:
            raise ValueError("--check-config requires --config")
        return dict(status="valid", inputs=inputs["references"])
    parent.mkdir(parents=True, exist_ok=True)
    evidence = Path(tempfile.mkdtemp(prefix=f"{args.platform}-{args.command}-", dir=parent))
    context = Context(evidence, redactor)
    instance = str(uuid.uuid4())
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        port = reserved.getsockname()[1]
    context.result.update(platform=args.platform, command=args.command, instanceID=instance, port=port,
                          startedAt=time.time(), rerun=rerun_command(args), evidence=str(evidence))
    runtime, client = None, None
    try:
        if inputs:
            context.result["inputs"] = inputs["references"]
            context.write("pir-inputs.json", dict(references=inputs["references"], policy=inputs["config"]["optOut"],
                                                 authentication="provided-token" if token else "interactive" if args.interactive_subscription else "none"))
            (evidence / "pir-broker.json").write_bytes(inputs["brokerBytes"])
        if runtime_factory is None:
            from runtime import Runtime
            runtime_factory = Runtime
        runtime = runtime_factory(args.platform, evidence, instance, port, device=args.device, keep=args.keep,
                                  pir_environment=inputs["config"].get("pirEnvironment", "production") if inputs else "production")
        if args.command == "build":
            context.result["build"] = runtime.build()
            context.write("build.json", context.result["build"])
        else:
            context.result["launch"] = runtime.launch()
            context.write("launch.json", context.result["launch"])
            client = Client(evidence, port, instance, redactor)
            workflow(context, inputs, client, token, args.interactive_subscription)
        context.result["status"] = "pass"
    except KeyboardInterrupt:
        context.result.update(status="inconclusive", reason="cancelled; submitted broker requests cannot be undone")
    except Failed as error:
        context.result.update(status="fail", reason=str(error))
    except Exception as error:
        context.result.update(status="inconclusive", reason=f"{type(error).__name__}: {error}")
    finally:
        # Evidence errors and cancellation during capture must still reach owned cleanup.
        try:
            if client and client.last_run is not None:
                try:
                    context.write("pir-final-run.json", client.last_run)
                except (Exception, KeyboardInterrupt) as error:
                    context.result["evidenceErrors"].append(f"final run: {type(error).__name__}: {error}")
            if runtime and args.command == "run":
                try:
                    if client and client.owned:
                        client.request("GET", "/api/logs?limit=1000")
                except (Exception, KeyboardInterrupt) as error:
                    context.result["evidenceErrors"].append(f"debug logs: {type(error).__name__}: {error}")
                try:
                    # Native logs may echo backend responses. Scrub before adding them to evidence.
                    with tempfile.TemporaryDirectory(prefix="pir-log-") as scratch:
                        log = Path(scratch) / "app.log"
                        runtime.logs(log)
                        (evidence / "pir-app.log").write_text(redactor.text(log.read_text(errors="replace")))
                except (Exception, KeyboardInterrupt) as error:
                    context.result["evidenceErrors"].append(f"application logs: {type(error).__name__}: {error}")
        finally:
            if runtime:
                try:
                    context.result["cleanup"] = runtime.stop()
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
            # Publish consistent failure artifacts without repeating the failed manifest operation.
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
    except (ValueError, OSError) as error:
        # Do not echo input JSON, paths containing file contents, or a credential value.
        print(f"Invalid inputs: {type(error).__name__}: {error if isinstance(error, ValueError) and not isinstance(error, json.JSONDecodeError) else 'could not read or parse input files'}", file=sys.stderr)
        return 2
    print(f"PIR {result['status']}" + (f"\n{result['evidence']}/report.md" if "evidence" in result else ""))
    return {"pass": 0, "valid": 0, "fail": 1, "inconclusive": 2}[result["status"]]


if __name__ == "__main__":
    sys.exit(main())
