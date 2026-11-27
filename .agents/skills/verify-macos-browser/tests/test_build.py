"""Tests for build and doctor on this Mac, with xcodebuild faked and no app: build resolves the packages once when
-skipPackageUpdates can't, and doctor reads a process's start time in any locale.
Run: python3 -I -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
SKILL = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
VERIFY = os.path.join(SKILL, "scripts", "verify.sh")
VHELP = os.path.join(SKILL, "scripts", "vhelp.py")

# Plays xcodebuild. A build fails as SwiftPM does on a pin its cache lacks until -resolvePackageDependencies has run
# (stale-cache), always fails to compile (compile-error), or fails with the resolution failing too (resolve-fails).
# A build that succeeds leaves the app where verify.sh looks for it.
FAKE_XCODEBUILD = r'''#!/bin/bash
echo "$*" >> "$FAKE_CALLS"
for a in "$@"; do
    case $prev in -derivedDataPath) data=$a ;; -configuration) conf=$a ;; esac
    [[ $a == PRODUCT_NAME_PREFIX=* ]] && name=${a#PRODUCT_NAME_PREFIX=}
    prev=$a
done
unresolved() { printf "xcodebuild: error: Could not resolve package dependencies:\n  no versions of 'kit' match 0.4.2\n"; exit 74; }
if [[ " $* " == *" -resolvePackageDependencies "* ]]; then
    [[ $FAKE_XCODEBUILD == resolve-fails ]] && unresolved
    mkdir -p "$data" && touch "$data/resolved" && exit 0
fi
[[ $FAKE_XCODEBUILD == compile-error ]] && { echo "Main.swift:1:1: error: cannot find 'x' in scope"; exit 65; }
[[ -f "$data/resolved" ]] || unresolved
app="$data/Build/Products/$conf/$name.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
printf '#!/bin/sh\n' > "$app/MacOS/$name" && chmod +x "$app/MacOS/$name"
: > "$app/MacOS/$name.debug.dylib"
/bin/dd if=/dev/zero of="$app/Resources/Assets.car" bs=1m count=2 2>/dev/null
echo "** BUILD SUCCEEDED **"
'''


def git_repo():
    repo = tempfile.mkdtemp()
    for args in (["init", "-q"], ["config", "user.email", "t@example.com"], ["config", "user.name", "T"],
                 ["commit", "-q", "--allow-empty", "-m", "base"]):
        subprocess.run(["git", "-C", repo, *args], check=True)
    return repo


class BuildResolvesPackagesTests(unittest.TestCase):
    """build passes -skipPackageUpdates, which fetches nothing: a pin missing from the SwiftPM cache (a new
    DerivedData, a bumped dependency) fails the build until the packages are resolved."""

    def setUp(self):
        self.repo, self.home, fake_bin = git_repo(), tempfile.mkdtemp(), tempfile.mkdtemp()
        self.calls = os.path.join(self.home, "calls")
        with open(os.path.join(fake_bin, "xcodebuild"), "w") as f:
            f.write(FAKE_XCODEBUILD)
        os.chmod(os.path.join(fake_bin, "xcodebuild"), 0o755)
        self.env = {**os.environ, "PATH": fake_bin + ":" + os.environ["PATH"], "VERIFY_MACOS_HOME": self.home,
                    "VERIFY_RUN_DIR": os.path.join(self.home, "run"), "FAKE_CALLS": self.calls,
                    "VERIFY_DERIVED_DATA": os.path.join(self.home, "DerivedData")}

    def build(self, mode):
        p = subprocess.run([VERIFY, "build", "build-test", self.repo, "--no-launch"], env={**self.env,
                           "FAKE_XCODEBUILD": mode}, capture_output=True, text=True, timeout=120)
        with open(self.calls) as f:
            calls = ["resolve" if "-resolvePackageDependencies" in line else "build" for line in f]
        self.assertFalse(os.path.exists(os.path.join(self.home, ".build-lock")), "the build lock is released")
        return p, calls

    def test_a_pin_missing_from_the_cache_is_resolved_once_and_the_build_retried(self):
        p, calls = self.build("stale-cache")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(calls, ["build", "resolve", "build"])
        self.assertIn("resolving packages", p.stdout)
        self.assertTrue(os.path.exists(os.path.join(self.home, "run", "build.json")))

    def test_a_compile_error_is_reported_without_resolving(self):
        p, calls = self.build("compile-error")
        self.assertEqual(p.returncode, 1)
        self.assertEqual(calls, ["build"])
        self.assertIn("error: cannot find 'x' in scope", p.stdout)

    def test_a_resolution_that_fails_is_reported_and_not_retried(self):
        p, calls = self.build("resolve-fails")
        self.assertEqual(p.returncode, 1)
        self.assertEqual(calls, ["build", "resolve"])
        self.assertIn("Could not resolve package dependencies", p.stdout)


class DoctorInAnyLocaleTests(unittest.TestCase):
    """doctor compares the app's start time with the build's end. ps prints that time in the session's locale, and
    ssh forwards LANG and LC_* to a VM."""

    def setUp(self):
        self.repo, self.home = git_repo(), tempfile.mkdtemp()
        macos = os.path.join(self.home, "DuckDuckGo - verify-locale.app", "Contents", "MacOS")
        os.makedirs(macos)
        exe = os.path.join(macos, "DuckDuckGo - verify-locale")
        # Compiled, not a copy of /bin/sleep: macOS kills a platform binary run from another path.
        subprocess.run(["cc", "-x", "c", "-", "-o", exe], input="#include <unistd.h>\nint main(void) { sleep(60); }\n",
                       text=True, check=True)
        open(exe + ".debug.dylib", "w").close()
        build_end = int(time.time()) - 5
        self.app = subprocess.Popen([exe])
        time.sleep(0.5)

        def out(*args):
            return json.loads(subprocess.run([sys.executable, "-I", VHELP, *args], capture_output=True, text=True,
                                             check=True).stdout)
        self.run_dir = os.path.join(self.home, "run")
        os.makedirs(self.run_dir)
        with open(os.path.join(self.run_dir, "build.json"), "w") as f:
            json.dump(dict(worktree=self.repo, build_end=build_end, app=os.path.dirname(os.path.dirname(macos)),
                           source=out("fingerprint", self.repo), hashes=out("hash", exe, exe + ".debug.dylib")), f)

    def tearDown(self):
        self.app.send_signal(signal.SIGKILL)
        self.app.wait()

    def test_doctor_accepts_a_fresh_launch_in_any_locale(self):
        for locale in ("en_US.UTF-8", "en_GB.UTF-8", "es_AR.UTF-8"):
            with self.subTest(locale=locale):
                p = subprocess.run([VERIFY, "doctor", "locale"], capture_output=True, text=True, timeout=60,
                                   env={**os.environ, "LANG": locale, "LC_ALL": locale, "VERIFY_MACOS_HOME": self.home,
                                        "VERIFY_RUN_DIR": self.run_dir})
                self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
                self.assertEqual(p.stdout.splitlines()[-1], "OK")


if __name__ == "__main__":
    unittest.main()
