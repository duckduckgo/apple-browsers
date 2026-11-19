#!/usr/bin/env python3
"""Queue feature flag removals for the Apple agent worker.

Finds open tasks in the Apple Feature Flags Registry whose "Auto Removal"
field is set, and gives each one a subtask that the agent worker picks up:
the subtask's description is the prompt (``prompt.md`` filled in for the
flag), it lives in a project the agent watches, and its "Apple Agent Status"
is Ready. The worker then removes the flag and opens the PR.

A Registry task that already has the subtask is skipped, so the script is
safe to run repeatedly. Workflow logs are public: log task ids, flag names
and counts only, never task names, notes or comments.

Environment:
    ASANA_PAT       Asana personal access token (required)
    FFC_DRY_RUN     "1" to log what would be created without writing
    FFC_LIMIT       Maximum subtasks to create per run (default 1)
    FFC_TASK_GID    Only consider this Registry task
"""

from __future__ import annotations

import json
import logging
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from string import Template
from typing import Iterator, Optional, Protocol

ASANA_BASE = "https://app.asana.com/api/1.0"

REGISTRY_PROJECT_GID = "1211834678943996"
PLATFORM_FIELD_GID = "1211861178525877"
AUTO_REMOVAL_FIELD_GID = "1220399141879087"
KEEP_FEATURE_OPTION_GID = "1220399141879088"
REMOVE_FEATURE_OPTION_GID = "1220399141879089"
AGENT_STATUS_FIELD_GID = "1220497931497848"
AGENT_STATUS_READY_OPTION_GID = "1220497931497849"

# Projects the agent bot watches, per platform. iOS has none yet.
AGENT_PROJECT_GIDS = {
    "macOS": "1201037661562251",  # macOS App Development
}

FEATURE_FLAG_FILES = {
    "iOS": "iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift",
    "macOS": "macOS/LocalPackages/FeatureFlags-macOS/Sources/FeatureFlags/FeatureFlag.swift",
}

FLAG_NAME_PATTERN = re.compile(r"Flag name:\s*`?([A-Za-z_][A-Za-z0-9_]*)")

REGISTRY_TASK_FIELDS = "notes,assignee.gid,custom_fields.gid,custom_fields.enum_value.gid,custom_fields.enum_value.name"

logger = logging.getLogger("feature-flag-cleanup")


class AsanaError(RuntimeError):
    pass


@dataclass(frozen=True)
class FlagRemoval:
    registry_task_gid: str
    flag: str
    platform: str
    keep_enabled_path: bool
    owner_gid: Optional[str]

    @property
    def subtask_name(self) -> str:
        return f"Remove {self.flag} feature flag"

    @property
    def agent_project_gid(self) -> str:
        return AGENT_PROJECT_GIDS[self.platform]


class AsanaClientProtocol(Protocol):
    def registry_tasks(self) -> Iterator[dict]: ...
    def task(self, gid: str) -> dict: ...
    def subtask_names(self, gid: str) -> list[str]: ...
    def create_ready_subtask(self, removal: FlagRemoval, notes: str) -> str: ...


class AsanaClient:
    def __init__(self, pat: str):
        self.pat = pat

    def registry_tasks(self) -> Iterator[dict]:
        params = {"completed_since": "now", "limit": 100, "opt_fields": REGISTRY_TASK_FIELDS}
        while True:
            response = self._request("GET", f"/projects/{REGISTRY_PROJECT_GID}/tasks", params=params)
            yield from response.get("data", [])
            next_page = response.get("next_page")
            if not next_page:
                return
            params = {**params, "offset": next_page["offset"]}

    def task(self, gid: str) -> dict:
        params = {"opt_fields": f"completed,{REGISTRY_TASK_FIELDS}"}
        return self._request("GET", f"/tasks/{gid}", params=params)["data"]

    def subtask_names(self, gid: str) -> list[str]:
        response = self._request("GET", f"/tasks/{gid}/subtasks", params={"opt_fields": "name"})
        return [subtask["name"] for subtask in response.get("data", [])]

    def create_ready_subtask(self, removal: FlagRemoval, notes: str) -> str:
        body = {
            "name": removal.subtask_name,
            "notes": notes,
            "parent": removal.registry_task_gid,
            "projects": [removal.agent_project_gid],
            "custom_fields": {AGENT_STATUS_FIELD_GID: AGENT_STATUS_READY_OPTION_GID},
        }
        if removal.owner_gid:
            body["assignee"] = removal.owner_gid
        return self._request("POST", "/tasks", body=body)["data"]["gid"]

    def _request(self, method: str, path: str, *, params: Optional[dict] = None, body: Optional[dict] = None) -> dict:
        url = f"{ASANA_BASE}{path}"
        if params:
            url = f"{url}?{urllib.parse.urlencode(params)}"
        headers = {"Authorization": f"Bearer {self.pat}", "Accept": "application/json"}
        data = None
        if body is not None:
            data = json.dumps({"data": body}).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read().decode("utf-8")
        except urllib.error.HTTPError as error:
            raise AsanaError(f"{method} {path} -> HTTP {error.code}") from error
        except urllib.error.URLError as error:
            raise AsanaError(f"{method} {path} -> {error.reason}") from error
        return json.loads(payload) if payload else {}


