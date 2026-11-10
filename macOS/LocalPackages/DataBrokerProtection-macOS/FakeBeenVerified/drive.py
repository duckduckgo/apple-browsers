#!/usr/bin/env python3
"""Runs a BeenVerified user-assisted opt-out against the local fake, through the PIR debug server.

It turns the real BeenVerified broker JSON into one for the fake (same actions, URLs pointing at
server.py, broker url `fakebroker.com`), installs it in the running agent, scans, starts the
assisted opt-out and follows it until it's submitted. With --solve it also does the user's part at
each hand-off; without it, it waits for you to do them in the agent's window.

Needs a debug build of the agent started with `-pirDebugServer true`, the `dbpUserAssistance` flag
on, and `fakebroker.com` in Debug → Personal Information Removal → User Assistance → Override
Enabled Brokers….
"""

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).parent
DEFAULT_BROKER_URL = "fakebroker.com"
REAL_ORIGIN = "https://www.beenverified.com"

SOLVE_JS = r"""
const did = [];
const challenge = document.querySelector('#cf-challenge .box');
if (challenge) { challenge.click(); did.push('cloudflare'); }
for (const widget of document.querySelectorAll('.cf-turnstile[data-mode]')) {
  const token = widget.querySelector("input[name='cf-turnstile-response']");
  const box = widget.querySelector('.box');
  if (token && !token.getAttribute('value') && box) { box.click(); did.push('turnstile'); }
}
const hcaptcha = document.querySelector('#captcha-widget iframe[srcdoc]');
if (hcaptcha && !hcaptcha.getAttribute('data-hcaptcha-response')) {
  const box = hcaptcha.contentDocument && hcaptcha.contentDocument.getElementById('hc-box');
  if (box) { box.click(); did.push('hcaptcha'); }
} else if (hcaptcha && document.querySelector("input[name='certify']")?.checked) {
  document.querySelector('.additional-footer button[type=submit]').click();
  did.push('remove my info');
}
return did;
"""


def make_fake_broker_json(source: Path, fake_origin: str, broker_url: str) -> bytes:
    broker = json.loads(source.read_text())
    text = json.dumps(broker).replace(REAL_ORIGIN, fake_origin)
    broker = json.loads(text)
    broker["name"] = f"BeenVerified local fake ({broker_url})"
    broker["url"] = broker_url
    broker["mirrorSites"] = []
    broker.pop("removedAt", None)
    return json.dumps(broker, indent=2).encode()


class Client:
    def __init__(self, base):
        self.base = base.rstrip("/")

    def request(self, path, method="GET", body=None, timeout=60):
        request = urllib.request.Request(self.base + path, data=body, method=method)
        if body is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data = response.read()
        except urllib.error.HTTPError as error:
            raise SystemExit(f"{method} {path} failed with {error.code}: {error.read().decode()[:500]}")
        content_type = response.headers.get("Content-Type", "")
        if "json" in content_type and data:
            return json.loads(data)
        return data

    def is_up(self, path):
        try:
            urllib.request.urlopen(self.base + path, timeout=3).read()
            return True
        except (urllib.error.URLError, ConnectionError, TimeoutError):
            return False


def say(message):
    print(time.strftime("%H:%M:%S"), message, flush=True)


