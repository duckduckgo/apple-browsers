"""Tests for prove --base's pure parts: base expectations, the combined verdict, report.md and the kept base worktree.
No app, build or VM. Run: python3 -I -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import os
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "scripts"))
import base  # noqa: E402
import harness  # noqa: E402


def run(checks, app_running=True, error=None, problems=(), cancelled=False):
    """A finished run's record; checks are (name, ok, base)."""
    rec = harness.Record()
    rec.checks = [(name, ok, None, expect) for name, ok, expect in checks]
    rec.app_running, rec.error, rec.problems, rec.cancelled = app_running, error, list(problems), cancelled
    return rec


def pair(before, after, **kw):
    """(label, exit code, reason) for a base run and a change run."""
    b, a = run(before, **kw), run(after)
    return base.verdict(b, a, base.judge(b.checks, a.checks))


BUG = ("menu shows New Verify Window", False, "fail")
FIXED = ("menu shows New Verify Window", True, "fail")
SETUP = ("1 tab(s) open", True, "unchanged")


class VerdictTests(unittest.TestCase):
    def test_bug_on_base_and_fix_here_passes(self):
        self.assertEqual(pair([SETUP, BUG], [SETUP, FIXED]), ("PASS", 0, None))

    def test_a_fail_expected_check_that_passes_on_base_fails_the_pair(self):
        verdict, code, reason = pair([SETUP, FIXED], [SETUP, FIXED])
        self.assertEqual((verdict, code), ("FAIL", 1))
        self.assertIn("doesn't reproduce the bug", reason)

    def test_a_base_setup_failure_is_inconclusive_and_needs_no_change_run(self):
        b = run([], app_running=None, error="setup: build: exit 1")
        self.assertEqual(base.verdict(b, None, base.judge(b.checks, []))[:2], ("INCONCLUSIVE", 2))

    def test_a_base_run_that_could_not_tell_is_inconclusive_whatever_this_checkout_did(self):
        verdict, code, reason = pair([SETUP, BUG], [SETUP, FIXED], app_running=None)   # e.g. ssh dropped at the end
        self.assertEqual((verdict, code), ("INCONCLUSIVE", 2))
        self.assertIn("base run", reason)

    def test_an_unchanged_check_that_differs_on_base_fails(self):
        verdict, code, reason = pair([("1 tab(s) open", False, "unchanged"), BUG], [SETUP, FIXED])
        self.assertEqual((verdict, code), ("FAIL", 1))
        self.assertIn("not what the proof declared", reason)

    def test_this_checkout_failing_fails(self):
        b, a = run([SETUP, BUG]), run([SETUP, BUG], error="proof: check failed: menu")
        self.assertEqual(base.verdict(b, a, base.judge(b.checks, a.checks))[:2], ("FAIL", 1))

    def test_no_check_declared_to_fail_on_base_is_inconclusive(self):
        verdict, code, reason = pair([SETUP], [SETUP])
        self.assertEqual((verdict, code), ("INCONCLUSIVE", 2))
        self.assertIn('on_base("fail")', reason)

    def test_a_check_seen_on_one_run_only_is_inconclusive(self):
        verdict, _, reason = pair([BUG], [SETUP, FIXED])
        self.assertEqual(verdict, "INCONCLUSIVE")
        self.assertIn("not observed on both runs", reason)

    def test_cancelled_exits_130(self):
        self.assertEqual(pair([SETUP, BUG], [SETUP, FIXED], cancelled=True)[:2], ("INCONCLUSIVE", 130))

    def test_a_pass_with_problems_on_either_run_exits_2(self):
        self.assertEqual(pair([SETUP, BUG], [SETUP, FIXED], problems=["VM not released"])[:2], ("PASS", 2))


    def test_runs_on_different_macos_versions_are_inconclusive_and_name_both(self):
        b, a = run([SETUP, BUG]), run([SETUP, FIXED])
        rows = base.judge(b.checks, a.checks)
        on = lambda host, macos: dict(vm=dict(host=host, macos=macos))   # noqa: E731
        verdict, code, reason = base.verdict(b, a, rows, base_m=on("vm-1", "15.5"), change_m=on("vm-2", "26.1"))
        self.assertEqual((verdict, code), ("INCONCLUSIVE", 2))
        self.assertIn("VM vm-1 (macOS 15.5)", reason)
        self.assertIn("VM vm-2 (macOS 26.1)", reason)
        self.assertEqual(base.verdict(b, a, rows, base_m=on("vm-1", "26.1"), change_m=on("vm-2", "26.1")), ("PASS", 0, None))


