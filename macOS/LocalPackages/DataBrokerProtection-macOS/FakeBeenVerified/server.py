#!/usr/bin/env python3
"""A local stand-in for BeenVerified's opt-out flow, for testing PIR user-assisted opt-outs.

It serves the pages at the same paths and with the same selectors the BeenVerified broker JSON uses:
the opt-out search form with a Turnstile, the comprehensive form for highly populated states, the
results cards, the additional-fields page with an hCaptcha and "Remove my Info", and the confirmation.
The captchas and the Cloudflare interstitial are fakes whose behaviour you pick with flags or
POST /__fake/config, so each hand-off can be made to pass by itself or to wait for a person.

Run `./server.py --help` for the flags. Control endpoints:
  GET  /__fake/config        current config
  POST /__fake/config        merge a JSON object into the config
  GET  /__fake/submissions   opt-out requests submitted with "Remove my Info"
  POST /__fake/reset         forget submissions and remembered people
"""

import argparse
import html
import json
import secrets
import sys
import threading
import time
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

OPTOUT_PATH = "/svc/optout/search/optouts"
COMPREHENSIVE_PATH = "/svc/optout/search/comprehensive_optouts"
ADDITIONAL_FIELDS_PATH = "/svc/optout/search/comprehensive_optouts/comprehensive_additional_fields"
SUBMIT_PATH = "/svc/optout/search/comprehensive_optouts/submit"
VERIFY_PATH = "/svc/optout/verify"
CHALLENGE_SCRIPT_PATH = "/cdn-cgi/challenge-platform/h/b/orchestrate/chl_page/v1"

STATES = ("AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY "
          "NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY").split()

STATE_FILE = Path(__file__).with_name(".fake-beenverified-state.json")

lock = threading.Lock()
config = {
    "cloudflare": "off",
    "turnstile": "auto",
    "hcaptcha": "manual",
    "challengeDelayMs": 1500,
    "comprehensiveStates": ["CA", "NY", "TX", "FL"],
    "results": "match",
    "decoys": 4,
    "age": None,
    "city": None,
    "freshRecords": True,
}
remembered_people = {}
submissions = []


def load_state():
    if STATE_FILE.exists():
        data = json.loads(STATE_FILE.read_text())
        remembered_people.update(data.get("people", {}))
        submissions.extend(data.get("submissions", []))


def save_state():
    STATE_FILE.write_text(json.dumps({"people": remembered_people, "submissions": submissions}, indent=2))


def log(message):
    print(time.strftime("%H:%M:%S"), message, file=sys.stderr, flush=True)


def esc(value):
    return html.escape(str(value or ""), quote=True)


def title_case(name):
    return " ".join(part.capitalize() for part in str(name or "").split())


# ---------------------------------------------------------------------------------------------------------------------
# Page chrome

