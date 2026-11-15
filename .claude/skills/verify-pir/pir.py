"""PIR.1: scan one exact broker for a test profile and, with optOut, complete the opt-out for one matched record."""
import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.request
import uuid

from verify_ios import env, steps
from verify_ios.env import Failed, SetupFailed

DEVICES = ["iphone"]
LIVE = ["duckduckgo.com", "data broker sites", "PIR email and captcha services"]
FLAGS = {"dbpCustomWebViewUserAgent": True, "dbpExtractedProfileRefresh": True}
INPUT_ENV = ["PIR_PROOF_INPUT"]
INSTANCE = str(uuid.uuid4())
PORT = env.BASE_PORT + env.PIR_DEBUG_OFFSET
LAUNCH = {"environment": {"PIR_DEBUG_SERVER": "true", "PIR_DEBUG_PORT": str(PORT),
                          "PIR_DEBUG_INSTANCE_ID": INSTANCE}}


def configuration():
    path = os.environ.get("PIR_PROOF_INPUT")
    if not path:
        raise ValueError("set PIR_PROOF_INPUT to the local PIR proof configuration JSON")
    config_path = Path(path).resolve()
    config_bytes = config_path.read_bytes()
    config = json.loads(config_bytes)
    if not isinstance(config, dict):
        raise ValueError("PIR proof configuration must be an object")
    for field in ("brokerFile", "profileFile", "expectedFile"):
        if field in config:
            config[field] = str((config_path.parent / config[field]).resolve())
    config["configurationFile"] = str(config_path)
    config["configurationSHA256"] = hashlib.sha256(config_bytes).hexdigest()
    return config


def inputs():
    config = configuration()
    raw = {k: Path(config[k]).read_bytes() for k in ("brokerFile", "profileFile", "expectedFile") if k in config}
    broker, profile = json.loads(raw["brokerFile"]), json.loads(raw["profileFile"])
    expected = json.loads(raw["expectedFile"]) if "expectedFile" in raw else {}
    config["inputHashes"] = {k: hashlib.sha256(v).hexdigest() for k, v in raw.items()}
    config["brokerBytes"] = raw["brokerFile"]
    if not isinstance(broker, dict) or not all(broker.get(k) for k in ("name", "url", "version", "steps")):
        raise ValueError("brokerFile needs complete broker JSON including name, url, version, and steps")
    if not isinstance(profile, dict) or not all(k in profile for k in ("names", "addresses", "phones", "birthYear")):
        raise ValueError("profileFile needs names, addresses, phones, and birthYear")
    if (not profile["names"] or not profile["addresses"] or not isinstance(profile["birthYear"], int)
            or not 1900 <= profile["birthYear"] <= time.localtime().tm_year):
        raise ValueError("profileFile needs a name, address, and valid birthYear")
    if not isinstance(expected, dict) or set(expected) - {"profileUrl"} or not isinstance(expected.get("profileUrl", ""), str):
        raise ValueError("expectedFile may only name the profileUrl of one scan result")
    if not isinstance(config.get("optOut"), bool):
        raise ValueError("optOut must explicitly be true (scan and opt-out) or false (scan only)")
    if config["optOut"]:
        if not isinstance(config.get("emailConfirmation"), bool):
            raise ValueError("emailConfirmation must explicitly be true or false")
        from urllib.parse import urlsplit
        endpoint = urlsplit(config.get("pirEndpoint", ""))
        if endpoint.scheme not in ("http", "https") or not endpoint.hostname or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment:
            raise ValueError("pirEndpoint must name the expected credential-free PIR backend URL")
        for key in ("subscriptionEnvironment", "pirEnvironment"):
            if config.get(key) not in ("production", "staging"):
                raise ValueError(f"{key} must explicitly be production or staging")
    for key, default, maximum in (("checkpointTimeout", 900, 3600), ("activityTimeout", 600, 3600), ("emailTimeout", 300, 1800)):
        value = config.setdefault(key, default)
        if isinstance(value, bool) or not isinstance(value, (float, int)) or not 0 < value <= maximum:
            raise ValueError(f"{key} must be positive and no more than {maximum} seconds")
    return config, broker, profile, expected


def validate():
    return inputs()


def checkpoint(ios, instruction, timeout):
    """Wait for a person to do `instruction`, acknowledged or cancelled by touching a file named in checkpoint.json."""
    checkpoint_id = uuid.uuid4().hex
    ack = os.path.join(ios.evidence, f"ack-{checkpoint_id}")
    cancel = os.path.join(ios.evidence, f"cancel-{checkpoint_id}")
    record = ios.human_step(instruction)
    record.update(id=checkpoint_id, acknowledge=ack, cancel=cancel, timeout=timeout, status="pending")
    path = Path(ios.evidence) / "checkpoint.json"
    path.write_text(json.dumps(record, indent=2))
    print(f"{instruction}\nAcknowledge: touch {ack}\nCancel: touch {cancel}", flush=True)
    deadline = time.monotonic() + timeout
    try:
        while True:
            if os.path.exists(cancel):
                record["status"] = "cancelled"
                raise SetupFailed("manual checkpoint cancelled")
            if os.path.exists(ack):
                record.update(status="acknowledged", acknowledgedAt=time.time())
                print(f"Acknowledged checkpoint {checkpoint_id}; continuing", flush=True)
                return checkpoint_id
            if time.monotonic() >= deadline:
                record["status"] = "timedOut"
                raise SetupFailed("manual checkpoint timed out")
            time.sleep(0.2)
    finally:
        if record["status"] == "pending":
            record["status"] = "interrupted"
        record["finishedAt"] = time.time()
        path.write_text(json.dumps(record, indent=2))


