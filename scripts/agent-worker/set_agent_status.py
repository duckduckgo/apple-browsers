#!/usr/bin/env python3
"""Update the Asana task as the worker run goes, as the Apple Agent App Actor.

Every status change comes with a comment saying what happened and what a person should do next.
STAGE=approval: Waiting for approval, with the evidence links and what to click to approve.
Otherwise, when the run ends:
- PR open with the draft PR link
- When the agent or verify failed and retries are left: back to Ready for the planner to pick up again,
  with Agent retries one higher and this run in Agent last run, so the retry reuses the plan and starts
  from this run's patch and results
- Needs attention otherwise, with how to retry by hand. Agent last run is cleared so that re-plans

Env: ASANA_APP_CLIENT_ID, ASANA_APP_CLIENT_SECRET, ASANA_APP_REFRESH_TOKEN, TASK_GID, RUN_URL,
EVIDENCE_URL, VERIFY_URL, STATUS_FIELD (Agent Status field gid), STATUS_OPTIONS (JSON map of status to option
gid), and at the end AGENT and PUBLISH (job results), CANCELLED, VERIFY_OK, FAILURE, PR_URL, RETRY, MAX_RETRIES,
RETRIES_FIELD and LAST_RUN_FIELD (retries are off when either is empty), HANDOFF, SHA256 and RUN
"""

import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request

API = "https://app.asana.com/api/1.0"


def esc(v):
    # Not html.escape(quote=True): Asana shows &#x27; as text, and apostrophes are safe in double-quoted attributes
    return html.escape(str(v), quote=False).replace('"', "&quot;")


def a(url, text):
    return f'<a href="{esc(url)}">{esc(text)}</a>'


def evidence(e):
    ev = e.get("EVIDENCE_URL", "").rstrip("/")
    return ev, (a(ev + "/summary.md", "summary") if ev else "the summary linked in the run summary")


def approval_comment(e):
    ev, summary = evidence(e)
    vu = e.get("VERIFY_URL", "").rstrip("/")
    if vu:
        review = f"Review the {a(vu + '/verify.md', 'summary')}"
    else:
        change = f" and the {a(ev + '/changes.patch', 'change')}" if ev else ""
        review = f"Review the agent's {summary}{change} (the worker couldn't build or test it)"
    return ("<body><strong>The agent has a proposed fix ready for review.</strong> Nothing is published until it's approved.\n"
            f"<ol><li>{review}. Check that the fix makes sense and that nothing sensitive would go into the public PR, "
            "such as user data, crash details or internal links and names.</li>"
            f"<li>Approve the {a(e['RUN_URL'], 'worker run')} to open the PR: click <strong>Review deployments</strong>, "
            "tick <strong>agent-publish</strong> and click <strong>Approve and deploy</strong>, "
            "or <strong>Reject</strong> to drop the change.</li></ol>"
            "Only reviewers of the agent-publish environment can approve.</body>")


RETRY = ("<li>Set Agent Status back to <strong>Ready</strong> to try again with a new plan, "
         "or mark the task complete to drop it.</li>")
ATTENTION = "<body>⚠️ "


def failure(e):
    """A headline for what went wrong and the page that shows it, or None when the agent and verify passed"""
    if e["AGENT"] != "success":
        _, summary = evidence(e)
        return "The agent failed or made no change", f"the agent's {summary}"
    if e.get("VERIFY_OK") != "true":
        vu = e.get("VERIFY_URL", "").rstrip("/")
        what = e.get("FAILURE") or "the build and test job didn't finish"
        return f"The agent's fix didn't pass: {what}", ("the " + a(vu + "/verify.md", "summary") if vu else "the summary linked in the run summary")
    return None