class JudgeTests(unittest.TestCase):
    def test_repeated_checks_line_up_by_occurrence(self):
        rows = base.judge([("x", True, None, "unchanged"), ("x", False, None, "fail")],
                          [("x", True, None, "unchanged"), ("x", True, None, "fail")])
        self.assertEqual([(r["base"], r["before"], r["after"], r["judged"]) for r in rows],
                         [("unchanged", "pass", "pass", "as declared"), ("fail", "fail", "pass", "as declared")])

    def test_tokens_and_local_ports_do_not_split_a_check_across_the_runs(self):
        b, a = harness.Record(), harness.Record()
        tb = harness.Mac("t", tempfile.mkdtemp(), b).token()
        ta = harness.Mac("t", tempfile.mkdtemp(), a).token()
        b.checks = [(f"URL contains 127.0.0.1:50001/index.html?token={tb}", False, None, "fail")]
        a.checks = [(f"URL contains 127.0.0.1:50002/index.html?token={ta}", True, None, "fail")]
        rows = base.judge(b.checks, a.checks, b.tokens + a.tokens)
        self.assertEqual([(r["check"], r["before"], r["after"], r["judged"]) for r in rows],
                         [(a.checks[0][0], "fail", "pass", "as declared")])


class OnBaseTests(unittest.TestCase):
    def mac(self, as_base):
        return harness.Mac("t", tempfile.mkdtemp(), harness.Record(), as_base=as_base)

    def test_a_declared_failure_on_the_base_run_is_recorded_and_the_proof_carries_on(self):
        mac = self.mac(as_base=True)
        with mac.on_base("fail"):
            self.assertIs(mac.check("menu", False), False)
        with self.assertRaises(harness.CheckFailed):   # outside the block a failure still stops the proof
            mac.check("tabs", False)
        self.assertEqual([(n, ok, b) for n, ok, _, b in mac.rec.checks], [("menu", False, "fail"), ("tabs", False, "unchanged")])

    def test_on_this_checkout_a_declared_failure_still_stops_the_proof(self):
        mac = self.mac(as_base=False)
        with self.assertRaises(harness.CheckFailed), mac.on_base("fail"):
            mac.check("menu", False)

    def test_a_waiting_check_returns_on_the_base_run(self):
        mac = self.mac(as_base=True)
        with mac.on_base("fail"):
            self.assertIs(mac.eventually("menu", lambda: False, timeout=0, every=0), False)

    def test_blocks_nest_and_restore(self):
        mac = self.mac(as_base=False)
        with mac.on_base("fail"):
            with mac.on_base("pass"):
                mac.check("a", True)
            mac.check("b", True)
        mac.check("c", True)
        self.assertEqual([b for *_, b in mac.rec.checks], ["pass", "fail", "unchanged"])

    def test_an_unknown_outcome_is_refused(self):
        with self.assertRaises(ValueError), self.mac(as_base=False).on_base("broken"):
            pass

    def test_the_base_run_gets_its_own_short_topic(self):
        self.assertEqual(base.base_topic("duck-ai-s-1a2b"), "b-duck-ai-1a2b")
        self.assertLessEqual(len(base.base_topic("abcdefghi-1a2b")), 14)
        self.assertNotEqual(base.base_topic("abcdefghi-1a2b"), "abcdefghi-1a2b")


