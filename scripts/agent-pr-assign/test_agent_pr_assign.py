import unittest

import agent_pr_assign as assign

USER_MAP = """
# macOS
someone: 1111111111111111
octocat: '1216562358561797'  # quoted
  nested: 1216562358561797
"""


class TaskGidFromBodyTests(unittest.TestCase):
    def test_reads_the_task_gid_from_short_and_long_task_urls(self):
        short_body = "Task/Issue URL: https://app.asana.com/0/0/1220707808674818/f\n\n### Description"
        long_body = "Task/Issue URL: https://app.asana.com/1/137249556945/project/1201037661562251/task/1220707808674818?focus=true"

        gids = [assign.task_gid_from_body(short_body), assign.task_gid_from_body(long_body)]

        self.assertEqual(gids, ["1220707808674818", "1220707808674818"])

    def test_returns_none_without_a_task_line(self):
        body = "### Description\nSee https://app.asana.com/0/0/1220707808674818/f"

        gid = assign.task_gid_from_body(body)

        self.assertIsNone(gid)


class GithubLoginForTests(unittest.TestCase):
    def test_maps_an_asana_user_to_their_top_level_login(self):
        known = assign.github_login_for("1216562358561797", USER_MAP)
        unknown = assign.github_login_for("999", USER_MAP)

        self.assertEqual(known, "octocat")
        self.assertIsNone(unknown)


if __name__ == "__main__":
    unittest.main()
