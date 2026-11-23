"""Tests for vhelp.py and verify.sh, run as commands the way the harness runs them: pixel and wide-event matching from
a mark, flag validation against FeatureFlag.swift, DerivedData resolution and VM locks. No app, build, VM or network.
Run: python3 -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import textwrap
import unittest

sys.dont_write_bytecode = True
SCRIPTS = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "scripts")
VHELP = os.path.join(SCRIPTS, "vhelp.py")
VERIFY_SH = os.path.join(SCRIPTS, "verify.sh")
sys.path.insert(0, SCRIPTS)
import vhelp  # noqa: E402

PATH = "/usr/bin:/bin:/usr/sbin:/sbin"


def tmp():
    return os.path.realpath(tempfile.mkdtemp())


def run(cmd, env=None, cwd=None):
    """(exit code, stdout+stderr) of a command run with a minimal environment."""
    p = subprocess.run(cmd, env={"PATH": PATH, "HOME": tmp(), **(env or {})}, cwd=cwd, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout


def read(*parts):
    with open(os.path.join(*parts)) as f:
        return f.read()


def pixel(name, status="Fired", frequency="Standard", params=None):
    """One `log stream --style ndjson` line, as PixelKit's printDebugInfo writes it."""
    message = f"👾[{frequency}-{status}] {name}"
    if params is not None:
        message += " [" + ", ".join('"%s": "%s"' % kv for kv in sorted(params.items())) + "]"
    return json.dumps(dict(eventMessage=message, timestamp="2026-11-19 10:00:00.000000+0000")) + "\n"


def dead_pid():
    p = subprocess.Popen(["/usr/bin/true"])
    p.wait()
    return p.pid


class PixelLineTests(unittest.TestCase):
    def test_a_fired_pixel_with_params(self):
        self.assertEqual(vhelp.parse_pixel('👾[Standard-Fired] m_mac_a ["kind": "two words", "n": "1"]'),
                         dict(name="m_mac_a", status="Fired", frequency="Standard", params={"kind": "two words", "n": "1"}))

    def test_a_dry_run_is_fired_and_a_wide_pixel_has_no_params(self):
        self.assertEqual(vhelp.parse_pixel("👾[Unique-Fired(dryRun)] m_mac_wide_x"),
                         dict(name="m_mac_wide_x", status="Fired", frequency="Unique", params={}))

    def test_skipped_is_not_fired_and_a_frequency_may_have_spaces(self):
        p = vhelp.parse_pixel('👾[Daily and Count-Skipped] m_mac_b ["n": "1"]')
        self.assertEqual((p["status"], p["frequency"], p["name"]), ("Skipped", "Daily and Count", "m_mac_b"))

    def test_other_pixelkit_lines_are_not_pixels(self):
        self.assertIsNone(vhelp.parse_pixel("👾 PixelKit initialised: dryRun: false appVersion: 1.0"))
        self.assertIsNone(vhelp.parse_pixel(None))