class Client:
    def __init__(self, evidence, port=PORT, instance=INSTANCE):
        self.evidence, self.port, self.instance = Path(evidence), port, instance
        self.number = 0
        self.last_get = {}   # path -> last saved (status, response), so unchanged polls are not saved again
        self.owned = False
        self.reported = set()

    def report_progress(self, run):
        for event in run.get("events", []):
            key = (event.get("timestamp"), event.get("summary"), event.get("profileQuery"))
            if event.get("kind") == "History" and key not in self.reported:
                self.reported.add(key)
                print(f"PIR {event.get('timestamp')}: {event.get('summary')}", flush=True)

    def request(self, method, path, body=None, timeout=10):
        if method != "GET" and not self.owned:
            raise SetupFailed("PIR endpoint ownership has not been verified")
        request = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", method=method,
                                         headers={"Content-Type": "application/json", "X-PIR-Debug-Instance": self.instance},
                                         data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                status, raw = response.status, response.read().decode()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read().decode(errors="replace")
        try:
            result = json.loads(raw)
        except ValueError:
            result = {"text": raw}
        if method != "GET" or self.last_get.get(path) != (status, result):
            self.number += 1
            record = dict(method=method, path=path, status=status, response=result)
            (self.evidence / f"pir-http-{self.number:04d}.json").write_text(json.dumps(record, indent=2))
        if method == "GET":
            self.last_get[path] = (status, result)
        if status not in (200, 202):
            raise Failed(f"PIR HTTP {status}; see pir-http-{self.number:04d}.json")
        return result

    def prerequisite(self, timeout=35):
        # The app reads the token with the normal .localValid policy and keeps errors, unlike the feature check's
        # cached-entitlement fallback, so "ready" does not prove a fresh server-side subscription refresh.
        check_id = str(uuid.uuid4())
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                result = self.request("GET", f"/api/debug/prerequisites?checkID={check_id}", timeout=min(5, max(.1, deadline - time.monotonic())))
            except urllib.error.URLError:
                time.sleep(.25)
                continue
            if result.get("instanceID") != self.instance or result.get("checkID") != check_id:
                raise SetupFailed("PIR endpoint belongs to another launch or returned an uncorrelated prerequisite")
            self.owned = True
            if result.get("result", {}).get("status") != "pending":
                return result
            time.sleep(.25)
        raise SetupFailed("PIR prerequisite did not complete within its deadline")

    def idle(self, run_id, timeout):
        # Debug runs live in memory; /api/events reads persisted job history and cannot prove this run.
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            run = self.request("GET", f"/api/debug/runs/{run_id}", timeout=min(10, max(.1, deadline - time.monotonic())))
            if run.get("id") != run_id:
                raise Failed("PIR returned a different run")
            self.report_progress(run)
            if not run.get("activity"):
                assert_clean(run)
                return run
            time.sleep(.5)
        raise Failed("PIR activity timed out; cleanup must stop the test app")


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


def stop_test_app(ios):
    ident = ios.d.identity()
    if ios.d.driver.state() in (0, 1):
        return {"alreadyStopped": True}
    if not ident.get("pid"):
        raise Failed("cannot establish the running app identity; test app cleanup is unverified")
    if not ident.get("ok"):
        raise Failed("refusing to terminate an app whose build identity does not match")
    ios.d.terminate()
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if ios.d.driver.state() in (0, 1):
            return {"terminated": True}
        time.sleep(0.2)
    raise Failed("test app survived termination; PIR work may still be running")


