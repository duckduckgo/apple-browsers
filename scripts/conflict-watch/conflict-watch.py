#!/usr/bin/env python3
"""Daily pairwise conflict detector for duckduckgo/apple-browsers.

For every pair of branches with commits in the last ``CW_RECENCY_HOURS``
(default 48), runs an in-memory three-way merge (``git merge-tree``) and
reports any pair that conflicts as a deduplicated Asana task in the
configured project.

Two kinds of conflict are detected:

* **Hard merge conflicts** — the same lines edited on both sides, or
  modify-vs-delete situations. Git would refuse to auto-merge these.
* **Soft conflicts** — both branches changed the same file but on
  different lines, so git would merge cleanly. These often produce
  semantic bugs and are still worth flagging. Files matching
  ``CW_ALWAYS_IGNORE`` patterns (defaults cover Xcode project files and
  lockfiles) are excluded from the soft-conflict bucket.

Filters
-------
* Branch tip committed within the recency window.
* Branch is not already merged into ``main`` (``git diff --quiet
  main..branch`` — two-dot, so it catches squash-merged refs whose
  tip content already matches main).
* Branch's most recent PR (if any) is OPEN — branches whose latest PR
  is MERGED or CLOSED-unmerged are skipped via the GitHub API (catches
  the "PR landed but the bare mirror hasn't fetched yet" race).
* Pair authors differ — single-author pair-conflicts aren't a
  coordination signal.
* Branch author is not a known bot (dependabot, renovate, …).
* Pairs are ordered by recency-of-newer-tip so the time budget hits
  the freshest pairs first.

Idempotency
-----------
Each pair gets at most one Asana task, ever. Tasks are deduplicated by
an order-independent title of the form ``Likely merge conflict:
<branchA> ↔ <branchB>`` (branch names sorted alphabetically).

* No matching task → create a new task + post a kickoff comment
  (capped at ``CW_MAX_NEW_TASKS`` per run).
* Matching task (open or completed) → leave it alone. No daily
  snapshot comments, no reopens. Once a teammate completes a task it
  stays closed.

End-of-run sweep
----------------
After reconciliation, the run walks every open ``Likely merge
conflict:`` task in the project and auto-closes it if either of two
conditions holds:

* one of its branches has been merged (PR state ``MERGED``) → the
  conflict is no longer actionable;
* a fresh ``merge-tree`` probe on the current tips finds no remaining
  conflict above ``CW_MIN_CONFLICT_LINES`` → the overlap was rebased
  or refactored away, or the original detection was a false positive
  that no longer reproduces.

Each auto-close adds a one-line story explaining why.

Tagging branch owners
---------------------
If a user-map file is provided via ``CW_USER_MAP_PATH`` (a flat YAML of
``github_login: asana_user_gid``), the kickoff comment posted right
after task creation ``@``-mentions both branch authors using Asana's
rich-text format (``<a data-asana-gid="…"/>``). Asana auto-adds
mentioned users as task followers, so a single comment delivers the
inbox notification *and* the long-term association. When
``CW_NO_MENTIONS=1`` the mentions collapse to plain author names and
no notification fires.

Configuration
-------------
All knobs are environment variables (see ``CW_*`` constants below);
the optional ``CW_ROOT/config.env`` file feeds ``ASANA_PAT`` only —
the ``CW_*`` constants are evaluated at import time, so they must be
set in the process environment before the script runs.

Required:
    ASANA_PAT          Asana personal access token

Optional (defaults shown):
    CW_REPO=duckduckgo/apple-browsers
    CW_DEFAULT_BRANCH=main
    CW_RECENCY_HOURS=48
    CW_ASANA_WORKSPACE_GID=137249556945
    CW_ASANA_PROJECT_GID=1214448335754394
    CW_ROOT=~/.conflict-watch
    CW_DRY_RUN=0          (1 to skip Asana writes)
    CW_VERBOSE=0
    CW_TIME_BUDGET_S=540  (soft cap, 9 minutes)
    CW_MAX_NEW_TASKS=50   (hard cap on new tasks per run)
    CW_INCLUDE_SOFT=0     (1 to also emit soft-conflict tasks; off by default
                           — soft conflicts are noisy and not real merge
                           conflicts)
    CW_ALWAYS_IGNORE=…    (comma-separated globs applied to BOTH hard and
                           soft buckets; see DEFAULT_ALWAYS_IGNORE)
    CW_MIN_CONFLICT_LINES=20
                          (skip pairs whose hard-conflict regions sum to
                           fewer lines after the always-ignore filter)
    CW_NO_MENTIONS=0      (1 to render kickoff comments with plain author
                           names instead of Asana @-mentions — no inbox
                           notification fires; useful for first-run pilots)
    CW_BOT_AUTHORS=…      (comma-separated GitHub logins to skip)
    CW_BRANCH_SKIP_PATTERNS=…
                          (comma-separated fnmatch globs on branch name;
                           default "release/*,hotfix/*")
    CW_USER_MAP_PATH=     (path to a flat YAML of github→asana gid)

CLI flags
---------
    --dry-run    Same as CW_DRY_RUN=1 — don't create / update Asana tasks.
    --self-test  Build a synthetic git repo and verify conflict detection.
    --once PAIR  Probe a single pair "branchA..branchB" and exit (debug).
    --report     Probe all pairs and print a histogram + top conflict
                 files in each bucket. No Asana calls. Used to calibrate
                 CW_ALWAYS_IGNORE and CW_MIN_CONFLICT_LINES from real
                 data; takes --top N for list size.
    --verbose    Verbose logging.

Exit codes
----------
    0  OK (whether or not conflicts were found)
    1  Run-time error
    2  Configuration / auth error
"""

from __future__ import annotations

import argparse
import fnmatch
import itertools
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone, timedelta
from html import escape as html_escape
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO = os.environ.get("CW_REPO", "duckduckgo/apple-browsers")
DEFAULT_BRANCH = os.environ.get("CW_DEFAULT_BRANCH", "main")
RECENCY_HOURS = int(os.environ.get("CW_RECENCY_HOURS", "48"))
ASANA_WORKSPACE_GID = os.environ.get("CW_ASANA_WORKSPACE_GID", "137249556945")
ASANA_PROJECT_GID = os.environ.get("CW_ASANA_PROJECT_GID", "1214448335754394")
TIME_BUDGET_S = int(os.environ.get("CW_TIME_BUDGET_S", "540"))
MAX_NEW_TASKS = int(os.environ.get("CW_MAX_NEW_TASKS", "50"))
INCLUDE_SOFT_CONFLICTS = os.environ.get("CW_INCLUDE_SOFT", "0").lower() in ("1", "true", "yes")

ROOT = Path(os.environ.get("CW_ROOT", str(Path.home() / ".conflict-watch")))
MIRROR = ROOT / f"{REPO.split('/')[-1]}.git"
STATE_PATH = ROOT / "state.json"
LOG_DIR = ROOT / "logs"
CONFIG_ENV = ROOT / "config.env"
USER_MAP_PATH = os.environ.get("CW_USER_MAP_PATH", "").strip()

DEFAULT_ALWAYS_IGNORE = (
    # Xcode and SwiftPM bookkeeping
    "*.pbxproj,"
    "*.xcworkspace/**,"
    "*.xcodeproj/project.xcworkspace/**,"
    "Package.resolved,"
    "**/Package.resolved,"
    "**/Package.swift,"
    "*.lock,"
    "*.lockfile,"
    # Generated sources
    "**/Generated/**,"
    "**/*.generated.swift,"
    # Append-only registries that everyone touches
    "**/PixelDefinitions/**,"
    "iOS/Core/PixelEvent.swift,"
    "iOS/Core/FeatureFlag.swift,"
    # Localized strings and localization bundles
    "iOS/DuckDuckGo/UserText.swift,"
    "iOS/DuckDuckGo/en.lproj/Localizable.strings,"
    # Design system asset catalog
    "SharedPackages/Infrastructure/DesignResourcesKitIcons/**,"
    # Maestro flow scripts and JS lockfile
    ".maestro/**,"
    "**/.maestro/**,"
    "package-lock.json,"
    "**/package-lock.json"
)
# Patterns that suppress a path from BOTH the hard and soft buckets.
# Originally named CW_SOFT_IGNORE because pbxproj-style files showed up
# only as soft conflicts in the cowork prototype, but on real apple-
# browsers data they appear as hard conflicts too (UUID-region edits in
# fixed line slots). Apply-everywhere is the right semantics.
ALWAYS_IGNORE_PATTERNS = [
    p.strip()
    for p in os.environ.get("CW_ALWAYS_IGNORE", DEFAULT_ALWAYS_IGNORE).split(",")
    if p.strip()
]
MIN_CONFLICT_LINES = int(os.environ.get("CW_MIN_CONFLICT_LINES", "20"))
# When set, suppress all Asana @-mentions and skip the addFollowers call so
# the run writes tasks without notifying anyone. Useful for the first real
# write while the team is still inspecting filter output.
NO_MENTIONS = os.environ.get("CW_NO_MENTIONS", "0").lower() in ("1", "true", "yes")