class TelemetryTests(unittest.TestCase):
    """mark, expect-pixel, expect-no-pixel and expect-wide-event over a run folder, as verify.sh calls them."""

    def setUp(self):
        self.dir = tmp()
        self.wide = os.path.join(self.dir, "vm-wide.jsonl")
        self.write("pixels.ndjson", "")
        self.write("vm-wide.jsonl", "")
        self.write("pixel_stream.pid", str(os.getpid()))   # a live process: the stream is up

    def write(self, name, text):
        with open(os.path.join(self.dir, name), "a") as f:
            f.write(text)

    def vhelp(self, *args):
        return run([sys.executable, "-I", VHELP, args[0], self.dir, *args[1:]], env={"VERIFY_WIDE_LOG": self.wide})

    def expect(self, *args):
        return self.vhelp("expect-pixel", *args, "--timeout", "0")

    def test_only_pixels_after_the_mark_count(self):
        self.write("pixels.ndjson", pixel("m_mac_a"))
        self.assertEqual(self.vhelp("mark")[0], 0)
        self.assertEqual(self.expect("m_mac_a")[0], 1)
        self.write("pixels.ndjson", "not json\n" + pixel("m_mac_a"))
        code, out = self.expect("m_mac_a")
        self.assertEqual(code, 0, out)
        self.assertEqual([p["name"] for p in json.loads(read(self.dir, "pixels.json"))], ["m_mac_a"])

    def test_skipped_is_not_fired(self):
        self.vhelp("mark")
        self.write("pixels.ndjson", pixel("m_mac_a", "Skipped", "Daily"))
        code, out = self.expect("m_mac_a")
        self.assertEqual(code, 1)
        self.assertIn("skipped by frequency rule", out)

    def test_params_are_checked_on_the_first_fired_pixel_never_searched_for(self):
        self.vhelp("mark")
        self.write("pixels.ndjson", pixel("m_mac_a", params={"n": "1"}) + pixel("m_mac_a", params={"n": "2"}))
        self.assertEqual(self.expect("m_mac_a", "n=1")[0], 0)
        self.assertEqual(self.expect("m_mac_a", "n=2")[0], 1)

    def test_another_pixel_is_not_a_match(self):
        self.vhelp("mark")
        self.write("pixels.ndjson", pixel("m_mac_a_daily"))
        self.assertEqual(self.expect("m_mac_a")[0], 1)

    def test_a_dead_stream_cant_tell(self):
        self.vhelp("mark")
        self.write("pixels.ndjson", pixel("m_mac_a"))
        with open(os.path.join(self.dir, "pixel_stream.pid"), "w") as f:
            f.write(str(dead_pid()))
        code, out = self.expect("m_mac_a")
        self.assertEqual(code, 2)
        self.assertIn("PIXEL STREAM DEAD", out)
        self.assertEqual(self.vhelp("expect-no-pixel", "m_mac_b", "--within", "0")[0], 2)

    def test_without_a_mark_it_cant_tell(self):
        self.write("pixels.ndjson", pixel("m_mac_a"))
        code, out = self.expect("m_mac_a")
        self.assertEqual(code, 2)
        self.assertIn("NO MARK", out)

    def test_expect_no_pixel_fails_only_on_a_fired_pixel_after_the_mark(self):
        self.write("pixels.ndjson", pixel("m_mac_a"))
        self.vhelp("mark")
        self.write("pixels.ndjson", pixel("m_mac_a", "Skipped"))
        self.assertEqual(self.vhelp("expect-no-pixel", "m_mac_a", "--within", "0")[0], 0)
        self.write("pixels.ndjson", pixel("m_mac_a"))
        self.assertEqual(self.vhelp("expect-no-pixel", "m_mac_a", "--within", "0")[0], 1)

    def wide_event(self, feature, status):
        self.write("vm-wide.jsonl", json.dumps(dict(feature=dict(name=feature, status=status))) + "\n")

    def test_a_wide_event_written_before_the_mark_does_not_count(self):
        self.wide_event("sync-setup", "SUCCESS")
        self.vhelp("mark")
        self.assertEqual(self.vhelp("expect-wide-event", "sync-setup", "--timeout", "0")[0], 1)
        self.wide_event("sync-setup", "SUCCESS")
        code, out = self.vhelp("expect-wide-event", "sync-setup", "--timeout", "0")
        self.assertEqual(code, 0, out)

    def test_a_wide_event_with_another_status_fails(self):
        self.vhelp("mark")
        self.wide_event("sync-setup", "FAILURE")
        self.assertEqual(self.vhelp("expect-wide-event", "sync-setup", "--status", "SUCCESS", "--timeout", "0")[0], 1)
        self.assertEqual(self.vhelp("expect-wide-event", "sync-setup", "--status", "FAILURE", "--timeout", "0")[0], 0)


FEATURE_FLAG_SWIFT = textwrap.dedent("""\
    public enum FeatureFlag: String, CaseIterable {
        /// a doc comment
        case plainFlag
        case fixedFlag
        case groupedA
        case groupedB
        case wrappedFixed
        case coveredByDefault
    }

    extension FeatureFlag: FeatureFlagDescribing {
        private var config: Config {
            switch self {
            case .plainFlag:
                Config(source: .remoteReleasable(Sub.plain))
            case .fixedFlag:
                Config(source: .remoteReleasable(Sub.fixed), supportsLocalOverriding: false)
            case .groupedA, .groupedB:
                Config(source: .disabled, supportsLocalOverriding: false)
            case .wrappedFixed:
                Config(defaultValue: .enabled,
                       source: .remoteReleasable(Sub.wrapped),
                       supportsLocalOverriding: false)
            default:
                Config(source: .internalOnly())
            }
        }
    }
    """)