def run(ios):
    config, broker, profile, expected = ios.inputs
    directory = Path(ios.evidence)
    ios.on_cleanup("stop PIR work", lambda: stop_test_app(ios))
    client = Client(directory)

    def collect():
        # A capture failure is an evidence problem, never a proof failure.
        if client.owned:
            client.request("GET", "/api/logs?limit=1000")
        ios.d.app_logs(str(directory / "pir-app.log"))
    ios.on_cleanup("capture PIR debug and application logs", collect)

    metadata = dict(configuration=dict(reference=config["configurationFile"], sha256=config["configurationSHA256"]),
                    policy=dict(optOut=config["optOut"], emailConfirmation=config.get("emailConfirmation"),
                                reset="fresh_start before the scan; no reset afterwards",
                                checkpointTimeout=config["checkpointTimeout"], activityTimeout=config["activityTimeout"], emailTimeout=config["emailTimeout"]),
                    instanceID=INSTANCE, port=PORT, broker=dict(name=broker["name"], version=broker["version"],
                    sha256=config["inputHashes"]["brokerFile"]), profile=dict(reference=config["profileFile"], sha256=config["inputHashes"]["profileFile"]),
                    expected=dict(reference=config["expectedFile"], sha256=config["inputHashes"]["expectedFile"])
                    if "expectedFile" in config else None)
    # The exact bytes submitted, not a re-serialization.
    (directory / "pir-broker.json").write_bytes(config["brokerBytes"])
    (directory / "pir-inputs.json").write_text(json.dumps(metadata, indent=2))
    steps.fresh_start(ios)
    before = client.prerequisite()  # also proves this launch owns the endpoint; scans need no subscription
    (directory / "pir-prerequisites.json").write_text(json.dumps(dict(before=before, build=ios.launched), indent=2))
    ios.note("PIR.1 debug scan/opt-out oracle; debug jobs suppress ordinary pixels.")
    ios.unverified("PIR worker and backend traffic", "host observation covers only browser traffic; broker, email and captcha requests run in PIR workers")
    started = client.request("POST", "/api/debug/scans", dict(broker=broker, profile=profile, hidesWebView=True))
    run_id = started.get("id")
    if not isinstance(run_id, str) or not re.fullmatch(r"[A-Za-z0-9-]+", run_id):
        raise Failed("scan did not return a valid run ID")
    scan = client.idle(run_id, config["activityTimeout"])
    ios.check("scan emitted Scan Started", history(scan, "Scan Started"))
    if not scan.get("results"):
        ios.check("empty scan emitted No Match", history(scan, "No Match"))
        ios.unverified("PIR opt-out and email flow", "the app matched no records to the profile; no opt-out was submitted")
        raise SetupFailed("no match: opt-out contract remains unverified")
    if not config["optOut"]:
        ios.check(f"scan found {len(scan['results'])} record(s) the app matched to the profile", True)
        if expected.get("profileUrl"):
            ios.check("scan found the expected profileUrl", any(r.get("profileUrl") == expected["profileUrl"] for r in scan["results"]))
        (directory / "pir-final-run.json").write_text(json.dumps(scan, indent=2))
        ios.unverified("PIR opt-out", "scan-only run (optOut: false)")
        return
    # The opt-out submits one result ID, so it needs exactly one record.
    result = selected(scan, expected.get("profileUrl"))
    result_id = result["id"]
    if not re.fullmatch(r"[A-Za-z0-9-]+", result_id):
        raise Failed("invalid result ID")
    ios.check("scan selected one record to opt out", True)
    checkpoint(ios, "Use the app's normal subscription UI to activate/restore the test subscription. "
               "Do not reset or relaunch. Acknowledge when ready; never put credentials in the proof.", config["checkpointTimeout"])
    after = client.prerequisite()  # a fresh check after acknowledgement
    (directory / "pir-prerequisites.json").write_text(json.dumps(dict(before=before, after=after, build=ios.launched), indent=2))
    prerequisite = after.get("result", {})
    if (prerequisite.get("status") != "ready" or prerequisite.get("authenticated") is not True or not after.get("checkedAt")
            or prerequisite.get("environment") != config["subscriptionEnvironment"]
            or prerequisite.get("pirEnvironment") != config["pirEnvironment"]
            or prerequisite.get("pirEndpoint") != config["pirEndpoint"]
            or after.get("debugRunnerReady") is not True):
        raise SetupFailed("real entitlement or configured backend prerequisite not satisfied; see pir-prerequisites.json")
    path = f"/api/debug/runs/{run_id}"
    client.request("POST", f"{path}/optouts/{result_id}")
    opted = client.idle(run_id, config["activityTimeout"])
    result = selected(opted, result_id=result_id)
    ios.check("selected record emitted Opt-out Started", history(opted, "Opt-out Started", result.get("profileQuery")))
    if config["emailConfirmation"]:
        ios.check("selected record awaits email confirmation", result.get("optOutStatus") == "awaitingEmailConfirmation")
        deadline = time.monotonic() + config["emailTimeout"]
        while not result.get("hasEmailConfirmationLink"):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise Failed("email confirmation link not available within deadline")
            client.request("POST", f"{path}/email-confirmation/check", timeout=min(10, remaining))
            opted = client.idle(run_id, min(config["activityTimeout"], remaining))
            result = selected(opted, result_id=result_id)
            if not result.get("hasEmailConfirmationLink"):
                time.sleep(min(2, max(0, deadline - time.monotonic())))
        ios.check("selected record has an email confirmation link", result["hasEmailConfirmationLink"])
        client.request("POST", f"{path}/optouts/{result_id}/continue")
        opted = client.idle(run_id, config["activityTimeout"])
        result = selected(opted, result_id=result_id)
    ios.check("selected record opt-out flow confirmed", result.get("optOutStatus") == "confirmed")
    ios.check("selected record emitted Opt-out Confirmed", history(opted, "Opt-out Confirmed", result.get("profileQuery")))
    (directory / "pir-final-run.json").write_text(json.dumps(opted, indent=2))
    ios.unverified("broker removal", "confirmed proves the submission/confirmation flow; removal needs a later scan")
