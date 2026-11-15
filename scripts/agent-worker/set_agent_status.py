#!/usr/bin/env python3
"""Update the Asana task as the worker run goes, as the Apple Agent App Actor.

Every status change comes with a comment saying what happened and what a person should do next.
STAGE=approval: Waiting for approval, with the evidence links and what to click to approve.
Otherwise, when the run ends:
- PR open with the PR link
- Needs attention otherwise, with what to look at and how to try again

Env: ASANA_APP_CLIENT_ID, ASANA_APP_CLIENT_SECRET, ASANA_APP_REFRESH_TOKEN, TASK_GID, RUN_URL,
EVIDENCE_URL, VERIFY_URL, STATUS_FIELD (Agent Status field gid), STATUS_OPTIONS (JSON map of status to option
gid), and at the end AGENT and PUBLISH (job results), CANCELLED, VERIFY_OK, FAILURE and PR_URL
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
    return (f"{REVIEW}<strong>The agent has a proposed fix ready for review.</strong> Nothing is published until it's approved.\n"
            f"<ol><li>{review}. Check that the fix makes sense and that nothing sensitive would go into the public PR, "
            "such as user data, crash details or internal links and names.</li>"
            f"<li>Approve the {a(e['RUN_URL'], 'worker run')} to open the PR: click <strong>Review deployments</strong>, "
            "tick <strong>agent-publish</strong> and click <strong>Approve and deploy</strong>, "
            "or <strong>Reject</strong> to drop the change.</li></ol>"
            "Only reviewers of the agent-publish environment can approve.</body>")


AGAIN = ("<li>Set Agent Status back to <strong>Ready</strong> to try again with a new plan, "
         "or mark the task complete to drop it.</li>")
ATTENTION = "<body>⚠️ "
REVIEW = "<body>🙋 "


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
    """The end status and its comment"""
    run = a(e["RUN_URL"], "worker run")
    if e["PUBLISH"] == "success" and re.fullmatch(r"https://github\.com/[^\s]+/pull/[0-9]+", e.get("PR_URL", "")):
        return "pr_open", (f"{REVIEW}<strong>The agent opened a PR ready for review:</strong> {a(e['PR_URL'], e['PR_URL'])}\n"
                           "<ol><li>Review the PR. The worker's build and test results are in the evidence linked above.</li>"
                           "<li>When it merges, set Agent Status to <strong>Done</strong>.</li></ol></body>")
    if e.get("CANCELLED") == "true":
        return "needs_attention", (f"{ATTENTION}<strong>The worker run was cancelled.</strong>\n"
                                   f"<ol><li>Open the {run} to see who cancelled it or why it timed out.</li>" + AGAIN + "</ol></body>")
    failed = failure(e)
    if failed:
        what, page = failed
        return "needs_attention", (f"{ATTENTION}<strong>{esc(what)}.</strong>\n"
                                   f"<ol><li>Open {page} and the {run} to see why.</li>"
                                   "<li>Fix the cause, or add what the agent needs as a comment.</li>" + AGAIN + "</ol></body>")
    return "needs_attention", (f"{ATTENTION}<strong>The agent's change wasn't published.</strong> The approval was rejected or the publish step failed.\n"
                               f"<ol><li>Open the {run} to see which.</li>" + AGAIN + "</ol></body>")


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
        status, text = "waiting_for_approval", approval_comment(e)
    else:
        status, text = outcome(e)
    token = access_token(e)
    call(token, "PUT", f"/tasks/{gid}", {"custom_fields": {e["STATUS_FIELD"]: json.loads(e["STATUS_OPTIONS"])[status]}})
    call(token, "POST", f"/tasks/{gid}/stories", {"html_text": text})
    print(f"task {gid}: Agent Status {status}")


if __name__ == "__main__":
    main()