DEFAULT_BOT_AUTHORS = (
    "dependabot[bot],"
    "renovate[bot],"
    "github-actions[bot],"
    "daxtheduck,"
    "ddg-automation-ci"
)
BOT_AUTHORS = {
    a.strip().lower()
    for a in os.environ.get("CW_BOT_AUTHORS", DEFAULT_BOT_AUTHORS).split(",")
    if a.strip()
}

DEFAULT_BRANCH_SKIP_PATTERNS = "release/*,hotfix/*"
BRANCH_SKIP_PATTERNS = [
    p.strip()
    for p in os.environ.get(
        "CW_BRANCH_SKIP_PATTERNS", DEFAULT_BRANCH_SKIP_PATTERNS
    ).split(",")
    if p.strip()
]

TITLE_PREFIX = "Likely merge conflict:"
TITLE_SEP = " ↔ "
COMPARE_URL_TEMPLATE = f"https://github.com/{REPO}/compare/{{a}}...{{b}}"

ASANA_BASE = "https://app.asana.com/api/1.0"

logger = logging.getLogger("conflict-watch")


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class Branch:
    name: str
    sha: str
    committer_iso: str
    author_name: str
    author_email: str
    github_login: Optional[str] = None
    asana_gid: Optional[str] = None
    pr_url: Optional[str] = None

    @property
    def short_sha(self) -> str:
        return self.sha[:7]

    @property
    def owner_key(self) -> str:
        """Stable identifier for "who owns this branch" used to skip
        same-author pair-conflicts (a single engineer touching their own
        two branches doesn't need an Asana task to coordinate with
        themselves). Preference order: GitHub login (canonical), commit
        author email, commit author name. Lowercased + trimmed.
        """
        candidate = self.github_login or self.author_email or self.author_name
        return (candidate or "").lower().strip()

    @property
    def committer_dt(self) -> datetime:
        try:
            ts = datetime.fromisoformat(self.committer_iso)
            if ts.tzinfo is None:
                ts = ts.replace(tzinfo=timezone.utc)
            return ts
        except ValueError:
            return datetime.fromtimestamp(0, tz=timezone.utc)


@dataclass
class ConflictPair:
    a: Branch
    b: Branch
    merge_base: str
    hard_files: list[str] = field(default_factory=list)
    soft_files: list[str] = field(default_factory=list)
    # Total lines inside <<<<<<< / >>>>>>> markers across all non-ignored
    # hard-conflict files. Used by the line-count threshold filter.
    # Available only on the modern git path (>=2.38) where merge-tree
    # writes a tree we can inspect; legacy path leaves this at 0 and
    # bypasses the filter.
    hard_conflict_lines: int = 0
    # OID of the merged tree produced by `git merge-tree --write-tree`
    # (modern git only). Empty on the legacy path. Lets --report
    # recount lines under different filter assumptions without rerunning
    # merge-tree.
    merged_tree_oid: str = ""

    @property
    def has_conflicts(self) -> bool:
        return bool(self.hard_files or self.soft_files)

    @property
    def title_key(self) -> str:
        names = sorted([self.a.name, self.b.name])
        return f"{TITLE_PREFIX} {names[0]}{TITLE_SEP}{names[1]}"

    @property
    def newer_tip_dt(self) -> datetime:
        return max(self.a.committer_dt, self.b.committer_dt)


@dataclass
class RunSummary:
    branches_checked: int = 0
    branches_skipped_merged: int = 0
    branches_skipped_bot: int = 0
    branches_skipped_pattern: int = 0
    branches_skipped_inactive_pr: int = 0
    pairs_probed: int = 0
    pairs_with_hard_conflicts: int = 0
    pairs_with_soft_conflicts: int = 0
    pairs_with_both: int = 0
    pairs_below_line_threshold: int = 0
    pairs_same_author: int = 0
    pairs_already_reported: int = 0
    tasks_created: int = 0
    tasks_auto_closed_merged: int = 0
    tasks_auto_closed_resolved: int = 0
    tasks_skipped_cap: int = 0
    errors: list[str] = field(default_factory=list)
    skipped_pairs: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Config / setup
# ---------------------------------------------------------------------------

