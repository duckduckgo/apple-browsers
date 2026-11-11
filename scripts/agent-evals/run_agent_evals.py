#!/usr/bin/env python3
"""Runs coding-agent tasks with different versions of the agent instructions and grades the results.

Each case in cases/*.json is a small, real task plus deterministic graders. Every case runs in
each "arm":
  candidate  AGENTS.md/CLAUDE.md, skills and REVIEW files from your working tree
  base       the same files from --base (default origin/main)
  none       candidate files with every AGENTS.md/CLAUDE.md removed (skills stay)

Runs happen in a reusable scratch worktree with project settings only: no user CLAUDE.md, rules,
skills, memory or MCP servers. With ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN set, each run
also gets a fresh CLAUDE_CONFIG_DIR.

Usage:
  run_agent_evals.py [--case GLOB] [--arms candidate,base,none] [--reps 3] [--model sonnet]
                     [--base origin/main] [--max-cost-usd 20] [--workdir DIR] [--dry-run]
"""

import argparse
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR.parent / "agent-context-check"))
from agent_context_check import INSTRUCTION_NAMES, Tree  # noqa: E402

ARMS = ("candidate", "base", "none")
DEFAULT_ALLOWED_TOOLS = [
    "Read", "Grep", "Glob", "Edit", "Write", "Skill", "TodoWrite",
    "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)",
    "Bash(git grep:*)", "Bash(ls:*)", "Bash(find:*)", "Bash(grep:*)", "Bash(rg:*)",
    "Bash(cat:*)", "Bash(head:*)", "Bash(sed -n:*)", "Bash(wc:*)", "Bash(plutil -lint:*)",
    "Bash(python3 -c:*)", "Bash(mint run swiftlint:*)", "Bash(swiftlint:*)",
]
DISALLOWED_TOOLS = [
    "Bash(git push:*)", "Bash(gh:*)", "Bash(xcodebuild:*)", "Bash(swift build:*)",
    "Bash(swift test:*)", "WebFetch", "WebSearch", "Agent",
]


def git(*args, cwd, check=True):
    return subprocess.run(["git", *args], cwd=cwd, check=check, capture_output=True, text=True).stdout


# ---------------------------------------------------------------------------
# Transcript
# ---------------------------------------------------------------------------

@dataclass
class Transcript:
    tool_uses: list = field(default_factory=list)   # (name, input dict)
    result: dict = field(default_factory=dict)
    init: dict = field(default_factory=dict)

    @classmethod
    def parse(cls, lines):
        transcript = cls()
        for line in lines:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            kind = event.get("type")
            if kind == "system" and event.get("subtype") == "init":
                transcript.init = event
            elif kind == "assistant":
                for block in event.get("message", {}).get("content", []):
                    if isinstance(block, dict) and block.get("type") == "tool_use":
                        transcript.tool_uses.append((block.get("name"), block.get("input") or {}))
            elif kind == "result":
                transcript.result = event
        return transcript

    def skills_invoked(self):
        names = set()
        for name, args in self.tool_uses:
            if name == "Skill":
                names.add(str(args.get("skill", "")).lstrip("/"))
            elif name == "Read" and (m := re.search(r"\.claude/skills/([^/]+)/SKILL\.md$", str(args.get("file_path", "")))):
                names.add(m.group(1))
        return names

    def files_read(self):
        return [str(args.get("file_path", "")) for name, args in self.tool_uses if name == "Read"]

    def commands(self):
        return [str(args.get("command", "")) for name, args in self.tool_uses if name == "Bash"]


# ---------------------------------------------------------------------------
# Grading
# ---------------------------------------------------------------------------

def added_lines(diff, path_glob):
    """Added lines per file from a unified diff, limited to files matching path_glob."""
    lines, current = [], None
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[4:].removeprefix("b/")
            current = path if fnmatch.fnmatch(path, path_glob) else None
        elif current and line.startswith("+") and not line.startswith("+++"):
            lines.append(line[1:])
    return "\n".join(lines)


def changed_files(diff):
    files = []
    for line in diff.splitlines():
        if m := re.match(r"^diff --git a/(.+) b/(.+)$", line):
            files += [m.group(1)] if m.group(1) == m.group(2) else [m.group(1), m.group(2)]
    return files


