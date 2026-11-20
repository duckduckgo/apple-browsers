"""`prove PROOF --base REF`: run one proof on the base revision, then on this checkout, and judge each check against both.

A check carries what it should do on the base build (`with mac.on_base("fail"):`, or "pass"; "unchanged" outside any
block). Both runs use this checkout's skill and proof, the same target, flags, CONDITIONS and video setting. Their
evidence is kept as `base/` and `change/` inside one attempt folder, next to the comparison's report.md and
manifest.json, so the folder uploads as one.

The base revision is checked out in a worktree under ~/.ddg-verify-macos/base/<sha12>, with its own DerivedData
inside (.build/, ignored by git). It is kept, so the next run on the same base only rebuilds incrementally, and it is
trusted only while it is clean at that commit: otherwise it is removed and added again. Each --base run removes the
others not used for STALE_DAYS, since the merge-base moves daily; `clean-base` removes them all.
"""
import copy
import json
import os
import re
import shutil
import subprocess
import time

import harness
from harness import HOME, ROOT, ProofError, Record, label

BASE_TREES = os.path.join(HOME, "base")
AS_DECLARED, UNEXPECTED, NOT_SHOWN = "as declared", "unexpected", "not shown"
BY_DESIGN = ["app under test", "output folder"]   # all that should differ between the two runs
LOCAL_PORT = re.compile(r"(127\.0\.0\.1|localhost|\[::1\]):\d+")   # the fixture's port is new every run
STALE_DAYS = 3   # longer than any run, so a base worktree another run is using is never removed under it


# ---------------------------------------------------------------- judging (pure)
def match_key(name, tokens):
    """A check's name with local ports and this run's tokens as placeholders: they differ between the two runs."""
    key = LOCAL_PORT.sub(r"\1:<port>", name)
    for token, prefix in tokens:
        key = key.replace(token, f"<token:{prefix}>")
    return key


def judge(base_checks, change_checks, tokens=()):
    """One row per check of either run, matched by name (`match_key`, with `tokens` the (token, prefix) pairs both
    runs issued) and occurrence, in this checkout's order (checks only the base run made come last): what the base
    build should do, what each run did, and whether that is as declared."""
    def keyed(checks):
        seen, out = {}, {}
        for c in checks:
            name = match_key(c[0], tokens)
            seen[name] = seen.get(name, -1) + 1
            out[(name, seen[name])] = c
        return out
    before, after = keyed(base_checks), keyed(change_checks)
    rows = []
    for k in list(after) + [k for k in before if k not in after]:
        b, a = before.get(k), after.get(k)
        expect = (a or b)[3]
        was = None if b is None else "pass" if b[1] else "fail"
        now = None if a is None else "pass" if a[1] else "fail"
        if was is None or now is None:
            judged = NOT_SHOWN
        else:
            judged = AS_DECLARED if was == (now if expect == "unchanged" else expect) else UNEXPECTED
        rows.append(dict(check=(a or b)[0], base=expect, before=was or "not run", after=now or "not run", judged=judged))
    return rows


def where(m):
    """The machine and macOS a run used, from its manifest."""
    vm = m.get("vm")
    return f"VM {vm.get('host')} (macOS {vm.get('macos')})" if vm else f"this Mac (macOS {m.get('macos') or '?'})"


