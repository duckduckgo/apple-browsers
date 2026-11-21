"""Tests for cleanup's process signals: it signals a recorded process only while its identity (pid, start time and
command) still matches what was recorded when it started. Runs `verify.sh cleanup` against a temporary run folder with
`sleep` processes standing in for the streams. No app, build or VM.
Run: python3 -I -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import os
import subprocess
import tempfile
import unittest

SKILL = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def start_time(pid):
    return " ".join(subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True).stdout.split())


class CleanupIdentityTests(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.run_dir = os.path.join(self.home, "run")
        os.makedirs(self.run_dir)
        self.procs = []

    def tearDown(self):
        for p in self.procs:
            p.kill()
            p.wait()

    def sleeper(self, pid_file, start=None, word="sleep"):
        """A live process with its identity recorded in `pid_file`, as verify.sh records a stream it starts."""
        p = subprocess.Popen(["/bin/sleep", "60"])
        self.procs.append(p)
        with open(os.path.join(self.run_dir, pid_file), "w") as f:
            f.write(f"{p.pid}\n{start or start_time(p.pid)}\n{word}\n")
        return p

    def cleanup(self):
        return subprocess.run([os.path.join(SKILL, "scripts", "verify.sh"), "cleanup", "cleanup-test"],
                              env={**os.environ, "VERIFY_MACOS_HOME": self.home, "VERIFY_RUN_DIR": self.run_dir},
                              capture_output=True, text=True, timeout=60)

    def alive(self, p):
        try:
            p.wait(timeout=2)
            return False
        except subprocess.TimeoutExpired:
            return True

    def test_a_process_whose_identity_still_matches_is_signalled(self):
        ours = self.sleeper("pixel_stream.pid")
        self.cleanup()
        self.assertFalse(self.alive(ours), "the recorded stream must be stopped")

    def test_a_reused_pid_with_another_start_time_is_left_alone(self):
        other = self.sleeper("pixel_stream.pid", start="Mon Jan 1 00:00:00 2001")
        out = self.cleanup().stdout
        self.assertTrue(self.alive(other), "a pid that now names another process must not be signalled")
        self.assertIn(f"not signalled: pid {other.pid}", out)

    def test_a_pid_now_running_another_command_is_left_alone(self):
        other = self.sleeper("tunnel.pid", word="ssh")
        self.cleanup()
        self.assertTrue(self.alive(other))

    def test_a_pid_file_without_an_identity_is_never_signalled(self):
        p = subprocess.Popen(["/bin/sleep", "60"])
        self.procs.append(p)
        with open(os.path.join(self.run_dir, "wide_stream.pid"), "w") as f:
            f.write(f"{p.pid}\n")
        self.cleanup()
        self.assertTrue(self.alive(p))


if __name__ == "__main__":
    unittest.main()


class SkillFilesAreNotAppCodeTests(unittest.TestCase):
    """The skills live in .agents/skills, with .claude/skills symlinks. Their files mention `[VERIFY]` and change
    while you work on a proof, so cleanup's leftover check and the build fingerprint skip both directories."""

    def setUp(self):
        self.repo = tempfile.mkdtemp()
        for args in (["init", "-q"], ["config", "user.email", "t@example.com"], ["config", "user.name", "T"]):
            subprocess.run(["git", "-C", self.repo, *args], check=True)
        self.write("App/Main.swift", "let x = 1\n")
        self.write(".agents/skills/verify-x/run.sh", 'echo "[VERIFY] tag"\n')
        self.write(".claude/notes.md", "[VERIFY] tag\n")
        subprocess.run(["git", "-C", self.repo, "add", "-A"], check=True)
        subprocess.run(["git", "-C", self.repo, "commit", "-qm", "base"], check=True)
        self.home = tempfile.mkdtemp()
        self.run_dir = os.path.join(self.home, "run")
        os.makedirs(self.run_dir)
        with open(os.path.join(self.run_dir, "build.json"), "w") as f:
            f.write('{"worktree": "%s"}' % self.repo)

    def write(self, path, text):
        full = os.path.join(self.repo, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(text)

    def cleanup(self):
        return subprocess.run([os.path.join(SKILL, "scripts", "verify.sh"), "cleanup", "cleanup-test"],
                              env={**os.environ, "VERIFY_MACOS_HOME": self.home, "VERIFY_RUN_DIR": self.run_dir},
                              capture_output=True, text=True, timeout=60)

    def test_verify_tags_in_skill_files_are_not_leftovers(self):
        result = self.cleanup()
        self.assertNotIn("[VERIFY] lines left", result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_verify_tag_in_app_code_is_a_leftover(self):
        self.write("App/Main.swift", 'print("[VERIFY] here")\n')
        subprocess.run(["git", "-C", self.repo, "add", "-A"], check=True)
        result = self.cleanup()
        self.assertIn("App/Main.swift", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_editing_a_skill_file_keeps_the_build_fingerprint(self):
        import sys
        sys.path.insert(0, os.path.join(SKILL, "scripts"))
        import vhelp
        before = vhelp.fingerprint(self.repo)["stamp"]
        self.write(".agents/skills/verify-x/run.sh", "changed\n")
        self.write(".claude/notes.md", "changed\n")
        self.assertEqual(vhelp.fingerprint(self.repo)["stamp"], before)
        self.write("App/Main.swift", "let x = 2\n")
        self.assertNotEqual(vhelp.fingerprint(self.repo)["stamp"], before)
