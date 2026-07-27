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


def free_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


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

        self.wpr_http_port = free_port()
        self.wpr_https_port = free_port()
        self.tsproxy_port = free_port()
        self.httpproxy_port = free_port()
        self.safaridriver_port = free_port()

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
            import sys

            state_path = os.environ["DEFAULTS_STATE"]
            with open(state_path, encoding="utf-8") as source:
                state = json.load(source)
            command = sys.argv[1]
            domain = sys.argv[2]
            key = sys.argv[3] if len(sys.argv) > 3 else ""
            if command == "read" and domain.endswith("Info.plist"):
                print("99.1")
                raise SystemExit(0)
            if command == "read":
                if key not in state:
                    raise SystemExit(1)
                print(state[key])
            elif command == "read-type":
                if key not in state:
                    raise SystemExit(1)
                print("Type is string")
            elif command == "write":
                value = sys.argv[-1]
                if (
                    key == os.environ.get("DEFAULTS_FAIL_RESTORE_KEY")
                    and not value.startswith("http://127.0.0.1:")
                ):
                    raise SystemExit(9)
                state[key] = value
            elif command == "delete":
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
            import socket
            import sys

            args = sys.argv[1:]
            ports = []
            for index, arg in enumerate(args):
                if arg == "-p":
                    ports.append(int(args[index + 1]))
                elif arg == "--port":
                    ports.append(int(args[index + 1]))
                elif arg.startswith("--http-port=") or arg.startswith("--https-port="):
                    ports.append(int(arg.split("=", 1)[1]))
            listeners = []
            for port in ports:
                sock = socket.socket()
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.bind(("127.0.0.1", port))
                sock.listen()
                listeners.append(sock)
            while True:
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
            if site == fail_site or mode == "failure":
                print("simulated automation failure", file=sys.stderr)
                raise SystemExit(7)
            if mode != "no_connect":
                with socket.create_connection(
                    ("127.0.0.1", int(os.environ["HTTPPROXY_PORT"]))
                ) as proxy:
                    proxy.sendall(
                        f"CONNECT {site}:443 HTTP/1.1\r\n\r\n".encode()
                    )
                time.sleep(0.05)
            lcp = "-1" if mode == "unfinalized" else "1000"
            print(f'detail={{"ms": {lcp}, "loc": "{url}/"}}')
            print(f"landed_url={url}/")
            print("landed_offsite=0")
            print(f"lcp_ms={lcp}")
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
        self.assertEqual(row[2:5], ["apple.com", "measured", "ok"])
        self.assertEqual(row[9:14], ["1", "1", "1", "0", "0"])
        self.assertEqual(json.loads(self.defaults_state.read_text()), {})

    def test_unfinalized_lcp_is_not_an_infrastructure_failure(self) -> None:
        result = self.run_harness(AUTOMATION_MODE="unfinalized")
        self.assertEqual(result.returncode, 1)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3], "no_samples")
        self.assertEqual(row[9:14], ["1", "1", "0", "1", "0"])
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

    def test_missing_connect_is_an_infrastructure_failure(self) -> None:
        result = self.run_harness(AUTOMATION_MODE="no_connect")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.disposition_rows()[0][3], "infra_error")
        self.assertIn("no proxy CONNECT", result.stderr)

    def test_dead_shared_proxy_is_an_infrastructure_failure(self) -> None:
        result = self.run_harness(FAKE_HTTPPROXY_EXIT_AFTER_ACCEPT="1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.disposition_rows()[0][3], "infra_error")
        self.assertIn("httpproxy exited unexpectedly", result.stderr)

    def test_automation_failure_continues_to_later_site(self) -> None:
        self.add_valid_site("example.com")
        result = self.run_harness(
            sites="apple.com,example.com",
            AUTOMATION_FAIL_SITE="apple.com",
        )
        self.assertEqual(result.returncode, 1)
        rows = self.disposition_rows()
        self.assertEqual(
            [(row[2], row[3]) for row in rows],
            [("apple.com", "infra_error"), ("example.com", "measured")],
        )
        self.assertEqual(len(self.measurement_rows()), 1)
        self.assertTrue(
            (self.root / "diagnostics" / "wpr-apple.com.log").is_file()
        )

    def test_archive_hash_mismatch_is_excluded(self) -> None:
        (self.archives / "navToLCP_apple.com.wprgo").write_text("changed")
        result = self.run_harness()
        self.assertEqual(result.returncode, 0, result.stderr)
        row = self.disposition_rows()[0]
        self.assertEqual(row[3:6], ["excluded", "error", "validated_archive_hash_mismatch"])


if __name__ == "__main__":
    unittest.main()