class FlagTests(unittest.TestCase):
    """`verify.sh flag` against a FeatureFlag.swift fixture. Refused flags exit before anything is written."""

    @classmethod
    def setUpClass(cls):
        cls.root = tmp()
        path = os.path.join(cls.root, vhelp.FEATURE_FLAG_SWIFT)
        os.makedirs(os.path.dirname(path))
        with open(path, "w") as f:
            f.write(FEATURE_FLAG_SWIFT)

    def flag(self, name):
        home = tmp()
        code, out = run([VERIFY_SH, "flag", "flag-test", name, "on"],
                        env={"VERIFY_WORKTREE": self.root, "VERIFY_MACOS_HOME": home, "VERIFY_RUN_DIR": home})
        self.assertEqual(sorted(os.listdir(home)), [], "a refused flag wrote state")
        return code, out

    def test_cases_and_the_ones_the_app_ignores(self):
        self.assertEqual(vhelp.feature_flags(self.root),
                         ({"plainFlag", "fixedFlag", "groupedA", "groupedB", "wrappedFixed", "coveredByDefault"},
                          {"fixedFlag", "groupedA", "groupedB", "wrappedFixed"}))

    def test_an_overridable_flag_gets_its_override_key(self):
        self.assertEqual(run([sys.executable, "-I", VHELP, "flag", self.root, "plainFlag"]), (0, "localOverridePlainFlag\n"))

    def test_a_pinned_flag_is_written_where_the_app_reads_overrides(self):
        # A stand-in `defaults`: the real one drops writes to a group container under a made-up HOME.
        home, bin_dir = tmp(), tmp()
        with open(os.path.join(bin_dir, "defaults"), "w") as f:
            f.write('#!/bin/bash\nprintf "%s\\n" "$@" > "$HOME/defaults_args"\n')
        os.chmod(os.path.join(bin_dir, "defaults"), 0o755)
        code, out = run([VERIFY_SH, "flag", "flag-test", "plainFlag", "on"],
                        env={"HOME": home, "PATH": bin_dir + ":" + PATH, "VERIFY_WORKTREE": self.root,
                             "VERIFY_MACOS_HOME": home, "VERIFY_RUN_DIR": home})
        self.assertEqual(code, 0, out)
        suite = "HKE973VLUW.com.duckduckgo.macos.browser.app-configuration.debug"
        domain = os.path.join(home, "Library/Group Containers", suite, "Library/Preferences", suite)
        self.assertEqual(read(home, "defaults_args").splitlines(), ["write", domain, "localOverridePlainFlag", "-bool", "true"])
        self.assertEqual(read(home, "defaults_written"), "config localOverridePlainFlag\n")

    def test_an_unknown_flag_is_refused(self):
        code, out = self.flag("noSuchFlag")
        self.assertEqual(code, 2)
        self.assertIn("UNKNOWN FLAG", out)

    def test_a_flag_the_app_would_ignore_is_refused(self):
        for name in ("fixedFlag", "groupedB", "wrappedFixed"):
            code, out = self.flag(name)
            self.assertEqual(code, 2, name)
            self.assertIn("NOT OVERRIDABLE", out)


