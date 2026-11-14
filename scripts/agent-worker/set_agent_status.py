#!/usr/bin/env python3
"""Update the Asana task as the worker run goes, as the Apple Agent App Actor.

Every status change comes with a comment saying what happened and what a person should do next.
STAGE=approval: Waiting for approval, with the evidence links and what to click to approve.
Otherwise, when the run ends: PR open with the draft PR link, or Needs attention with how to retry.

Env: ASANA_APP_CLIENT_ID, ASANA_APP_CLIENT_SECRET, ASANA_APP_REFRESH_TOKEN, TASK_GID, RUN_URL,
EVIDENCE_URL, STATUS_FIELD (Agent Status field gid), STATUS_OPTIONS (JSON map of status to option
gid), and at the end AGENT and PUBLISH (job results) and PR_URL
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
    return html.escape(str(v), quote=True)


def a(url, text):
    return f'<a href="{esc(url)}">{esc(text)}</a>'


def evidence(e):
    ev = e.get("EVIDENCE_URL", "").rstrip("/")
    return ev, (f"{a(ev + '/result.md', 'result.md')} (the agent's summary)" if ev else "the evidence linked in the run summary")


def approval_comment(e):
    ev, summary = evidence(e)
    patch = f"{a(ev + '/changes.patch', 'changes.patch')} (the change) and " if ev else ""
    return ("<body><strong>The agent made a change. It needs approval before a draft PR is opened.</strong>\n"
            f"<ol><li>Review {patch}{summary}.</li>"
            f"<li>Open the {a(e['RUN_URL'], 'worker run')} and click <strong>Review deployments</strong>.</li>"
            "<li>Tick <strong>agent-publish</strong>, then click <strong>Approve and deploy</strong> to open the draft PR, "
            "or <strong>Reject</strong> to drop the change.</li></ol>"
            "Only reviewers of the agent-publish environment can approve. "
            "This task moves to PR open when the PR is opened, or Needs attention if it's rejected.</body>")


RETRY = "<li>Set Agent Status back to <strong>Ready</strong> to try again, or mark the task complete to drop it.</li>"


def outcome(e):
    """The end status and its comment"""
    run = a(e["RUN_URL"], "worker run")
    if e["PUBLISH"] == "success" and re.fullmatch(r"https://github\.com/[^\s]+/pull/[0-9]+", e.get("PR_URL", "")):
        return "pr_open", (f"<body><strong>The agent opened a draft PR:</strong> {a(e['PR_URL'], e['PR_URL'])}\n"
                           "<ol><li>Review the PR, then build and test it. The agent couldn't run either.</li>"
                           "<li>Finish the change and mark the PR <strong>Ready for review</strong>.</li>"
                           "<li>When it merges, set Agent Status to <strong>Done</strong>.</li></ol></body>")
    if e["AGENT"] != "success":
        _, summary = evidence(e)
        return "needs_attention", ("<body><strong>The agent failed or made no change.</strong>\n"
                                   f"<ol><li>Open the {run} and {summary} to see why.</li>"
                                   "<li>Fix the cause, or add what the agent needs as a comment.</li>" + RETRY + "</ol></body>")
    return "needs_attention", ("<body><strong>The agent's change wasn't published.</strong> The approval was rejected or the publish step failed.\n"
                               f"<ol><li>Open the {run} to see which.</li>" + RETRY + "</ol></body>")


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