def enum_value(task: dict, field_gid: str) -> Optional[dict]:
    for field in task.get("custom_fields", []):
        if field.get("gid") == field_gid:
            return field.get("enum_value")
    return None


def plan_removal(task: dict) -> tuple[Optional[FlagRemoval], str]:
    """Return the removal for a Registry task, or None and why it's skipped."""
    auto_removal = enum_value(task, AUTO_REMOVAL_FIELD_GID)
    if not auto_removal:
        return None, "Auto Removal not set"
    keep_enabled_path = auto_removal["gid"] == KEEP_FEATURE_OPTION_GID
    if not keep_enabled_path and auto_removal["gid"] != REMOVE_FEATURE_OPTION_GID:
        return None, "unknown Auto Removal option"

    platform = (enum_value(task, PLATFORM_FIELD_GID) or {}).get("name")
    if platform not in FEATURE_FLAG_FILES:
        return None, "Platform not set"
    if platform not in AGENT_PROJECT_GIDS:
        return None, f"no agent project for {platform} yet"

    match = FLAG_NAME_PATTERN.search(task.get("notes", ""))
    if not match:
        return None, "no 'Flag name:' line in the notes"

    owner_gid = (task.get("assignee") or {}).get("gid")
    return FlagRemoval(task["gid"], match.group(1), platform, keep_enabled_path, owner_gid), ""


def render_prompt(removal: FlagRemoval, template: str) -> str:
    return Template(template).substitute(
        flag=removal.flag,
        platform=removal.platform,
        decision="approved" if removal.keep_enabled_path else "rejected",
        kept_path="enabled (`true`)" if removal.keep_enabled_path else "disabled (`false`)",
        feature_flag_file=FEATURE_FLAG_FILES[removal.platform],
    )


def queue_removals(
    asana: AsanaClientProtocol,
    template: str,
    *,
    limit: int,
    dry_run: bool,
    only_task_gid: Optional[str] = None
) -> list[FlagRemoval]:
    """Create up to ``limit`` agent subtasks and return the removals queued."""
    tasks = [asana.task(only_task_gid)] if only_task_gid else asana.registry_tasks()
    queued: list[FlagRemoval] = []
    for task in tasks:
        if len(queued) >= limit:
            break
        if task.get("completed"):
            logger.info("%s: skipped, task is completed", task["gid"])
            continue
        removal, reason = plan_removal(task)
        if not removal:
            logger.debug("%s: skipped, %s", task["gid"], reason)
            continue
        if removal.subtask_name in asana.subtask_names(removal.registry_task_gid):
            logger.info("%s (%s): skipped, already queued", removal.registry_task_gid, removal.flag)
            continue

        notes = render_prompt(removal, template)
        if dry_run:
            logger.info("%s (%s): would create '%s' with this prompt:\n%s",
                        removal.registry_task_gid, removal.flag, removal.subtask_name, notes)
        else:
            subtask_gid = asana.create_ready_subtask(removal, notes)
            logger.info("%s (%s): created subtask %s", removal.registry_task_gid, removal.flag, subtask_gid)
        queued.append(removal)
    return queued


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    pat = os.environ.get("ASANA_PAT", "").strip()
    if not pat:
        logger.error("ASANA_PAT is not set.")
        return 1
    dry_run = os.environ.get("FFC_DRY_RUN") == "1"
    limit = int(os.environ.get("FFC_LIMIT") or "1")
    only_task_gid = os.environ.get("FFC_TASK_GID", "").strip() or None
    template = (Path(__file__).parent / "prompt.md").read_text()

    queued = queue_removals(AsanaClient(pat), template, limit=limit, dry_run=dry_run, only_task_gid=only_task_gid)
    verb = "Would queue" if dry_run else "Queued"
    logger.info("%s %d flag removal(s): %s", verb, len(queued), ", ".join(r.flag for r in queued) or "none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
