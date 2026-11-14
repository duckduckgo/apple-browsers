#!/usr/bin/env python3
"""Set the Asana task's Agent Status from how the worker run ended, as the Apple Agent App Actor.

PR open with a comment linking the draft PR, or Needs attention with a comment linking the run.

Env: ASANA_APP_CLIENT_ID, ASANA_APP_CLIENT_SECRET, ASANA_APP_REFRESH_TOKEN, TASK_GID, FIELD (Agent
Status field gid), OPTIONS (JSON map of status to option gid), AGENT and PUBLISH (job results),
PR_URL, RUN_URL
"""

import json
import os
import re
import sys
import urllib.parse
import urllib.request

API = "https://app.asana.com/api/1.0"


def outcome(e):
    if e["PUBLISH"] == "success" and re.fullmatch(r"https://github\.com/[^\s]+/pull/[0-9]+", e.get("PR_URL", "")):
        return "pr_open", f"Agent worker opened a draft PR: {e['PR_URL']}"
    if e["AGENT"] != "success":
        return "needs_attention", f"Agent worker failed or made no changes: {e['RUN_URL']}"
    return "needs_attention", f"Agent worker's change was not published (approval declined or publish failed): {e['RUN_URL']}"


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
    status, text = outcome(e)
    token = access_token(e)
    call(token, "PUT", f"/tasks/{gid}", {"custom_fields": {e["FIELD"]: json.loads(e["OPTIONS"])[status]}})
    call(token, "POST", f"/tasks/{gid}/stories", {"text": text})
    print(f"task {gid}: Agent Status {status}")


if __name__ == "__main__":
    main()
