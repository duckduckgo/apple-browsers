#!/usr/bin/env python3
"""Tests for agent_context_check.py. Run: python3 -m unittest discover scripts/agent-context-check"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import agent_context_check as check  # noqa: E402

CONFIG = {
    "bytes_per_token": 1,
    "budgets": {"always-loaded-total": 1000, "root": 100, "nested": 100,
                "skill-description": 50, "skill-body": 500, "review": 500},
    "overrides": {},
    "ignored_references": [],
}


class RepoTestCase(unittest.TestCase):
    """Builds a throwaway git repo with agent context files."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.run_git("init", "-q")
        self.run_git("config", "user.email", "test@example.com")
        self.run_git("config", "user.name", "Test")
        self.write("Sources/App/Widget.swift", "struct WidgetStore {}\n")
        self.write("AGENTS.md", "- Use `WidgetStore` from `Sources/App/Widget.swift`.\n")
        os.symlink("AGENTS.md", self.root / "CLAUDE.md")
        self.write(".claude/skills/ddg-widget/SKILL.md",
                   "---\nname: ddg-widget\ndescription: >-\n  Use when adding\n  a widget.\n---\n\nBody.\n")

    def tearDown(self):
        self.tmp.cleanup()

    def run_git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def write(self, path, text):
        full = self.root / path
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text(text)

    def errors(self, config=CONFIG):
        tree = check.Tree(self.root).load()
        items = check.measure(tree, config["bytes_per_token"])
        return (check.check_budgets(items, config) + check.check_claude_links(tree)
                + check.check_references(tree, self.root, set(config["ignored_references"])))


class BudgetTests(RepoTestCase):

    def testWhenFilesAreWithinBudgetThenNoErrors(self):
        self.assertEqual(self.errors(), [])

    def testWhenRootFileExceedsBudgetThenItFails(self):
        self.write("AGENTS.md", "x" * 101)
        self.assertEqual(self.errors(), ["AGENTS.md: ~101 tokens, budget 100 (root)"])

    def testWhenOverrideRaisesTheLimitThenItPasses(self):
        self.write("AGENTS.md", "x" * 101)
        config = {**CONFIG, "overrides": {"AGENTS.md": 200}}
        self.assertEqual(self.errors(config), [])

    def testWhenSkillDescriptionIsFoldedThenItsFullTextIsMeasured(self):
        self.write(".claude/skills/ddg-widget/SKILL.md",
                   "---\nname: ddg-widget\ndescription: >-\n  " + "y" * 60 + "\n---\n")
        self.assertEqual(self.errors(), [
            ".claude/skills/ddg-widget/SKILL.md#description: ~72 tokens, budget 50 (skill-description)"])

    def testWhenAlwaysLoadedTotalExceedsBudgetThenItFails(self):
        config = {**CONFIG, "budgets": {**CONFIG["budgets"], "always-loaded-total": 10}}
        self.assertTrue(any(e.startswith("always-loaded total") for e in self.errors(config)))


class LinkTests(RepoTestCase):

    def testWhenNestedAgentsFileHasNoClaudeSymlinkThenItFails(self):
        self.write("Sources/AGENTS.md", "- Rule.\n")
        self.assertEqual(self.errors(), [
            "Sources/AGENTS.md: Claude Code won't load it; add `CLAUDE.md` as a symlink to AGENTS.md"])

    def testWhenClaudeFileImportsAgentsThenItPasses(self):
        self.write("Sources/AGENTS.md", "- Rule.\n")
        self.write("Sources/CLAUDE.md", "@AGENTS.md\n")
        self.assertEqual(self.errors(), [])


class ReferenceTests(RepoTestCase):

    def testWhenReferencedTypeIsRenamedThenItFails(self):
        self.write("Sources/App/Widget.swift", "struct WidgetRepository {}\n")
        self.assertEqual(self.errors(), ["AGENTS.md: `WidgetStore` isn't declared anywhere in the repo"])

    def testWhenTypeNameSurvivesOnlyInACommentThenItFails(self):
        self.write("Sources/App/Widget.swift", "// Replaces WidgetStore.\nstruct WidgetRepository {}\n")
        self.assertEqual(self.errors(), ["AGENTS.md: `WidgetStore` isn't declared anywhere in the repo"])

    def testWhenTypeIsDeclaredWithGenericsOrAsAProtocolThenItPasses(self):
        self.write("Sources/App/Widget.swift", "public final class WidgetStore<T>: Sendable {}\n")
        self.assertEqual(self.errors(), [])
        self.write("Sources/App/Widget.swift", "protocol WidgetStore {}\n")
        self.assertEqual(self.errors(), [])

    def testWhenNameIsAModuleFolderThenItPasses(self):
        self.write("Packages/WidgetKitCore/Sources/File.swift", "struct WidgetStore {}\n")
        self.write("AGENTS.md", "- Import `WidgetKitCore`.\n")
        self.assertEqual(self.errors(), [])

    def testWhenReferencedFileIsMovedThenItFails(self):
        (self.root / "Sources/App/Widget.swift").rename(self.root / "Sources/App/Gadget.swift")
        self.run_git("add", "-A")
        self.assertIn("AGENTS.md: `Sources/App/Widget.swift` doesn't exist in the repo", self.errors())

    def testWhenReferencedSkillIsMissingThenItFails(self):
        self.write("AGENTS.md", "- Use the `ddg-gadget` skill.\n")
        self.assertEqual(self.errors(), ["AGENTS.md: skill `ddg-gadget` isn't in .claude/skills/"])

    def testWhenReferenceIsIgnoredThenItPasses(self):
        self.write("AGENTS.md", "- Never commit `Sources/Generated/Out.swift`.\n")
        config = {**CONFIG, "ignored_references": ["Sources/Generated/Out.swift"]}
        self.assertEqual(self.errors(config), [])

    def testWhenSpanIsNotARepoPathThenItIsNotChecked(self):
        self.write("AGENTS.md", "`12/16/24` `Color/32px` `duckduckgo/other`\n"
                                "```\n`Sources/Missing.swift`\n```\n")
        self.assertEqual(self.errors(), [])


class BaseComparisonTests(RepoTestCase):

    def testWhenComparingAgainstBaseThenReportShowsTheChange(self):
        self.run_git("add", "-A")
        self.run_git("commit", "-qm", "base")
        self.write("AGENTS.md", (self.root / "AGENTS.md").read_text() + "- More.\n")
        base = check.measure(check.Tree(self.root, "HEAD").load(), 1)
        head = check.measure(check.Tree(self.root).load(), 1)
        report = check.render_markdown(head, base, [])
        self.assertIn("| AGENTS.md | 53 | 61 | +8 |", report)


if __name__ == "__main__":
    unittest.main()
