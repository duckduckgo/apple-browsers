#!/usr/bin/env python3
"""Tests for run_agent_evals.py (no model calls). Run: python3 -m unittest discover scripts/agent-evals"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_agent_evals as evals  # noqa: E402

DIFF = """diff --git a/Tests/FooTests.swift b/Tests/FooTests.swift
new file mode 100644
--- /dev/null
+++ b/Tests/FooTests.swift
@@ -0,0 +1,2 @@
+@Test("x", .timeLimit(.minutes(1)))
+func x() {}
diff --git a/Sources/Foo.swift b/Sources/Foo.swift
--- a/Sources/Foo.swift
+++ b/Sources/Foo.swift
@@ -1 +1 @@
-old
+AppDependencyProvider.shared
"""


def stream(*events):
    return [json.dumps(e) for e in events]


def tool(name, **args):
    return {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": name, "input": args}]}}


class TranscriptTests(unittest.TestCase):

    def testWhenStreamHasToolUsesThenTheyAreCollected(self):
        transcript = evals.Transcript.parse(stream(
            {"type": "system", "subtype": "init", "mcp_servers": []},
            tool("Skill", skill="ddg-add-pixel"),
            tool("Read", file_path="/w/.claude/skills/ddg-xcode-add-file/SKILL.md"),
            tool("Bash", command="mint run swiftlint lint --strict Foo.swift"),
            {"type": "result", "total_cost_usd": 0.5, "num_turns": 4},
        ) + ["not json"])
        self.assertEqual(transcript.skills_invoked(), {"ddg-add-pixel", "ddg-xcode-add-file"})
        self.assertEqual(transcript.commands(), ["mint run swiftlint lint --strict Foo.swift"])
        self.assertEqual(transcript.result["num_turns"], 4)

    def testWhenRunLoadedMemoryOrServersThenIsolationFails(self):
        transcript = evals.Transcript.parse(stream(
            {"type": "system", "subtype": "init", "mcp_servers": [{"name": "Asana"}],
             "memory_paths": {"auto": "/x"}}))
        self.assertEqual(evals.isolation_problems(transcript), ["MCP servers loaded", "auto-memory loaded"])


class GraderTests(unittest.TestCase):

    def check(self, grader, transcript=None):
        return evals.grade(grader, transcript or evals.Transcript(), DIFF)[0]

    def testWhenAddedTestHasTimeLimitThenDiffContainsPasses(self):
        self.assertTrue(self.check({"type": "diff_contains", "path": "*Tests.swift", "pattern": r"\.timeLimit"}))

    def testWhenPatternIsOnlyInOtherFilesThenDiffContainsFails(self):
        self.assertFalse(self.check({"type": "diff_contains", "path": "*Tests.swift", "pattern": "AppDependencyProvider"}))

    def testWhenForbiddenTextIsAddedThenDiffNotContainsFails(self):
        self.assertFalse(self.check({"type": "diff_not_contains", "pattern": "AppDependencyProvider"}))

    def testWhenRemovedLineMatchesThenDiffContainsIgnoresIt(self):
        self.assertFalse(self.check({"type": "diff_contains", "pattern": "^old$"}))

    def testWhenFileIsInDiffThenFileChangedPasses(self):
        self.assertTrue(self.check({"type": "file_changed", "path": "Sources/*.swift"}))
        self.assertFalse(self.check({"type": "file_changed", "path": "*.pbxproj"}))

    def testWhenDiffIsEmptyThenNoChangesPasses(self):
        self.assertTrue(evals.grade({"type": "no_changes"}, evals.Transcript(), "")[0])
        self.assertFalse(self.check({"type": "no_changes"}))

    def testWhenFileWasReadThenFileGradersAgree(self):
        transcript = evals.Transcript(tool_uses=[("Read", {"file_path": "/w/REVIEW.md"})])
        self.assertTrue(self.check({"type": "file_read", "pattern": r"(^|/)REVIEW\.md$"}, transcript))
        self.assertFalse(self.check({"type": "file_not_read", "pattern": r"REVIEW\.md$"}, transcript))

    def testWhenGraderTypeIsUnknownThenItRaises(self):
        with self.assertRaises(ValueError):
            self.check({"type": "vibes"})


class WorkspaceTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.write("AGENTS.md", "- main rule\n")
        os.symlink("AGENTS.md", self.repo / "CLAUDE.md")
        self.write(".claude/skills/ddg-x/SKILL.md", "---\nname: ddg-x\ndescription: x\n---\n")
        self.write("Sources/Foo.swift", "struct Foo {}\n")
        self.git("add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base")
        self.commit = self.git("rev-parse", "HEAD").strip()
        self.workspace = evals.Workspace(self.repo, Path(self.tmp.name) / "work" / "worktree")
        self.workspace.ensure(self.commit)

    def tearDown(self):
        subprocess.run(["git", "worktree", "remove", "--force", str(self.workspace.path)],
                       cwd=self.repo, capture_output=True)
        self.tmp.cleanup()

    def git(self, *args):
        return evals.git(*args, cwd=self.repo)

    def write(self, path, text):
        full = self.repo / path
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(text)

    def testWhenArmIsCandidateThenWorkingTreeChangesAreUsed(self):
        self.write("AGENTS.md", "- candidate rule\n")
        self.workspace.reset(self.commit)
        self.workspace.apply_context(evals.arm_tree("candidate", self.repo, "HEAD"))
        self.assertEqual((self.workspace.path / "CLAUDE.md").read_text(), "- candidate rule\n")

    def testWhenArmIsBaseThenCommittedFilesAreUsed(self):
        self.write("AGENTS.md", "- candidate rule\n")
        self.workspace.reset(self.commit)
        self.workspace.apply_context(evals.arm_tree("base", self.repo, "HEAD"))
        self.assertEqual((self.workspace.path / "AGENTS.md").read_text(), "- main rule\n")

    def testWhenArmIsNoneThenInstructionFilesAreRemovedButSkillsStay(self):
        self.workspace.reset(self.commit)
        self.workspace.apply_context(evals.arm_tree("none", self.repo, "HEAD"))
        self.assertFalse((self.workspace.path / "AGENTS.md").exists())
        self.assertFalse((self.workspace.path / "CLAUDE.md").is_symlink())
        self.assertTrue((self.workspace.path / ".claude/skills/ddg-x/SKILL.md").exists())

    def testWhenAgentEditsThenDiffExcludesArmSetupAndIncludesNewFiles(self):
        self.write("AGENTS.md", "- candidate rule\n")
        self.workspace.reset(self.commit)
        arm_commit = self.workspace.apply_context(evals.arm_tree("candidate", self.repo, "HEAD"))
        (self.workspace.path / "Sources/Bar.swift").write_text("struct Bar {}\n")
        diff = self.workspace.diff_since(arm_commit)
        self.assertEqual(evals.changed_files(diff), ["Sources/Bar.swift"])

    def testWhenResetAfterARunThenAgentChangesAndArmCommitAreGone(self):
        self.workspace.reset(self.commit)
        self.workspace.apply_context(evals.arm_tree("none", self.repo, "HEAD"))
        (self.workspace.path / "Sources/Bar.swift").write_text("struct Bar {}\n")
        self.workspace.reset(self.commit)
        self.assertFalse((self.workspace.path / "Sources/Bar.swift").exists())
        self.assertTrue((self.workspace.path / "AGENTS.md").exists())


class ReportTests(unittest.TestCase):

    def testWhenRunsAreSummarizedThenEachArmGetsPassRateAndCost(self):
        runs = [
            {"case": "c", "arm": "candidate", "rep": 1, "passed": True, "graders": [], "turns": 4, "input_tokens": 90_000, "output_tokens": 2_000},
            {"case": "c", "arm": "none", "rep": 1, "passed": False, "error": "",
             "graders": [{"detail": "ran swiftlint", "passed": False}], "turns": 2, "input_tokens": 80_000, "output_tokens": 1_000},
        ]
        report = evals.summarize(runs, ["candidate", "none"])
        self.assertIn("| c | 1/1 · 90k in · 4 turns | 0/1 · 80k in · 2 turns |", report)
        self.assertIn("| candidate | 1/1 (100%) | 90,000 | 2,000 | 4.0 |", report)
        self.assertNotIn("$", report)
        self.assertIn("- c / none #1: ran swiftlint", report)

    def testWhenRunsPartiallyPassThenEachCheckGetsItsOwnRate(self):
        def run(arm, rep, time_limit, available):
            return {"case": "c", "arm": arm, "rep": rep, "passed": time_limit and available, "error": "",
                    "graders": [{"detail": "timeLimit", "passed": time_limit},
                                {"detail": "a|b", "passed": available}],
                    "turns": 1, "input_tokens": 1, "output_tokens": 1}
        runs = [run("candidate", 1, True, True), run("candidate", 2, True, True),
                run("none", 1, True, False), run("none", 2, False, False)]
        report = evals.summarize(runs, ["candidate", "none"])
        self.assertIn("| c | timeLimit | 2/2 | 1/2 |", report)
        self.assertIn("| c | a\\|b | 2/2 | 0/2 |", report)


class CaseFileTests(unittest.TestCase):

    def testWhenCasesAreLoadedThenEachHasAPromptAndKnownGraders(self):
        cases = evals.load_cases("*")
        self.assertTrue(cases)
        for case in cases:
            self.assertTrue(case["prompt"], case["id"])
            for grader in case["graders"]:
                evals.grade(grader, evals.Transcript(), "")


if __name__ == "__main__":
    unittest.main()