class DerivedDataTests(unittest.TestCase):
    """verify.sh's resolve_derived_data: which DerivedData `build` uses for a checkout, and why."""

    def setUp(self):
        self.home = tmp()

    def xcode_folder(self, name, checkout, mtime):
        d = os.path.join(self.home, "Library/Developer/Xcode/DerivedData", name)
        os.makedirs(d)
        with open(os.path.join(d, "info.plist"), "wb") as f:
            plistlib.dump({"WorkspacePath": os.path.join(checkout, "DuckDuckGo.xcworkspace")}, f)
        os.utime(d, (mtime, mtime))
        return d

    def resolve(self, checkout, **env):
        functions = f'sed -n "/^derived_data_of()/,/^}}/p; /^resolve_derived_data()/,/^}}/p" "{VERIFY_SH}"'
        code, out = run(["bash", "-c", f'eval "$({functions})"; resolve_derived_data "$1"', "-", checkout],
                        env={"HOME": self.home, **env})
        self.assertEqual(code, 0, out)
        return tuple(out.rstrip("\n").split("\t"))

    def test_the_environment_wins(self):
        checkout = tmp()
        self.xcode_folder("DuckDuckGo-a", checkout, 1000)
        self.assertEqual(self.resolve(checkout, VERIFY_DERIVED_DATA="/dd"), ("/dd", "VERIFY_DERIVED_DATA"))

    def test_the_newest_xcode_folder_of_this_checkout(self):
        checkout, other = tmp(), tmp()
        self.xcode_folder("DuckDuckGo-old", checkout, 1000)
        newest = self.xcode_folder("DuckDuckGo-new", checkout, 2000)
        self.xcode_folder("DuckDuckGo-other", other, 3000)
        self.assertEqual(self.resolve(checkout), (newest, "this checkout"))

    def test_the_runners_folder_when_xcode_has_none(self):
        checkout = tmp()
        os.makedirs(os.path.join(checkout, ".build/DerivedData"))
        self.assertEqual(self.resolve(checkout), (os.path.join(checkout, ".build/DerivedData"), "this checkout"))

    def test_a_worktree_shares_the_main_checkouts(self):
        main = tmp()
        git = ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-C", main]
        for args in (["init", "-q"], ["commit", "-q", "--allow-empty", "-m", "x"], ["worktree", "add", "-q", "wt"]):
            self.assertEqual(run(git + args)[0], 0)
        shared = self.xcode_folder("DuckDuckGo-main", main, 1000)
        self.assertEqual(self.resolve(os.path.join(main, "wt")), (shared, f"main checkout {main}"))

    def test_otherwise_a_new_one_in_the_checkout(self):
        checkout = tmp()
        self.assertEqual(self.resolve(checkout),
                         (os.path.join(checkout, ".build/DerivedData"), "new (first build is a full build)"))


class VMLockTests(unittest.TestCase):
    """`verify.sh vm` and `cleanup` with a fake ssh: a VM another topic holds is never taken, and cleanup releases only
    its own topic's lock."""

    def setUp(self):
        self.home = tmp()
        self.run_dir = os.path.join(self.home, "run")
        self.locks = os.path.join(self.home, ".vm-locks")
        self.bin = tmp()
        with open(os.path.join(self.bin, "ssh"), "w") as f:
            f.write('#!/bin/sh\nexit "${FAKE_SSH_EXIT:-0}"\n')
        os.chmod(os.path.join(self.bin, "ssh"), 0o755)

    def lock(self, host, topic):
        os.makedirs(os.path.join(self.locks, host))
        with open(os.path.join(self.locks, host, "topic"), "w") as f:
            f.write(topic + "\n")

    def verify(self, *args, ssh_exit=0):
        return run([VERIFY_SH, args[0], "lock-test", *args[1:]],
                   env={"PATH": f"{self.bin}:{PATH}", "FAKE_SSH_EXIT": str(ssh_exit),
                        "VERIFY_MACOS_HOME": self.home, "VERIFY_RUN_DIR": self.run_dir})

    def test_a_vm_another_topic_holds_is_refused_and_kept(self):
        self.lock("vm-x", "other-topic")
        code, out = self.verify("vm", "vm-x")
        self.assertEqual(code, 2)
        self.assertIn("NO VM FREE", out)
        self.assertIn("vm-x: reserved by other-topic", out)
        self.assertEqual(read(self.locks, "vm-x", "topic"), "other-topic\n")
        self.assertFalse(os.path.exists(os.path.join(self.run_dir, "vm")))

    def test_an_unreachable_vm_is_not_left_locked(self):
        code, out = self.verify("vm", "vm-x", ssh_exit=255)
        self.assertEqual(code, 2)
        self.assertIn("NO VM FREE", out)
        self.assertFalse(os.path.exists(os.path.join(self.locks, "vm-x")))

    def test_cleanup_releases_its_own_lock(self):
        self.lock("vm-x", "lock-test")
        os.makedirs(self.run_dir)
        with open(os.path.join(self.run_dir, "vm"), "w") as f:
            f.write("vm-x\n")
        code, out = self.verify("cleanup")
        self.assertEqual(code, 0, out)
        self.assertFalse(os.path.exists(os.path.join(self.locks, "vm-x")))
        self.assertFalse(os.path.exists(os.path.join(self.run_dir, "vm")))

    def test_cleanup_never_releases_another_topics_lock(self):
        self.lock("vm-x", "other-topic")
        os.makedirs(self.run_dir)
        with open(os.path.join(self.run_dir, "vm"), "w") as f:
            f.write("vm-x\n")
        self.assertEqual(self.verify("cleanup")[0], 0)
        self.assertEqual(read(self.locks, "vm-x", "topic"), "other-topic\n")


if __name__ == "__main__":
    unittest.main()
