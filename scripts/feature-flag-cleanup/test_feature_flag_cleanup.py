import unittest
from pathlib import Path

import feature_flag_cleanup as ffc

TEMPLATE = (Path(__file__).parent / "prompt.md").read_text()


class FakeAsana:
    def __init__(self, tasks, subtasks=None):
        self.tasks = tasks
        self.subtask_lists = subtasks or {}
        self.created = []

    def registry_tasks(self):
        return iter(self.tasks)

    def task(self, gid):
        return next(task for task in self.tasks if task["gid"] == gid)

    def subtasks(self, gid):
        return self.subtask_lists.get(gid, [])

    def create_ready_subtask(self, removal, notes):
        self.created.append((removal, notes))
        return "new"


def registry_task(gid, flag="someFlag", platform="macOS", auto_removal=ffc.KEEP_FEATURE_OPTION_GID):
    fields = [{"gid": ffc.PLATFORM_FIELD_GID, "enum_value": {"gid": "p", "name": platform} if platform else None}]
    if auto_removal:
        fields.append({"gid": ffc.AUTO_REMOVAL_FIELD_GID, "enum_value": {"gid": auto_removal}})
    return {
        "gid": gid,
        "notes": f"Author: someone\nFlag name: {flag} (macOS), remote releasable\n",
        "assignee": {"gid": "owner"},
        "custom_fields": fields,
        "memberships": [{"project": {"gid": ffc.REGISTRY_PROJECT_GID}}],
    }


def agent_subtask(name):
    return {"name": name, "custom_fields": [{"gid": ffc.AGENT_STATUS_FIELD_GID, "enum_value": {"gid": "done"}}]}


class PlanRemovalTests(unittest.TestCase):
    def test_reads_flag_platform_owner_and_kept_path(self):
        keep = registry_task("1", flag="dataImportHistory")
        remove = registry_task("2", platform="iOS", auto_removal=ffc.REMOVE_FEATURE_OPTION_GID)

        kept, _ = ffc.plan_removal(keep)
        removed, _ = ffc.plan_removal(remove)

        self.assertEqual(kept, ffc.FlagRemoval("1", "dataImportHistory", "macOS", True, "owner"))
        self.assertEqual(kept.agent_project_gid, "1201037661562251")
        self.assertFalse(removed.keep_enabled_path)
        self.assertEqual(removed.agent_project_gid, "414709148257752")

    def test_skips_tasks_the_agent_cannot_take(self):
        tasks = [
            registry_task("1", auto_removal=None),
            registry_task("2", platform=None),
            {**registry_task("3"), "notes": "No flag line"},
            registry_task("4", platform="Windows"),
        ]

        plans = [ffc.plan_removal(task) for task in tasks]

        self.assertEqual([removal for removal, _ in plans], [None] * 4)
        self.assertEqual(plans[3][1], "unsupported Platform 'Windows'")


class RenderPromptTests(unittest.TestCase):
    def test_fills_every_placeholder_for_a_rejected_flag(self):
        removal = ffc.FlagRemoval("1", "someFlag", "macOS", False, None)

        prompt = ffc.render_prompt(removal, TEMPLATE)

        self.assertNotIn("$", prompt)
        self.assertIn("the flag was rejected", prompt)
        self.assertIn("runs when the flag is disabled", prompt)
        self.assertIn("ddg-remove-feature-flag/SKILL.md", prompt)


class MarkdownToAsanaHtmlTests(unittest.TestCase):
    def test_converts_the_prompt_to_rich_text(self):
        removal = ffc.FlagRemoval("1", "someFlag", "macOS", True, None)

        html = ffc.markdown_to_asana_html(ffc.render_prompt(removal, TEMPLATE))

        self.assertTrue(html.startswith("<body>Remove the <code>someFlag</code> feature flag"))
        self.assertIn("<ul><li><strong>Decision:</strong> the flag was approved.", html)
        self.assertTrue(html.endswith("</li></ul></body>"))
        self.assertNotIn("**", html)


class QueueRemovalsTests(unittest.TestCase):
    def test_skips_queued_flags_and_stops_at_the_limit(self):
        asana = FakeAsana(
            [
                registry_task("1", flag="queued"),
                registry_task("2", flag="renamed"),
                registry_task("3", flag="first"),
                registry_task("4", flag="second"),
            ],
            subtasks={
                "1": [{"name": "Remove queued feature flag"}],
                "2": [agent_subtask("Remove renamed feature flag (PR open)")],
            },
        )

        queued = ffc.queue_removals(asana, TEMPLATE, limit=1, dry_run=False)

        self.assertEqual([removal.flag for removal in queued], ["first"])
        self.assertEqual([removal.flag for removal, _ in asana.created], ["first"])

    def test_dry_run_writes_nothing_and_logs_only_the_task_and_flag(self):
        asana = FakeAsana([registry_task("1", flag="first")])

        with self.assertLogs(ffc.logger, level="INFO") as logs:
            queued = ffc.queue_removals(asana, TEMPLATE, limit=5, dry_run=True)

        self.assertEqual(len(queued), 1)
        self.assertEqual(asana.created, [])
        self.assertEqual(logs.output, ["INFO:feature-flag-cleanup:1 (first): would create a subtask"])

    def test_targeted_run_skips_a_task_outside_the_registry(self):
        asana = FakeAsana([{**registry_task("1"), "memberships": [{"project": {"gid": "other"}}]}])

        queued = ffc.queue_removals(asana, TEMPLATE, limit=1, dry_run=False, only_task_gid="1")

        self.assertEqual(queued, [])
        self.assertEqual(asana.created, [])


if __name__ == "__main__":
    unittest.main()