CSS = """
* { box-sizing: border-box; }
body { margin: 0; font-family: Lato, -apple-system, Helvetica, Arial, sans-serif; color: #1c1d3a; background: #fff; }
header.site { background: #fff; border-bottom: 1px solid #e4e4ec; padding: 14px 32px; display: flex; align-items: center; gap: 10px; }
header.site .logo { width: 30px; height: 30px; border-radius: 50%; background: #6bb43f; }
header.site .brand { font-weight: 800; font-size: 20px; }
header.site .fake { margin-left: auto; font-size: 12px; background: #fff3cd; color: #7a5a00; padding: 3px 8px; border-radius: 10px; }
main { max-width: 760px; margin: 0 auto; padding: 32px 24px 64px; }
h1 { font-size: 28px; margin: 0 0 8px; }
p.lead { color: #4b4c6b; margin: 0 0 24px; }
label.field { display: block; margin: 0 0 14px; font-size: 14px; font-weight: 700; }
label.field input, label.field select { display: block; width: 100%; margin-top: 6px; padding: 10px 12px; font-size: 16px;
  border: 1px solid #b9bacb; border-radius: 4px; font-family: inherit; }
.row { display: flex; gap: 16px; } .row > * { flex: 1; }
button.primary { background: #1c1d3a; color: #fff; border: 0; border-radius: 4px; padding: 14px 28px; font-size: 16px; font-weight: 700; cursor: pointer; }
button.primary:disabled { opacity: .4; cursor: default; }
.error { color: #b3261e; font-weight: 700; margin: 12px 0; }
footer.site { background: #f5f5f8; margin-top: 48px; padding: 24px 32px; color: #4b4c6b; font-size: 14px; }

.cf-turnstile { width: 300px; height: 65px; border: 1px solid #e0e0e0; background: #fafafa; display: flex; align-items: center;
  padding: 0 12px; gap: 10px; font-size: 14px; margin: 18px 0; }
.cf-turnstile .box { width: 24px; height: 24px; border: 2px solid #4a4a4a; border-radius: 3px; background: #fff; cursor: pointer; }
.cf-turnstile .spinner { width: 22px; height: 22px; border: 3px solid #ddd; border-top-color: #f38020; border-radius: 50%; animation: spin .8s linear infinite; }
.cf-turnstile .tick { color: #16a34a; font-size: 22px; font-weight: 800; }
.cf-turnstile .cf { margin-left: auto; font-size: 10px; font-weight: 800; letter-spacing: 1px; color: #f38020; }
@keyframes spin { to { transform: rotate(360deg); } }

.results-main { display: flex; flex-direction: column; gap: 14px; }
.result-card { display: flex; border: 1px solid #e4e4ec; border-radius: 8px; padding: 18px 20px; gap: 16px; }
.result-card-body { flex: 1; }
.result-card-name { margin: 0 0 4px; font-size: 20px; }
.result-card-location { margin: 0 0 10px; color: #4b4c6b; }
.result-entry { font-size: 14px; margin: 3px 0; }
.result-entry-label { font-weight: 700; margin-right: 6px; }
.result-card-action { display: flex; align-items: center; }
.optout-button { background: #6bb43f; color: #fff; border: 0; border-radius: 4px; padding: 12px 18px; font-weight: 700; cursor: pointer; }

#additional-fields-form details { border-bottom: 1px solid #e4e4ec; padding: 14px 0; font-size: 18px; }
.certify { display: flex; gap: 10px; align-items: flex-start; margin: 24px 0 8px; font-size: 14px; }
#captcha-widget iframe { width: 304px; height: 78px; border: 0; }
.additional-footer { margin-top: 20px; }
"""


def page(title, body, head_extra=""):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<style>{CSS}</style>
{head_extra}
</head>
<body>
<header class="site"><div class="logo"></div><div class="brand">BeenVerified</div><div class="fake">Local fake</div></header>
<main>
{body}
</main>
<footer class="site">About Us · Member Perks · Contact Us</footer>
</body>
</html>"""


# ---------------------------------------------------------------------------------------------------------------------
# Fake Turnstile, hCaptcha and Cloudflare interstitial

TURNSTILE_JS = """
<script>
(function () {
  const widget = document.currentScript.previousElementSibling;
  const mode = widget.dataset.mode;
  const delay = Number(widget.dataset.delay);
  const status = widget.querySelector('.status');
  const label = widget.querySelector('.label');
  const token = widget.querySelector("input[name='cf-turnstile-response']");
  function verifying() { status.innerHTML = '<div class="spinner"></div>'; label.textContent = 'Verifying...'; }
  function solved() {
    status.innerHTML = '<div class="tick">&#10003;</div>';
    label.textContent = 'Success!';
    token.setAttribute('value', '0.fake-turnstile-' + Date.now());
  }
  if (mode === 'auto') {
    verifying();
    setTimeout(solved, delay);
  } else {
    status.innerHTML = '<div class="box" role="checkbox" aria-label="Verify you are human"></div>';
    label.textContent = 'Verify you are human';
    status.querySelector('.box').addEventListener('click', () => { verifying(); setTimeout(solved, 600); });
  }
  widget.closest('form').addEventListener('submit', (event) => {
    if (!token.getAttribute('value')) {
      event.preventDefault();
      alert('Please complete the security check.');
    }
  });
})();
</script>
"""


def turnstile(widget_id="captcha-widget"):
    with lock:
        mode, delay = config["turnstile"], config["challengeDelayMs"]
    return f"""<div id="{widget_id}" class="cf-turnstile" data-mode="{esc(mode)}" data-delay="{esc(delay)}">
  <span class="status"></span><span class="label"></span><span class="cf">CLOUDFLARE</span>
  <input type="hidden" name="cf-turnstile-response">
