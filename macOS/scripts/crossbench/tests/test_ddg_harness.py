#!/usr/bin/env python3
"""Focused integration tests for the DDG shell harness using local fakes."""

import hashlib
import json
import os
import plistlib
import socket
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "test-ddg.sh"
MANIFEST_HEADER = (
    "site\tarchive\tsha256\tarchive_bytes\tverdict\treason_code\thttp_status\t"
    "detail\tstatus_chain\tfinal_url\tcontent_type\tblocked_marker\n"
)


def free_ports(count):
    listeners = []
    try:
        for _ in range(count):
            listener = socket.socket()
            listener.bind(("127.0.0.1", 0))
            listeners.append(listener)
        return [listener.getsockname()[1] for listener in listeners]
    finally:
        for listener in listeners:
            listener.close()


class DDGHarnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.archives = self.root / "archives"
        self.app = self.root / "DuckDuckGo Review.app"
        self.executable = self.app / "Contents" / "MacOS" / "DuckDuckGo Review"
        self.bin.mkdir()
        self.archives.mkdir()
        self.executable.parent.mkdir(parents=True)
        with (self.app / "Contents" / "Info.plist").open("wb") as output:
            plistlib.dump(
                {
                    "CFBundleShortVersionString": "99.1",
                    "CFBundleVersion": "99A1",
                    "CFBundleIdentifier": "com.duckduckgo.macos.browser.review",
                    "CFBundleExecutable": self.executable.name,
                },
                output,
            )
        self.wpr_http, self.wpr_https, self.tsproxy, self.automation = (
            free_ports(4)
        )
        self.app_launches = self.root / "app-launches.jsonl"
        self.tsproxy_args = self.root / "tsproxy-args.json"
        self.tsproxy_launches = self.root / "tsproxy-launches.jsonl"
        self._write_fakes()
        cert = self.root / "cert.pem"
        key = self.root / "key.pem"
        cert.write_text("cert")
        key.write_text("key")
        self.env = {
            **os.environ,
            "PYTHON_BIN": sys.executable,
            "WPR_DIR": str(self.archives),
            "WPR_ARCHIVES_PREPARED": "1",
            "WPR_BIN": str(self.bin / "fake-wpr"),
            "WPR_HTTP_PORT": str(self.wpr_http),
            "WPR_HTTPS_PORT": str(self.wpr_https),
            "WPR_CERT_FILE": str(cert),
            "WPR_KEY_FILE": str(key),
            "TSPROXY_PY": str(self.bin / "fake-tsproxy.py"),
            "TSPROXY_PORT": str(self.tsproxy),
            "DDG_APP": str(self.app),
            "DDG_AUTOMATION_PY": str(self.bin / "fake-automation.py"),
            "DDG_LAUNCHER": str(self.bin / "fake-launcher"),
            "DDG_AUTOMATION_HOST": "127.0.0.1",
            "AUTOMATION_PORT": str(self.automation),
            "APP_LAUNCHES_FILE": str(self.app_launches),
            "TSPROXY_ARGS_FILE": str(self.tsproxy_args),
            "TSPROXY_LAUNCHES_FILE": str(self.tsproxy_launches),
            "LOAD_WINDOW_SECONDS": "0",
            "ALLOW_TEST_OVERRIDES": "1",
            "LCP_SETTLE_MS": "0",
            "REPETITION_TIMEOUT_SECONDS": "3",
            "SERVICE_START_TIMEOUT_SECONDS": "1",
            "RESULTS_DIR": str(self.root / "results"),
            "DISPOSITIONS_DIR": str(self.root / "dispositions"),
            "DIAGNOSTICS_DIR": str(self.root / "diagnostics"),
        }
        self.add_valid_site("apple.com")

    def tearDown(self):
        self.temp.cleanup()

    def _write_executable(self, path, source):
        path.write_text(textwrap.dedent(source).lstrip())
        path.chmod(0o755)

    def _write_fakes(self):
        listener_source = r"""
            #!/usr/bin/env python3
            import os
            import socket
            import sys
            import time

            start_failure = os.environ.get("FAKE_WPR_FIRST_START_FAILURE_MARKER")
            if start_failure and not os.path.exists(start_failure):
                open(start_failure, "w", encoding="utf-8").close()
                raise SystemExit(9)
            die_on_request = False
            death_marker = os.environ.get("FAKE_WPR_FIRST_DEATH_MARKER")
            if death_marker and not os.path.exists(death_marker):
                open(death_marker, "w", encoding="utf-8").close()
                die_on_request = True
            ports = []
            for arg in sys.argv[1:]:
                if arg.startswith("--http-port=") or arg.startswith("--https-port="):
                    ports.append(int(arg.split("=", 1)[1]))
            listeners = []
            for port in ports:
                sock = socket.socket()
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.bind(("127.0.0.1", port))
                sock.listen()
                sock.settimeout(0.1)
                listeners.append(sock)
            while True:
                for sock in listeners:
                    try:
                        client, _ = sock.accept()
                        data = client.recv(1024)
                        client.close()
                        if data == b"die" and die_on_request:
                            raise SystemExit(8)
                        if data == b"replay-miss":
                            print(
                                'level=WARN msg="Proxy: FAILED to find request"',
                                file=sys.stderr,
                                flush=True,
                            )
                    except socket.timeout:
                        pass
                time.sleep(0.01)
        """
        self._write_executable(self.bin / "fake-wpr", listener_source)
        self._write_executable(
            self.bin / "fake-tsproxy.py",
            r"""
            #!/usr/bin/env python3
            import json
            import os
            import socket
            import sys

            args = sys.argv[1:]
            with open(os.environ["TSPROXY_ARGS_FILE"], "w", encoding="utf-8") as out:
                json.dump(args, out)
            with open(
                os.environ["TSPROXY_LAUNCHES_FILE"], "a", encoding="utf-8"
            ) as out:
                out.write(json.dumps({"args": args, "pid": os.getpid()}) + "\n")
            port = int(args[args.index("--port") + 1])
            listener = socket.socket()
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", port))
            listener.listen()
            resolved = set()
            while True:
                client, _ = listener.accept()
                data = client.recv(1024).decode(errors="replace").strip()
                client.close()
                if data:
                    if data not in resolved:
                        resolved.add(data)
                        print(
                            "12:00:00.000 - [1] Resolving b'{}':443".format(data),
                            file=sys.stderr,
                            flush=True,
                        )
                    if os.environ.get("FAKE_TSPROXY_EXIT_AFTER_ROUTE") == "1":
                        raise SystemExit(0)
            """,
        )
        self._write_executable(
            self.executable,
            r"""
            #!/usr/bin/env python3
            import json
            import os
            import socket
            import sys
            import time

            args = sys.argv[1:]
            port = int(args[args.index("-automationPort") + 1])
            with open(os.environ["APP_LAUNCHES_FILE"], "a", encoding="utf-8") as out:
                out.write(json.dumps({
                    "args": args,
                    "pid": os.getpid(),
                    "token": os.environ.get("AUTOMATION_TOKEN", ""),
                }) + "\n")
            fail_marker = os.environ.get("FAKE_APP_FAIL_FIRST_MARKER")
            if fail_marker and not os.path.exists(fail_marker):
                open(fail_marker, "w", encoding="utf-8").close()
                raise SystemExit(9)
            if os.environ.get("FAKE_APP_START_FAILURE") == "1":
                raise SystemExit(9)
            log_bytes = int(os.environ.get("FAKE_APP_LOG_BYTES", "0"))
            if log_bytes:
                print("x" * log_bytes, file=sys.stderr, flush=True)
            listener = socket.socket()
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", port))
            listener.listen()
            while True:
                client, _ = listener.accept()
                data = client.recv(1024)
                client.close()
                if data == b"shutdown":
                    time.sleep(
                        float(
                            os.environ.get(
                                "FAKE_APP_SHUTDOWN_DELAY_SECONDS", "0"
                            )
                        )
                    )
                    break
            """,
        )
        self._write_executable(
            self.bin / "fake-launcher",
            r"""
            #!/usr/bin/env bash
            set -euo pipefail
            app="$1"
            executable="$2"
            log_file="$3"
            shift 3
            [ "$1" = -- ]
            shift
            [ -d "$app" ]
            "$executable" "$@" >>"$log_file" 2>&1 &
            printf '%s\n' "$!"
            """,
        )
        self._write_executable(
            self.bin / "fake-automation.py",
            r"""
            #!/usr/bin/env python3
            import json
            import os
            import socket
            import sys
            import time
            import urllib.parse

            port = int(sys.argv[1])
            command = sys.argv[2]
            with open(
                os.environ["APP_LAUNCHES_FILE"], encoding="utf-8"
            ) as launches:
                expected_token = json.loads(launches.readlines()[-1])["token"]
            if os.environ.get("AUTOMATION_TOKEN") != expected_token:
                raise SystemExit(8)
            if command == "check":
                # Emulates a window that only appears after a few polls.
                budget = int(os.environ.get("AUTOMATION_CHECK_FAILURES", "0"))
                if budget:
                    counter = os.path.join(
                        os.path.dirname(os.environ["APP_LAUNCHES_FILE"]),
                        "check-attempts",
                    )
                    attempts = 0
                    if os.path.exists(counter):
                        with open(counter, encoding="utf-8") as source:
                            attempts = int(source.read() or "0")
                    attempts += 1
                    with open(counter, "w", encoding="utf-8") as sink:
                        sink.write(str(attempts))
                    if attempts <= budget:
                        raise SystemExit(1)
                raise SystemExit(0)
            if command == "shutdown":
                with socket.create_connection(("127.0.0.1", port)) as client:
                    client.sendall(b"shutdown")
                raise SystemExit(0)

            url = sys.argv[3]
            site = urllib.parse.urlparse(url).hostname
            mode = os.environ.get("AUTOMATION_MODE", "success")
            fail_site = os.environ.get("AUTOMATION_FAIL_SITE", "")
            time.sleep(float(os.environ.get("AUTOMATION_DELAY_SECONDS", "0")))
            if mode == "hang":
                time.sleep(10)
            if mode == "malformed":
                print("detail=malformed")
                raise SystemExit(0)
            if mode != "no_route":
                with socket.create_connection(
                    ("127.0.0.1", int(os.environ["TSPROXY_PORT"]))
                ) as proxy:
                    proxy.sendall(site.encode())
            if site == os.environ.get("AUTOMATION_KILL_WPR_SITE"):
                with socket.create_connection(
                    ("127.0.0.1", int(os.environ["WPR_HTTP_PORT"]))
                ) as wpr:
                    wpr.sendall(b"die")
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    try:
                        with socket.create_connection(
                            ("127.0.0.1", int(os.environ["WPR_HTTP_PORT"]))
                        ):
                            pass
                    except OSError:
                        break
                    time.sleep(0.01)
            if mode == "replay_miss":
                with socket.create_connection(
                    ("127.0.0.1", int(os.environ["WPR_HTTP_PORT"]))
                ) as wpr:
                    wpr.sendall(b"replay-miss")
                time.sleep(0.1)
            landed = (
                "https://offsite.test/"
                if mode == "offsite"
                else "https://{}/".format(site)
            )
            lcp = (
                -1
                if mode == "unfinalized"
                else -2
                if mode == "invalid_negative"
                else 1000
            )
            offsite = 1 if mode == "offsite" else 0
            print('detail={{"ms":{},"loc":"{}"}}'.format(lcp, landed))
            print("landed_url={}".format(landed))
            print("landed_offsite={}".format(offsite))
            print("lcp_ms={}".format(lcp))
            if (
                site == fail_site
                or mode in ("failure", "offsite", "invalid_negative")
            ):
                raise SystemExit(7)
            """,
        )

    def add_valid_site(self, site):
        archive = self.archives / "navToLCP_{}.wprgo".format(site)
        data = site.encode()
        archive.write_bytes(data)
        manifest = self.archives / "manifest.tsv"
        if not manifest.exists():
            manifest.write_text(MANIFEST_HEADER)
        with manifest.open("a") as output:
            output.write(
                "{}\t{}\t{}\t{}\tok\t\t\t\t200\thttps://{}/\ttext/html\t\n".format(
                    site,
                    archive.name,
                    hashlib.sha256(data).hexdigest(),
                    len(data),
                    site,
                )
            )

    def run_harness(self, sites="apple.com", reps="1", **env):
        return subprocess.run(
            ["/bin/bash", str(SCRIPT), "--sites", sites, "--reps", reps],
            cwd=self.root,
            env={**self.env, **env},
            text=True,
            capture_output=True,
            timeout=30,
        )

    def disposition_rows(self):
        path = next((self.root / "dispositions").glob("*.tsv"))
        return [
            line.split("\t") for line in path.read_text().splitlines()[1:]
        ]

    def measurement_rows(self):
        path = next((self.root / "results").glob("*.tsv"))
        return [
            line.split("\t") for line in path.read_text().splitlines()[1:]
        ]

    def launches(self):
        return [
            json.loads(line) for line in self.app_launches.read_text().splitlines()
        ]

    def shaping_launches(self):
        return [
            json.loads(line)
            for line in self.tsproxy_launches.read_text().splitlines()
        ]

    def test_success_uses_fresh_authenticated_app_per_repetition(self):
        result = self.run_harness(reps="2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.measurement_rows()), 2)
        launches = self.launches()
        self.assertEqual(len(launches), 2)
        shaping_launches = self.shaping_launches()
        self.assertEqual(len(shaping_launches), 2)
        self.assertEqual(len({item["token"] for item in launches}), 2)
        for launch in launches:
            self.assertTrue(launch["token"])
            self.assertNotIn(launch["token"], launch["args"])
            self.assertIn(
                "socks5://127.0.0.1:{}".format(self.tsproxy),
                launch["args"],
            )
            self.assertIn("-isOnboardingCompleted", launch["args"])
            self.assertIn("-acceptInsecureCerts", launch["args"])
            # A normal launch arms Sparkle, which must not reach the network
            # mid-measurement.
            self.assertEqual(
                launch["args"][launch["args"].index("-SUEnableAutomaticChecks") + 1],
                "false",
            )
            self.assertNotIn(launch["token"], result.stdout + result.stderr)
            with self.assertRaises(ProcessLookupError):
                os.kill(launch["pid"], 0)

    def test_readiness_gate_waits_for_the_window_instead_of_giving_up(self):
        result = self.run_harness(AUTOMATION_CHECK_FAILURES="3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.measurement_rows()), 1)

    def test_readiness_gate_gives_up_within_its_budget(self):
        result = self.run_harness(
            AUTOMATION_CHECK_FAILURES="1000",
            AUTOMATION_READY_TIMEOUT_SECONDS="1",
        )
        self.assertIn(
            "did not report a ready window", result.stdout + result.stderr
        )
        self.assertEqual(
            self.disposition_rows()[0][9:11], ["automation", "app_start_failed"]
        )

    def test_delayed_shutdown_releases_port_before_next_launch(self):
        result = self.run_harness(
            reps="2",
            FAKE_APP_SHUTDOWN_DELAY_SECONDS="0.5",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.launches()), 2)

    def test_cleanup_uses_owned_pids_and_precedes_reporting(self):
        harness = SCRIPT.read_text()
        self.assertNotIn("pkill", harness)
        self.assertNotIn("killall", harness)
        self.assertIn('stop_exact_pid "$DDG_PID"', harness)
        self.assertIn('stop_exact_pid "$WPR_PID"', harness)
        self.assertIn('stop_exact_pid "$TSPROXY_PID"', harness)
        self.assertNotIn("finalize_shared_proxy", harness)

    def test_tsproxy_uses_wpr_preset_and_no_http_proxy(self):
        result = self.run_harness()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.tsproxy_args.read_text())
        for option, value in (
            ("--rtt", "28"),
            ("--inkbps", "50000"),
            ("--outkbps", "10000"),
            ("--window", "10"),
        ):
            self.assertEqual(args[args.index(option) + 1], value)
        self.assertEqual(
            args[args.index("--mapports") + 1],
            "443:{},*:{}".format(self.wpr_https, self.wpr_http),
        )
        self.assertNotIn("httpproxy", result.stdout + result.stderr)
        self.assertNotIn("WebKit2HTTPProxy", result.stdout + result.stderr)

    def test_site_automation_failure_continues_to_later_site(self):
        self.add_valid_site("example.com")
        result = self.run_harness(
            sites="apple.com,example.com",
            AUTOMATION_FAIL_SITE="apple.com",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [(row[2], row[3]) for row in self.disposition_rows()],
            [("apple.com", "infra_error"), ("example.com", "measured")],
        )
        self.assertEqual(len(self.measurement_rows()), 1)

    def test_missing_proxy_route_is_site_infrastructure_error(self):
        result = self.run_harness(AUTOMATION_MODE="no_route")
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3], "infra_error")
        self.assertEqual(row[9:11], ["replay", "missing_proxy_route"])

    def test_wpr_subresource_miss_does_not_reject_valid_measurement(self):
        result = self.run_harness(AUTOMATION_MODE="replay_miss")
        self.assertEqual(result.returncode, 0, result.stderr)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3], "measured")
        self.assertEqual(row[9:11], ["-", "-"])
        self.assertEqual(len(self.measurement_rows()), 1)

    def test_offsite_landing_keeps_specific_failure_reason(self):
        result = self.run_harness(AUTOMATION_MODE="offsite")
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[9:11], ["replay", "offsite_landing"])

    def test_invalid_negative_lcp_is_not_unfinalized(self):
        result = self.run_harness(AUTOMATION_MODE="invalid_negative")
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[9:11], ["automation", "invalid_lcp"])

    def test_live_app_log_is_bounded_before_preservation(self):
        result = self.run_harness(
            AUTOMATION_MODE="failure",
            FAKE_APP_LOG_BYTES="16384",
            MAX_LIVE_LOG_BYTES="1024",
            MAX_DIAGNOSTIC_BYTES="4096",
        )
        self.assertEqual(result.returncode, 1)
        logs = list((self.root / "diagnostics").glob("ddg-*.log"))
        self.assertTrue(logs)
        self.assertTrue(all(path.stat().st_size <= 1024 for path in logs))

    def test_app_metadata_and_executable_are_derived_from_bundle(self):
        result = self.run_harness(
            DDG_EXECUTABLE="/tmp/not-the-app",
            DDG_MARKETING_VERSION="forged",
            DDG_BUILD_VERSION="forged",
            DDG_BUNDLE_ID="com.example.production",
            ALLOW_TEST_OVERRIDES="0",
            LOAD_WINDOW_SECONDS="12",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.measurement_rows()[0][1], "99.1 (99A1)")
        self.assertGreater(self.launches()[0]["pid"], 0)

    def test_validator_error_excludes_site_without_live_fallback(self):
        manifest = self.archives / "manifest.tsv"
        fields = manifest.read_text().splitlines()[1].split("\t")
        fields[4:7] = ["error", "http_403", "403"]
        manifest.write_text(MANIFEST_HEADER + "\t".join(fields) + "\n")
        result = self.run_harness()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.disposition_rows()[0][3:7],
            ["excluded", "error", "http_403", "403"],
        )
        self.assertFalse(self.app_launches.exists())

    def test_tsproxy_death_isolated_but_zero_samples_fails_run(self):
        self.add_valid_site("example.com")
        result = self.run_harness(
            sites="apple.com,example.com",
            FAKE_TSPROXY_EXIT_AFTER_ROUTE="1",
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            [(row[2], row[3]) for row in self.disposition_rows()],
            [("apple.com", "infra_error"), ("example.com", "infra_error")],
        )
        self.assertEqual(
            self.disposition_rows()[1][9:11],
            ["shaping", "tsproxy_exited"],
        )
        self.assertEqual(len(self.shaping_launches()), 2)

    def test_tsproxy_death_overrides_nonzero_automation_result(self):
        result = self.run_harness(
            FAKE_TSPROXY_EXIT_AFTER_ROUTE="1",
            AUTOMATION_MODE="failure",
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            self.disposition_rows()[0][9:11],
            ["shaping", "tsproxy_exited"],
        )

    def test_app_start_failure_continues_without_breaking_accounting(self):
        result = self.run_harness(
            reps="2",
            FAKE_APP_FAIL_FIRST_MARKER=str(self.root / "app-failed"),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3], "infra_error")
        self.assertEqual(row[12:17], ["2", "1", "1", "0", "0"])

    def test_malformed_output_is_not_observed_or_no_metric(self):
        result = self.run_harness(AUTOMATION_MODE="malformed")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            self.disposition_rows()[0][12:17],
            ["1", "0", "0", "0", "0"],
        )

    def test_watchdog_timeout_has_stable_reason(self):
        result = self.run_harness(
            AUTOMATION_MODE="hang",
            REPETITION_TIMEOUT_SECONDS="3",
        )
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[9:11], ["automation", "watchdog_timeout"])
        self.assertEqual(row[12:17], ["1", "0", "0", "0", "0"])

    def test_wpr_start_failure_is_isolated_and_later_site_runs(self):
        self.add_valid_site("example.com")
        result = self.run_harness(
            sites="apple.com,example.com",
            FAKE_WPR_FIRST_START_FAILURE_MARKER=str(
                self.root / "wpr-start-failed"
            ),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [(row[2], row[3]) for row in self.disposition_rows()],
            [("apple.com", "infra_error"), ("example.com", "measured")],
        )
        self.assertEqual(
            self.disposition_rows()[0][9:11],
            ["replay", "wpr_start_failed"],
        )

    def test_wpr_death_overrides_automation_and_later_site_runs(self):
        self.add_valid_site("example.com")
        result = self.run_harness(
            sites="apple.com,example.com",
            AUTOMATION_FAIL_SITE="apple.com",
            AUTOMATION_KILL_WPR_SITE="apple.com",
            FAKE_WPR_FIRST_DEATH_MARKER=str(self.root / "wpr-died"),
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [(row[2], row[3]) for row in self.disposition_rows()],
            [("apple.com", "infra_error"), ("example.com", "measured")],
        )
        self.assertEqual(
            self.disposition_rows()[0][9:11],
            ["replay", "wpr_exited"],
        )

    def test_zero_total_samples_is_run_fatal(self):
        result = self.run_harness(AUTOMATION_MODE="unfinalized")
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3], "no_samples")
        self.assertEqual(row[12:17], ["1", "1", "0", "1", "0"])
        self.assertIn("no usable LCP samples", result.stderr)

    def test_invalid_handoff_is_run_fatal_but_later_site_is_accounted(self):
        self.add_valid_site("example.com")
        lines = (self.archives / "manifest.tsv").read_text().splitlines()
        fields = lines[1].split("\t")
        fields[2] = "invalid"
        lines[1] = "\t".join(fields)
        (self.archives / "manifest.tsv").write_text("\n".join(lines) + "\n")
        result = self.run_harness(sites="apple.com,example.com")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            [(row[2], row[3]) for row in self.disposition_rows()],
            [("apple.com", "infra_error"), ("example.com", "measured")],
        )

    def test_screenshots_are_opt_in_and_never_fail_the_run(self):
        """A tiny LCP candidate and an unpainted page produce the same number."""
        harness = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("capture_screenshot() {", harness)
        self.assertIn('CAPTURE_SCREENSHOTS="${CAPTURE_SCREENSHOTS:-0}"', harness)
        self.assertIn("bounded_integer CAPTURE_SCREENSHOTS 0 1", harness)
        # Captured after the measurement and before the app goes away, so the
        # image shows the page the LCP number was read from.
        measure_then_capture = harness.index('capture_screenshot "$site" "$rep"')
        self.assertLess(
            harness.index('measure "$navigation_url"'), measure_then_capture
        )
        self.assertLess(
            measure_then_capture,
            harness.index("if ! shutdown_app", measure_then_capture),
        )
        # Diagnostics must not decide whether a run passes: the helper logs
        # its own failure instead of propagating one under `set -euo pipefail`.
        body = harness[
            harness.index("capture_screenshot() {") :
            harness.index("record_machine_load() {")
        ]
        self.assertIn('log "screenshot: capture failed', body)
        self.assertIn("/usr/sbin/screencapture -x", body)
        self.assertIn('log "screen: capture failed', body)
        self.assertNotIn("set_shared_failure", body)
        self.assertNotIn("exit 1", body)

    def test_screenshot_runs_keep_the_replay_log(self):
        """A green run discards the only record of what failed to load."""
        harness = SCRIPT.read_text(encoding="utf-8")
        gate = harness[
            harness.index('if [ "$site_failed" -ne 0 ]') :
            harness.index('preserve_site_diagnostics "$site"',
                          harness.index('if [ "$site_failed" -ne 0 ]'))
        ]
        self.assertIn('[ "$CAPTURE_SCREENSHOTS" = 1 ]', gate)

    def test_screenshot_verb_exists_in_automation_client(self):
        """The harness cannot capture what the client cannot request."""
        client = (SCRIPT.parent / "ddg-automation.py").read_text(encoding="utf-8")
        self.assertIn('command == "screenshot"', client)
        self.assertIn('request(port, "GET", "/screenshot"', client)
        self.assertIn("base64.b64decode", client)

    def test_machine_load_is_recorded_between_sites(self):
        """A run-long transient looks identical to a real regression."""
        harness = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("record_machine_load() {", harness)
        self.assertIn('record_machine_load "before $site"', harness)
        self.assertIn('record_machine_load "after $site"', harness)
        # Sampled between sites only. Inside measure_site it would land in a
        # timed repetition and perturb the very number it exists to explain.
        measure = harness[
            harness.index("measure_site() {") :
            harness.index("# Records what else the machine was doing")
        ]
        self.assertNotIn("record_machine_load", measure)


if __name__ == "__main__":
    unittest.main()
