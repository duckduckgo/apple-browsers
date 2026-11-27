#!/usr/bin/env python3
"""Find the GitHub login to assign an agent PR to.

The agent worker opens PRs with a "Task/Issue URL:" line pointing at the
Asana task it worked on. This script reads that task's assignee and maps it
to a GitHub login through the GitHub → Asana user map, then writes
``login=<login>`` to ``GITHUB_OUTPUT`` (empty when there's no one to assign).
Workflow logs are public: log task ids and logins only.

Environment:
    ASANA_PAT       Asana personal access token (required)
    PR_BODY         The pull request description
    USER_MAP_PATH   Path to user_map.yml (``github_login: asana_user_gid``)
    GITHUB_OUTPUT   Set by GitHub Actions
"""

from __future__ import annotations

import json
import logging
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional

ASANA_BASE = "https://app.asana.com/api/1.0"
TASK_LINE_PATTERN = re.compile(r"^Task/Issue URL:\s*(\S*app\.asana\.com\S*)", re.MULTILINE)
GID_PATTERN = re.compile(r"\d{10,}")
LOGIN_PATTERN = re.compile(r"[A-Za-z0-9_.-]+")

logger = logging.getLogger("agent-pr-assign")


class AsanaError(RuntimeError):
    pass


def task_gid_from_body(body: str) -> Optional[str]:
    """Return the Asana task gid from the PR's "Task/Issue URL:" line."""
    match = TASK_LINE_PATTERN.search(body or "")
    if not match:
        return None
    gids = GID_PATTERN.findall(match.group(1))
    return gids[-1] if gids else None


def parse_user_map(text: str) -> dict[str, str]:
    """Parse a flat ``github_login: asana_user_gid`` YAML map.

    Same rules as ``parse_user_map`` in scripts/conflict-watch: indented,
    keyless, valueless and non-login lines are skipped.
    """
    result: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip() or line[0].isspace() or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip().strip("'\"")
        value = value.strip().strip("'\"")
        if key and value and LOGIN_PATTERN.fullmatch(key):
            result[key] = value
    return result


def github_login_for(asana_user_gid: str, user_map: str) -> Optional[str]:
    """Look up the GitHub login mapped to an Asana user in user_map.yml."""
    return next((login for login, gid in parse_user_map(user_map).items() if gid == asana_user_gid), None)


def task_assignee_gid(task_gid: str, pat: str) -> Optional[str]:
    url = f"{ASANA_BASE}/tasks/{task_gid}?opt_fields=assignee.gid"
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {pat}", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            task = json.loads(response.read().decode("utf-8"))["data"]
    except urllib.error.HTTPError as error:
        raise AsanaError(f"HTTP {error.code}") from error
    except OSError as error:  # URLError, timeouts, connection resets
        raise AsanaError(str(getattr(error, "reason", error))) from error
    return (task.get("assignee") or {}).get("gid")


def find_assignee(body: str, user_map: str, pat: str) -> Optional[str]:
    task_gid = task_gid_from_body(body)
    if not task_gid:
        logger.warning("No Asana task in the PR description; leaving it unassigned.")
        return None
    try:
        assignee_gid = task_assignee_gid(task_gid, pat)
    except AsanaError as error:
        logger.warning("Couldn't read task %s (%s); leaving the PR unassigned.", task_gid, error)
        return None
    if not assignee_gid:
        logger.warning("Task %s has no assignee; leaving the PR unassigned.", task_gid)
        return None
    login = github_login_for(assignee_gid, user_map)
    if not login:
        logger.warning("Task %s's assignee isn't in the user map; leaving the PR unassigned.", task_gid)
        return None
    logger.info("Task %s: assigning the PR to %s.", task_gid, login)
    return login


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    pat = os.environ.get("ASANA_PAT", "").strip()
    if not pat:
        logger.error("ASANA_PAT is not set.")
        return 1
    user_map_path = Path(os.environ.get("USER_MAP_PATH", ""))
    user_map = user_map_path.read_text() if user_map_path.is_file() else ""

    login = find_assignee(os.environ.get("PR_BODY", ""), user_map, pat)

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a") as file:
            file.write(f"login={login or ''}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