</div>{TURNSTILE_JS}"""


HCAPTCHA_FRAME = """<!doctype html><html><head><style>
body { margin: 0; font: 14px -apple-system, Helvetica, Arial, sans-serif; }
.w { box-sizing: border-box; width: 300px; height: 74px; border: 1px solid #d5d5d5; border-radius: 4px; background: #fafafa; display: flex; align-items: center; padding: 0 14px; gap: 12px; }
.box { width: 28px; height: 28px; border: 2px solid #555; border-radius: 4px; background: #fff; cursor: pointer; }
.tick { color: #16a34a; font-size: 24px; font-weight: 800; }
.spinner { width: 24px; height: 24px; border: 3px solid #ddd; border-top-color: #0074bf; border-radius: 50%; animation: s .8s linear infinite; }
@keyframes s { to { transform: rotate(360deg); } }
.logo { margin-left: auto; font-weight: 800; color: #0074bf; font-size: 12px; }
</style></head><body>
<div class="w"><span id="status"><div class="box" id="hc-box" role="checkbox" aria-label="I am human"></div></span><span id="label">I am human</span><span class="logo">hCaptcha</span></div>
<script>
const mode = '__MODE__', delay = __DELAY__;
function solved() {
  document.getElementById('status').innerHTML = '<div class="tick">&#10003;</div>';
  document.getElementById('label').textContent = 'Verified';
  const token = 'P1_fake-hcaptcha-' + Date.now();
  const frame = window.frameElement;
  frame.setAttribute('data-hcaptcha-response', token);
  frame.parentElement.querySelector("textarea[name='h-captcha-response']").value = token;
}
function verifying() { document.getElementById('status').innerHTML = '<div class="spinner"></div>'; }
if (mode === 'auto') { verifying(); setTimeout(solved, delay); }
else document.getElementById('hc-box').addEventListener('click', () => { verifying(); setTimeout(solved, 800); });
</script></body></html>"""


def hcaptcha():
    with lock:
        frame = HCAPTCHA_FRAME.replace("__MODE__", config["hcaptcha"]).replace("__DELAY__", str(config["challengeDelayMs"]))
    return f"""<div id="captcha-widget">
  <iframe title="Widget containing checkbox for hCaptcha security challenge" data-hcaptcha-response="" srcdoc="{esc(frame)}"></iframe>
  <textarea name="h-captcha-response" style="display:none"></textarea>
</div>"""


def cloudflare_interstitial():
    with lock:
        mode, delay = config["cloudflare"], config["challengeDelayMs"]
    body = f"""
<div style="max-width:900px;margin:120px auto 0;padding:0 24px;font-family:-apple-system,Helvetica,Arial,sans-serif;color:#313131">
  <h1 style="font-size:40px">localhost (fake www.beenverified.com)</h1>
  <h2>Performing security verification</h2>
  <p>This website uses a security service to protect against malicious bots. This page is displayed while the website verifies you are not a bot.</p>
  <div class="cf-turnstile" id="cf-challenge">
    <span class="status"></span><span class="label"></span><span class="cf">CLOUDFLARE</span>
  </div>
  <p style="margin-top:80px;font-size:13px;color:#777">Ray ID: {secrets.token_hex(8)} · Performance and Security by Cloudflare (fake)</p>
</div>
<script>window._cf_chl_opt = {{ cType: 'managed', cRay: 'fake' }};</script>
<script src="{CHALLENGE_SCRIPT_PATH}"></script>
<script>
(function () {{
  const widget = document.getElementById('cf-challenge');
  const status = widget.querySelector('.status'), label = widget.querySelector('.label');
  function pass() {{
    status.innerHTML = '<div class="tick">&#10003;</div>'; label.textContent = 'Success!';
    document.cookie = 'cf_clearance=fake; path=/';
    setTimeout(() => location.reload(), 400);
  }}
  function verifying() {{ status.innerHTML = '<div class="spinner"></div>'; label.textContent = 'Verifying...'; }}
  if ('{mode}' === 'auto') {{ verifying(); setTimeout(pass, {int(delay)}); }}
  else {{
    status.innerHTML = '<div class="box" role="checkbox" aria-label="Verify you are human"></div>';
    label.textContent = 'Verify you are human';
    status.querySelector('.box').addEventListener('click', () => {{ verifying(); setTimeout(pass, 600); }});
  }}
}})();
</script>"""
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>Just a moment...</title><style>{CSS}</style></head>
<body>{body}</body></html>"""


# ---------------------------------------------------------------------------------------------------------------------
# Pages

def optout_form_page(error=None):
    options = '<option value="">All</option>' + "".join(f'<option value="{s}">{s}</option>' for s in STATES)
    error_html = f'<p class="error">{esc(error)}</p>' if error else ""
    return page("Opt Out | BeenVerified", f"""
<h1>Search for your record</h1>
<p class="lead">Find and remove your public record from BeenVerified search results.</p>
{error_html}
<form id="optout-form" action="{OPTOUT_PATH}" method="post" accept-charset="UTF-8">
  <input type="hidden" name="authenticity_token" value="{secrets.token_urlsafe(20)}">
  <div class="row">
    <label class="field">First name <input type="text" name="fname" required></label>
    <label class="field">Last name <input type="text" name="ln" required></label>
  </div>
  <label class="field">State <select id="state" name="state">{options}</select></label>
  {turnstile()}
  <button class="primary" type="submit" role="button" aria-label="search-optout-button">Search</button>
</form>""")


def comprehensive_form_page(fname, ln, state, error=None):
    error_html = f'<p class="error">{esc(error)}</p>' if error else ""
    return page("Opt Out | BeenVerified", f"""
<h1>Tell us a bit more</h1>
<p class="lead">We found a lot of records in {esc(state)}. Add a few details so we can find yours.</p>
{error_html}
<form id="comprehensive-form" action="{COMPREHENSIVE_PATH}" method="post" accept-charset="UTF-8">
  <input type="hidden" name="authenticity_token" value="{secrets.token_urlsafe(20)}">
  <input type="hidden" name="isManualRequest" value="false">
  <input type="hidden" name="clear_uploaded_documents" value="true">
  <input type="hidden" name="account_type" value="">
  <input type="hidden" name="state" value="{esc(state)}">
  <label class="field">Request type
    <select id="requestType" name="requestType"><option value="ccpa" selected>Do not sell or share my info</option><option value="delete">Delete my info</option></select>
  </label>
  <label class="field">Do you have an account with us?
    <select id="account_type_select" required>
      <option value="">Select</option><option value="member">Yes, I have an account</option><option value="guest">No</option>
    </select>
  </label>
  <label class="field">Unique code (optional) <input type="text" id="uc" name="uc"></label>
  <div class="row">
    <label class="field">First name <input type="text" id="fname" name="fname" required value="{esc(fname)}"></label>
    <label class="field">Middle name <input type="text" id="mn" name="mn"></label>
    <label class="field">Last name <input type="text" id="ln" name="ln" required value="{esc(ln)}"></label>
  </div>
  <label class="field">Email <input type="email" id="requestor_email" name="requestor_email" required></label>
  <div class="row">
    <label class="field">Age <input type="text" id="age" name="age" required></label>
    <label class="field">Street <input type="text" id="street" name="street" required></label>
  </div>
  <div class="row">
    <label class="field">City <input type="text" id="city" name="city" required></label>
    <label class="field">Zip <input type="text" id="zip" name="zip" required></label>
  </div>
  {turnstile()}
  <button class="primary" type="submit" aria-label="continue-button">Continue</button>
</form>
<script>
  document.getElementById('account_type_select').addEventListener('change', (event) => {{
    document.querySelector("input[name='account_type']").value = event.target.value;
  }});
</script>""")


def result_card(person):
    name = f"{person['first']} {person['middle']} {person['last']}".replace("  ", " ")
    teaser = json.dumps({"addresses": person["locations"], "aliases": person["aliases"],
                         "relatives": person["relatives"], "age": str(person["age"])})
    locations = person["locations"]
    shown_locations = " • ".join(locations[:3]) + (f" • +{len(locations) - 3} more" if len(locations) > 3 else "")
    return f"""<form class="result-card person-result-card" data-turbo="false" action="{ADDITIONAL_FIELDS_PATH}" accept-charset="UTF-8" method="post">
  <input type="hidden" name="authenticity_token" value="{secrets.token_urlsafe(20)}">
  <input type="hidden" name="bvid" value="{esc(person['bvid'])}">
  <input type="hidden" name="display_name" value="{esc(name.upper())}">
  <input type="hidden" name="teaser_data" value="{esc(teaser)}">
  <div class="result-card-body">
    <h2 class="result-card-name">
      {esc(name)}, {esc(person['age'])}
    </h2>
    <p class="result-card-location">{esc(locations[0])}</p>
    <div class="result-entry"><span class="result-entry-label">Born</span><span class="result-entry-value">Jan {2026 - int(person['age'])}</span></div>
    <div class="result-entry"><span class="result-entry-label">Aliases</span><span class="result-entry-value">{esc(', '.join(person['aliases']))}</span></div>
    <div class="result-entry"><span class="result-entry-label">Relatives</span><span class="result-entry-value">{esc(', '.join(person['relatives']))}</span></div>
    <div class="result-entry"><span class="result-entry-label">Locations</span><span class="result-entry-value">{esc(shown_locations)}</span></div>
  </div>
  <div class="result-card-action">
    <button class="optout-button" type="submit">Proceed to Opt Out</button>
  </div>
</form>"""


DECOY_CITIES = [("Greer", "SC"), ("Howell", "NJ"), ("Denver", "PA"), ("Ketchikan", "AK"), ("Napa", "CA"), ("Akron", "OH")]
DECOY_MIDDLES = ["J", "Patrick", "L", "Thomas", "A", "R"]


def people_for(fname, ln, state, age, city):
    first, last = title_case(fname), title_case(ln)
    with lock:
        decoys, fresh = int(config["decoys"]), config["freshRecords"]
    people = []
    # PIR identifies a record by a hash of its card, so a new relative makes each scan find a new record.
    relatives = ["Alex Doe", "Sam Doe"] + ([f"Robin {secrets.token_hex(2).upper()} Doe"] if fresh else [])
    if age and city:
        people.append({
            "bvid": f"D_{secrets.token_hex(8)}", "first": first, "middle": "", "last": last, "age": int(age),
            "locations": [f"{title_case(city)}, {state}", "Springfield, IL", "Portland, OR", "Austin, TX"],
            "aliases": [f"{first[:1]} {last}"], "relatives": relatives,
        })
    for index in range(decoys):
        decoy_city, decoy_state = DECOY_CITIES[index % len(DECOY_CITIES)]
        people.append({
            "bvid": f"D_{secrets.token_hex(8)}", "first": first, "middle": DECOY_MIDDLES[index % len(DECOY_MIDDLES)],
            "last": last, "age": (int(age) + 17 + index * 5) if age else 30 + index * 9,
            "locations": [f"{decoy_city}, {decoy_state}", "Houston, TX"],
            "aliases": [f"{first} {last}"], "relatives": ["Pat Roe"],
        })
    # Put the real match in the middle so the opt-out has to pick the right card.
    if people and age and city and len(people) > 2:
        people.insert(len(people) // 2, people.pop(0))
    return people


def results_page(fname, ln, state, age=None, city=None):
    with lock:
        no_results = config["results"] == "none"
    if no_results:
        return page("No results | BeenVerified", """
<div class="results-main"><img alt="Search Logo" src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" width="1" height="1">
<h1>We couldn't find any records</h1></div>""")
    if not (age and city):
        log(f"No age/city known for {fname} {ln}: the results won't include a match. "
            f"Pass --age/--city, or search from a state in comprehensiveStates once so they're remembered.")
    cards = "\n".join(result_card(person) for person in people_for(fname, ln, state, age, city))
    return page("Results | BeenVerified", f"""
<h1>Select your record</h1>
<p class="lead">Results for {esc(title_case(fname))} {esc(title_case(ln))}{', ' + esc(state) if state else ''}.</p>
<div class="results-main">
{cards}
</div>""")


def additional_fields_page(fields, error=None):
    error_html = f'<p class="error">{esc(error)}</p>' if error else ""
    sections = ["Add names you would like to opt out", "Add phone numbers you would like to opt out",
                "Add all addresses you would like to opt out", "Add all email addresses you would like to opt out",
                "Add all social media you would like to opt out"]
    details = "".join(f"<details><summary>{s}</summary><p style='font-size:14px'>Optional.</p></details>" for s in sections)
    return page("Opt Out | BeenVerified", f"""
<h1>Review your opt-out request</h1>
<p class="lead">{esc(title_case(fields.get('display_name')))}</p>
{error_html}
<form id="additional-fields-form" action="{SUBMIT_PATH}" method="post" accept-charset="UTF-8">
  <input type="hidden" name="authenticity_token" value="{secrets.token_urlsafe(20)}">
  <input type="hidden" name="bvid" value="{esc(fields.get('bvid'))}">
  <input type="hidden" name="display_name" value="{esc(fields.get('display_name'))}">
  {details}
  <p style="text-align:center;margin-top:24px">Please review the information above. Use the sections to modify the request.</p>
  <label class="certify"><input type="checkbox" name="certify" value="1">
    <span>I certify that I am the person whose information is being requested, or their authorized agent.</span></label>
  {hcaptcha()}
  <div class="additional-footer">
    <button class="primary" type="submit">Remove my Info</button>
  </div>
</form>
<script>
  document.getElementById('additional-fields-form').addEventListener('submit', (event) => {{
    const certified = document.querySelector("input[name='certify']").checked;
    const solved = document.querySelector("textarea[name='h-captcha-response']").value;
    if (!certified || !solved) {{
      event.preventDefault();
      alert(!certified ? 'Please certify that you are the person or their agent.' : 'Please complete the captcha.');
    }}
  }});
</script>""")


def confirm_page():
    return page("Request submitted | BeenVerified", """
<h1 class="comprehensive-confirm-title">Your optout request was submitted.</h1>
<p class="lead">Check your email for a link to confirm your request. This fake doesn't send one.</p>""")


def verify_page():
    return page("Opted out | BeenVerified", "<h1>You have successfully been opted out</h1>")


# ---------------------------------------------------------------------------------------------------------------------
# HTTP

class Handler(BaseHTTPRequestHandler):
    server_version = "FakeBeenVerified/1.0"

    def log_message(self, fmt, *args):
        log(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}")

    def send_html(self, body, status=HTTPStatus.OK, headers=None):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, value, status=HTTPStatus.OK):
        data = json.dumps(value, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def redirect(self, location):
        self.send_response(HTTPStatus.SEE_OTHER)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    def form(self):
        return {key: values[-1] for key, values in parse_qs(self.body().decode(), keep_blank_values=True).items()}

    def has_clearance(self):
        cookie = SimpleCookie(self.headers.get("Cookie") or "")
        return "cf_clearance" in cookie

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", ""):
            return self.redirect(OPTOUT_PATH)
        if path == OPTOUT_PATH:
            with lock:
                cloudflare = config["cloudflare"]
            if cloudflare != "off" and not self.has_clearance():
                return self.send_html(cloudflare_interstitial(), HTTPStatus.FORBIDDEN)
            return self.send_html(optout_form_page())
        if path == CHALLENGE_SCRIPT_PATH:
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/javascript")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        if path == VERIFY_PATH:
            return self.send_html(verify_page())
        if path == "/__fake/config":
            with lock:
                return self.send_json(config)
        if path == "/__fake/submissions":
            with lock:
                return self.send_json(submissions)
        if path == "/favicon.ico":
            self.send_response(HTTPStatus.NO_CONTENT)
            self.end_headers()
            return None
        return self.send_html(page("Not found", "<h1>Not found</h1>"), HTTPStatus.NOT_FOUND)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/__fake/config":
            try:
                update = json.loads(self.body() or b"{}")
            except json.JSONDecodeError as error:
                return self.send_json({"error": str(error)}, HTTPStatus.BAD_REQUEST)
            unknown = set(update) - set(config)
            if unknown:
                return self.send_json({"error": f"unknown keys: {sorted(unknown)}"}, HTTPStatus.BAD_REQUEST)
            with lock:
                config.update(update)
                log(f"config: {config}")
                return self.send_json(config)
        if path == "/__fake/reset":
            with lock:
                remembered_people.clear()
                submissions.clear()
                save_state()
            return self.send_json({"ok": True})

        fields = self.form()
        if path == OPTOUT_PATH:
            fname, ln, state = fields.get("fname", "").strip(), fields.get("ln", "").strip(), fields.get("state", "")
            if not (fname and ln) or not fields.get("cf-turnstile-response"):
                return self.send_html(optout_form_page("Enter a first and last name and complete the security check."),
                                      HTTPStatus.UNPROCESSABLE_ENTITY)
            with lock:
                comprehensive = state in config["comprehensiveStates"] or "*" in config["comprehensiveStates"]
                known = remembered_people.get(f"{fname} {ln}".lower(), {})
                age, city = config["age"] or known.get("age"), config["city"] or known.get("city")
            if comprehensive:
                return self.send_html(comprehensive_form_page(fname, ln, state))
            return self.send_html(results_page(fname, ln, state, age, city))
        if path == COMPREHENSIVE_PATH:
            required = ["fname", "ln", "requestor_email", "age", "street", "city", "zip", "account_type",
                        "cf-turnstile-response"]
            missing = [key for key in required if not fields.get(key, "").strip()]
            if missing:
                log(f"comprehensive form missing {missing}")
                return self.send_html(comprehensive_form_page(fields.get("fname"), fields.get("ln"), fields.get("state"),
                                                              f"Missing: {', '.join(missing)}"),
                                      HTTPStatus.UNPROCESSABLE_ENTITY)
            fname, ln = fields["fname"].strip(), fields["ln"].strip()
            with lock:
                remembered_people[f"{fname} {ln}".lower()] = {"age": fields["age"].strip(), "city": fields["city"].strip()}
                save_state()
            return self.send_html(results_page(fname, ln, fields.get("state", ""), fields["age"].strip(), fields["city"].strip()))
        if path == ADDITIONAL_FIELDS_PATH:
            return self.send_html(additional_fields_page(fields))
        if path == SUBMIT_PATH:
            if fields.get("certify") != "1" or not fields.get("h-captcha-response"):
                return self.send_html(additional_fields_page(fields, "Certify the request and complete the captcha."),
                                      HTTPStatus.UNPROCESSABLE_ENTITY)
            with lock:
                submissions.append({"date": time.strftime("%Y-%m-%dT%H:%M:%S"), "bvid": fields.get("bvid"),
                                    "displayName": fields.get("display_name")})
                save_state()
            log(f"opt-out submitted for {fields.get('display_name')}")
            return self.send_html(confirm_page())
        return self.send_html(page("Not found", "<h1>Not found</h1>"), HTTPStatus.NOT_FOUND)


def main():
    parser = argparse.ArgumentParser(description="Serve a fake BeenVerified opt-out flow.")
    parser.add_argument("--port", type=int, default=3002)
    parser.add_argument("--cloudflare", choices=["off", "auto", "manual"], default=config["cloudflare"],
                        help="Interstitial on the opt-out page: off, passes by itself, or needs a click")
    parser.add_argument("--turnstile", choices=["auto", "manual"], default=config["turnstile"],
                        help="Turnstile on the search and comprehensive forms")
    parser.add_argument("--hcaptcha", choices=["auto", "manual"], default=config["hcaptcha"],
                        help="hCaptcha on the review page")
    parser.add_argument("--delay-ms", type=int, default=config["challengeDelayMs"],
                        help="How long an 'auto' challenge takes to pass")
    parser.add_argument("--comprehensive-states", default=",".join(config["comprehensiveStates"]),
                        help="States that get the comprehensive form ('*' for all, '' for none)")
    parser.add_argument("--results", choices=["match", "none"], default=config["results"])
    parser.add_argument("--decoys", type=int, default=config["decoys"], help="Non-matching cards around the match")
    parser.add_argument("--same-record", action="store_true",
                        help="Serve the same matching record every time, so rescans don't create new opt-outs")
    parser.add_argument("--age", help="Age of the matching record, for states without the comprehensive form")
    parser.add_argument("--city", help="City of the matching record, for states without the comprehensive form")
    args = parser.parse_args()

    config.update({
        "cloudflare": args.cloudflare, "turnstile": args.turnstile, "hcaptcha": args.hcaptcha,
        "challengeDelayMs": args.delay_ms, "results": args.results, "decoys": args.decoys,
        "comprehensiveStates": [s.strip().upper() for s in args.comprehensive_states.split(",") if s.strip()],
        "age": args.age, "city": args.city, "freshRecords": not args.same_record,
    })
    load_state()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    log(f"Fake BeenVerified on http://localhost:{args.port}{OPTOUT_PATH}")
    log(f"config: {config}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