def grade(grader, transcript, diff):
    """Returns (passed, detail) for one grader."""
    kind = grader["type"]
    if kind == "diff_contains":
        text = added_lines(diff, grader.get("path", "*"))
        return re.search(grader["pattern"], text) is not None, f"/{grader['pattern']}/ in added lines of {grader.get('path', '*')}"
    if kind == "diff_not_contains":
        text = added_lines(diff, grader.get("path", "*"))
        return re.search(grader["pattern"], text) is None, f"no /{grader['pattern']}/ in added lines of {grader.get('path', '*')}"
    if kind == "file_changed":
        files = changed_files(diff)
        return any(fnmatch.fnmatch(f, grader["path"]) for f in files), f"{grader['path']} changed"
    if kind == "no_changes":
        return diff.strip() == "", "no files changed"
    if kind == "skill_invoked":
        return grader["skill"] in transcript.skills_invoked(), f"skill {grader['skill']} used"
    if kind == "skill_not_invoked":
        return grader["skill"] not in transcript.skills_invoked(), f"skill {grader['skill']} not used"
    if kind == "file_read":
        return any(re.search(grader["pattern"], p) for p in transcript.files_read()), f"read /{grader['pattern']}/"
    if kind == "file_not_read":
        return not any(re.search(grader["pattern"], p) for p in transcript.files_read()), f"didn't read /{grader['pattern']}/"
    if kind == "command_run":
        return any(re.search(grader["pattern"], c) for c in transcript.commands()), f"ran /{grader['pattern']}/"
    raise ValueError(f"unknown grader type {kind}")


# ---------------------------------------------------------------------------
# Worktree and arms
# ---------------------------------------------------------------------------

class Workspace:
    """A reusable detached worktree, reset to the case commit before every run."""

    def __init__(self, repo, path):
        self.repo, self.path = repo, path

    def ensure(self, commit):
        if not (self.path / ".git").exists():
            self.path.parent.mkdir(parents=True, exist_ok=True)
            git("worktree", "add", "--detach", "-q", str(self.path), commit, cwd=self.repo)

    def reset(self, commit):
        git("checkout", "-q", "--detach", "--force", commit, cwd=self.path)
        git("reset", "-q", "--hard", commit, cwd=self.path)
        git("clean", "-q", "-fd", cwd=self.path)

    def apply_context(self, tree):
        """Makes the worktree's context files exactly `tree`, then commits so the run's diff excludes them."""
        current = Tree(self.path).load()
        for path in set(current.files) | set(current.symlinks):
            if path not in tree.files and path not in tree.symlinks:
                (self.path / path).unlink()
        for path, text in tree.files.items():
            target = self.path / path
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.is_symlink():
                target.unlink()
            target.write_text(text, encoding="utf-8")
        for path, link in tree.symlinks.items():
            target = self.path / path
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.is_symlink() or target.exists():
                target.unlink()
            os.symlink(link, target)
        git("add", "-A", cwd=self.path)
        git("-c", "user.name=agent-evals", "-c", "user.email=agent-evals@localhost",
            "commit", "-q", "--no-verify", "--allow-empty", "-m", "eval arm", cwd=self.path)
        return git("rev-parse", "HEAD", cwd=self.path).strip()

    def diff_since(self, commit):
        git("add", "-A", cwd=self.path)
        return git("diff", "--cached", commit, cwd=self.path)


def arm_tree(arm, repo, base_ref):
    if arm == "base":
        return Tree(repo, base_ref).load()
    tree = Tree(repo).load()
    if arm == "none":
        tree.files = {p: t for p, t in tree.files.items() if Path(p).name not in INSTRUCTION_NAMES}
        tree.symlinks = {p: t for p, t in tree.symlinks.items() if Path(p).name not in INSTRUCTION_NAMES}
    return tree


# ---------------------------------------------------------------------------
# Running
# ---------------------------------------------------------------------------

def claude_command(case, model):
    return [
        "claude", "-p", case["prompt"],
        "--output-format", "stream-json", "--verbose",
        "--max-turns", str(case.get("max_turns", 30)),
        "--model", model,
        "--setting-sources", "project",
        "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
        "--allowedTools", *case.get("allowed_tools", DEFAULT_ALLOWED_TOOLS),
        "--disallowedTools", *DISALLOWED_TOOLS,
    ]


