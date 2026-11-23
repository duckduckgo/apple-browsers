#!/usr/bin/env python3
"""Write tool-report.md: every tool call the agent was denied, and every GitHub, git network or auto script call that
failed, each with what to change to fix it.

Usage: tool_report.py <result.json> <claude projects dir> <evidence dir>
Env: CHECKOUT_DIR, the checkout the agent ran in, for rules written with ./

Denials come from result.json's permission_denials. Failures are tool results marked as errors for gh, git push,
fetch and pull, and auto's node scripts. A failed xc build or test isn't listed: fixing those is the agent's job.
allowed-tools.txt and denied-tools.txt in the evidence dir say whether a denial was on purpose. The report goes to
evidence behind SSO; the log and GITHUB_OUTPUT get the count only
"""

import fnmatch
import glob
import json
import os
import re
import shlex
import sys

WORKFLOW = "`scripts/agent-worker/run_agent.sh` (`allow` or `deny`) on the agent-worker branch"
CUT = 400

# Why a rule is denied on purpose, by the start of the rule
WHY_DENIED = [
    ("Bash(gh pr merge", "Merging is a person's call. Branch protection on main also requires an approving review."),
    ("Bash(gh pr close", "Closing PRs is left to people."),
    ("Bash(gh pr review", "The agent doesn't approve or review its own PRs."),
    ("Bash(gh pr comment", "The agent replies on review threads through `gh api`, but doesn't post top-level comments."),
    ("Bash(gh ", "Only the gh commands for the agent's own PRs and their CI are allowed."),
    ("Bash(git config", "The git identity and credential helper are set by the worker."),
    ("Bash(git remote", "The agent pushes only to this repo's origin."),
    ("Bash(claude", "No nested Claude sessions."),
    ("Bash(codex", "Other models aren't available in the worker."),
    ("Bash(node", "This auto script needs credentials or network the worker doesn't give (Codex, dub), signs in "
                  "interactively, or would change setup."),
    ("Edit(./.claude", "The checkout's .claude holds scripts the agent runs."),
    ("Write(./.claude", "The checkout's .claude holds scripts the agent runs."),
    ("Edit(./.git", "The agent changes git state with git commands only."),
    ("Write(./.git", "The agent changes git state with git commands only."),
    ("Read(", "Credential files stay out of the agent's reach."),
    ("WebFetch", "The agent has no web access."),
    ("WebSearch", "The agent has no web access."),
]

# What a failure's error text points to
HINTS = [
    (r"GH013|[Rr]epository rule violations|[Rr]ule violations found",
     "A repository ruleset blocked the push. Ruleset 27679350 lets the agent's app push only to `agent/**`, so check "
     "the branch name. If the branch was right, check the ruleset's bypass list and Rule insights."),
    (r"refusing to allow a GitHub App to create or update workflow",
     "The change touches `.github/workflows/`, and the app has no Workflows permission on purpose. The agent "
     "shouldn't change workflows."),
    (r"AUTO_DEPENDENCIES_UNPREPARED|dependencies are not prepared",
     "auto's npm dependencies weren't prepared. Check that the `Set up auto plugin` step ran setup-deps without "
     "errors."),
    (r"Azure evidence|AADSTS|AuthorizationPermissionMismatch|ManagedIdentityCredential|WorkloadIdentityCredential",
     "auto's upload-evidence couldn't sign in to or write to auto's artifact storage. Check that the `Azure identity "
     "for auto` step ran and its refresher was still running (`azure_identity.sh`), that ARTIFACTS_CLIENT_ID's "
     "identity has a federated credential for the agent-worker environment, and that it can create blobs in the "
     "`auto` container."),
    (r"Resource not accessible by integration|HTTP 403",
     "The ddg-apple-agent-publish app is missing a permission for this call. Compare the call with the app's "
     "permissions (contents and pull requests write, checks, statuses read, actions write) and the `permissions` "
     "list in `scripts/agent-worker/github_token.sh`. Add it to both if the agent should be able to do this."),
    (r"Bad credentials|HTTP 401|[Aa]uthentication failed|token.*expired",
     "The token was missing or expired. Check that the `GitHub token for the agent` step ran and that its refresher "
     "was still running (`github_token.sh` mints a new token every 45 minutes)."),
    (r"could not read Username|terminal prompts disabled|Authentication required",
     "git found no credentials. Check the credential helper that `github_token.sh` writes to GITHUB_ENV "
     "(GIT_CONFIG_*) and that the step ran."),
    (r"[Cc]ould not resolve host|[Nn]etwork is unreachable|[Cc]onnection (refused|timed out|reset)",
     "A network failure on the runner. Rerun; if it keeps failing, check the runner's network."),
    (r"API rate limit|secondary rate limit",
     "GitHub rate limiting. Fewer polls or a later retry fixes it."),
    (r"non-fast-forward|fetch first|\[rejected\]",
     "The branch moved on GitHub. The agent should fetch and rebase its own branch, not force-push."),
    (r"no pull requests? found|could not resolve to a PullRequest",
     "The PR doesn't exist or isn't visible to the app."),
]