def load_config_env() -> None:
    """Merge KEY=VALUE lines from CW_ROOT/config.env into os.environ."""
    if not CONFIG_ENV.exists():
        return
    for raw in CONFIG_ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def setup_logging(verbose: bool) -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = LOG_DIR / f"{datetime.now().strftime('%Y-%m-%d')}.log"
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)-7s %(message)s",
        handlers=[
            logging.FileHandler(log_file, encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )


# ---------------------------------------------------------------------------
# Subprocess helpers
# ---------------------------------------------------------------------------

def run(cmd: list[str], *, check: bool = True, cwd: Optional[Path] = None,
        capture: bool = True) -> subprocess.CompletedProcess:
    logger.debug("$ %s", " ".join(cmd))
    return subprocess.run(
        cmd,
        check=check,
        cwd=str(cwd) if cwd else None,
        text=True,
        capture_output=capture,
    )


def git(args: list[str], *, check: bool = True,
        cwd: Optional[Path] = None) -> subprocess.CompletedProcess:
    return run(["git", *args], check=check, cwd=cwd or MIRROR)


def have_command(cmd: str) -> bool:
    return shutil.which(cmd) is not None


# ---------------------------------------------------------------------------
# Git: refresh + branch enumeration
# ---------------------------------------------------------------------------

def refresh_mirror() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    if not MIRROR.exists():
        url = f"https://github.com/{REPO}.git"
        logger.info("Cloning bare mirror from %s into %s", url, MIRROR)
        run(["git", "clone", "--mirror", url, str(MIRROR)], cwd=ROOT)
        return
    logger.info("Fetching updates into %s", MIRROR)
    git(["fetch", "--prune", "origin", "+refs/heads/*:refs/heads/*"])


def _is_merged_into_default(branch: str) -> bool:
    """True if ``branch`` and ``DEFAULT_BRANCH`` have identical tip-tree
    content — i.e. every change in branch is already in main, regardless
    of how it got there.

    Uses two-dot (``main..branch``) rather than three-dot
    (``main...branch``). Three-dot diffs from the merge-base and would
    miss squash-merged branches (the squash commit lives on main but the
    original branch commits don't, so three-dot reports a diff even
    though the *contents* are identical). Two-dot compares tip trees,
    which is what "are these branches effectively the same?" means.
    """
    proc = git(["diff", "--quiet", f"{DEFAULT_BRANCH}..{branch}"], check=False)
    return proc.returncode == 0


def list_active_branches(within_hours: int, summary: RunSummary) -> list[Branch]:
    sep = "\x1f"
    fmt = sep.join([
        "%(refname:short)",
        "%(committerdate:iso-strict)",
        "%(authorname)",
        "%(authoremail)",
        "%(objectname)",
    ])
    proc = git(["for-each-ref", f"--format={fmt}", "refs/heads/"])
    cutoff = datetime.now(timezone.utc) - timedelta(hours=within_hours)
    branches: list[Branch] = []
    for line in proc.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split(sep)
        if len(parts) != 5:
            logger.warning("Skipping unparseable ref line: %r", line)
            continue
        name, iso, author_name, author_email, sha = parts
        if name == DEFAULT_BRANCH:
            continue
        if any(fnmatch.fnmatch(name, pat) for pat in BRANCH_SKIP_PATTERNS):
            logger.debug("Skipping branch by pattern: %s", name)
            summary.branches_skipped_pattern += 1
            continue
        try:
            ts = datetime.fromisoformat(iso)
        except ValueError:
            logger.warning("Skipping ref %s: bad date %r", name, iso)
            continue
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        if ts < cutoff:
            continue
        if _is_merged_into_default(name):
            logger.debug("Skipping merged branch: %s", name)
            summary.branches_skipped_merged += 1
            continue
        branches.append(Branch(
            name=name,
            sha=sha,
            committer_iso=iso,
            author_name=author_name,
            author_email=author_email.strip("<>"),
        ))
    # Sort by parsed datetime, not the raw ISO string. ``committer_iso``
    # carries the committer's local timezone, so lex-sorting puts e.g.
    # 12:00+02:00 (10:00 UTC) after 11:00+00:00 (11:00 UTC) even though
    # it's earlier; ``committer_dt`` normalises to a tz-aware datetime.
    branches.sort(key=lambda b: b.committer_dt, reverse=True)
    return branches


# ---------------------------------------------------------------------------
# GitHub: author -> login + PR lookup
# ---------------------------------------------------------------------------

@dataclass
class BranchPRStatus:
    """Snapshot of a branch's PR history from GitHub.

    Used by main() to filter branches whose only PRs are merged or
    closed-unmerged (the engineer is not actively preparing this for
    merge), and by the end-of-run sweep to auto-close tasks whose
    branches have since merged.
    """
    has_any_pr: bool = False
    has_open_pr: bool = False
    open_pr_url: Optional[str] = None
    most_recent_state: Optional[str] = None    # "OPEN" | "MERGED" | "CLOSED" | None
    most_recent_merged_at: Optional[str] = None
    most_recent_pr_number: Optional[int] = None


_login_cache: dict[str, Optional[str]] = {}
_pr_status_cache: dict[str, BranchPRStatus] = {}


def lookup_github_login(sha: str) -> Optional[str]:
    if sha in _login_cache:
        return _login_cache[sha]
    if not have_command("gh"):
        _login_cache[sha] = None
        return None
    try:
        proc = run(
            ["gh", "api", f"repos/{REPO}/commits/{sha}",
             "--jq", ".author.login // \"\""],
            check=False,
        )
        login = (proc.stdout or "").strip()
        _login_cache[sha] = login or None
    except Exception as exc:
        logger.warning("gh lookup failed for %s: %s", sha, exc)
        _login_cache[sha] = None
    return _login_cache[sha]


def lookup_branch_pr_status(branch_name: str) -> BranchPRStatus:
    """Fetch the branch's PR history once and cache it.

    A single ``gh pr list --state all`` query is enough to populate
    everything we need: the open-PR URL for the description, plus the
    "is this branch still actively heading toward merge?" signal that
    drives both the pre-create branch filter and the post-create
    auto-close sweep.
    """
    if branch_name in _pr_status_cache:
        return _pr_status_cache[branch_name]
    status = BranchPRStatus()
    if not have_command("gh"):
        _pr_status_cache[branch_name] = status
        return status
    try:
        proc = run(
            ["gh", "pr", "list",
             "--repo", REPO,
             "--head", branch_name,
             "--state", "all",
             "--json", "state,url,mergedAt,createdAt,number",
             "--limit", "10"],
            check=False,
        )
        if proc.returncode != 0:
            _pr_status_cache[branch_name] = status
            return status
        prs = json.loads(proc.stdout or "[]")
    except Exception as exc:
        logger.warning("gh pr list failed for %s: %s", branch_name, exc)
        _pr_status_cache[branch_name] = status
        return status
    if not prs:
        _pr_status_cache[branch_name] = status
        return status
    status.has_any_pr = True
    prs_sorted = sorted(prs, key=lambda p: p.get("createdAt", ""), reverse=True)
    most_recent = prs_sorted[0]
    status.most_recent_state = most_recent.get("state")
    status.most_recent_merged_at = most_recent.get("mergedAt")
    status.most_recent_pr_number = most_recent.get("number")
    for pr in prs_sorted:
        if pr.get("state") == "OPEN":
            status.has_open_pr = True
            status.open_pr_url = pr.get("url")
            break
    _pr_status_cache[branch_name] = status
    return status


# ---------------------------------------------------------------------------
# User map (github login -> asana user gid)
# ---------------------------------------------------------------------------

def parse_user_map(text: str) -> dict[str, str]:
    """Parse a flat YAML mapping of ``github_login: asana_user_gid``.

    Handles only flat scalar mappings. Lines that aren't ``key: value``
    pairs (anchors, lists, nested maps) are skipped.
    """
    result: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip() or line.startswith(" ") or line.startswith("\t"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip().strip('"').strip("'")
        value = value.strip().strip('"').strip("'")
        if not key or not value:
            continue
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", key):
            continue
        result[key] = value
    return result


def load_user_map() -> dict[str, str]:
    if not USER_MAP_PATH:
        return {}
    path = Path(USER_MAP_PATH)
    if not path.exists():
        logger.warning("CW_USER_MAP_PATH=%s does not exist; skipping mentions",
                       USER_MAP_PATH)
        return {}
    try:
        return parse_user_map(path.read_text(encoding="utf-8"))
    except OSError as exc:
        logger.warning("Failed to read user map %s: %s", USER_MAP_PATH, exc)
        return {}


# ---------------------------------------------------------------------------
# Git: pairwise conflict probe
# ---------------------------------------------------------------------------

_LEGACY_TRIPLE = re.compile(r"^(?:base|our|their)\s+\d+\s+\S+\s+(.+)$")
_GIT_VERSION: Optional[tuple[int, int]] = None


def _git_version() -> tuple[int, int]:
    global _GIT_VERSION
    if _GIT_VERSION is None:
        out = run(["git", "--version"]).stdout.strip()
        m = re.search(r"(\d+)\.(\d+)", out)
        _GIT_VERSION = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    return _GIT_VERSION


def _supports_modern_merge_tree() -> bool:
    return _git_version() >= (2, 38)


def _matches_always_ignore(path: str) -> bool:
    """Match ``path`` against the always-ignore globs (applied to both
    hard and soft buckets).

    fnmatch doesn't treat ``**/`` specially — it's just ``*`` (any chars
    including ``/``), which means a pattern like ``**/Generated/**``
    requires at least one slash before ``Generated``. To make the common
    "anywhere in tree" intent work, for any pattern starting with
    ``**/`` we also try matching the suffix (no path prefix).
    """
    base = os.path.basename(path)
    for pat in ALWAYS_IGNORE_PATTERNS:
        if fnmatch.fnmatch(path, pat):
            return True
        if pat.startswith("**/") and fnmatch.fnmatch(path, pat[3:]):
            return True
        if fnmatch.fnmatch(base, pat):
            return True
    return False


def _count_marker_lines(text: str) -> int:
    """Count content lines inside ``<<<<<<<`` / ``>>>>>>>`` regions.

    Lines that are themselves the conflict markers (``<<<<<<<``,
    ``=======``, ``>>>>>>>``) are excluded; everything else between an
    opening and closing marker is counted, summing both the "ours" and
    "theirs" sides of each hunk.
    """
    total = 0
    in_conflict = False
    for line in text.split("\n"):
        if line.startswith("<<<<<<< "):
            in_conflict = True
            continue
        if line.startswith(">>>>>>> "):
            in_conflict = False
            continue
        if in_conflict and not line.startswith("======="):
            total += 1
    return total


def _count_conflict_lines_for_files(tree_oid: str, paths: list[str]) -> int:
    """For each path in ``paths``, fetch the file from the merged tree
    and count lines inside conflict markers. Returns the total."""
    if not tree_oid or not paths:
        return 0
    total = 0
    for path in paths:
        proc = git(["show", f"{tree_oid}:{path}"], check=False)
        if proc.returncode != 0:
            # File may not exist on the merged tree (e.g. modify/delete
            # conflicts) or path encoding got mangled; skip silently —
            # the line filter is best-effort.
            continue
        total += _count_marker_lines(proc.stdout)
    return total


def probe_pair(a: Branch, b: Branch, *, compute_soft: bool = True,
               apply_ignore_filter: bool = True) -> Optional[ConflictPair]:
    """Run an in-memory three-way merge and return a ``ConflictPair`` if
    any conflict is found.

    ``compute_soft=False`` skips the soft-conflict computation entirely
    (the pair is reported only if there are hard conflicts). The
    production daily run uses this path to avoid soft-conflict noise.

    ``apply_ignore_filter=False`` includes paths that would normally be
    suppressed by ``CW_ALWAYS_IGNORE`` — used by ``--report`` to inspect
    what the filter is currently catching.
    """
    base_proc = git(["merge-base", a.name, b.name], check=False)
    if base_proc.returncode != 0 or not base_proc.stdout.strip():
        raise ProbeError(
            f"no merge base between {a.name} and {b.name}"
        )
    base = base_proc.stdout.strip()

    hard_files: set[str] = set()
    merged_tree_oid: Optional[str] = None

    if _supports_modern_merge_tree():
        proc = git(
            ["merge-tree", "--write-tree", f"--merge-base={base}",
             a.name, b.name],
            check=False,
        )
        if proc.returncode == 0:
            pass
        elif proc.returncode == 1:
            # First non-empty line of stdout is the merged tree's OID
            # when there are conflicts (per git-merge-tree(1)).
            for line in proc.stdout.splitlines():
                stripped = line.strip()
                if stripped and re.fullmatch(r"[0-9a-f]{40,}", stripped):
                    merged_tree_oid = stripped
                    break
            # Conflicted paths are emitted as stage-1/2/3 index entries:
            #     <mode> <oid> <stage>\t<path>
            # This is authoritative for every conflict type the
            # --write-tree path produces (content, modify/delete,
            # rename/delete, binary, …) so we don't need a second
            # parser on the human-readable "CONFLICT (...): ..."
            # messages — those had ambiguous file-path placement
            # (e.g. "X deleted in HEAD and modified in branch") that
            # made a regex unreliable.
            for line in proc.stdout.splitlines():
                if "\t" in line:
                    left, _, path = line.partition("\t")
                    bits = left.split()
                    if len(bits) == 3 and bits[2] in ("1", "2", "3"):
                        hard_files.add(path)
        else:
            raise ProbeError(
                f"merge-tree --write-tree rc={proc.returncode} for "
                f"{a.name} vs {b.name}: {proc.stderr.strip()[:200]}"
            )
    else:
        legacy = git(["merge-tree", base, a.name, b.name], check=False)
        if legacy.returncode != 0:
            raise ProbeError(
                f"legacy merge-tree failed for {a.name} vs {b.name} "
                f"(rc={legacy.returncode})"
            )
        in_section = False
        current_path: Optional[str] = None
        section_has_marker = False
        for line in legacy.stdout.splitlines():
            if line == "changed in both":
                if section_has_marker and current_path:
                    hard_files.add(current_path)
                in_section = True
                current_path = None
                section_has_marker = False
                continue
            if not in_section:
                continue
            stripped = line.strip()
            m = _LEGACY_TRIPLE.match(stripped)
            if m:
                if current_path is None:
                    current_path = m.group(1)
                continue
            if "<<<<<<<" in line or ">>>>>>>" in line:
                section_has_marker = True
        if section_has_marker and current_path:
            hard_files.add(current_path)

    # Apply the always-ignore filter to the hard bucket so that single-
    # bookkeeping-file conflicts (pbxproj, Package.resolved, …) drop out
    # before line counting. The unfiltered set is preserved for --report
    # callers that pass apply_ignore_filter=False.
    if apply_ignore_filter:
        hard_files_kept = {p for p in hard_files if not _matches_always_ignore(p)}
    else:
        hard_files_kept = set(hard_files)

    if compute_soft:
        a_changed = set(_diff_names(base, a.name))
        b_changed = set(_diff_names(base, b.name))
        candidates = (a_changed & b_changed) - hard_files
        if apply_ignore_filter:
            soft_files = sorted(
                p for p in candidates if not _matches_always_ignore(p)
            )
        else:
            soft_files = sorted(candidates)
    else:
        soft_files = []

    # Cross-reference filter: only keep files BOTH branches actually
    # modify vs current main. Drops the false-positive class where a
    # branch's "change" was inherited via a merge-from-main (the file
    # genuinely changed in main, and the old pair-merge-base reports
    # that change as the branch's own).
    if apply_ignore_filter:
        a_vs_main = _branch_files_vs_main(a.name)
        b_vs_main = _branch_files_vs_main(b.name)
        hard_files_kept = {
            p for p in hard_files_kept
            if p in a_vs_main and p in b_vs_main
        }
        soft_files = [
            p for p in soft_files
            if p in a_vs_main and p in b_vs_main
        ]

    if not hard_files_kept and not soft_files:
        return None

    hard_lines = _count_conflict_lines_for_files(
        merged_tree_oid or "", sorted(hard_files_kept)
    ) if hard_files_kept else 0

    return ConflictPair(
        a=a,
        b=b,
        merge_base=base,
        hard_files=sorted(hard_files_kept),
        soft_files=soft_files,
        hard_conflict_lines=hard_lines,
        merged_tree_oid=merged_tree_oid or "",
    )


def _diff_names(base: str, ref: str) -> list[str]:
    proc = git(["diff", "--name-only", base, ref], check=False)
    if proc.returncode != 0:
        return []
    return [ln for ln in proc.stdout.splitlines() if ln.strip()]


_branch_files_vs_main_cache: dict[str, set[str]] = {}


def _branch_files_vs_main(branch: str) -> set[str]:
    """Set of files the branch added on top of its merge-base with main.

    Used by probe_pair to drop "false-positive via inheritance" conflicts:
    a branch whose apparent change to a file came from somewhere other
    than its own commits (either an explicit merge-from-main or — far
    more commonly — main moving ahead of the branch's base) shouldn't be
    pinged when that file conflicts with another branch's real edit.

    Uses three-dot (``main...branch``, == ``diff $(merge-base main
    branch)..branch``) deliberately. Two-dot would also include files
    where main moved past the branch's base — those show up in
    ``diff main..branch`` even though the branch contributed nothing to
    them, which re-introduces exactly the false positives this filter
    exists to drop. (Contrast with ``_is_merged_into_default``, which
    deliberately wants two-dot tip-tree semantics — see its docstring.)

    Cached per branch within a single run.
    """
    if branch in _branch_files_vs_main_cache:
        return _branch_files_vs_main_cache[branch]
    proc = git(["diff", "--name-only",
                f"{DEFAULT_BRANCH}...{branch}"], check=False)
    if proc.returncode != 0:
        files: set[str] = set()
    else:
        files = {ln.strip() for ln in proc.stdout.splitlines() if ln.strip()}
    _branch_files_vs_main_cache[branch] = files
    return files


# ---------------------------------------------------------------------------
# Asana client
# ---------------------------------------------------------------------------

class AsanaError(RuntimeError):
    pass


class ProbeError(RuntimeError):
    """Raised when ``probe_pair`` can't determine whether a pair
    conflicts due to a git error (no shared merge-base, unexpected
    ``merge-tree`` exit code, legacy ``merge-tree`` failure, …).

    Callers should treat this as "unknown — try again next run":
    ``main()`` skips the pair and records the failure in ``summary.errors``;
    ``sweep_existing_tasks`` leaves the existing Asana task open instead
    of auto-closing it.
    """
    pass


class AsanaClient:
    def __init__(self, pat: str, workspace_gid: str, project_gid: str,
                 dry_run: bool = False):
        self.pat = pat
        self.workspace_gid = workspace_gid
        self.project_gid = project_gid
        self.dry_run = dry_run

    def _request(self, method: str, path: str, *, params: Optional[dict] = None,
                 body: Optional[dict] = None) -> dict:
        url = f"{ASANA_BASE}{path}"
        if params:
            url = f"{url}?{urllib.parse.urlencode(params, doseq=True)}"
        data = None
        headers = {
            "Authorization": f"Bearer {self.pat}",
            "Accept": "application/json",
        }
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                payload = resp.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise AsanaError(f"{method} {path} -> {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise AsanaError(f"{method} {path} -> network error: {exc}") from exc
        if not payload:
            return {}
        try:
            return json.loads(payload)
        except json.JSONDecodeError as exc:
            raise AsanaError(f"{method} {path} -> non-JSON: {payload[:200]}") from exc

    def list_project_tasks_by_name(self, prefix: str = "") -> dict[str, dict]:
        """Return ``{name: task_dict}`` for tasks in the configured project.

        One paginated call covers the whole project (100 tasks per page),
        so dedup-lookup for a whole conflict-watch run is at most a handful
        of API calls regardless of how many conflict pairs we found. Filters
        by name prefix client-side to avoid pulling unrelated tasks into
        memory.
        """
        out: dict[str, dict] = {}
        offset: Optional[str] = None
        while True:
            params: dict = {
                "opt_fields": "name,completed,permalink_url",
                "limit": 100,
            }
            if offset:
                params["offset"] = offset
            data = self._request(
                "GET",
                f"/projects/{self.project_gid}/tasks",
                params=params,
            )
            for item in data.get("data", []):
                name = item.get("name", "")
                if name and (not prefix or name.startswith(prefix)):
                    out[name] = item
            next_page = data.get("next_page") or {}
            offset = next_page.get("offset")
            if not offset:
                break
        return out

    def create_task(self, name: str, html_notes: str) -> dict:
        if self.dry_run:
            logger.info("[dry-run] would create task: %s", name)
            return {"gid": "dry-run", "name": name, "permalink_url": ""}
        body = {
            "data": {
                "name": name,
                "html_notes": html_notes,
                "workspace": self.workspace_gid,
                "projects": [self.project_gid],
            }
        }
        data = self._request("POST", "/tasks", body=body)
        return data.get("data", {})

    def add_comment(self, task_gid: str, html_text: str,
                    plain_preview: str = "") -> None:
        if self.dry_run:
            logger.info("[dry-run] would comment on %s: %s",
                        task_gid, plain_preview[:80] or html_text[:80])
            return
        body = {"data": {"html_text": html_text}}
        self._request("POST", f"/tasks/{task_gid}/stories", body=body)

    def complete_task(self, task_gid: str) -> None:
        if self.dry_run:
            logger.info("[dry-run] would complete %s", task_gid)
            return
        body = {"data": {"completed": True}}
        self._request("PUT", f"/tasks/{task_gid}", body=body)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def asana_mention(b: Branch) -> str:
    """Asana rich-text mention if we have the user's gid; otherwise a
    plain-text label that won't notify.

    Honours ``CW_NO_MENTIONS=1`` by always returning a plain-text label —
    no Asana-mention HTML, no leading ``@`` — so the task body shows the
    author name as context but generates no inbox notification.
    """
    if NO_MENTIONS:
        return html_escape(b.author_name or b.github_login or b.author_email or "unknown")
    if b.asana_gid:
        return f'<a data-asana-gid="{html_escape(b.asana_gid)}"/>'
    if b.github_login:
        return f"@{html_escape(b.github_login)}"
    return html_escape(b.author_name or b.author_email or "unknown")


def _author_label(b: Branch) -> str:
    """Plain-text author label for the task description (no mentions —
    description is informational; the kickoff comment carries the
    notification)."""
    return html_escape(
        b.author_name or b.author_email or b.github_login or "unknown"
    )


def _branches_alpha(pair: ConflictPair) -> tuple[Branch, Branch]:
    """Return the pair's branches in alphabetical name order so the
    rendered task always matches the alphabetised title."""
    if pair.a.name <= pair.b.name:
        return pair.a, pair.b
    return pair.b, pair.a


def render_task_body_html(pair: ConflictPair, today_local: str) -> str:
    """Plain-English description for the conflict task.

    Lead sentence carries the action so the inbox preview is meaningful
    on its own; structured sections follow with branch tips, file list,
    GitHub compare link, and a detection footnote.
    """
    a_branch, b_branch = _branches_alpha(pair)
    compare_url = COMPARE_URL_TEMPLATE.format(a=a_branch.name, b=b_branch.name)
    n_files = len(pair.hard_files)
    n_lines = pair.hard_conflict_lines
    file_word = "file" if n_files == 1 else "files"

    parts: list[str] = ["<body>"]
    parts.append(
        f"<strong>{html_escape(a_branch.name)}</strong> and "
        f"<strong>{html_escape(b_branch.name)}</strong> both modify the same "
        f"lines in {n_files} {file_word} — {n_lines} conflict line"
        f"{'' if n_lines == 1 else 's'} total. "
        "Whoever lands first is fine; the other branch will need to rebase "
        "and resolve the overlap before merging."
    )
    parts.append("")

    parts.append("<strong>Branches</strong>")
    parts.append("<ul>")
    for b in (a_branch, b_branch):
        pr_segment = (
            f' (<a href="{html_escape(b.pr_url)}">PR</a>)'
            if b.pr_url else " (no open PR yet)"
        )
        parts.append(
            f"<li>{html_escape(b.name)} — last commit "
            f"<code>{html_escape(b.short_sha)}</code> by {_author_label(b)}"
            f"{pr_segment} on {html_escape(b.committer_iso)}</li>"
        )
    parts.append("</ul>")
    parts.append("")

    parts.append(f"<strong>Files in conflict ({n_files})</strong>")
    parts.append("<ul>")
    parts.extend(f"<li>{html_escape(p)}</li>" for p in pair.hard_files)
    parts.append("</ul>")
    parts.append("")

    parts.append(
        f'Compare on GitHub: <a href="{html_escape(compare_url)}">'
        f"{html_escape(a_branch.name)}...{html_escape(b_branch.name)}</a>"
    )
    parts.append("")
    parts.append(
        f"<em>Detected {html_escape(today_local)} by conflict-watch "
        "(runs daily at 07:00 CEST / 06:00 CET).</em>"
    )
    parts.append("</body>")
    return "\n".join(parts)


def render_creation_comment_html(pair: ConflictPair) -> str:
    """Kickoff comment posted right after task creation. Carries the
    @-mentions (so this is what fires the inbox notification) and a
    short next-steps prompt. In NO_MENTIONS mode the lead-in switches
    to plain author names and no notification fires.
    """
    a_branch, b_branch = _branches_alpha(pair)
    rest = (
        " — your branches are likely to conflict at merge. "
        "You can use this thread to coordinate."
    )
    if NO_MENTIONS:
        head = (
            f"Heads up {_author_label(a_branch)} and {_author_label(b_branch)}"
        )
    else:
        head = (
            f"Hey {asana_mention(a_branch)} {asana_mention(b_branch)}"
        )
    return f"<body>{head}{rest}</body>"


# ---------------------------------------------------------------------------
# Reconciliation
# ---------------------------------------------------------------------------

def reconcile(asana: AsanaClient, conflicts: list[ConflictPair],
              state: dict, summary: RunSummary) -> None:
    """Single-write-per-pair: each pair gets one Asana task (description
    + kickoff comment) on first detection. If the same pair surfaces
    again — open or closed — the run skips it. Avoids inbox spam at the
    cost of stale task bodies; teammates can complete a task and trust
    it won't be reopened.
    """
    today_local = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    today_utc = datetime.now(timezone.utc).isoformat()

    try:
        existing_index = asana.list_project_tasks_by_name(prefix=TITLE_PREFIX)
        logger.info("Prefetched %d existing %s tasks from Asana",
                    len(existing_index), TITLE_PREFIX)
    except AsanaError as exc:
        logger.warning("Failed to prefetch project tasks (%s); "
                       "treating all pairs as new (may create duplicates)", exc)
        existing_index = {}

    for pair in conflicts:
        title = pair.title_key
        existing = existing_index.get(title)

        if existing is not None:
            status = "completed" if existing.get("completed") else "open"
            summary.pairs_already_reported += 1
            logger.info(
                "Pair %s already has Asana task %s (status=%s); skipping",
                title, existing.get("gid", "?"), status,
            )
            continue

        if summary.tasks_created >= MAX_NEW_TASKS:
            summary.tasks_skipped_cap += 1
            logger.warning(
                "Hard cap of %d new tasks reached; skipping create for %s",
                MAX_NEW_TASKS, title,
            )
            continue

        body_html = render_task_body_html(pair, today_local)
        try:
            created = asana.create_task(title, body_html)
            gid = created.get("gid", "")
            logger.info("Created Asana task %s for %s", gid, title)
            summary.tasks_created += 1
            _record_state(state, title, pair, gid, "new", today_utc)
            # Kickoff comment carries the @-mentions (and therefore the
            # inbox notification + auto-follow). Without it, the task
            # would be silently created with no one notified.
            if gid and gid != "dry-run":
                comment_html = render_creation_comment_html(pair)
                asana.add_comment(gid, comment_html, plain_preview="")
        except AsanaError as exc:
            summary.errors.append(f"asana write failed for {title}: {exc}")


def _branch_from_ref(name: str) -> Optional[Branch]:
    """Build a minimal Branch object from a ref name.

    Used by the sweep to re-probe pairs against current tips. Only the
    ``name`` and ``sha`` fields are populated — author/committer
    metadata is not needed for probe_pair.
    """
    proc = git(["rev-parse", name], check=False)
    if proc.returncode != 0:
        return None
    sha = (proc.stdout or "").strip()
    if not sha:
        return None
    return Branch(name=name, sha=sha, committer_iso="",
                  author_name="", author_email="")


def sweep_existing_tasks(asana: AsanaClient, summary: RunSummary) -> None:
    """Auto-close open conflict-watch tasks whose underlying conflict no
    longer applies. Two close paths:

    1. **Merged**: at least one branch's most recent PR is MERGED. The
       merged branch is now in main; the other will conflict with main
       on its own merits, not with this now-merged peer.
    2. **Resolved**: neither branch has merged, but a fresh probe_pair
       on the current tips finds no conflict above threshold (e.g. the
       overlap was rebased away, or one branch's "conflict" was an
       inherited-from-main false positive that's now been corrected).

    Tasks that humans have already completed are left alone — human
    decision wins.
    """
    try:
        tasks = asana.list_project_tasks_by_name(prefix=TITLE_PREFIX)
    except AsanaError as exc:
        logger.warning("Sweep prefetch failed: %s", exc)
        return

    for title, task in tasks.items():
        if task.get("completed"):
            continue
        body = title[len(TITLE_PREFIX):].strip()
        if TITLE_SEP not in body:
            logger.debug("Sweep: skipping unparseable title %r", title)
            continue
        a_name, _, b_name = body.partition(TITLE_SEP)
        a_name, b_name = a_name.strip(), b_name.strip()
        if not a_name or not b_name:
            continue
        gid = task.get("gid", "")
        if not gid:
            continue

        # Path 1: did a branch merge?
        merged_branches: list[tuple[str, Optional[str]]] = []
        for name in (a_name, b_name):
            status = lookup_branch_pr_status(name)
            if status.most_recent_state == "MERGED":
                merged_branches.append((name, status.most_recent_merged_at))
        if merged_branches:
            merged_summary = ", ".join(
                f"<code>{html_escape(n)}</code> (merged "
                f"{html_escape(m or 'recently')})"
                for n, m in merged_branches
            )
            comment_html = (
                f"<body>Auto-closing — {merged_summary} merged since "
                "this task was created, so the conflict no longer needs "
                "coordination. Reopen if a new conflict surfaces.</body>"
            )
            try:
                asana.add_comment(gid, comment_html,
                                  plain_preview="auto-closing (merged)")
                asana.complete_task(gid)
                summary.tasks_auto_closed_merged += 1
                logger.info("Auto-closed Asana task %s for %s "
                            "(merged: %s)", gid, title,
                            ", ".join(n for n, _ in merged_branches))
            except AsanaError as exc:
                summary.errors.append(f"auto-close failed for {title}: {exc}")
            continue

        # Path 2: re-probe. If the pair no longer conflicts above the
        # noise threshold, close.
        a_branch = _branch_from_ref(a_name)
        b_branch = _branch_from_ref(b_name)
        if a_branch is None or b_branch is None:
            # One of the refs is gone from the mirror (e.g. branch
            # deleted but PR not merged). Leave for human cleanup.
            continue
        try:
            result = probe_pair(a_branch, b_branch,
                                compute_soft=INCLUDE_SOFT_CONFLICTS)
        except ProbeError as exc:
            # Can't determine whether the conflict still exists — leave
            # the task open rather than risk auto-closing a real one on
            # a transient git error.
            logger.warning("Sweep re-probe inconclusive for %s: %s",
                           title, exc)
            continue
        # Mirror the creation-path threshold guard: hard_conflict_lines
        # is meaningful only on modern git (>= 2.38) where merge-tree
        # writes a tree we can inspect. On legacy git the line count is
        # always 0, so without the merged_tree_oid check we'd auto-close
        # every legacy-detected hard-only conflict — even genuine ones.
        modern_path = bool(result is not None and result.merged_tree_oid)
        still_conflicts = (
            result is not None
            and (
                bool(result.soft_files)
                or (
                    bool(result.hard_files)
                    and (
                        not modern_path
                        or result.hard_conflict_lines >= MIN_CONFLICT_LINES
                    )
                )
            )
        )
        if still_conflicts:
            continue
        comment_html = (
            "<body>Auto-closing — a fresh check found no remaining "
            f"conflict between <code>{html_escape(a_name)}</code> and "
            f"<code>{html_escape(b_name)}</code>. The overlap may have "
            "been resolved by a rebase or refactor. Reopen if a new "
            "conflict surfaces.</body>"
        )
        try:
            asana.add_comment(gid, comment_html,
                              plain_preview="auto-closing (resolved)")
            asana.complete_task(gid)
            summary.tasks_auto_closed_resolved += 1
            logger.info("Auto-closed Asana task %s for %s (resolved)",
                        gid, title)
        except AsanaError as exc:
            summary.errors.append(f"auto-close failed for {title}: {exc}")


def _record_state(state: dict, title: str, pair: ConflictPair,
                  gid: str, status: str, now_iso: str) -> None:
    pairs = state.setdefault("pairs", {})
    entry = pairs.get(title) or {}
    entry["asanaTaskGid"] = gid
    entry["branches"] = sorted([pair.a.name, pair.b.name])
    entry.setdefault("firstSeen", now_iso)
    entry["lastSeen"] = now_iso
    entry["lastStatus"] = status
    pairs[title] = entry


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

def load_state() -> dict:
    if not STATE_PATH.exists():
        return {"version": 1, "pairs": {}}
    try:
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        logger.warning("State file %s was corrupt; starting fresh.", STATE_PATH)
        return {"version": 1, "pairs": {}}


def save_state(state: dict) -> None:
    state["lastRun"] = datetime.now(timezone.utc).isoformat()
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(STATE_PATH)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def run_self_test() -> int:
    """Build a temporary git repo with branches that hard-conflict on
    file X, soft-conflict on file Y, and soft-conflict on an ignored
    pbxproj file. Verify probe_pair classifies each correctly. Also
    exercise the user-map parser and merged-branch filter.
    """
    global MIRROR
    saved_mirror = MIRROR
    tmpdir = Path(tempfile.mkdtemp(prefix="conflict-watch-test-"))
    try:
        repo = tmpdir / "repo.git"
        wc = tmpdir / "wc"
        run(["git", "init", "--bare", str(repo)])
        run(["git", "init", str(wc)])
        run(["git", "-C", str(wc), "config", "user.email", "test@example.com"])
        run(["git", "-C", str(wc), "config", "user.name", "Tester"])
        run(["git", "-C", str(wc), "config", "commit.gpgsign", "false"])
        (wc / "X").write_text("line1\nline2\nline3\n")
        (wc / "Y").write_text("a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n")
        (wc / "App.pbxproj").write_text("a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n")
        run(["git", "-C", str(wc), "add", "X", "Y", "App.pbxproj"])
        run(["git", "-C", str(wc), "commit", "-m", "init"])
        run(["git", "-C", str(wc), "branch", "-M", "main"])
        run(["git", "-C", str(wc), "remote", "add", "origin", str(repo)])
        run(["git", "-C", str(wc), "push", "origin", "main"])

        # feature/hard1 / hard2: line2 of X — hard conflict
        run(["git", "-C", str(wc), "checkout", "-b", "feature/hard1"])
        (wc / "X").write_text("line1\nLINE-2-A\nline3\n")
        run(["git", "-C", str(wc), "commit", "-am", "hard1"])
        run(["git", "-C", str(wc), "push", "origin", "feature/hard1"])

        run(["git", "-C", str(wc), "checkout", "main"])
        run(["git", "-C", str(wc), "checkout", "-b", "feature/hard2"])
        (wc / "X").write_text("line1\nLINE-2-B\nline3\n")
        run(["git", "-C", str(wc), "commit", "-am", "hard2"])
        run(["git", "-C", str(wc), "push", "origin", "feature/hard2"])

        # feature/soft1 / soft2: top vs bottom of Y — soft conflict
        run(["git", "-C", str(wc), "checkout", "main"])
        run(["git", "-C", str(wc), "checkout", "-b", "feature/soft1"])
        (wc / "Y").write_text("a-NEW\nb\nc\nd\ne\nf\ng\nh\ni\nj\n")
        run(["git", "-C", str(wc), "commit", "-am", "soft1"])
        run(["git", "-C", str(wc), "push", "origin", "feature/soft1"])

        run(["git", "-C", str(wc), "checkout", "main"])
        run(["git", "-C", str(wc), "checkout", "-b", "feature/soft2"])
        (wc / "Y").write_text("a\nb\nc\nd\ne\nf\ng\nh\ni\nj-NEW\n")
        run(["git", "-C", str(wc), "commit", "-am", "soft2"])
        run(["git", "-C", str(wc), "push", "origin", "feature/soft2"])

        # feature/pbx1 / pbx2: pbxproj soft conflict — should be IGNORED
        run(["git", "-C", str(wc), "checkout", "main"])
        run(["git", "-C", str(wc), "checkout", "-b", "feature/pbx1"])
        (wc / "App.pbxproj").write_text("a-NEW\nb\nc\nd\ne\nf\ng\nh\ni\nj\n")
        run(["git", "-C", str(wc), "commit", "-am", "pbx1"])
        run(["git", "-C", str(wc), "push", "origin", "feature/pbx1"])

        run(["git", "-C", str(wc), "checkout", "main"])
        run(["git", "-C", str(wc), "checkout", "-b", "feature/pbx2"])
        (wc / "App.pbxproj").write_text("a\nb\nc\nd\ne\nf\ng\nh\ni\nj-NEW\n")
        run(["git", "-C", str(wc), "commit", "-am", "pbx2"])
        run(["git", "-C", str(wc), "push", "origin", "feature/pbx2"])

        MIRROR = repo  # type: ignore[assignment]
        branches = []
        for ref in ["feature/hard1", "feature/hard2", "feature/soft1",
                    "feature/soft2", "feature/pbx1", "feature/pbx2"]:
            sha = git(["rev-parse", ref]).stdout.strip()
            branches.append(Branch(ref, sha, "1970-01-01T00:00:00+00:00",
                                   "Tester", "test@example.com"))
        bymap = {b.name: b for b in branches}

        ok = True

        # hard1 vs hard2 → hard conflict on X
        result = probe_pair(bymap["feature/hard1"], bymap["feature/hard2"])
        if not result or "X" not in result.hard_files or result.soft_files:
            print(f"FAIL: hard1 vs hard2 → {result}")
            ok = False
        else:
            print("PASS: hard1 vs hard2 → hard conflict on X")

        # soft1 vs soft2 → soft conflict on Y
        result = probe_pair(bymap["feature/soft1"], bymap["feature/soft2"])
        if not result or result.hard_files or "Y" not in result.soft_files:
            print(f"FAIL: soft1 vs soft2 → {result}")
            ok = False
        else:
            print("PASS: soft1 vs soft2 → soft conflict on Y")

        # pbx1 vs pbx2 → soft conflict on App.pbxproj, but IGNORED → None
        result = probe_pair(bymap["feature/pbx1"], bymap["feature/pbx2"])
        if result is not None:
            print(f"FAIL: pbx1 vs pbx2 expected None (ignored), got {result}")
            ok = False
        else:
            print("PASS: pbx1 vs pbx2 → ignored by always-ignore filter")

        # _branch_files_vs_main must use three-dot semantics. Reproduce
        # the production false-positive class: a branch is created and
        # never touches X; main then moves ahead on X (some unrelated PR
        # lands). Two-dot would include X in the branch's "vs main"
        # set — since the branch is now behind main on X — and the
        # cross-reference filter in probe_pair would then keep X as a
        # conflict candidate against any branch that does edit X. The
        # filter must instead reflect only what the branch contributed.
        run(["git", "-C", str(wc), "checkout", "main"])
        run(["git", "-C", str(wc), "checkout", "-b", "feature/passive-on-X"])
        (wc / "Side").write_text("side\n")
        run(["git", "-C", str(wc), "add", "Side"])
        run(["git", "-C", str(wc), "commit", "-m", "passive: edit Side, not X"])
        run(["git", "-C", str(wc), "push", "origin", "feature/passive-on-X"])

        run(["git", "-C", str(wc), "checkout", "main"])
        (wc / "X").write_text("line1\nMAIN-MOVED-2\nline3\n")
        run(["git", "-C", str(wc), "commit", "-am", "main: PR edits X line 2"])
        run(["git", "-C", str(wc), "push", "origin", "main"])

        _branch_files_vs_main_cache.clear()
        passive_files = _branch_files_vs_main("feature/passive-on-X")
        if "X" in passive_files or "Side" not in passive_files:
            print(
                f"FAIL: _branch_files_vs_main(passive-on-X) → {passive_files} "
                "(expected Side present, X absent)"
            )
            ok = False
        else:
            print(
                "PASS: _branch_files_vs_main is three-dot — branch that "
                "didn't touch X stays out of X's vs-main set when main "
                "moves ahead"
            )

        # User-map parser
        sample = (
            "# comment\n"
            'octocat: "12345"\n'
            "monalisa: 67890\n"
            "  nested-key: 11111\n"  # indented => skip
            "broken_no_value:\n"
            "ok-name: 22222 # trailing comment\n"
        )
        parsed = parse_user_map(sample)
        if parsed != {"octocat": "12345", "monalisa": "67890", "ok-name": "22222"}:
            print(f"FAIL: parse_user_map → {parsed}")
            ok = False
        else:
            print("PASS: parse_user_map → flat mapping with comments + skips")

        # _matches_always_ignore against defaults
        cases = [
            ("App.pbxproj", True),
            ("Sub/Pkg.xcodeproj/project.xcworkspace/foo.xcworkspacedata", True),
            ("Package.resolved", True),
            ("ios/SubProj/Package.resolved", True),
            ("Sources/foo.swift", False),
            ("Generated/Strings.swift", True),
            ("Foo.generated.swift", True),
        ]
        for path, expected in cases:
            actual = _matches_always_ignore(path)
            if actual != expected:
                print(f"FAIL: always-ignore {path}: expected {expected}, got {actual}")
                ok = False
            else:
                print(f"PASS: always-ignore {path} → {actual}")

        return 0 if ok else 1
    finally:
        MIRROR = saved_mirror
        shutil.rmtree(tmpdir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--dry-run", action="store_true",
                        help="Skip all Asana writes; log what would happen.")
    parser.add_argument("--self-test", action="store_true",
                        help="Run synthetic-repo tests and exit.")
    parser.add_argument("--once", metavar="A..B",
                        help="Probe one pair (e.g. 'feature/x..feature/y') and exit.")
    parser.add_argument(
        "--report", action="store_true",
        help="Probe all pairs and print top files appearing in hard-/soft-"
             "conflict buckets. No Asana calls. Includes paths normally "
             "filtered by CW_ALWAYS_IGNORE so the filter can be tuned.",
    )
    parser.add_argument("--top", type=int, default=30,
                        help="Top-N entries to print in --report (default 30).")
    parser.add_argument("--verbose", action="store_true", help="Verbose logging.")
    return parser.parse_args()


def run_report(top_n: int) -> int:
    """Probe all pairs and print frequency of files appearing in conflict
    buckets. No Asana calls.
    """
    from collections import Counter

    try:
        refresh_mirror()
    except subprocess.CalledProcessError as exc:
        logger.error("Failed to refresh mirror: %s", exc)
        return 1

    summary = RunSummary()
    branches = list_active_branches(RECENCY_HOURS, summary)
    logger.info("Active branches in last %dh (post-merged-filter): %d",
                RECENCY_HOURS, len(branches))

    kept: list[Branch] = []
    for b in branches:
        b.github_login = lookup_github_login(b.sha)
        if b.github_login and b.github_login.lower() in BOT_AUTHORS:
            summary.branches_skipped_bot += 1
            continue
        kept.append(b)
    branches = kept

    pairs = list(itertools.combinations(branches, 2))
    logger.info("Probing %d pairs", len(pairs))

    hard_counts_kept: Counter = Counter()      # post-filter
    hard_counts_filtered: Counter = Counter()  # caught by ignore-list
    soft_counts_kept: Counter = Counter()
    soft_counts_filtered: Counter = Counter()
    pairs_with_hard_kept = 0
    pairs_with_soft_kept = 0
    line_buckets = [(0, 0), (1, 5), (6, 10), (11, 20), (21, 50), (51, 100),
                    (101, 10**9)]
    line_histogram: dict[tuple[int, int], int] = {b: 0 for b in line_buckets}

    for a, b in pairs:
        try:
            # Probe without the ignore-filter so we see what's getting
            # caught; we re-apply the filter client-side to bucket the
            # files into kept vs filtered.
            result = probe_pair(a, b, compute_soft=True,
                                apply_ignore_filter=False)
        except ProbeError as exc:
            logger.warning("probe failed for %s vs %s: %s",
                           a.name, b.name, exc)
            continue
        if result is None:
            continue
        kept_hard = [p for p in result.hard_files if not _matches_always_ignore(p)]
        filtered_hard = [p for p in result.hard_files if _matches_always_ignore(p)]
        kept_soft = [p for p in result.soft_files if not _matches_always_ignore(p)]
        filtered_soft = [p for p in result.soft_files if _matches_always_ignore(p)]

        if kept_hard:
            pairs_with_hard_kept += 1
            for f in kept_hard:
                hard_counts_kept[f] += 1
            # Re-count lines on the post-filter set so the histogram
            # reflects what the production filter would see.
            kept_lines = _count_conflict_lines_for_files(
                result.merged_tree_oid, kept_hard
            )
            for lo, hi in line_buckets:
                if lo <= kept_lines <= hi:
                    line_histogram[(lo, hi)] += 1
                    break
        for f in filtered_hard:
            hard_counts_filtered[f] += 1
        if kept_soft:
            pairs_with_soft_kept += 1
            for f in kept_soft:
                soft_counts_kept[f] += 1
        for f in filtered_soft:
            soft_counts_filtered[f] += 1

    print()
    print("=== conflict-watch report ===")
    print(f"Branches probed: {len(branches)}")
    print(f"Pairs probed: {len(pairs)}")
    print(f"Pairs with hard conflicts after always-ignore filter: "
          f"{pairs_with_hard_kept}")
    print(f"Pairs with soft conflicts after always-ignore filter: "
          f"{pairs_with_soft_kept}")
    print()
    print("Distribution of total conflict-region lines per kept-hard pair:")
    for (lo, hi), n in line_histogram.items():
        label = f"{lo}" if lo == hi else (
            f"{lo}-{hi}" if hi < 10**8 else f"{lo}+"
        )
        bar = "#" * min(n, 60)
        print(f"  {label:>8}  {n:5d}  {bar}")
    print()
    print(f"Top {top_n} hard-conflict files AFTER always-ignore filter "
          f"(real signal):")
    for f, c in hard_counts_kept.most_common(top_n):
        print(f"  {c:5d}  {f}")
    print()
    print(f"Top {top_n} hard-conflict files currently caught by ignore-list "
          f"(validation):")
    for f, c in hard_counts_filtered.most_common(top_n):
        print(f"  {c:5d}  {f}")
    print()
    print(f"Top {top_n} soft-conflict files AFTER always-ignore filter:")
    for f, c in soft_counts_kept.most_common(top_n):
        print(f"  {c:5d}  {f}")
    print()
    print(f"Top {top_n} soft-conflict files currently caught by ignore-list "
          f"(validation):")
    for f, c in soft_counts_filtered.most_common(top_n):
        print(f"  {c:5d}  {f}")
    return 0




def main() -> int:
    args = parse_args()
    load_config_env()
    setup_logging(args.verbose or os.environ.get("CW_VERBOSE", "") in ("1", "true"))

    if args.self_test:
        return run_self_test()

    if args.report:
        return run_report(args.top)

    dry_run = (
        args.dry_run
        or os.environ.get("CW_DRY_RUN", "").lower() in ("1", "true", "yes")
    )

    pat = os.environ.get("ASANA_PAT", "").strip()
    if not pat and not dry_run:
        logger.error("ASANA_PAT is not set (env or %s).", CONFIG_ENV)
        return 2
    asana = AsanaClient(pat or "missing", ASANA_WORKSPACE_GID,
                        ASANA_PROJECT_GID, dry_run=dry_run)

    summary = RunSummary()
    started = time.monotonic()

    try:
        refresh_mirror()
    except subprocess.CalledProcessError as exc:
        logger.error("Failed to refresh mirror: %s", exc)
        return 1

    if args.once:
        if ".." not in args.once:
            logger.error("--once expects 'A..B'")
            return 2
        a_name, b_name = args.once.split("..", 1)
        a_sha = git(["rev-parse", a_name]).stdout.strip()
        b_sha = git(["rev-parse", b_name]).stdout.strip()
        a = Branch(a_name, a_sha, "n/a", "n/a", "n/a")
        b = Branch(b_name, b_sha, "n/a", "n/a", "n/a")
        try:
            result = probe_pair(a, b)
        except ProbeError as exc:
            logger.error("probe failed: %s", exc)
            return 1
        print(json.dumps({
            "pair": [a_name, b_name],
            "has_conflicts": bool(result and result.has_conflicts),
            "hard_files": result.hard_files if result else [],
            "soft_files": result.soft_files if result else [],
        }, indent=2))
        return 0

    branches = list_active_branches(RECENCY_HOURS, summary)
    logger.info("Active branches in last %dh (post-merged-filter): %d",
                RECENCY_HOURS, len(branches))

    user_map = load_user_map()
    if user_map:
        logger.info("Loaded user map with %d entries", len(user_map))

    kept: list[Branch] = []
    for b in branches:
        b.github_login = lookup_github_login(b.sha)
        if b.github_login and b.github_login.lower() in BOT_AUTHORS:
            summary.branches_skipped_bot += 1
            logger.debug("Skipping bot branch: %s (%s)", b.name, b.github_login)
            continue
        if b.github_login and b.github_login in user_map:
            b.asana_gid = user_map[b.github_login]
        pr_status = lookup_branch_pr_status(b.name)
        # PR-state filter: if every PR for this branch is non-open, the
        # engineer isn't actively heading toward merge. Closes the
        # "PR merged but bare mirror is stale" race that produces
        # creation-time false positives.
        if pr_status.has_any_pr and not pr_status.has_open_pr:
            summary.branches_skipped_inactive_pr += 1
            logger.info("Skipping branch %s: most recent PR is %s "
                        "(no open PR)", b.name, pr_status.most_recent_state)
            continue
        b.pr_url = pr_status.open_pr_url
        kept.append(b)
    branches = kept
    summary.branches_checked = len(branches)

    state = load_state()
    conflicts: list[ConflictPair] = []
    pairs = list(itertools.combinations(branches, 2))
    summary.pairs_probed = len(pairs)
    for a, b in pairs:
        if time.monotonic() - started > TIME_BUDGET_S:
            summary.skipped_pairs.append(f"{a.name} ↔ {b.name}")
            continue
        # Same-author pairs aren't a coordination signal — the engineer
        # is rebasing their own branches and already knows. Skip before
        # the expensive merge-tree probe.
        if a.owner_key and a.owner_key == b.owner_key:
            summary.pairs_same_author += 1
            continue
        try:
            result = probe_pair(a, b, compute_soft=INCLUDE_SOFT_CONFLICTS)
        except ProbeError as exc:
            summary.errors.append(
                f"probe failed for {a.name} vs {b.name}: {exc}"
            )
            continue
        if result is None:
            continue
        # Line-count threshold: a pair whose only hard conflicts are tiny
        # (e.g. a 1-line Package.swift bump that survived the path
        # filter) is below the noise floor. Soft-only pairs aren't
        # subject to the threshold — they're either off entirely or
        # already a coordination signal regardless of size.
        #
        # Skip the filter on the legacy git path (< 2.38): line counting
        # requires a merged-tree OID from `merge-tree --write-tree`,
        # which legacy doesn't produce. Without that, hard_conflict_lines
        # is always 0 and the threshold would unconditionally drop every
        # hard-only pair on a CI runner that happens to have old git.
        if (result.hard_files
                and result.merged_tree_oid
                and result.hard_conflict_lines < MIN_CONFLICT_LINES
                and not result.soft_files):
            summary.pairs_below_line_threshold += 1
            continue
        if result.hard_files and result.soft_files:
            summary.pairs_with_both += 1
        elif result.hard_files:
            summary.pairs_with_hard_conflicts += 1
        elif result.soft_files:
            summary.pairs_with_soft_conflicts += 1
        # Log the kept pair + its conflict files so the artifact log
        # carries enough detail to inspect a run without cracking open
        # individual Asana tasks.
        logger.info(
            "PAIR %s ↔ %s | hard=%d (%d lines): %s | soft=%d: %s",
            a.name, b.name,
            len(result.hard_files), result.hard_conflict_lines,
            ", ".join(result.hard_files) if result.hard_files else "-",
            len(result.soft_files),
            ", ".join(result.soft_files) if result.soft_files else "-",
        )
        conflicts.append(result)

    conflicts.sort(key=lambda p: p.newer_tip_dt, reverse=True)

    logger.info("Conflict pairs found: %d", len(conflicts))
    if conflicts and not pat and dry_run:
        logger.info("Dry-run with no Asana PAT — listing only:")
        for pair in conflicts:
            logger.info("  %s  (hard=%d, soft=%d)", pair.title_key,
                        len(pair.hard_files), len(pair.soft_files))
    elif conflicts:
        reconcile(asana, conflicts, state, summary)

    # End-of-run sweep: auto-close tasks whose branches merged since
    # creation. Handles the race-after-creation case (e.g. a PR that
    # merged a few minutes after the task was opened — yesterday's task
    # closes on today's cron run).
    if not dry_run or pat:
        try:
            sweep_existing_tasks(asana, summary)
        except Exception as exc:  # pragma: no cover — defensive
            summary.errors.append(f"sweep failed: {exc}")

    save_state(state)

    print()
    print("=== conflict-watch summary ===")
    for k, v in asdict(summary).items():
        print(f"{k}: {v}")
    total_auto_closed = (
        summary.tasks_auto_closed_merged + summary.tasks_auto_closed_resolved
    )
    print(
        f"Conflict watch: {len(conflicts)} pairs found "
        f"({summary.tasks_created} new / "
        f"{summary.pairs_already_reported} already-reported / "
        f"{summary.tasks_skipped_cap} skipped-by-cap / "
        f"{total_auto_closed} auto-closed "
        f"[{summary.tasks_auto_closed_merged} merged + "
        f"{summary.tasks_auto_closed_resolved} resolved])"
    )
    return 0 if not summary.errors else 1


if __name__ == "__main__":
    sys.exit(main())