def verdict(base, change, rows, differ=(), base_m=None, change_m=None):
    """(label, exit code, reason) for the pair. PASS only when this checkout passes and the base build did what the proof
    declared, including at least one check it declared to fail there (the bug), under the same conditions (`differ`
    names those that weren't: then the screenshots don't compare) and on the same macOS version."""
    if base.cancelled or (change and change.cancelled):
        return "INCONCLUSIVE", 130, "cancelled"
    if base_could_not_tell(base):
        return "INCONCLUSIVE", 2, f"the base run could not tell: {base.error or 'see base/report.md'}"
    if change is None or label(change)[0] == "INCONCLUSIVE":
        return "INCONCLUSIVE", 2, f"this checkout's run could not tell: {(change and change.error) or 'not run'}"
    if base_m and change_m and (base_m.get("vm") or base_m).get("macos") != (change_m.get("vm") or change_m).get("macos"):
        return "INCONCLUSIVE", 2, f"the runs used different macOS versions, so a check could flip because of the OS: " \
                                  f"before on {where(base_m)}, after on {where(change_m)}; pin one VM with --target vm-N"
    if differ:
        return "INCONCLUSIVE", 2, f"conditions differ between the runs: {', '.join(differ)}"
    missed = [r["check"] for r in rows if r["base"] == "fail" and r["before"] == "pass"]
    if missed:
        return "FAIL", 1, f"the proof doesn't reproduce the bug: expected to fail on the base build, passed: {missed}"
    unexpected = [r["check"] for r in rows if r["judged"] == UNEXPECTED]
    if unexpected:
        return "FAIL", 1, f"not what the proof declared for the base build: {unexpected}"
    if label(change)[0] == "FAIL":
        return "FAIL", 1, f"this checkout's run failed: {change.error or 'see change/report.md'}"
    if not any(r["base"] == "fail" for r in rows):
        return "INCONCLUSIVE", 2, "no check is declared with on_base(\"fail\"): nothing shows the bug on the base build"
    hidden = [r["check"] for r in rows if r["judged"] == NOT_SHOWN]
    if hidden:
        return "INCONCLUSIVE", 2, f"not observed on both runs: {hidden}"
    return "PASS", 2 if base.problems or change.problems else 0, None


def base_could_not_tell(base):
    """The base run's own label, with its declared failures (the bug) counted as passes so they can't hide a setup,
    action or read that failed."""
    declared = copy.copy(base)
    declared.checks = [(n, ok or b == "fail", d, b) for n, ok, d, b in base.checks]
    return label(declared)[0] == "INCONCLUSIVE"


def base_topic(topic):
    """verify.sh's topic for the base run: its own app name in the shared build products, 14 characters at most."""
    name, uid = topic.rsplit("-", 1)
    return f"b-{name[:7].strip('-')}-{uid}"


def _host(m):
    return (m.get("vm") or {}).get("host")


def between_runs(base_m, change_m):
    """What differs between the two runs' starts, from their manifests: the app under test and the output folder by
    design; anything else (another VM, a reset that failed or is missing, a condition) is named."""
    differ = list(BY_DESIGN)
    if _host(base_m) != _host(change_m):
        differ.append(f"VM: {_host(base_m) or 'this Mac'} then {_host(change_m) or 'this Mac'}")
    for side, m in (("before", base_m), ("after", change_m)):
        reset = m.get("reset")
        failed = [w for w, ok in (reset or {}).get("checks", {}).items() if not ok]
        if reset is None or failed:
            differ.append(f"start state {side}: " + ("not reset" if reset is None else "; ".join(failed) + " failed"))
    return differ + [f"condition {c}" for c in harness.conditions_differ(base_m, change_m)]


# ---------------------------------------------------------------- the base worktree
def _git(cwd, *args):
    return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)


def base_worktree(sha, root=ROOT, trees=BASE_TREES):
    """This repo at `sha` in a worktree kept for reuse, with its own DerivedData. A worktree left by an earlier run is
    trusted only when it is checked out at `sha` with nothing changed; otherwise it is removed and added again."""
    tree = os.path.join(trees, sha[:12])
    if os.path.isdir(tree):
        status = _git(tree, "status", "--porcelain")
        if _git(tree, "rev-parse", "HEAD").stdout.strip() == sha and status.returncode == 0 and not status.stdout.strip():
            os.utime(tree)   # last used, for prune_base
            return tree
        _remove(tree, root)
    os.makedirs(trees, exist_ok=True)
    p = _git(root, "worktree", "add", "--detach", tree, sha)
    if p.returncode:
        raise ProofError(f"git worktree add {sha[:12]} failed: {harness._line(p.stderr[-400:])}")
    os.makedirs(os.path.join(tree, ".build", "DerivedData"), exist_ok=True)   # verify.sh builds there: its own
    return tree


def _remove(tree, root=ROOT):
    _git(root, "worktree", "remove", "--force", tree)
    shutil.rmtree(tree, ignore_errors=True)
    _git(root, "worktree", "prune")


