#!/usr/bin/env python3

import hashlib
import json
import os
import socket
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "test-safari.sh"
MANIFEST_HEADER = (
    "site\tarchive\tsha256\tarchive_bytes\tverdict\treason_code\thttp_status\t"
    "detail\tstatus_chain\tfinal_url\tcontent_type\tblocked_marker\n"
)


def free_ports(count: int) -> list[int]:
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


class SafariHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.archives = self.root / "archives"
        self.safari_app = self.root / "Safari.app"
        self.bin.mkdir()
        self.archives.mkdir()
        self.safari_app.mkdir()
        self.defaults_state = self.root / "defaults.json"
        self.defaults_state.write_text("{}")
        self._write_fakes()

        (
            self.wpr_http_port,
            self.wpr_https_port,
            self.tsproxy_port,
            self.httpproxy_port,
            self.safaridriver_port,
        ) = free_ports(5)

        cert = self.root / "cert.pem"
        key = self.root / "key.pem"
        cert.write_text("cert")
        key.write_text("key")
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "PYTHON_BIN": sys.executable,
            "WPR_DIR": str(self.archives),
            "WPR_ARCHIVES_PREPARED": "1",
            "WPR_BIN": str(self.bin / "fake-wpr"),
            "WPR_HTTP_PORT": str(self.wpr_http_port),
            "WPR_HTTPS_PORT": str(self.wpr_https_port),
            "WPR_CERT_FILE": str(cert),
            "WPR_KEY_FILE": str(key),
            "TSPROXY_PY": str(self.bin / "fake-listener.py"),
            "TSPROXY_PORT": str(self.tsproxy_port),
            "HTTPPROXY_PY": str(self.bin / "fake-httpproxy.py"),
            "HTTPPROXY_PORT": str(self.httpproxy_port),
            "SAFARI_AUTOMATION_PY": str(self.bin / "fake-automation.py"),
            "SAFARIDRIVER_PORT": str(self.safaridriver_port),
            "SAFARI_APP": str(self.safari_app),
            "DEFAULTS_STATE": str(self.defaults_state),
            "ASSUME_YES": "1",
            "LCP_SETTLE_MS": "0",
            "RESULTS_DIR": str(self.root / "results"),
            "DISPOSITIONS_DIR": str(self.root / "dispositions"),
            "DIAGNOSTICS_DIR": str(self.root / "diagnostics"),
        }
        self.add_valid_site("apple.com")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _write_executable(self, name: str, source: str) -> Path:
        path = self.bin / name
        path.write_text(textwrap.dedent(source).lstrip())
        path.chmod(0o755)
        return path

    def _write_fakes(self) -> None:
        self._write_executable(
            "defaults",
            r"""
            #!/usr/bin/env python3
            import json
            import os
            import socket
            import sys

            state_path = os.environ["DEFAULTS_STATE"]
            with open(state_path, encoding="utf-8") as source:
                state = json.load(source)
            command = sys.argv[1]
            domain = sys.argv[2]
            key = sys.argv[3] if len(sys.argv) > 3 else ""
            if command == "read" and domain.endswith("Info.plist"):
                print("99.1" if key == "CFBundleShortVersionString" else "99A1")
                raise SystemExit(0)
            if command == "read":
                if key not in state:
                    raise SystemExit(1)
                print(state[key])
            elif command == "read-type":
                if key not in state:
                    raise SystemExit(1)
                if key == os.environ.get("DEFAULTS_NON_STRING_KEY"):
                    print("Type is integer")
                else:
                    print("Type is string")
            elif command == "write":
                value = sys.argv[-1]
                if (
                    key == os.environ.get("DEFAULTS_FAIL_APPLY_KEY")
                    and value.startswith("http://127.0.0.1:")
                ):
                    raise SystemExit(8)
                if (
                    key == os.environ.get("DEFAULTS_FAIL_RESTORE_KEY")
                    and not value.startswith("http://127.0.0.1:")
                ):
                    raise SystemExit(9)
                if (
                    os.environ.get("DEFAULTS_REQUIRE_PROXY_ON_RESTORE") == "1"
                    and not value.startswith("http://127.0.0.1:")
                ):
                    with socket.create_connection(
                        ("127.0.0.1", int(os.environ["HTTPPROXY_PORT"]))
                    ):
                        pass
                state[key] = value
            elif command == "delete":
                if os.environ.get("DEFAULTS_REQUIRE_PROXY_ON_RESTORE") == "1":
                    with socket.create_connection(
                        ("127.0.0.1", int(os.environ["HTTPPROXY_PORT"]))
                    ):
                        pass
                state.pop(key, None)
            else:
                raise SystemExit(2)
            with open(state_path, "w", encoding="utf-8") as output:
                json.dump(state, output)
            """,
        )
        listener = self._write_executable(
            "fake-listener.py",
            r"""
            #!/usr/bin/env python3
            import os
            import socket
            import sys
            import time

            args = sys.argv[1:]
            ports = []
            for index, arg in enumerate(args):
                if arg == "-p":
                    ports.append(int(args[index + 1]))
                elif arg == "--port":
                    ports.append(int(args[index + 1]))
                elif arg.startswith("--http-port=") or arg.startswith("--https-port="):
                    ports.append(int(arg.split("=", 1)[1]))
            exit_at = None
            if any(arg.startswith("--http-port=") for arg in args):
                marker = os.environ.get("FAKE_WPR_FIRST_EXIT_MARKER")
                if marker and not os.path.exists(marker):
                    open(marker, "w", encoding="utf-8").close()
                    exit_at = time.monotonic() + 0.8
            listeners = []
            for port in ports:
                sock = socket.socket()
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.bind(("127.0.0.1", port))
                sock.listen()
                listeners.append(sock)
            while True:
                if exit_at is not None and time.monotonic() >= exit_at:
                    raise SystemExit(0)
                for sock in listeners:
                    sock.settimeout(0.1)
                    try:
                        client, _ = sock.accept()
                        client.close()
                    except socket.timeout:
                        pass
            """,
        )
        (self.bin / "fake-wpr").write_text(listener.read_text())
        (self.bin / "fake-wpr").chmod(0o755)
        (self.bin / "safaridriver").write_text(listener.read_text())
        (self.bin / "safaridriver").chmod(0o755)
        self._write_executable(
            "fake-httpproxy.py",
            r"""
            #!/usr/bin/env python3
            import os
            import socket
            import sys
            import threading

            listener = socket.socket()
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", int(sys.argv[1])))
            listener.listen()
            def handle(client):
                data = client.recv(4096).decode(errors="replace")
                if data:
                    request = data.splitlines()[0].split()
                    print(" ".join(request[:2]), file=sys.stderr, flush=True)
                client.close()
            while True:
                client, _ = listener.accept()
                threading.Thread(target=handle, args=(client,), daemon=True).start()
                if os.environ.get("FAKE_HTTPPROXY_EXIT_AFTER_ACCEPT") == "1":
                    raise SystemExit(0)
            """,
        )
        self._write_executable(
            "fake-automation.py",
            r"""
            #!/usr/bin/env python3
            import os
            import socket
            import sys
            import time
            import urllib.parse

            command = sys.argv[2]
            if command == "check":
                raise SystemExit(0)
            url = sys.argv[3]
            site = urllib.parse.urlparse(url).hostname
            mode = os.environ.get("AUTOMATION_MODE", "success")
            fail_site = os.environ.get("AUTOMATION_FAIL_SITE", "")
            delay_site = os.environ.get("AUTOMATION_DELAY_SITE", "")
            if site == delay_site:
                time.sleep(1)
            if site == fail_site or mode == "failure":
                print("simulated automation failure", file=sys.stderr)
                raise SystemExit(7)
            if mode == "malformed":
                print("detail=missing required fields")
                raise SystemExit(0)
            if mode != "no_connect":
                with socket.create_connection(
                    ("127.0.0.1", int(os.environ["HTTPPROXY_PORT"]))
                ) as proxy:
                    proxy.sendall(
                        f"CONNECT {site}:443 HTTP/1.1\r\n\r\n".encode()
                    )
                time.sleep(0.05)
            lcp = "-1" if mode == "unfinalized" else "1000"
            landed_url = "https://offsite.test/" if mode == "offsite" else f"{url}/"
            offsite = "garbage" if mode == "invalid_offsite" else (
                "1" if mode == "offsite" else "0"
            )
            print(f'detail={{"ms": {lcp}, "loc": "{landed_url}"}}')
            print(f"landed_url={landed_url}")
            print(f"landed_offsite={offsite}")
            print(f"lcp_ms={lcp}")
            if mode == "structured_failure":
                raise SystemExit(7)
            """,
        )

    def add_valid_site(self, site: str) -> None:
        archive = self.archives / f"navToLCP_{site}.wprgo"
        archive.write_bytes(site.encode())
        sha = hashlib.sha256(site.encode()).hexdigest()
        manifest = self.archives / "manifest.tsv"
        if not manifest.exists():
            manifest.write_text(MANIFEST_HEADER)
        with manifest.open("a") as output:
            output.write(
                f"{site}\t{archive.name}\t{sha}\t{len(site)}\tok\t\t\t\t"
                f"200\thttps://{site}/\ttext/html\t\n"
            )

    def run_harness(
        self, sites: str = "apple.com", **env: str
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["/bin/bash", str(SCRIPT), "--sites", sites, "--reps", "1", "--yes"],
            cwd=self.root,
            env={**self.env, **env},
            text=True,
            capture_output=True,
            timeout=30,
        )

    def disposition_rows(self) -> list[list[str]]:
        path = next((self.root / "dispositions").glob("*.tsv"))
        return [
            line.split("\t")
            for line in path.read_text().splitlines()[1:]
        ]

    def measurement_rows(self) -> list[list[str]]:
        path = next((self.root / "results").glob("*.tsv"))
        return [
            line.split("\t")
            for line in path.read_text().splitlines()[1:]
        ]

    def test_success_records_metric_and_restores_absent_preferences(self) -> None:
        result = self.run_harness()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.measurement_rows()), 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[1], "99.1 (99A1)")
        self.assertEqual(row[2:5], ["apple.com", "measured", "ok"])
        self.assertEqual(row[12:17], ["1", "1", "1", "0", "0"])
        self.assertEqual(json.loads(self.defaults_state.read_text()), {})

    def test_unfinalized_lcp_is_not_an_infrastructure_failure(self) -> None:
        result = self.run_harness(AUTOMATION_MODE="unfinalized")
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3], "no_samples")
        self.assertEqual(row[12:17], ["1", "1", "0", "1", "0"])
        self.assertNotIn("browser harness failures", result.stderr)

    def test_preexisting_preferences_are_restored_exactly(self) -> None:
        expected = {
            "WebKit2HTTPProxy": "http://old-http.test:8080",
            "WebKit2HTTPSProxy": "http://old-https.test:8443",
        }
        self.defaults_state.write_text(json.dumps(expected))
        result = self.run_harness()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.defaults_state.read_text()), expected)

    def test_restore_failure_fails_run_and_attempts_other_key(self) -> None:
        initial = {
            "WebKit2HTTPProxy": "http://old-http.test:8080",
            "WebKit2HTTPSProxy": "http://old-https.test:8443",
        }
        self.defaults_state.write_text(json.dumps(initial))
        result = self.run_harness(
            DEFAULTS_FAIL_RESTORE_KEY="WebKit2HTTPProxy"
        )
        self.assertEqual(result.returncode, 1)
        restored = json.loads(self.defaults_state.read_text())
        self.assertEqual(
            restored["WebKit2HTTPSProxy"], initial["WebKit2HTTPSProxy"]
        )
        self.assertNotEqual(
            restored["WebKit2HTTPProxy"], initial["WebKit2HTTPProxy"]
        )
        self.assertIn("failed to restore Safari proxy preferences", result.stderr)

    def test_partial_proxy_application_restores_both_original_values(self) -> None:
        initial = {
            "WebKit2HTTPProxy": "http://old-http.test:8080",
            "WebKit2HTTPSProxy": "http://old-https.test:8443",
        }
        self.defaults_state.write_text(json.dumps(initial))
        result = self.run_harness(
            DEFAULTS_FAIL_APPLY_KEY="WebKit2HTTPSProxy"
        )
        self.assertEqual(result.returncode, 8)
        self.assertEqual(json.loads(self.defaults_state.read_text()), initial)

    def test_cleanup_restores_preferences_while_proxy_is_alive(self) -> None:
        result = self.run_harness(DEFAULTS_REQUIRE_PROXY_ON_RESTORE="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.defaults_state.read_text()), {})

    def test_non_string_preference_is_not_mutated(self) -> None:
        initial = {"WebKit2HTTPProxy": 42}
        self.defaults_state.write_text(json.dumps(initial))
        result = self.run_harness(
            DEFAULTS_NON_STRING_KEY="WebKit2HTTPProxy"
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(self.defaults_state.read_text()), initial)
        self.assertIn("unsupported pre-existing type", result.stderr)

    def test_missing_connect_is_an_infrastructure_failure(self) -> None:
        result = self.run_harness(AUTOMATION_MODE="no_connect")
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3], "infra_error")
        self.assertEqual(row[9:12], ["replay", "missing_proxy_connect", "repetition=1"])
        self.assertIn("no proxy CONNECT", result.stderr)

    def test_malformed_output_is_not_counted_as_observed(self) -> None:
        result = self.run_harness(AUTOMATION_MODE="malformed")
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3], "infra_error")
        self.assertEqual(row[9:11], ["automation", "malformed_output"])
        self.assertEqual(row[12:17], ["1", "0", "0", "0", "0"])

    def test_structured_automation_failure_records_durable_reason(self) -> None:
        result = self.run_harness(AUTOMATION_MODE="structured_failure")
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3], "infra_error")
        self.assertEqual(
            row[9:12],
            ["automation", "command_failed", "repetition=1; exit_status=7"],
        )
        self.assertEqual(row[12:17], ["1", "1", "0", "0", "1"])

    def test_dead_shared_proxy_is_an_infrastructure_failure(self) -> None:
        self.add_valid_site("example.com")
        result = self.run_harness(
            sites="apple.com,example.com",
            FAKE_HTTPPROXY_EXIT_AFTER_ACCEPT="1",
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            [(row[2], row[3]) for row in self.disposition_rows()],
            [("apple.com", "infra_error"), ("example.com", "infra_error")],
        )
        self.assertTrue(
            all(
                row[9:11] == ["runner", "shared_service_stopped"]
                for row in self.disposition_rows()
            )
        )
        self.assertIn("httpproxy exited unexpectedly", result.stderr)
        self.assertIn("not measured because a shared replay service stopped", result.stderr)

    def test_dead_site_wpr_does_not_stop_later_site(self) -> None:
        self.add_valid_site("example.com")
        result = self.run_harness(
            sites="apple.com,example.com",
            FAKE_WPR_FIRST_EXIT_MARKER=str(self.root / "first-wpr"),
            AUTOMATION_DELAY_SITE="apple.com",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [(row[2], row[3]) for row in self.disposition_rows()],
            [("apple.com", "infra_error"), ("example.com", "measured")],
        )
        self.assertEqual(
            self.disposition_rows()[0][9:12],
            ["replay", "wpr_exited", "repetition=1"],
        )
        self.assertNotIn("shared replay service died", result.stderr)

    def test_automation_failure_continues_to_later_site(self) -> None:
        self.add_valid_site("example.com")
        result = self.run_harness(
            sites="apple.com,example.com",
            AUTOMATION_FAIL_SITE="apple.com",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = self.disposition_rows()
        self.assertEqual(
            [(row[2], row[3]) for row in rows],
            [("apple.com", "infra_error"), ("example.com", "measured")],
        )
        self.assertEqual(len(self.measurement_rows()), 1)
        self.assertTrue(
            (self.root / "diagnostics" / "wpr-apple.com.log").is_file()
        )

    def test_corrupt_handoff_fails_even_when_another_site_measures(self) -> None:
        self.add_valid_site("example.com")
        manifest = self.archives / "manifest.tsv"
        fields = manifest.read_text().splitlines()[1].split("\t")
        fields[2] = "not-a-sha256"
        lines = manifest.read_text().splitlines()
        lines[1] = "\t".join(fields)
        manifest.write_text("\n".join(lines) + "\n")
        result = self.run_harness(sites="apple.com,example.com")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            [(row[2], row[3]) for row in self.disposition_rows()],
            [("apple.com", "infra_error"), ("example.com", "measured")],
        )

    def test_site_failure_preserves_size_bounded_diagnostics(self) -> None:
        result = self.run_harness(
            AUTOMATION_MODE="offsite",
            MAX_DIAGNOSTIC_BYTES="4",
        )
        self.assertEqual(result.returncode, 1)
        diagnostics = list((self.root / "diagnostics").iterdir())
        self.assertTrue(diagnostics)
        self.assertTrue(all(path.stat().st_size <= 4 for path in diagnostics))
        self.assertTrue(any(path.name == "httpproxy.log" for path in diagnostics))

    def test_invalid_diagnostic_limits_fail_before_measurement(self) -> None:
        result = self.run_harness(MAX_SITE_DIAGNOSTICS="invalid")
        self.assertEqual(result.returncode, 2)
        self.assertIn("MAX_SITE_DIAGNOSTICS", result.stderr)

    def test_offsite_landing_is_an_infrastructure_failure(self) -> None:
        result = self.run_harness(AUTOMATION_MODE="offsite")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.disposition_rows()[0][3], "infra_error")

    def test_invalid_offsite_protocol_is_an_infrastructure_failure(self) -> None:
        result = self.run_harness(AUTOMATION_MODE="invalid_offsite")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.disposition_rows()[0][3], "infra_error")
        self.assertIn("invalid landed_offsite", result.stderr)

    def test_archive_hash_mismatch_is_an_infrastructure_failure(self) -> None:
        (self.archives / "navToLCP_apple.com.wprgo").write_text("changed")
        result = self.run_harness()
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(
            row[3:6],
            ["infra_error", "error", "validated_archive_hash_mismatch"],
        )
        self.assertEqual(row[8], "-")

    def test_invalid_manifest_hash_is_an_infrastructure_failure(self) -> None:
        manifest = self.archives / "manifest.tsv"
        fields = manifest.read_text().splitlines()[1].split("\t")
        fields[2] = "not-a-sha256"
        manifest.write_text(MANIFEST_HEADER + "\t".join(fields) + "\n")
        result = self.run_harness()
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(
            row[3:6],
            ["infra_error", "error", "validated_archive_hash_invalid"],
        )
        self.assertEqual(row[8], "-")

    def test_validator_site_error_remains_an_exclusion(self) -> None:
        manifest = self.archives / "manifest.tsv"
        fields = manifest.read_text().splitlines()[1].split("\t")
        fields[4] = "error"
        fields[5] = "http_403"
        fields[6] = "403"
        manifest.write_text(MANIFEST_HEADER + "\t".join(fields) + "\n")
        result = self.run_harness()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.disposition_rows()[0][3:7],
            ["excluded", "error", "http_403", "403"],
        )


if __name__ == "__main__":
    unittest.main()
