#!/usr/bin/env python3
"""Update the Asana task as the worker run goes, as the Apple Agent App Actor.

Every status change comes with a comment saying what happened and what a person should do next.
When the run ends:
- PR open with the PR links (a stack lists each), plus any problems the publish audit or tool report found
- Needs attention otherwise, with what to look at and how to try again

Env: ASANA_APP_CLIENT_ID, ASANA_APP_CLIENT_SECRET, ASANA_APP_REFRESH_TOKEN, TASK_GID, RUN_URL,
EVIDENCE_URL, DECISION_LOG_URL (auto's, when it kept one), STATUS_FIELD (Agent Status field gid), STATUS_OPTIONS
(JSON map of status to option gid), and at the end AGENT and PUBLISH (job results), CANCELLED, BUILD_OK, FAILURE,
PR_URL (from publish, without auto), and with auto PR_URLS (the agent's own PRs, bottom of the stack first),
AUDIT_FLAGS and TOOL_ISSUES (counts), and AUTO
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


def how(e):
    """Where to see how the agent worked: auto's decision log and the full session, behind SSO"""
    ev, log = e.get("EVIDENCE_URL", "").rstrip("/"), e.get("DECISION_LOG_URL", "")
    links = []
    if re.fullmatch(r"https://artifacts\.go\.duckduckgo\.com/view/[^\s\"<>]+", log):
        links.append("its " + a(log, "decision log") + " with its proofs")
    if ev:
        links.append("the " + a(ev + "/transcript.md", "full session transcript"))
    return " or ".join(links)


AGAIN = ("<li>Set Agent Status back to <strong>Ready</strong> to try again with a new plan, "
         "or mark the task complete to drop it.</li>")
ATTENTION = "<body>⚠️ "
REVIEW = "<body>🙋 "


def failure(e):
    """A headline for what went wrong and the page that shows it, or None when the agent and verify passed"""
    if e["AGENT"] != "success":
        _, summary = evidence(e)
        return "The agent failed or made no change", f"the agent's {summary}"
    if e.get("BUILD_OK") != "true":
        _, summary = evidence(e)
        what = e.get("FAILURE") or "the build and test check didn't finish"
        return f"The agent's fix didn't pass: {what}", f"the agent's {summary}"
    return None


PR = re.compile(r"https://github\.com/[^\s/]+/[^\s/]+/pull/[0-9]+")


def prs(e):
    """The PRs this run opened: the agent's own with auto, or the one publish opened"""
    if e.get("AUTO") == "true":
        return [u for u in e.get("PR_URLS", "").split() if PR.fullmatch(u)]
    return [e["PR_URL"]] if e.get("PUBLISH") == "success" and PR.fullmatch(e.get("PR_URL", "")) else []


def count(e, key):
    try:
        return int(e.get(key) or 0)
    except ValueError:
        return 0


def warnings(e):
    """List items for problems to look at first: what went public, and denied or failed tool calls"""
    ev, items = e.get("EVIDENCE_URL", "").rstrip("/"), []
    flags, issues = count(e, "AUDIT_FLAGS"), count(e, "TOOL_ISSUES")
    page = lambda name, text: a(f"{ev}/{name}", text) if ev else text
    if flags:
        items.append(f"<li>⚠️ The worker found {flags} problem(s) in what the agent published. Open the "
                     f"{page('pr-audit.md', 'publish check')} first, and close the PR if anything sensitive went public.</li>")
    if issues:
        items.append(f"<li>{issues} tool call(s) were denied or failed. The {page('tool-report.md', 'tool report')} "
                     "says how to fix each.</li>")
    return "".join(items)


def outcome(e):
    """The end status and its comment"""
    run = a(e["RUN_URL"], "worker run")
    opened = prs(e)
    if opened:
        _, summary = evidence(e)
        steps = warnings(e)
        if len(opened) > 1:
            steps += ("<li>It's a stack of " + str(len(opened)) + " PRs. Review them from the bottom: "
                      + ", ".join(a(u, u) for u in opened) + ".</li>")
        steps += f"<li>Review the PR. The agent's {summary} has the problem, the fix and its build and test results.</li>"
        if e.get("AUTO") == "true" and e.get("BUILD_OK") != "true":
            steps += (f"<li>The agent's last build or test run before the PR didn't pass ({esc(e.get('FAILURE') or 'no result')}), "
                      "so check the PR checks closely.</li>")
        if e.get("CANCELLED") == "true":
            steps += f"<li>The {run} was cancelled or timed out, so the agent may not have finished babysitting the PR.</li>"
        if how(e):
            steps += f"<li>To see how the agent worked, open {how(e)}.</li>"
        return "pr_open", (f"{REVIEW}<strong>The agent opened a PR ready for review:</strong> {a(opened[0], opened[0])}\n"
                           f"<ol>{steps}</ol></body>")
    if e.get("CANCELLED") == "true":
        return "needs_attention", (f"{ATTENTION}<strong>The worker run was cancelled.</strong>\n"
                                   f"<ol>{warnings(e)}<li>Open the {run} to see who cancelled it or why it timed out.</li>" + AGAIN + "</ol></body>")
    failed = failure(e)
    if failed:
        what, page = failed
        more = f" You can also open {how(e)}." if how(e) else ""
        return "needs_attention", (f"{ATTENTION}<strong>{esc(what)}.</strong>\n"
                                   f"<ol>{warnings(e)}<li>Open {page} and the {run} to see why.{more}</li>"
                                   "<li>Fix the cause, or add what the agent needs as a comment.</li>" + AGAIN + "</ol></body>")
    if e.get("AUTO") == "true":
        _, summary = evidence(e)
        more = f" You can also open {how(e)}." if how(e) else ""
        return "needs_attention", (f"{ATTENTION}<strong>The agent didn't open a PR.</strong>\n"
                                   f"<ol>{warnings(e)}<li>Open the agent's {summary} and the {run} to see why.{more}</li>"
                                   + AGAIN + "</ol></body>")
    return "needs_attention", (f"{ATTENTION}<strong>The agent's change wasn't published.</strong> The publish step failed or was skipped.\n"
                               f"<ol>{warnings(e)}<li>Open the {run} to see why.</li>" + AGAIN + "</ol></body>")


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
    call(token, "PUT", f"/tasks/{gid}", {"custom_fields": {e["STATUS_FIELD"]: json.loads(e["STATUS_OPTIONS"])[status]}})
    call(token, "POST", f"/tasks/{gid}/stories", {"html_text": text})
    print(f"task {gid}: Agent Status {status}")


if __name__ == "__main__":
    main()