def parse_date(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def wait_for_scans(debug, broker_url, query_ids, started, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(3)
        detail = debug.request(f"/api/brokers/{broker_url}")
        pending, results = 0, []
        for query in detail["profileQueries"]:
            if query["profileQueryId"] not in query_ids:
                continue
            events = [e for e in query["scan"]["history"] if parse_date(e["date"]) >= started]
            last = events[-1] if events else None
            if last is None or last["type"] == "scanStarted":
                pending += 1
            else:
                error = (last.get("error") or {}).get("description", "")
                results.append(f"query {query['profileQueryId']}: {last['type']} {error}".strip())
        if pending == 0:
            return results, detail
    raise SystemExit("Scans didn't finish in time")


def fake_web_view(debug, broker_url, after_id=0):
    views = [v for v in debug.request("/api/webviews") if v.get("brokerURL") == broker_url and v["id"] > after_id]
    return views[-1] if views else None


def save_screenshot(debug, view, folder, label):
    if not (folder and view):
        return
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{time.strftime('%H%M%S')}-{label}.png"
    path.write_bytes(debug.request(f"/api/webviews/{view['id']}/screenshot"))
    say(f"  screenshot {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=HERE / "beenverified.com.json", help="BeenVerified broker JSON")
    parser.add_argument("--fake", default="http://localhost:3002", help="Where server.py runs")
    parser.add_argument("--debug-server", default="http://127.0.0.1:8474")
    parser.add_argument("--broker-url", default=DEFAULT_BROKER_URL,
                        help="Broker url for the fake; the email service must accept it")
    parser.add_argument("--no-scan", action="store_true", help="Use the matches from an earlier scan")
    parser.add_argument("--no-install", action="store_true", help="Keep the installed broker JSON")
    parser.add_argument("--solve", action="store_true", help="Do the user's part at each hand-off")
    parser.add_argument("--id", help="Assisted opt-out id to start (brokerId-profileQueryId-extractedProfileId)")
    parser.add_argument("--manual", default="",
                        help="Comma-separated challenges (cloudflare, turnstile, hcaptcha) to make wait for a click during "
                             "the opt-out, so their hand-offs fire. Scans still get passable ones.")
    parser.add_argument("--shots", type=Path, help="Folder for screenshots at each state change")
    parser.add_argument("--timeout", type=int, default=660, help="Seconds to wait for the opt-out")
    args = parser.parse_args()

    debug, fake = Client(args.debug_server), Client(args.fake)
    if not fake.is_up("/__fake/config"):
        raise SystemExit(f"The fake isn't running at {args.fake}. Start ./server.py first.")
    if not debug.is_up("/api"):
        raise SystemExit(f"No PIR debug server at {args.debug_server}. Launch the app with -pirDebugServer true.")

    if not args.no_install:
        if not args.source.exists():
            raise SystemExit(f"No broker JSON at {args.source}. Save the BeenVerified JSON with userAssist steps there "
                             "or pass --source.")
        broker_json = make_fake_broker_json(args.source, args.fake.rstrip("/"), args.broker_url)
        (HERE / f"{args.broker_url}.json").write_bytes(broker_json)
        installed = debug.request("/api/brokers", "POST", broker_json)
        say(f"Installed {installed['name']} {installed['version']} (id {installed['id']})")

    if not args.no_scan:
        started = datetime.now(timezone.utc).replace(microsecond=0)
        run = debug.request(f"/api/brokers/{args.broker_url}/scan", "POST")
        say(f"Scanning profile queries {run['profileQueryIds']}")
        results, _ = wait_for_scans(debug, args.broker_url, run["profileQueryIds"], started, timeout=180)
        for line in results:
            say(f"  {line}")

    # Clears an earlier run's submitted attempt, which otherwise hides its broker's new opt-outs until a dashboard reload.
    listing = debug.request("/api/assisted-optouts?dropSubmitted=true")
    if not listing["isFeatureOn"]:
        raise SystemExit("The dbpUserAssistance flag is off. Turn it on in Debug → Feature Flags.")
    if args.broker_url not in listing["enabledBrokers"]:
        raise SystemExit(f"{args.broker_url} isn't an enabled broker (enabled: {listing['enabledBrokers']}). "
                         "Add it in Debug → Personal Information Removal → User Assistance → Override Enabled Brokers….")
    optouts = [o for o in listing["optOuts"] if o["dataBroker"]["url"] == args.broker_url]
    if not optouts:
        raise SystemExit("No fake BeenVerified opt-out in Needs you. Did the scan find a match? "
                         "Check the server log for 'No age/city known'.")
    optout = next((o for o in optouts if o["id"] == args.id), None) if args.id else optouts[0]
    if optout is None:
        raise SystemExit(f"{args.id} isn't listed: {[o['id'] for o in optouts]}")
    if optout["state"] == "submitted":
        say(f"{optout['id']} is already submitted")
        return
    manual = [name.strip() for name in args.manual.split(",") if name.strip()]
    if manual:
        fake.request("/__fake/config", "POST", json.dumps({name: "manual" for name in manual}).encode())
        say(f"Fake challenges waiting for a click: {manual}")

    # A debug scan leaves its window open, so only follow web views the attempt creates.
    baseline = max((v["id"] for v in debug.request("/api/webviews")), default=0)
    say(f"Starting {optout['id']} ({optout['recordCount']} records, state {optout['state']})")
    debug.request(f"/api/assisted-optouts/{optout['id']}/start", "POST")

    submissions_before = len(fake.request("/__fake/submissions"))
    last_seen, last_begin, deadline = None, 0.0, time.time() + args.timeout
    while time.time() < deadline:
        time.sleep(2)
        current = next((o for o in debug.request("/api/assisted-optouts")["optOuts"] if o["id"] == optout["id"]), None)
        if current is None:
            raise SystemExit("The opt-out left Needs you without being submitted")
        view = fake_web_view(debug, args.broker_url, baseline)
        url = (view or {}).get("url") or ""
        step = (current.get("step") or {}).get("title")
        seen = (current["state"], step, url.split("?")[0])
        if seen != last_seen:
            say(f"{current['state']:<15} {step or '-':<28} {url}")
            save_screenshot(debug, view, args.shots, f"{current['state']}-{(step or 'none').replace(' ', '_')}")
            last_seen = seen

        if current["state"] == "submitted":
            break
        if current["state"] not in ("needsUser", "userInControl"):
            continue
        if not url.startswith("http"):
            # The window opens on an intro screen; starting again begins the attempt.
            if time.time() - last_begin > 5:
                debug.request(f"/api/assisted-optouts/{optout['id']}/start", "POST")
                last_begin = time.time()
            continue
        if args.solve:
            did = debug.request(f"/api/webviews/{view['id']}/evaluate", "POST", SOLVE_JS.encode())["result"]
            if did:
                say(f"  solved: {', '.join(did)}")
    else:
        raise SystemExit("Timed out waiting for the opt-out to be submitted")

    submissions = fake.request("/__fake/submissions")[submissions_before:]
    say(f"Fake received {len(submissions)} submission(s): {[s['displayName'] for s in submissions]}")
    detail = debug.request(f"/api/brokers/{args.broker_url}")
    for query in detail["profileQueries"]:
        for record in query["optOuts"]:
            if optout["id"].endswith(f"-{query['profileQueryId']}-{record['extractedProfileId']}") and record["history"]:
                say(f"History ends with {[e['type'] for e in record['history'][-3:]]}")


if __name__ == "__main__":
    main()
