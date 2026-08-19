#!/usr/bin/env python3
"""Integration tests for create-asana-subtask.sh using a fake curl."""

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "create-asana-subtask.sh"


class CreateAsanaSubtaskTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.captured_payload = self.root / "captured-payload.json"
        self.captured_url = self.root / "captured-url.txt"
        self.response = self.root / "response.json"
        self.response.write_text(json.dumps({"data": {"gid": "999"}}))
        self._write_fake_curl()
        self.notes = self.root / "notes.txt"
        self.notes.write_text("something broke")

    def _write_fake_curl(self):
        # Captures the JSON payload passed via --data and the request URL
        # (curl's lone non-flag argument), then returns the canned response
        # written to the --output file, mimicking a 201 from Asana.
        fake_curl = self.bin / "curl"
        fake_curl.write_text(
            textwrap.dedent(
                f"""\
                #!/usr/bin/env bash
                prev=""
                for arg in "$@"; do
                  if [ "$prev" = "--data" ]; then
                    printf '%s' "$arg" > "{self.captured_payload}"
                  fi
                  if [ "$prev" = "--output" ]; then
                    cp "{self.response}" "$arg"
                  fi
                  prev="$arg"
                done
                printf '%s' "${{@: -1}}" > "{self.captured_url}"
                printf '201'
                """
            )
        )
        fake_curl.chmod(0o755)

    def run_script(self, followers=None, project_gid="1217628708169653",
                    section_gid="1217628708169657"):
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}:{env['PATH']}"
        env["ASANA_ACCESS_TOKEN"] = "test-token"
        if followers is None:
            env.pop("ASANA_FOLLOWERS", None)
        else:
            env["ASANA_FOLLOWERS"] = followers
        result = subprocess.run(
            [
                str(SCRIPT), project_gid, section_gid, "task name",
                str(self.notes), "2026-01-01", "2026-01-02",
            ],
            text=True, capture_output=True, env=env,
        )
        payload = (
            json.loads(self.captured_payload.read_text())
            if self.captured_payload.exists()
            else None
        )
        return result, payload

    def test_omits_followers_when_asana_followers_is_unset(self):
        result, payload = self.run_script(followers=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("followers", payload["data"])

    def test_omits_followers_when_asana_followers_is_blank(self):
        result, payload = self.run_script(followers=" , ,")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("followers", payload["data"])

    def test_includes_trimmed_followers_when_asana_followers_is_set(self):
        result, payload = self.run_script(followers=" a@b.com , 123456 ")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(payload["data"]["followers"], ["a@b.com", "123456"])

    def test_creates_a_top_level_task_placed_in_the_project_section(self):
        result, payload = self.run_script(
            project_gid="1217628708169653", section_gid="1217628708169657",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.captured_url.read_text(), "https://app.asana.com/api/1.0/tasks")
        self.assertEqual(payload["data"]["projects"], ["1217628708169653"])
        self.assertEqual(
            payload["data"]["memberships"],
            [{"project": "1217628708169653", "section": "1217628708169657"}],
        )
        self.assertNotIn("subtasks", self.captured_url.read_text())

    def test_rejects_non_numeric_project_or_section_gid(self):
        result, _ = self.run_script(project_gid="not-a-gid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("project GID must be numeric", result.stderr)

        result, _ = self.run_script(section_gid="not-a-gid")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("section GID must be numeric", result.stderr)


if __name__ == "__main__":
    unittest.main()
