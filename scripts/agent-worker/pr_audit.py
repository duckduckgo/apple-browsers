#!/usr/bin/env python3
"""Find the PRs the agent opened for this task and check what it published, since with auto nobody reads it first.

Usage: pr_audit.py <evidence dir> <PR template>
Env: TASK_GID, RUN_STARTED (UTC, ISO 8601), GITHUB_REPOSITORY, GH (the gh to run), LEAK_CORPUS

The agent names its branches agent/<task gid>-..., so PRs from those branches opened since the run started are its
own. For each, it checks:
- links in the title and body: only the task, this repo, links already in the PR template, auto's evidence viewer and
  Claude Code's own "Generated with Claude Code" footer link
- images attached to the PR, which would make evidence public
- changed files under .github/ or scripts/agent-worker/
- text copied from the agent's instructions (leak_check.py), in the title, body and added lines
It also checks the repo's activity log for pushes by the agent's app since the run started that went outside
agent/**, and for branches it deleted. Ruleset 27679350 is in evaluate mode, so it records those pushes without
blocking them, since blocking would also stop GitHub Actions pushes to developer branches (Smartling) and releases.
Findings go to pr-audit.md in evidence. GITHUB_OUTPUT gets pr_urls (bottom of the stack first) and flags (a count);
the log gets counts only, since this repo's logs are public
"""

import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leak_check  # noqa: E402

LINK = re.compile(r"https?://[^\s)<>\]\"']+")
APP = "ddg-apple-agent-publish[bot]"


def gh(*args):
    out = subprocess.run([os.environ.get("GH", "gh"), *args], capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        raise RuntimeError(f"gh {args[0]} {args[1]} failed")
    return out.stdout


# The artifacts containers that auto's evidence-url links can point into. auto releases before
# DDG_AUTO_EVIDENCE_CONTAINER support always use auto, so both are allowed until the worker no longer runs one
CONTAINERS = (os.environ.get("DDG_AUTO_EVIDENCE_CONTAINER", "apple"), "auto")


def allowed_links(template, task, repo):
    try:
        with open(template, errors="replace") as f:
            known = set(LINK.findall(f.read()))
    except OSError:
        known = set()
    ok = (f"https://app.asana.com/0/0/{task}/f", f"https://app.asana.com/0/0/{task}")
    return lambda url: (url.rstrip(".,") in known or url.startswith(ok)
                        or url.startswith(f"https://github.com/{repo}/")
                        or url.startswith(tuple(f"https://artifacts.go.duckduckgo.com/view/{c}/" for c in CONTAINERS))
                        or url.startswith("https://claude.com/"))


def stray_pushes(repo, started):
    """The app's pushes outside agent/** and its branch deletions since the run started, from the activity log"""
    items = json.loads(gh("api", f"repos/{repo}/activity?actor={APP.replace('[', '%5B').replace(']', '%5D')}"
                                 "&time_period=day&per_page=100"))
    found = []
    for a in items:
        ref, kind, when = a.get("ref", ""), a.get("activity_type", ""), a.get("timestamp", "")
        # Timestamps are UTC with a Z, like RUN_STARTED
        if when < started:
            continue
        if not ref.startswith("refs/heads/agent/"):
            found.append(f"The app pushed outside `agent/**`: {kind} on `{ref}` at {when}.")
        elif kind == "branch_deletion":
            found.append(f"The app deleted `{ref}` at {when}, which the agent shouldn't do.")
    return found


def main():
    evidence, template = sys.argv[1:3]
    task, repo, started = os.environ["TASK_GID"], os.environ["GITHUB_REPOSITORY"], os.environ.get("RUN_STARTED", "")
    prs = json.loads(gh("pr", "list", "--repo", repo, "--state", "all", "--limit", "100",
                        "--json", "number,url,headRefName,createdAt"))
    mine = sorted((p for p in prs if p["headRefName"].startswith(f"agent/{task}-") and p["createdAt"] >= started),
                  key=lambda p: p["number"])
    ok_link, known = allowed_links(template, task, repo), leak_check.corpus()

    md, flags = ["# What the agent published", ""], 0
    if not mine:
        md += [f"No PRs from `agent/{task}-*` branches were opened in this run.", ""]
    for p in mine:
        n = str(p["number"])
        view = json.loads(gh("pr", "view", n, "--repo", repo, "--json", "title,body,files"))
        diff = gh("pr", "diff", n, "--repo", repo)
        text = f"{view.get('title', '')}\n{view.get('body') or ''}"
        found = []
        # Attached images get their own finding below
        bad = sorted({u for u in LINK.findall(text) if not ok_link(u) and "github.com/user-attachments/" not in u})
        found += [f"Link outside the allowed set: `{u}`" for u in bad]
        if "github.com/user-attachments/" in text:
            found.append("Images are attached to the PR, so evidence that should stay behind SSO is public.")
        paths = [f["path"] for f in view.get("files") or []]
        found += [f"Changes `{x}`, which the agent shouldn't touch." for x in paths
                  if x.startswith((".github/", "scripts/agent-worker/"))]
        found += [f"Copies the agent's instructions: \"{line.strip()[:200]}\"" for line in text.splitlines()
                  if leak_check.leaks(line, known)]
        added = [l[1:] for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
        if leak_check.leaks(" ".join(added), known):
            found.append("The diff's added lines copy text from the agent's instructions. Search them for it.")
        flags += len(found)
        md += [f"## {p['url']}", ""] + ([f"- {x}" for x in found] or ["No problems found."]) + [""]

    try:
        stray = stray_pushes(repo, started)
    except Exception:
        stray = ["Couldn't read the repo's activity log, so pushes outside `agent/**` weren't checked."]
    flags += len(stray)
    md += ["## Pushes outside agent/**", ""] + ([f"- {x}" for x in stray] or ["None."]) + [""]
    if stray:
        md += ["Check what the push changed on that branch and revert it if needed. Ruleset 27679350 is in evaluate "
               "mode, so its Rule insights show the same push.", ""]

    if flags:
        md += ["Anything public stays public. If one of these is sensitive, close the PR, delete its branch and ask "
               "GitHub support to purge it if needed. Then fix the prompt or the worker so it doesn't happen again.", ""]
    with open(os.path.join(evidence, "pr-audit.md"), "w") as f:
        f.write("\n".join(md))
    print(f"pr audit: {len(mine)} PR(s), {flags} problem(s)")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"pr_urls={' '.join(p['url'] for p in mine)}\nflags={flags}\n")


if __name__ == "__main__":
    main()
