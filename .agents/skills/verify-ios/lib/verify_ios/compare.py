"""`prove PROOF --base REF`: run one proof on the base revision and on this checkout, then judge each check against both.

Each check carries what it should do on the base build (`base`, set by `with ios.on_base(...)`: "fail", "pass", or
"unchanged" outside any block) and a `key`, its name without this run's tokens, so the two runs' checks line up.
The base revision is built and proved in its own worktree, so it gets its own simulators and build; the worktree is
removed afterwards. Both runs use this checkout's skill and the same proof, devices and video setting.
"""
import json, os, shlex, shutil, signal, subprocess, sys, time

from . import env, gallery, harness, page
from .device import Device
from .env import ROOT, SKILL, Failed, run

VERIFY_IOS = os.path.join(SKILL, "bin", "verify-ios")

# A row's judgement, and a device's verdict with its exit code (worst first).
AS_EXPECTED, UNEXPECTED, NOT_SHOWN = "as expected", "unexpected", "not shown"
VERDICT_CODES = (("CANCELLED", 130), ("INCONCLUSIVE", 2), ("UNEXPECTED", 1), ("AS EXPECTED", 0))


# ---------------------------------------------------------------- judging (pure)
def _by_key(checks):
    """{(key, occurrence): check}, in the order the run made them."""
    seen, out = {}, {}
    for c in checks:
        key = c.get("key", c["check"])
        seen[key] = seen.get(key, -1) + 1
        out[(key, seen[key])] = c
    return out


def judge(before_checks, after_checks):
    """One row per check of either run: what the base build should do, what each run did, and the judgement.
    Rows follow this checkout's order; checks only the base run made come last."""
    before, after = _by_key(before_checks), _by_key(after_checks)
    rows = []
    for k in list(after) + [k for k in before if k not in after]:
        b, a = before.get(k), after.get(k)
        expect = (a or b).get("base", "unchanged")
        was = None if b is None else ("pass" if b["ok"] else "fail")
        now = None if a is None else ("pass" if a["ok"] else "fail")
        if was is None or now is None:
            judged = NOT_SHOWN
        elif expect == "unchanged":
            judged = AS_EXPECTED if was == now else UNEXPECTED
        else:
            judged = AS_EXPECTED if was == expect else UNEXPECTED
        rows.append(dict(check=(a or b)["check"], base=expect, before=was or "not run", after=now or "not run",
                         judged=judged))
    return rows


def verdict(before, after, rows, capture_differs=()):
    """A device's verdict and why, from both runs' statuses, the judged rows and capture conditions that differ."""
    if "cancelled" in (before, after):
        return "CANCELLED", "a run was cancelled"
    if before not in ("pass", "fail"):
        return "INCONCLUSIVE", f"the base run did not finish ({before})"
    if after not in ("pass", "fail"):
        return "INCONCLUSIVE", f"this checkout's run did not finish ({after})"
    unexpected = [r["check"] for r in rows if r["judged"] == UNEXPECTED]
    if unexpected:
        return "UNEXPECTED", f"not what the proof declared for the base build: {unexpected}"
    if after != "pass":
        return "UNEXPECTED", "this checkout's run failed"
    if capture_differs:
        return "INCONCLUSIVE", f"capture conditions differ between the runs: {', '.join(capture_differs)}"
    hidden = [r["check"] for r in rows if r["judged"] == NOT_SHOWN]
    if hidden:
        return "INCONCLUSIVE", f"not observed on both runs: {hidden}"
    return "AS EXPECTED", None


def capture_differs(before, after):
    """Capture conditions (appearance, text size, orientation, status bar, language) that differ between two runs."""
    b, a = before or {}, after or {}
    return sorted(k for k in set(b) | set(a) if b.get(k) != a.get(k))


def exit_code(verdicts, problems=False):
    """cancelled 130 > inconclusive 2 > unexpected 1 > as expected 0; as expected with problems exits 2."""
    for v, code in VERDICT_CODES:
        if v in verdicts:
            return 2 if code == 0 and problems else code
    return 2