def run_once(case, model, workspace, out_path):
    env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE_CODE_SESSION")}
    env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    config_dir = None
    if env.get("ANTHROPIC_API_KEY") or env.get("CLAUDE_CODE_OAUTH_TOKEN"):
        config_dir = tempfile.mkdtemp(prefix="agent-evals-config-")
        env["CLAUDE_CONFIG_DIR"] = config_dir
    started = time.time()
    try:
        proc = subprocess.run(claude_command(case, model), cwd=workspace.path, env=env,
                              capture_output=True, text=True,
                              timeout=case.get("timeout_seconds", 900))
        output, timed_out = proc.stdout, False
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or ""
        output, timed_out = partial.decode() if isinstance(partial, bytes) else partial, True
    finally:
        if config_dir:
            shutil.rmtree(config_dir, ignore_errors=True)
    out_path.write_text(output, encoding="utf-8")
    transcript = Transcript.parse(output.splitlines())
    return transcript, timed_out, time.time() - started


def isolation_problems(transcript):
    problems = []
    if transcript.init.get("mcp_servers"):
        problems.append("MCP servers loaded")
    if any(p for p in (transcript.init.get("plugins") or []) if p.get("path") != "builtin"):
        problems.append("user plugins loaded")
    if (transcript.init.get("memory_paths") or {}).get("auto"):
        problems.append("auto-memory loaded")
    return problems