class ReportTests(unittest.TestCase):
    def write(self, files=()):
        d = tempfile.mkdtemp()
        for f in files:
            os.makedirs(os.path.dirname(os.path.join(d, f)), exist_ok=True)
            open(os.path.join(d, f), "w").close()
        b, a = run([SETUP, BUG]), run([SETUP, FIXED])
        b.shots = a.shots = ["menu.png"]
        rows = base.judge(b.checks, a.checks)
        v, code, reason = base.verdict(b, a, rows)
        m = dict(base=dict(ref="main", sha="a" * 40, worktree="/w", revision="a" * 40),
                 change=dict(revision="b" * 40, dirty=False), verdict=v, reason=reason, rows=rows, rerun="r", clean="c")
        return base.report("The menu says New Verify Window.", b, a, {}, {}, m, d)

    def test_each_check_shows_before_and_after(self):
        text = self.write()
        self.assertIn("| Check | Base build should | Before | After | Judged |", text)
        self.assertIn("| menu shows New Verify Window | fail | fail | pass | as declared |", text)
        self.assertIn("| 1 tab(s) open | unchanged | pass | pass | as declared |", text)
        self.assertIn("**PASS**", text)
        self.assertIn(f"`{'a' * 12}` (`main`)", text)
        self.assertIn(f"`{'b' * 12}`", text)

    def test_details_name_each_runs_machine_and_macos(self):
        d = tempfile.mkdtemp()
        b, a = run([SETUP, BUG]), run([SETUP, FIXED])
        b.unpinned = ["newFlag"]
        rows = base.judge(b.checks, a.checks)
        m = dict(base=dict(ref="main", sha="a" * 40, worktree="/w", revision="a" * 40, pruned=["/old"]),
                 change=dict(revision="b" * 40, dirty=False), verdict="PASS", reason=None, rows=rows, rerun="r", clean="c")
        text = base.report("Doc.", b, a, dict(vm=dict(host="vm-1", macos="26.1")), dict(macos="26.2", flags=["newFlag=on"]),
                           m, d)
        self.assertIn("on VM vm-1 (macOS 26.1)", text)
        self.assertIn("on this Mac (macOS 26.2)", text)
        self.assertIn("not pinned before, the base revision doesn't define newFlag", text)
        self.assertIn("(this run: /old)", text)

    def test_screenshots_pair_side_by_side_where_both_exist(self):
        text = self.write(["base/menu.png", "change/menu.png", "change/final.png"])
        self.assertIn("| menu | ![Before: menu.png](base/menu.png) | ![After: menu.png](change/menu.png) |", text)
        self.assertIn("| final | (none) | ![After: final.png](change/final.png) |", text)


class ConditionsTests(unittest.TestCase):
    SAME = dict(conditions=dict(appearance="dark (system)", window="40,60,1280,800", language="en", locale="en_US"),
                conditions_declared=["appearance", "window"])

    def side(self, **changed):
        return dict(self.SAME, conditions=dict(self.SAME["conditions"], **changed))

    def test_the_same_conditions_on_both_sides_do_not_differ(self):
        self.assertEqual(harness.conditions_differ(self.SAME, self.side()), [])

    def test_any_condition_that_differs_is_named(self):
        self.assertEqual(harness.conditions_differ(self.SAME, self.side(appearance="light (system)", locale="de_DE")),
                         ["appearance", "locale"])
        self.assertEqual(harness.conditions_differ(self.SAME, self.side(window="0,38,1200,700")), ["window"])

    def test_a_window_neither_side_declared_may_differ(self):
        a = dict(self.SAME, conditions_declared=["appearance"])
        self.assertEqual(harness.conditions_differ(a, dict(a, conditions=dict(a["conditions"], window="0,38,1200,700"))),
                         [])

    def test_conditions_that_differ_make_the_pair_inconclusive(self):
        b, a = run([SETUP, BUG]), run([SETUP, FIXED])
        verdict, code, reason = base.verdict(b, a, base.judge(b.checks, a.checks), ["appearance"])
        self.assertEqual((verdict, code), ("INCONCLUSIVE", 2))
        self.assertIn("conditions differ between the runs: appearance", reason)

    def report(self, base_m, change_m):
        b, a = run([SETUP, BUG]), run([SETUP, FIXED])
        rows = base.judge(b.checks, a.checks)
        differ = harness.conditions_differ(base_m, change_m)
        v, code, reason = base.verdict(b, a, rows, differ)
        m = dict(base=dict(ref="main", sha="a" * 40, worktree="/w", revision="a" * 40), conditions_differ=differ,
                 change=dict(revision="b" * 40, dirty=False), verdict=v, reason=reason, rows=rows, rerun="r", clean="c")
        return base.report("x", b, a, base_m, change_m, m, tempfile.mkdtemp()).split("## Details")[1]

    def test_report_shows_the_same_conditions_once(self):
        details = self.report(self.SAME, self.side())
        self.assertIn("- Conditions: appearance dark (system) (declared), window 40,60,1280,800 (declared), "
                      "language en, locale en_US\n", details)
        self.assertEqual(details.count("appearance dark"), 1)

    def test_report_flags_conditions_that_differ_with_both_sides(self):
        details = self.report(self.SAME, self.side(appearance="light (system)"))
        self.assertIn("- Conditions: **differ: appearance**; before appearance dark (system) (declared)", details)
        self.assertIn("after appearance light (system) (declared)", details)