# ---------------------------------------------------------------- running
def prove_against_base(path, ref, devices=None, decision_log=None, evidence_dir=None, video=True):
    """Prove `path` on `ref` in its own worktree, then on this checkout, and write a comparison report.
    Returns (exit code, summary)."""
    mod, problems = harness.load(path)
    if problems:
        return 2, dict(proof=path, ok=False, preflight=problems)
    devices = harness.check_devices(devices or getattr(mod, "DEVICES", list(env.PORT_OFFSET)))
    try:   # before a base build that can take 20 minutes, so a stale build here fails fast
        Device.check_build_current()
    except Failed as e:
        return 2, dict(proof=path, ok=False, code="BUILD_NOT_CURRENT", message=str(e))
    resolved = run(["git", "-C", ROOT, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"])
    if resolved.returncode:
        return 2, dict(proof=path, ok=False, code="BAD_BASE", message=f"--base {ref!r} is not a commit")
    sha = resolved.stdout.strip()
    attempt = harness._new_attempt(f"{os.path.splitext(os.path.basename(path))[0]}-vs-base",
                                   harness.evidence_root(decision_log, evidence_dir))
    proof = shutil.copy2(path, f"{attempt}/proof.py")
    log, problems, started = f"{attempt}/base-run.log", [], time.strftime("%Y-%m-%dT%H:%M:%S%z")
    worktree = os.path.join(env.HOME, "base", sha[:12])   # outside the checkout; its basename keys its simulators
    before = after = None
    skipped, missing = dict(status="cancelled", reason="cancelled"), "error"
    old = harness._catch(harness._on_signal)
    try:
        before, why = _prove_base(worktree, sha, proof, devices, f"{attempt}/before", video, log, problems)
        if before:
            harness._restore(old)   # harness.prove handles its own signals
            code, out = harness.prove(proof, devices, evidence_dir=f"{attempt}/after", video=video)
            after, missing = out.get("evidence"), "cancelled" if code == 130 else "error"
        else:
            skipped = dict(status="error", reason=why)
    except harness._Stop:
        pass
    finally:
        harness._ignore_signals()   # first: a Ctrl-C now must not cut the worktree cleanup short
        try:
            problems += _remove_worktree(worktree, log)
        finally:
            harness._restore(old)
    devices_out = {}
    for dev in devices:
        b = _result(before, dev) if before else skipped
        a = _result(after, dev, missing) if after else dict(skipped, reason=f"not run: {skipped['reason']}")
        rows = judge(b.get("checks", []), a.get("checks", []))
        differs = capture_differs(b.get("capture"), a.get("capture")) if b.get("capture") and a.get("capture") else []
        v, why = verdict(b["status"], a["status"], rows, differs)
        devices_out[dev] = dict(verdict=v, reason=why, rows=rows, before=b, after=a, captureDiffers=differs)
    cmp = dict(proof="proof.py", base=dict(ref=ref, sha=sha), started=started, finished=time.strftime("%Y-%m-%dT%H:%M:%S%z"),
               before=_rel(before, attempt), after=_rel(after, attempt),
               devices={d: {k: v for k, v in o.items() if k not in ("before", "after")} for d, o in devices_out.items()},
               problems=problems,
               rerun=f"cd {shlex.quote(ROOT)} && " + shlex.join([VERIFY_IOS, "prove", proof, "--base", sha,
                                                               "--devices", ",".join(devices)]
                                                              + harness.evidence_args(decision_log, evidence_dir)
                                                              + ([] if video else ["--no-video"])))
    handlers = harness._ignore_signals()   # drawing takes seconds: a Ctrl-C now must not lose the report
    try:
        failed = gallery.compose(gallery.comparison_jobs(attempt, cmp["before"], cmp["after"], devices_out))
        problems += [f"could not draw {os.path.relpath(out, attempt)}: {why}" for out, why in sorted(failed.items())]
        try:
            text = page.comparison_page(mod, cmp, devices_out, attempt)
            with open(f"{attempt}/index.html", "w") as f:
                f.write(text)
        except Exception as e:
            problems.append(f"could not write index.html: {type(e).__name__}: {e}")
        with open(f"{attempt}/comparison.json", "w") as f:
            json.dump(cmp, f, indent=1)
        with open(f"{attempt}/report.md", "w") as f:
            f.write(report(mod, cmp, devices_out, attempt))
    finally:
        harness._restore(handlers)
    any_problems = problems or any(o[s].get("problems") for o in devices_out.values() for s in ("before", "after"))
    code = exit_code([o["verdict"] for o in devices_out.values()], bool(any_problems))
    return code, dict(proof=proof, evidence=attempt, report=f"{attempt}/report.md", base=sha,
                      devices={d: dict(verdict=o["verdict"], reason=o["reason"]) for d, o in devices_out.items()},
                      problems=problems)


def _prove_base(worktree, sha, proof, devices, evidence_dir, video, log, problems):
    """Add a worktree at `sha`, build it and prove there with this skill. Returns (attempt folder, None), or
    (None, why) when there is no base run to compare."""
    if os.path.isdir(worktree):   # left by a run that was killed: start clean
        problems += _remove_worktree(worktree, log)
    os.makedirs(os.path.dirname(worktree), exist_ok=True)
    if _step(["git", "-C", ROOT, "worktree", "add", "--detach", worktree, sha], ROOT, log)[0]:
        return None, "could not add the base worktree (see base-run.log)"
    code = _step([sys.executable, VERIFY_IOS, "build"], worktree, log)[0]
    if code:
        return None, f"the base build failed (exit {code}; see base-run.log)"
    code, out = _step([sys.executable, VERIFY_IOS, "--json", "prove", proof, "--devices", ",".join(devices),
                       "--evidence-dir", evidence_dir, "--as-base"] + ([] if video else ["--no-video"]), worktree, log)
    try:
        return json.loads(out)["proofs"][0]["evidence"], None
    except (ValueError, KeyError, IndexError, TypeError):
        return None, f"the base run left no evidence (exit {code}; see base-run.log)"


def _step(cmd, cwd, log, interruptible=True):
    """Run `cmd` in `cwd`, appending its command line and output to `log`; returns (exit code, stdout). The child is
    always waited for, so it can clean up its simulators: SIGTERM and SIGHUP are passed on to it (Ctrl-C from the terminal reaches it
    directly), and a signal raises harness._Stop once it has exited. Not `interruptible`: the child runs in its own
    session, out of reach of the terminal's Ctrl-C, and signals are ignored."""
    stopped = []

    def on_signal(signum, _frame):
        if signum != signal.SIGINT and not stopped:   # Ctrl-C reaches the child from the terminal by itself
            p.send_signal(signum)
        stopped.append(signum)
    with open(log, "a") as f:
        f.write(f"\n$ (cd {shlex.quote(cwd)} && {shlex.join(cmd)})\n")
        f.flush()
        p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=f, text=True,
                             start_new_session=not interruptible)
        old = harness._catch(on_signal) if interruptible else harness._ignore_signals()
        try:
            out, _ = p.communicate()
        finally:
            for s, h in old.items():
                signal.signal(s, h)
        f.write(f"{out}\n(exit {p.returncode})\n")
    if stopped:
        raise harness._Stop(signal.Signals(stopped[0]).name)
    return p.returncode, out


def _remove_worktree(worktree, log):
    """Delete the base worktree's simulators and the worktree (its build goes with it), ignoring signals from the
    first step to the last so it finishes. Returns problems. A worktree another `--base` run is using (its devices are
    busy) is left alone."""
    if not os.path.isdir(worktree):
        return []
    handlers, problems = harness._ignore_signals(), []
    try:
        code = _step([sys.executable, VERIFY_IOS, "cleanup", "--all", "--delete-sims"], worktree, log,
                     interruptible=False)[0]
        if code == env.EXIT_BUSY:
            return [f"the base worktree {worktree} is in use by another --base run: left in place"]
        if code:
            problems.append(f"could not clean up the base worktree's simulators (see base-run.log): {worktree}")
        # --force: the build leaves untracked files behind
        if _step(["git", "-C", ROOT, "worktree", "remove", "--force", worktree], ROOT, log, interruptible=False)[0]:
            problems.append(f"could not remove the base worktree {worktree} (see base-run.log)")
        return problems
    finally:
        harness._restore(handlers)


def _result(attempt, device, missing="error"):
    try:
        with open(f"{attempt}/{device}/result.json") as f:
            return json.load(f)
    except (OSError, ValueError):
        return dict(status=missing, reason="the run left no result for this device", checks=[])


def _rel(path, start):
    return os.path.relpath(path, start) if path else None


# ---------------------------------------------------------------- report
def report(mod, cmp, devices, attempt):
    """One scenario: what it verifies, Before | After key frames, each check judged against both runs, details."""
    doc = (mod.__doc__ or "").strip()
    before, after = cmp["before"], cmp["after"]
    lines = [f"# Before and after: {doc.splitlines()[0]}", "", "## Verified", "", doc, "",
             f"Before is the base build (`{cmp['base']['sha'][:12]}`, from `{cmp['base']['ref']}`); "
             "after is this checkout.", "", "## Evidence", "",
             "Paths are relative to this report. [index.html](index.html) shows the same evidence with the videos "
             "playing in the page.", ""]
    for dev, o in devices.items():
        lines += [f"### {dev}", ""]
        if os.path.isfile(os.path.join(attempt, gallery.before_after(dev))):
            lines += [f"Key frames, before above after: "
                      f"{harness.thumbnail(gallery.before_after(dev), f'Before and after on {dev}')}", ""]
        lines += ["| | Before | After |", "|---|---|---|",
                  f"| Video | {_video(attempt, before, dev, o['before'])} | {_video(attempt, after, dev, o['after'])} |"]
        lines += [f"| {_cell(name[:-4])} | {_frame(attempt, before, dev, name, 'Before')} | {_frame(attempt, after, dev, name, 'After')} |"
                  for name in gallery.matched_frames(*(gallery.key_frames(os.path.join(attempt, run, dev) if run else None,
                                                                          o[side].get("shots"))
                                                       for run, side in ((before, "before"), (after, "after"))))]
        lines.append("")
    lines += ["## Outcome", ""]
    for dev, o in devices.items():
        lines += [f"### {dev}: {o['verdict']}" + (f" ({o['reason']})" if o["reason"] else ""), "",
                  f"Base run: {_status(o['before'])}. This checkout: {_status(o['after'])}.", "",
                  "| Check | Base build should | Before | After | Judged |", "|---|---|---|---|---|"]
        lines += [f"| {_cell(r['check'])} | {r['base']} | {r['before']} | {r['after']} | {r['judged']} |" for r in o["rows"]]
        problems = [f"{side}: {p}" for side in ("before", "after") for p in o[side].get("problems") or []]
        if problems:
            lines += ["", "**Problems (cleanup or evidence):**"] + [f"- {p}" for p in problems]
        lines.append("")
    if cmp["problems"]:
        lines += ["**Problems (base worktree, images or page):**"] + [f"- {p}" for p in cmp["problems"]] + [""]
    lines += ["## Details", "",
              f"- Base run: [report]({before}/report.md)" if before else "- Base run: none ([log](base-run.log))",
              f"- This checkout: [report]({after}/report.md)" if after else "- This checkout: not run",
              "- The base revision was built and proved in its own worktree with this checkout's skill and proof, "
              "then removed ([log](base-run.log))"]
    lines += [f"- Capture conditions, {dev}: " + ("differ: " + ", ".join(o["captureDiffers"]) if o["captureDiffers"]
                                                 else "same on both runs") for dev, o in devices.items()]
    lines += [f"- Rerun: `{cmp['rerun']}`", "", "## Unverified", ""]
    unverified = [f"- {dev}: {u['what']}: {u['why']}" for dev, o in devices.items() for u in o["after"].get("unverified") or []]
    unverified += [f"- {dev}: {r['check']}: not observed on both runs" for dev, o in devices.items()
                   for r in o["rows"] if r["judged"] == NOT_SHOWN]
    lines += unverified or ["- (none)"]
    return "\n".join(lines) + "\n"


def _status(r):
    return r.get("status", "error").upper() + (f" ({r['reason']})" if r.get("reason") else "")


def _cell(text):
    return text.replace("|", "\\|").replace("\n", " ")


def _frame(attempt, run_dir, dev, name, label):
    rel = f"{run_dir}/{dev}/{name}"
    if not run_dir or not os.path.isfile(os.path.join(attempt, rel)):
        return "not captured"
    return harness.thumbnail(rel, f"{label}: {name[:-4]} on {dev}")


def _video(attempt, run_dir, dev, result):
    """The run's poster thumbnail (when drawn) and a Watch video link, both opening its recording."""
    if not run_dir or not result.get("video"):
        return "-"
    rel, poster = f"{run_dir}/{dev}/{result['video']}", f"{run_dir}/{dev}/{gallery.POSTER}"
    still = harness.thumbnail(poster, f"Recording on {dev}", rel) + " " if os.path.isfile(os.path.join(attempt, poster)) else ""
    return still + harness.watch(rel)