def load_cases(pattern):
    cases = []
    for path in sorted((SCRIPT_DIR / "cases").glob("*.json")):
        case = json.loads(path.read_text(encoding="utf-8"))
        case.setdefault("id", path.stem)
        if fnmatch.fnmatch(case["id"], pattern):
            cases.append(case)
    return cases


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def summarize(runs, arms):
    by = {}
    for run in runs:
        by.setdefault((run["case"], run["arm"]), []).append(run)

    def stats(items):
        n = len(items)
        passed = sum(1 for r in items if r["passed"])
        mean = lambda key: sum(r[key] for r in items) / n if n else 0  # noqa: E731
        return passed, n, mean("cost_usd"), mean("turns"), mean("input_tokens")

    out = ["# Agent instruction evals", ""]
    out += ["| Case | " + " | ".join(arms) + " |", "|---|" + "---|" * len(arms)]
    for case in sorted({r["case"] for r in runs}):
        cells = []
        for arm in arms:
            items = by.get((case, arm), [])
            if not items:
                cells.append("–")
                continue
            passed, n, cost, turns, _ = stats(items)
            cells.append(f"{passed}/{n} · ${cost:.2f} · {turns:.0f} turns")
        out.append(f"| {case} | " + " | ".join(cells) + " |")

    out += ["", "| Arm | Pass rate | Mean cost | Mean turns | Mean input tokens |", "|---|---:|---:|---:|---:|"]
    for arm in arms:
        items = [r for r in runs if r["arm"] == arm]
        if items:
            passed, n, cost, turns, tokens = stats(items)
            out.append(f"| {arm} | {passed}/{n} ({100 * passed / n:.0f}%) | ${cost:.2f} | {turns:.1f} | {tokens:,.0f} |")

    out += ["", "## Checks", "", "| Case | Check | " + " | ".join(arms) + " |", "|---|---|" + "---:|" * len(arms)]
    for case in sorted({r["case"] for r in runs}):
        details = list(dict.fromkeys(g["detail"] for r in runs if r["case"] == case for g in r["graders"]))
        for detail in details:
            cells = []
            for arm in arms:
                results = [g["passed"] for r in by.get((case, arm), []) for g in r["graders"] if g["detail"] == detail]
                cells.append(f"{sum(results)}/{len(results)}" if results else "–")
            out.append(f"| {case} | {detail.replace('|', chr(92) + '|')} | " + " | ".join(cells) + " |")

    failures = [r for r in runs if not r["passed"]]
    if failures:
        out += ["", "## Failed graders", ""]
        for r in failures:
            missed = "; ".join(g["detail"] for g in r["graders"] if not g["passed"]) or r.get("error", "")
            out.append(f"- {r['case']} / {r['arm']} #{r['rep']}: {missed}")
    return "\n".join(out) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--case", default="*", help="glob over case ids")
    parser.add_argument("--arms", default=",".join(ARMS))
    parser.add_argument("--reps", type=int, default=3)
    parser.add_argument("--model", default="sonnet")
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--commit", default="HEAD", help="commit the tasks start from")
    parser.add_argument("--max-cost-usd", type=float, default=20.0)
    parser.add_argument("--workdir", default=str(Path(tempfile.gettempdir()) / "ddg-agent-evals"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    repo = Path(git("rev-parse", "--show-toplevel", cwd=Path.cwd()).strip())
    arms = [a for a in args.arms.split(",") if a]
    if unknown := set(arms) - set(ARMS):
        parser.error(f"unknown arms: {', '.join(sorted(unknown))}")
    cases = load_cases(args.case)
    if not cases:
        parser.error(f"no cases match {args.case}")
    commit = git("rev-parse", args.commit, cwd=repo).strip()

    plan = [(case, arm, rep) for case in cases for arm in arms for rep in range(1, args.reps + 1)]
    print(f"{len(plan)} runs: {len(cases)} cases × {len(arms)} arms × {args.reps} reps, model {args.model}, "
          f"start {commit[:10]}, base {args.base}, cost cap ${args.max_cost_usd:.2f}")
    if args.dry_run:
        for case, arm, rep in plan:
            print(f"  {case['id']} / {arm} #{rep}")
        return 0

    workdir = Path(args.workdir)
    results_dir = workdir / "results" / time.strftime("%Y%m%d-%H%M%S")
    results_dir.mkdir(parents=True, exist_ok=True)
    workspace = Workspace(repo, workdir / "worktree")
    workspace.ensure(commit)
    trees = {arm: arm_tree(arm, repo, args.base) for arm in arms}

    runs, spent = [], 0.0
    for index, (case, arm, rep) in enumerate(plan, 1):
        if spent >= args.max_cost_usd:
            print(f"Stopping: spent ${spent:.2f}, cap ${args.max_cost_usd:.2f}")
            break
        start = case.get("commit", commit)
        workspace.reset(start)
        arm_commit = workspace.apply_context(trees[arm])
        transcript, timed_out, seconds = run_once(case, args.model, workspace,
                                                  results_dir / f"{case['id']}-{arm}-{rep}.jsonl")
        diff = workspace.diff_since(arm_commit)
        (results_dir / f"{case['id']}-{arm}-{rep}.diff").write_text(diff, encoding="utf-8")

        graded = [{"detail": d, "passed": p} for p, d in (grade(g, transcript, diff) for g in case["graders"])]
        result = transcript.result
        usage = result.get("usage") or {}
        error = ("timed out" if timed_out else
                 "; ".join(isolation_problems(transcript)) or
                 (result.get("result", "") if result.get("is_error") else "") or
                 ("no result event" if not result else ""))
        run = {
            "case": case["id"], "arm": arm, "rep": rep,
            "passed": not error and all(g["passed"] for g in graded),
            "graders": graded, "error": error,
            "cost_usd": result.get("total_cost_usd") or 0.0,
            "turns": result.get("num_turns") or 0,
            "input_tokens": (usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0)
                             + usage.get("cache_creation_input_tokens", 0)),
            "output_tokens": usage.get("output_tokens", 0),
            "stop": result.get("subtype", ""), "seconds": round(seconds),
            "skills": sorted(transcript.skills_invoked()),
        }
        runs.append(run)
        spent += run["cost_usd"]
        status = "pass" if run["passed"] else "FAIL"
        print(f"[{index}/{len(plan)}] {case['id']} / {arm} #{rep}: {status} "
              f"${run['cost_usd']:.2f} {run['turns']} turns {run['seconds']}s"
              + (f" ({error})" if error else ""))

    (results_dir / "runs.json").write_text(json.dumps(runs, indent=2), encoding="utf-8")
    report = summarize(runs, arms)
    (results_dir / "report.md").write_text(report, encoding="utf-8")
    print("\n" + report)
    print(f"Transcripts, diffs and report: {results_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