def text_of(content):
    if isinstance(content, list):
        return "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return content if isinstance(content, str) else json.dumps(content)


def describe(name, data):
    data = data if isinstance(data, dict) else {}
    if name == "Bash":
        return (data.get("command") or "").strip()
    for key in ("file_path", "path", "pattern", "url", "description"):
        if data.get(key):
            return f"{key}: {data[key]}"
    return json.dumps(data)[:CUT]


def rule_for(name, data):
    """The allow rule that would permit this call"""
    if name != "Bash":
        path = (data or {}).get("file_path") or ""
        return f"{name}({os.path.dirname(path)}/**)" if path and name in ("Edit", "Write", "Read") else name
    words = (data.get("command") or "").split()
    if words[:1] == ["node"] and len(words) > 1:
        return f"Bash(node {words[1]}:*)"
    depth = 3 if words[:1] in (["gh"], ["git"]) and len(words) > 2 and not words[2].startswith("-") else 2
    return f"Bash({' '.join(words[:depth])}:*)"


def parts(command):
    """The commands in a chain joined by &&, ||, ; or |, or None when it isn't a chain or can't be parsed"""
    try:
        lex = shlex.shlex(command, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        return None
    out, cur = [], []
    for t in tokens:
        if t in ("&&", "||", ";", "|", ";;", "&"):
            if cur:
                out.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        out.append(cur)
    return [" ".join(p) for p in out] if len(out) > 1 else None


def bash_allowed(command, allow):
    """Whether one command matches a Bash allow rule's prefix"""
    for rule in allow:
        if rule.startswith("Bash(") and command.startswith(rule[5:].split(":*")[0].rstrip(")").rstrip()):
            return True
    return False


def bash_fix(command, allow):
    """What to do about a denied Bash command that no deny rule names"""
    if re.match(r"\s*git\s+-C\s", command):
        return ("`git -C <path>` doesn't match the git rules, which start with the subcommand. The prompt asks the agent "
                "to run git from the repository directory. Nothing to change unless it keeps happening.")
    chain = parts(command)
    if chain:
        missing = [p for p in chain if not bash_allowed(p, allow)]
        if not missing:
            return ("A chained command whose parts are each allowed, so Claude Code likely couldn't split it, for example "
                    "because of a multi-line quoted argument. The prompt asks for one command per call. Nothing to change "
                    "unless it keeps happening.")
        names = sorted({p.split()[0] for p in missing})
        listed = ", ".join(f"`{n}`" for n in names) + (" isn't" if len(names) == 1 else " aren't")
        return (f"A chained command, and Claude Code checks each part on its own: {listed} allowed. The prompt asks "
                "the agent to run one command per call and to read files with the Read, Glob and Grep tools, so usually "
                "nothing needs to change. If the agent really needs one of those commands, add a rule for it to `allow`.")
    return None


def matching_deny(name, data, deny):
    """The deny rule this call hit, if any"""
    for rule in deny:
        tool, _, arg = rule.partition("(")
        arg = arg[:-1] if arg.endswith(")") else arg
        if tool != name:
            continue
        if not arg:
            return rule
        if name == "Bash":
            if (data.get("command") or "").strip().startswith(arg.split(":*")[0].rstrip()):
                return rule
            continue
        path = (data or {}).get("file_path") or (data or {}).get("path") or ""
        # Rules spell absolute paths with a leading //, home with ~, and the checkout with ./
        pattern = os.path.expanduser(arg[1:] if arg.startswith("//") else arg)
        if pattern.startswith("./"):
            # The checkout the agent ran in; without it, a ./ rule can't be matched
            checkout = os.environ.get("CHECKOUT_DIR", "")
            if not checkout:
                continue
            pattern = os.path.join(checkout, pattern[2:])
        if path and fnmatch.fnmatch(path, pattern):
            return rule
    return None


def why(rule):
    return next((reason for start, reason in WHY_DENIED if rule.startswith(start)), "Denied on purpose.")


def hint(error):
    return next((text for pattern, text in HINTS if re.search(pattern, error)),
                "No known cause. Read the full error in transcript.md and the run's log for this step.")


def network_call(name, data):
    if name != "Bash":
        return False
    cmd = (data or {}).get("command") or ""
    return bool(re.match(r"\s*(gh\s|git\s+(push|fetch|pull)\b|node\s+\S*/skills/)", cmd))


def sessions(projects, session):
    main = glob.glob(os.path.join(projects, "*", f"{session}.jsonl")) if session else []
    return main[:1] + sorted(glob.glob(os.path.join(projects, "*", session, "subagents", "*.jsonl"))) if main else []


def main():
    src, projects, evidence = sys.argv[1:4]
    try:
        with open(src) as f:
            result = json.load(f)
    except Exception:
        result = {}
    read = lambda name: open(os.path.join(evidence, name)).read() if os.path.isfile(os.path.join(evidence, name)) else ""
    deny = [r for r in re.split(r",(?=[A-Z])", read("denied-tools.txt")) if r]
    allow = [r for r in re.split(r",(?=[A-Z])", read("allowed-tools.txt")) if r]

    denials = list(result.get("permission_denials") or [])
    denied_ids = {d.get("tool_use_id") for d in denials}

    uses, failures = {}, []
    for path in sessions(projects, result.get("session_id") or ""):
        with open(path, errors="replace") as f:
            for line in f:
                try:
                    msg = json.loads(line).get("message") or {}
                except ValueError:
                    continue
                content = msg.get("content")
                for block in content if isinstance(content, list) else []:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "tool_use":
                        uses[block.get("id")] = (block.get("name"), block.get("input") or {})
                    elif block.get("type") == "tool_result" and block.get("is_error"):
                        tid = block.get("tool_use_id")
                        name, data = uses.get(tid, ("?", {}))
                        error = text_of(block.get("content"))
                        if tid in denied_ids:
                            continue
                        # Subagents' denials aren't in result.json, only in their sessions
                        if re.search(r"has been denied|haven't granted|[Pp]ermission to use .* denied", error):
                            denials.append({"tool_name": name, "tool_input": data, "tool_use_id": tid})
                            denied_ids.add(tid)
                        elif network_call(name, data):
                            failures.append((name, data, error))

    md = ["# Tool report", "",
          "Tool calls the agent was denied, and GitHub, git network and auto script calls that failed. Each says how to "
          f"fix it. The allow and deny lists are in {WORKFLOW}.", ""]
    md += ["## Denied", ""]
    if not denials:
        md += ["None.", ""]
    for d in denials:
        name, data = d.get("tool_name", "?"), d.get("tool_input") or {}
        md += [f"- **{name}**: `{describe(name, data)[:CUT]}`"]
        rule = matching_deny(name, data, deny)
        fix = bash_fix(data.get("command") or "", allow) if name == "Bash" and not rule else None
        covered = name in ("Edit", "Write", "Read") and not rule and matching_deny(name, data, allow)
        if fix:
            md += [f"  - {fix}"]
        elif covered:
            md += [f"  - `{covered}` allows this path, but it's outside the checkout, and Claude Code also needs its "
                   "directory in the `--add-dir` list in `run_agent.sh`. Add the directory there."]
        elif rule:
            md += [f"  - Denied on purpose by `{rule}`. {why(rule)} If the agent needed this, change the plan or the "
                   "prompt so it doesn't, or remove the rule from `deny` after checking with the team."]
        else:
            md += [f"  - Not in the allowlist. If the agent should be able to do this, add `{rule_for(name, data)}` to "
                   "`allow`. Check first that it doesn't need a credential or network the worker doesn't give."]
    md += ["", "## Failed", ""]
    if not failures:
        md += ["None.", ""]
    for name, data, error in failures:
        md += [f"- `{describe(name, data)[:CUT]}`", "", "  ```", *("  " + l for l in error.strip()[:CUT * 2].splitlines()),
               "  ```", "", f"  - {hint(error)}", ""]

    with open(os.path.join(evidence, "tool-report.md"), "w") as f:
        f.write("\n".join(md) + "\n")
    issues = len(denials) + len(failures)
    print(f"tool report: {len(denials)} denied, {len(failures)} failed")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"issues={issues}\n")


if __name__ == "__main__":
    main()