def prune_base(keep, root=ROOT, trees=BASE_TREES, now=None):
    """Remove the kept base worktrees other than `keep` not used for STALE_DAYS; each holds a full DerivedData. Returns
    the removed paths."""
    cutoff = (now or time.time()) - STALE_DAYS * 86400
    removed = [os.path.join(trees, d) for d in sorted(os.listdir(trees))
               if os.path.join(trees, d) != keep and _used(os.path.join(trees, d)) < cutoff]
    for tree in removed:
        _remove(tree, root)
    return removed


def _used(tree):
    try:
        return os.path.getmtime(tree)
    except OSError:   # another run removed it first
        return float("inf")


def clean_base(root=ROOT, trees=BASE_TREES):
    """Remove every kept base worktree and its DerivedData. Returns the removed paths."""
    removed = [os.path.join(trees, d) for d in sorted(os.listdir(trees))] if os.path.isdir(trees) else []
    for tree in removed:
        _remove(tree, root)
    return removed


# ---------------------------------------------------------------- running
def prove_base(path, ref, target, evidence_dir=None, video=True):
    """Prove `path` on `ref` in its kept worktree, then on this checkout; write the comparison. Returns (exit code,
    summary). Raises harness.Refused, before anything is written, for a bad --evidence-dir or a ref that isn't a commit."""
    root = harness.evidence_root(evidence_dir)
    mod, problems = harness.load(path)
    if problems:
        return 2, dict(proof=path, ok=False, problems=problems)
    if target not in harness.TARGETS:
        return 2, dict(proof=path, ok=False, problems=[f"--target must be one of {harness.TARGETS}"])
    resolved = _git(ROOT, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if resolved.returncode:
        raise harness.Refused(f"--base {ref!r} is not a commit")
    sha = resolved.stdout.strip()
    evidence, proof = harness.attempt_dir(path, root)
    shown_dir = root if evidence_dir else None
    topic = harness.topic_of(evidence)
    rerun = harness.rerun_command(proof, target, shown_dir, video) + f" --base {sha}"
    tree = change = change_m = None
    base_m, pruned = {}, []
    try:
        tree = base_worktree(sha)
        pruned = prune_base(tree)
    except (ProofError, KeyboardInterrupt) as e:
        base = Record()
        base.cancelled = isinstance(e, KeyboardInterrupt)
        base.error = f"setup: base worktree: {e or 'cancelled'}"
    else:
        os.makedirs(os.path.join(evidence, "base"))
        base, base_m = harness.run_one(mod, proof, os.path.join(evidence, "base"), base_topic(topic), target, video,
                                       tree, harness.rerun_command(proof, target, shown_dir, video, tree), shown_dir,
                                       as_base=True, reset=True)
    if not base_could_not_tell(base):
        os.makedirs(os.path.join(evidence, "change"))
        change, change_m = harness.run_one(mod, proof, os.path.join(evidence, "change"), topic, target, video, ROOT,
                                           rerun, shown_dir, reset=True, prefer_vm=_host(base_m))
    rows = judge(base.checks, change.checks if change else [], base.tokens + (change.tokens if change else []))
    differ = harness.conditions_differ(base_m, change_m) if base_m and change_m else []
    v, code, reason = verdict(base, change, rows, differ, base_m, change_m)
    manifest = dict(proof="proof.py", base=dict(ref=ref, sha=sha, worktree=tree, revision=base_m.get("revision"),
                                                unpinned_flags=base.unpinned, pruned=pruned),
                    change=dict(revision=(change_m or {}).get("revision"), dirty=(change_m or {}).get("dirty")),
                    before="base/manifest.json" if base_m else None, after="change/manifest.json" if change_m else None,
                    target=target, verdict=v, exit=code, reason=reason, rows=rows, rerun=rerun, conditions_differ=differ,
                    between_runs=between_runs(base_m, change_m) if change_m else None,
                    clean=f"{harness._sh_path(os.path.join(harness.SKILL, 'bin', 'verify-macos-browser'))} clean-base")
    with open(os.path.join(evidence, "manifest.json"), "w") as f:
        f.write(harness._tilde(json.dumps(manifest, indent=1)))
    with open(os.path.join(evidence, "report.md"), "w") as f:
        f.write(report(mod.__doc__.strip(), base, change, base_m, change_m or {}, manifest, evidence))
    return code, dict(ok=code == 0, verdict=v, reason=reason, base=sha, proof=proof, evidence=evidence,
                      report=os.path.join(evidence, "report.md"))


# ---------------------------------------------------------------- report
def report(doc, base, change, base_m, change_m, m, evidence):
    """report.md for prove --base: the evidence Before | After, each check judged against both runs, both revisions."""
    def rel(side, name):
        return f"{side}/{name}" if os.path.isfile(os.path.join(evidence, side, name)) else None

    def image(side, name, title):
        return f"![{title}: {name}]({rel(side, name)})" if rel(side, name) else "(none)"

    def link(side, name):
        return f"[{name}]({rel(side, name)})" if rel(side, name) else "(none)"

    shots = list(dict.fromkeys((change.shots if change else []) + base.shots)) + ["final.png"]
    sha, after_rev = m["base"]["sha"], m["change"]["revision"] or "?"
    lines = [f"# Before and after: {doc.splitlines()[0]}", "", "## Verified", "", doc, "",
             f"Before is the base revision `{sha[:12]}` (`{m['base']['ref']}`); after is this checkout "
             f"`{after_rev[:12]}`" + (" (uncommitted changes)" if m["change"]["dirty"] else "") + ".", "",
             "## Evidence", "", "Paths are relative to this report.", "", "| | Before | After |", "|---|---|---|",
             f"| Recording | {link('base', harness.VIDEO)} | {link('change', harness.VIDEO)} |"]
    lines += [f"| {name[:-4]} | {image('base', name, 'Before')} | {image('change', name, 'After')} |" for name in shots]
    lines += ["", f"Each run's own report: {link('base', 'report.md')} (before), {link('change', 'report.md')} (after).",
              "", "## Outcome", "", f"**{m['verdict']}**" + (f" ({harness._line(m['reason'])})" if m["reason"] else ""), "",
              "| Check | Base build should | Before | After | Judged |", "|---|---|---|---|---|"]
    lines += [f"| {r['check'].replace('|', '/')} | {r['base']} | {r['before']} | {r['after']} | {r['judged']} |"
              for r in m["rows"]] or ["| (no checks ran) | | | | |"]
    problems = [f"before: {p}" for p in base.problems] + [f"after: {p}" for p in (change.problems if change else [])]
    lines += ["", "Problems (cleanup or evidence):"] + [f"- {p}" for p in problems or ["(none)"]]
    if m.get("conditions_differ"):
        conditions = (f"**differ: {', '.join(m['conditions_differ'])}**; before {harness.conditions_line(base_m)}; "
                      f"after {harness.conditions_line(change_m)}")
    else:
        conditions = harness.conditions_line(change_m or base_m)
    lines += ["", "## Details", "",
              f"- Before: `{(m['base']['revision'] or sha)[:12]}`, built in {harness._tilde(m['base']['worktree'] or '(no worktree)')}"
              + (f", on {where(base_m)}" if base_m else ""),
              f"- After: `{after_rev[:12]}`" + (f", on {where(change_m)}" if change_m else ", not run"),
              f"- Pinned flags: {', '.join(change_m.get('flags') or base_m.get('flags') or []) or '(none)'}"
              + (f"; not pinned before, the base revision doesn't define {', '.join(base.unpinned)}" if base.unpinned else ""),
              f"- Conditions: {conditions}",
              "- Between the runs: " + ("only the app under test and the output folder differ; each run started from "
                                        "a reset (`reset` in each manifest)" if m.get("between_runs") == BY_DESIGN
                                        else f"**differ: {'; '.join(m.get('between_runs') or ['(after not run)'])}**"),
              f"- Rerun: `{m['rerun']}`",
              f"- The base worktree is kept for the next run on that revision; those not used for {STALE_DAYS} days are "
              f"removed" + (f" (this run: {', '.join(map(harness._tilde, m['base']['pruned']))})"
                            if m["base"].get("pruned") else "") + f"; remove them all: `{m['clean']}`",
              f"- Manifest: [manifest.json](manifest.json)", "", "## Unverified", ""]
    unverified = [f"- {w}: {y}" for w, y in (change.unverified if change else [])]
    unverified += [f"- {r['check']}: not observed on both runs" for r in m["rows"] if r["judged"] == NOT_SHOWN]
    lines += unverified or ["- (none)"]
    return harness._tilde("\n".join(lines) + "\n")