class BaseWorktreeTests(unittest.TestCase):
    def setUp(self):
        self.repo, self.trees = tempfile.mkdtemp(), os.path.join(tempfile.mkdtemp(), "base")
        for cmd in (["init", "-q"], ["config", "user.email", "t@example.com"], ["config", "user.name", "t"]):
            self.git(*cmd)
        with open(os.path.join(self.repo, ".gitignore"), "w") as f:
            f.write(".build/\n")
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.sha = self.git("rev-parse", "HEAD").strip()

    def git(self, *args, cwd=None):
        return subprocess.run(["git", "-C", cwd or self.repo, *args], check=True, capture_output=True, text=True).stdout

    def test_a_clean_worktree_is_reused_with_its_build(self):
        tree = base.base_worktree(self.sha, self.repo, self.trees)
        built = os.path.join(tree, ".build", "DerivedData-verify", "built")
        open(built, "w").close()
        self.assertEqual(base.base_worktree(self.sha, self.repo, self.trees), tree)
        self.assertTrue(os.path.exists(built))

    def test_a_dirty_worktree_is_never_trusted(self):
        tree = base.base_worktree(self.sha, self.repo, self.trees)
        with open(os.path.join(tree, ".gitignore"), "a") as f:
            f.write("changed\n")
        open(os.path.join(tree, ".build", "DerivedData-verify", "built"), "w").close()
        self.assertEqual(base.base_worktree(self.sha, self.repo, self.trees), tree)
        self.assertEqual(self.git("status", "--porcelain", cwd=tree), "")
        self.assertFalse(os.path.exists(os.path.join(tree, ".build", "DerivedData-verify", "built")))

    def test_a_worktree_at_another_commit_is_never_trusted(self):
        tree = base.base_worktree(self.sha, self.repo, self.trees)
        self.git("commit", "-q", "--allow-empty", "-m", "moved", cwd=tree)
        base.base_worktree(self.sha, self.repo, self.trees)
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=tree).strip(), self.sha)

    def test_prune_removes_only_other_worktrees_unused_for_days(self):
        current = base.base_worktree(self.sha, self.repo, self.trees)
        old = os.path.join(self.trees, "old")
        recent = os.path.join(self.trees, "recent")
        self.git("worktree", "add", "-q", "--detach", old, self.sha)
        self.git("worktree", "add", "-q", "--detach", recent, self.sha)
        days_ago = time.time() - (base.STALE_DAYS + 1) * 86400
        for tree in (current, old):
            os.utime(tree, (days_ago, days_ago))
        self.assertEqual(base.prune_base(current, self.repo, self.trees), [old])
        self.assertFalse(os.path.exists(old))
        self.assertNotIn(old, self.git("worktree", "list"))
        self.assertTrue(os.path.isdir(current) and os.path.isdir(recent))

    def test_reusing_a_worktree_marks_it_used(self):
        tree = base.base_worktree(self.sha, self.repo, self.trees)
        days_ago = time.time() - (base.STALE_DAYS + 1) * 86400
        os.utime(tree, (days_ago, days_ago))
        base.base_worktree(self.sha, self.repo, self.trees)
        self.assertEqual(base.prune_base(None, self.repo, self.trees), [])

    def test_clean_base_removes_every_kept_worktree(self):
        tree = base.base_worktree(self.sha, self.repo, self.trees)
        self.assertEqual(base.clean_base(self.repo, self.trees), [tree])
        self.assertFalse(os.path.exists(tree))
        self.assertNotIn(tree, self.git("worktree", "list"))


if __name__ == "__main__":
    unittest.main()