def outcome(e):
    """The end status, its comment and any retry fields to set"""
    run = a(e["RUN_URL"], "worker run")
    if e["PUBLISH"] == "success" and re.fullmatch(r"https://github\.com/[^\s]+/pull/[0-9]+", e.get("PR_URL", "")):
        return "pr_open", (f"<body><strong>The agent opened a draft PR:</strong> {a(e['PR_URL'], e['PR_URL'])}\n"
                           "<ol><li>Review the PR. The worker's build and test results are in the evidence linked above.</li>"
                           "<li>Finish the change and mark the PR <strong>Ready for review</strong>.</li>"
                           "<li>When it merges, set Agent Status to <strong>Done</strong>.</li></ol></body>"), {}
    clear = {e["LAST_RUN_FIELD"]: ""} if e.get("LAST_RUN_FIELD") else {}
    if e.get("CANCELLED") == "true":
        return "needs_attention", (f"{ATTENTION}<strong>The worker run was cancelled.</strong>\n"
                                   f"<ol><li>Open the {run} to see who cancelled it or why it timed out.</li>" + RETRY + "</ol></body>"), clear
    failed = failure(e)
    if failed:
        what, page = failed
        retry, most = int(e.get("RETRY") or 0), int(e.get("MAX_RETRIES") or 0)
        if e.get("RETRIES_FIELD") and e.get("LAST_RUN_FIELD") and retry < most:
            fields = {e["RETRIES_FIELD"]: retry + 1,
                      e["LAST_RUN_FIELD"]: f"{e['HANDOFF']} {e['SHA256']} {e['RUN']}"}
            return "ready", (f"<body><strong>{esc(what)}.</strong> "
                             f"Retrying automatically ({retry + 1} of {most}). No action needed.\n"
                             f"<ul><li>What failed is in {page}.</li>"
                             + ("<li>The retry reuses the plan, starts from this change and gets these results to fix.</li>"
                                if e["AGENT"] == "success" else "<li>The retry reuses the plan and starts again from it.</li>")
                             + "</ul></body>"), fields
        tried = f" That was the last retry ({retry} of {most})." if retry else ""
        return "needs_attention", (f"{ATTENTION}<strong>{esc(what)}.</strong>{tried}\n"
                                   f"<ol><li>Open {page} and the {run} to see why.</li>"
                                   "<li>Fix the cause, or add what the agent needs as a comment.</li>" + RETRY + "</ol></body>"), clear
    return "needs_attention", (f"{ATTENTION}<strong>The agent's change wasn't published.</strong> The approval was rejected or the publish step failed.\n"
                               f"<ol><li>Open the {run} to see which.</li>" + RETRY + "</ol></body>"), clear


def access_token(e):
    """A 1-hour access token from the App Actor's refresh token, masked in the log"""
    grant = urllib.parse.urlencode({
        "grant_type": "refresh_token", "client_id": e["ASANA_APP_CLIENT_ID"],
        "client_secret": e["ASANA_APP_CLIENT_SECRET"], "refresh_token": e["ASANA_APP_REFRESH_TOKEN"]}).encode()
    with urllib.request.urlopen("https://app.asana.com/-/oauth_token", data=grant, timeout=30) as resp:
        token = json.load(resp)["access_token"]
    print(f"::add-mask::{token}")
    return token


def call(token, method, path, data):
    req = urllib.request.Request(f"{API}{path}", method=method, data=json.dumps({"data": data}).encode(),
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30):
        pass


def main():
    e = os.environ
    gid = e["TASK_GID"]
    if not re.fullmatch(r"[0-9]{1,20}", gid):
        sys.exit("bad task_gid")
    if e.get("STAGE") == "approval":
        status, text, fields = "waiting_for_approval", approval_comment(e), {}
    else:
        status, text, fields = outcome(e)
    token = access_token(e)
    fields = {e["STATUS_FIELD"]: json.loads(e["STATUS_OPTIONS"])[status], **fields}
    call(token, "PUT", f"/tasks/{gid}", {"custom_fields": fields})
    call(token, "POST", f"/tasks/{gid}/stories", {"html_text": text})
    print(f"task {gid}: Agent Status {status}")


if __name__ == "__main__":
    main()
