import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
SPEC = importlib.util.spec_from_file_location("pir", Path(__file__).resolve().parents[1] / "pir.py")
pir = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pir)


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pir-test-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.input_directory = self.directory / "inputs"
        self.input_directory.mkdir()
        self.broker_bytes = b'{ "name": "Test", "url": "https://broker.test", "version": "1", "steps": [{}] }\n'
        (self.input_directory / "broker.json").write_bytes(self.broker_bytes)
        (self.input_directory / "profile.json").write_text(json.dumps(dict(names=[dict(firstName="Test", lastName="Person")],
                                                                       addresses=[dict(city="City", state="CA")], phones=[], birthYear=1980)))
        self.config = dict(brokerFile="broker.json", profileFile="profile.json", optOut=False,
                           activityTimeout=2, emailTimeout=1)
        self.calls = []
        self.instances = []
        self.authenticated = False
        self.opt_status = None
        self.link = False
        self.events = []
        self.token = 'private"\\token/é'
        self.log_error = self.stop_error = self.launch_error = None
        self.no_matches = False
        self.opts_out_in_parent = False
        self.error = None
        self.foreign = False
        self.auth_diagnostics = {}
        self.server_port = self.server(self.handle)
        test = self

        class FakeRuntime:
            def __init__(self, platform, evidence, instance, port, **kwargs):
                self.platform, self.evidence, self.instance, self.port = platform, Path(evidence), instance, port
                self.kwargs = kwargs
                self.stopped = False
                test.instances.append(self)

            def build(self):
                return dict(source="source-sha", app="build-path", platform=self.platform)

            def launch(self, access_token=None):
                if self.snapshots_enabled:
                    (self.evidence / "snapshots").mkdir(mode=0o700)
                self.access_token = access_token
                test.authenticated = access_token is not None
                if access_token is not None:
                    test.token = access_token
                if test.launch_error:
                    raise RuntimeError(test.launch_error)
                return dict(instanceID=self.instance, source="source-sha", app="build-path", pid=42)

            def collect_snapshots(self):
                test.assertTrue(self.snapshots_enabled)
                test.assertFalse(self.stopped)

            def stop(self):
                self.stopped = True
                if test.stop_error:
                    raise RuntimeError(test.stop_error)
                return dict(verified=True, stopped=True)

        self.Runtime = FakeRuntime
        self.original_client = pir.Client

    def server(self, handler):
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def dispatch(self):
                size = int(self.headers.get("Content-Length", 0))
                body = json.loads(self.rfile.read(size)) if size else None
                status, value = handler(self.command, self.path, self.headers, body)
                if status is None:
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.connection.close()
                    return
                raw = json.dumps(value).encode()
                self.send_response(status)
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)
            do_GET = do_POST = dispatch

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def stop():
            server.shutdown()
            server.server_close()
            thread.join(2)
        self.addCleanup(stop)
        return server.server_port

    def run_state(self):
        return dict(id="run", results=[] if self.no_matches else [dict(id="record", profileUrl="https://record.test",
                    profileQuery="query", optOutStatus=self.opt_status, hasEmailConfirmationLink=self.link)],
                    scanErrors=[self.error] if self.error else [], events=self.events[:])

    def event(self, summary):
        self.events.append(dict(kind="History", summary=summary, profileQuery="query"))

    def handle(self, method, path, headers, body):
        self.calls.append((method, path, headers, body))
        instance = self.instances[-1].instance if self.instances else "owner"
        self.assertEqual(headers.get("X-PIR-Debug-Instance"), instance)
        if path.startswith("/api/debug/prerequisites"):
            check_id = parse_qs(urlsplit(path).query)["checkID"][0]
            auth = dict(status="credentialProvided" if self.authenticated else "unauthenticated",
                        backend="provided-token" if self.authenticated else "normal", authenticated=self.authenticated,
                        entitled=None, environment="staging", pirEnvironment="staging", pirEndpoint="https://backend.test")
            auth.update(self.auth_diagnostics)
            return 200, dict(checkID=check_id, instanceID="foreign" if self.foreign else instance,
                             checkedAt="now", debugRunnerReady=True, result=auth)
        if path == "/api/debug/scans":
            if self.config["optOut"]:
                self.assertTrue(self.auth_diagnostics.get("authenticated", self.authenticated))
            self.event("Scan Started")
            if self.no_matches:
                self.event("No Match")
            return 202, self.run_state()
        if path.endswith("/optouts/record"):
            if self.opts_out_in_parent:
                self.opt_status = "optsOutInParent"
                self.event("Opt-out skipped: broker opts out in parent")
                return 202, self.run_state()
            self.opt_status = "awaitingEmailConfirmation" if self.config["emailConfirmation"] else "confirmed"
            self.event("Opt-out Started")
            if self.opt_status == "confirmed":
                self.event("Opt-out Confirmed")
            return 202, self.run_state()
        if path.endswith("/email-confirmation/check"):
            self.link = True
            return 202, self.run_state()
        if path.endswith("/continue"):
            self.assertTrue(self.link)
            self.opt_status = "confirmed"
            self.event("Opt-out Confirmed")
            return 202, self.run_state()
        if path.startswith("/api/logs"):
            if self.log_error:
                return 500, dict(error=self.log_error)
            return 200, [dict(timestamp="2026-01-01T00:00:00Z", level="info", category="PIR", subsystem="test",
                              process="test-app", message=self.token + " " + json.dumps(self.token))]
        return 200, self.run_state()

    def args(self, *extra):
        self.config_file = self.input_directory / "config.json"
        self.config_file.write_text(json.dumps(self.config))
        return pir.parser().parse_args(["run", "--platform", "ios", "--config", str(self.config_file),
                                        "--evidence-dir", str(self.directory / "evidence"), *extra])

    def execute(self, *extra):
        return self.execute_args(self.args(*extra))

    def execute_args(self, args):
        def client(evidence, port, instance, redactor):
            return self.original_client(evidence, self.server_port, instance, redactor)
        with patch.object(pir, "Client", side_effect=client), contextlib.redirect_stdout(io.StringIO()):
            return pir.execute(args, self.Runtime)

    def configure_auth(self, opt_out=True):
        self.config.update(optOut=opt_out, emailConfirmation=True, subscriptionEnvironment="staging", pirEnvironment="staging",
                           pirEndpoint="https://backend.test")

    def auth_options(self, opt_out=True):
        self.configure_auth(opt_out)
        token_file = self.directory / "credential"
        token_file.write_text(self.token + "\n")
        return ["--token-file", str(token_file)]

    def test_scan_without_token_uses_no_injected_credential(self):
        result = self.execute()
        self.assertEqual(result["status"], "pass")
        self.assertIsNone(self.instances[-1].access_token)
        self.assertFalse(any("/optouts/" in path for _, path, _, _ in self.calls))
        evidence = Path(result["evidence"])
        self.assertEqual((evidence / "pir-broker.json").read_bytes(), self.broker_bytes)
        self.assertEqual(result["inputs"]["brokerFile"]["sha256"], pir.sha256(self.broker_bytes))
        for name in ("result.json", "report.md", "manifest.json", "pir-final-run.json", "launch.json", "pir-native-logs.json"):
            self.assertTrue((evidence / name).exists(), name)
        self.assertTrue(self.instances[-1].stopped)

    def test_token_precedes_scan_and_full_email_flow_uses_same_result_once(self):
        result = self.execute(*self.auth_options(), "--keep", "--platform", "macos")
        self.assertEqual(result["status"], "pass", result)
        mutations = [path for method, path, _, _ in self.calls if method == "POST"]
        self.assertEqual(mutations, ["/api/debug/scans", "/api/debug/runs/run/optouts/record",
                                     "/api/debug/runs/run/email-confirmation/check", "/api/debug/runs/run/optouts/record/continue"])
        checks = [path for _, path, _, _ in self.calls if path.startswith("/api/debug/prerequisites")]
        self.assertEqual(len(checks), 1)
        self.assertEqual(self.instances[-1].access_token, self.token)
        self.assertTrue(all(self.token not in json.dumps(body) for _, _, _, body in self.calls))
        self.assertTrue(self.instances[-1].kwargs["keep"])
        self.assertEqual(self.instances[-1].kwargs["pir_environment"], "staging")
        self.assertTrue(self.instances[-1].stopped)
        self.assertIn("--token-file", result["rerun"])
        self.assertIn("subscription entitlement", [u["what"] for u in result["unverified"]])
        for file in Path(result["evidence"]).iterdir():
            if file.is_dir():
                continue
            text = file.read_text()
            for form in pir.Redactor(self.token).forms:
                self.assertNotIn(form, text, file.name)

    def test_step_snapshots_collected_during_scan_and_before_cleanup(self):
        page = "snapshots/00000001-scan-extract-before.png"
        unavailable = "snapshots/00000002-optOut-click-error.unavailable"
        def collect(runtime):
            self.assertTrue(runtime.snapshots_enabled)
            self.assertFalse(runtime.stopped)
            if self.opt_status is None:
                (runtime.evidence / page).write_bytes(b"page")
            if any(path.startswith("/api/logs") for _, path, *_ in self.calls):
                (runtime.evidence / unavailable).write_text("unavailable")

        original = self.handle
        def handle(method, path, headers, body):
            if path.endswith("/optouts/record"):
                self.assertTrue((self.instances[-1].evidence / page).is_file())
            return original(method, path, headers, body)

        self.server_port = self.server(handle)
        with patch.object(self.Runtime, "collect_snapshots", collect):
            result = self.execute(*self.auth_options())
        self.assertEqual(result["status"], "pass", result)
        self.assertEqual(result["snapshots"], dict(directory="snapshots", captured=1, unavailable=1))
        evidence = Path(result["evidence"])
        report = (evidence / "report.md").read_text()
        manifest = json.loads((evidence / "manifest.json").read_text())["files"]
        for name in [page, unavailable]:
            self.assertIn(f"]({name})", report)
            self.assertEqual(manifest[name]["sha256"], pir.sha256((evidence / name).read_bytes()))

    def test_snapshot_collection_error_preserves_broker_verdict(self):
        with patch.object(self.Runtime, "collect_snapshots", side_effect=OSError("unreadable snapshots")):
            result = self.execute()
        self.assertEqual(result["status"], "pass", result)
        self.assertEqual(result["snapshots"]["captured"], 0)
        self.assertIn("unreadable snapshots", result["snapshots"]["collectionError"])
        self.assertTrue(self.instances[-1].stopped)

    def test_native_absent_entitlement_field_means_unverified(self):
        snapshot = dict(result=dict(authenticated=True, backend="provided-token", status="credentialProvided",
                                   environment="staging", pirEnvironment="staging", pirEndpoint="https://backend.test"))
        self.auth_options()
        pir.verify_auth(snapshot, self.config, provided=True)
        snapshot["result"]["entitled"] = False
        with self.assertRaises(pir.SetupFailed):
            pir.verify_auth(snapshot, self.config, provided=True)

    def test_scenario_title_is_recorded_and_kept_in_the_rerun(self):
        result = self.execute("--scenario", "Scan finds the profile's record")
        self.assertEqual(result["scenario"], "Scan finds the profile's record")
        self.assertIn("--scenario", result["rerun"])
        self.assertEqual(result["expected"], "pass")
        expected_fail = self.execute("--scenario", "A broker JSON with a userAssist step is handled safely", "--expect", "fail")
        self.assertEqual(expected_fail["expected"], "fail")
        self.assertIn("--expect fail", expected_fail["rerun"])
        with self.assertRaisesRegex(ValueError, "--scenario applies only to run and scheduler"):
            pir.execute(pir.parser().parse_args(["selftest", "--platform", "macos", "--scenario", "x"]))

    def test_a_scenario_attempt_in_a_batch_rewrites_the_batch_report(self):
        batch = self.directory / "batch"
        attempt = batch / "evidence" / "macos-run-1"
        attempt.mkdir(parents=True)
        (attempt / "result.json").write_text(json.dumps(dict(command="run", platform="macos", status="pass",
                                                             scenario="Scan finds the profile's record")))
        def run_main(*extra, evidence=attempt):
            with patch.object(pir, "execute", return_value=dict(status="pass", evidence=str(evidence))), \
                    contextlib.redirect_stdout(io.StringIO()):
                return pir.main(["run", "--platform", "macos", "--config", "config.json",
                                 "--evidence-dir", str(evidence.parent), *extra])
        self.assertEqual(run_main(), 0)
        self.assertFalse((batch / "report.html").exists())
        loose = self.directory / "loose" / "macos-run-2"
        loose.mkdir(parents=True)
        run_main("--scenario", "Scan finds the profile's record", evidence=loose)
        self.assertFalse((self.directory / "report.html").exists())
        self.assertEqual(run_main("--scenario", "Scan finds the profile's record"), 0)
        self.assertIn("Scan finds the profile&#x27;s record", (batch / "report.html").read_text())

    def test_native_log_array_preserves_success_report_and_redacts_evidence(self):
        result = self.execute(*self.auth_options())
        self.assertEqual(result["status"], "pass", result.get("evidenceErrors"))
        self.assertEqual(result["evidenceErrors"], [])
        self.assertTrue(result["cleanup"]["stopped"])
        evidence = Path(result["evidence"])
        responses = [json.loads(p.read_text()) for p in evidence.glob("pir-http-*.json")]
        logs = [r for r in responses if r["path"].startswith("/api/logs?since=") and r["path"].endswith("&limit=5000")]
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0]["status"], 200)
        self.assertIsInstance(logs[0]["response"], list)
        self.assertIn("[REDACTED]", logs[0]["response"][0]["message"])
        self.assertNotIn(self.token, json.dumps(responses, ensure_ascii=False))
        self.assertEqual(json.loads((evidence / "result.json").read_text())["status"], "pass")
        self.assertTrue((evidence / "report.md").read_text().startswith("# PIR pass\n"))
        manifest = json.loads((evidence / "manifest.json").read_text())
        self.assertEqual(manifest["status"], "pass")
        for name, metadata in manifest["files"].items():
            self.assertEqual(metadata["sha256"], pir.sha256((evidence / name).read_bytes()), name)

    def test_object_logs_prevent_pass_but_still_stop_runtime(self):
        original = self.handle
        self.server_port = self.server(lambda method, path, headers, body:
                                       (200, dict(message="incorrect object")) if path.startswith("/api/logs")
                                       else original(method, path, headers, body))
        result = self.execute()
        self.assertEqual(result["status"], "inconclusive")
        self.assertTrue(any("logs response is not a JSON array" in e for e in result["evidenceErrors"]))
        self.assertTrue(result["cleanup"]["stopped"])

    def test_run_and_prerequisite_arrays_are_rejected(self):
        port = self.server(lambda *_: (200, []))
        client = self.original_client(self.directory, port, "owner")
        for path in ("/api/debug/prerequisites?checkID=check", "/api/debug/runs/run"):
            with self.subTest(path=path), self.assertRaisesRegex(pir.Failed, "not a JSON object"):
                client.request("GET", path)

    def test_selftest_only_reads_native_endpoints_and_reports_owned_cleanup(self):
        self.auth_diagnostics["pirEndpoint"] = "https://dbp-staging.duckduckgo.com"
        args = pir.parser().parse_args(["selftest", "--platform", "ios", "--evidence-dir", str(self.directory / "evidence"),
                                        "--launch-profile", '{"onboardingCompleted": false}'])
        result = self.execute_args(args)
        self.assertEqual(result["status"], "pass", result)
        self.assertEqual(self.instances[-1].kwargs["launch_profile"], {"onboardingCompleted": False})
        self.assertTrue(result["cleanup"]["stopped"])
        self.assertEqual(result["brokerRequests"], 0)
        self.assertFalse(self.instances[-1].snapshots_enabled)
        self.assertNotIn("snapshots", result)
        self.assertTrue(self.calls)
        self.assertTrue(all(method == "GET" for method, *_ in self.calls))
        self.assertTrue(any(path.startswith("/api/debug/prerequisites") for _, path, *_ in self.calls))
        self.assertTrue(any(path.startswith("/api/logs") for _, path, *_ in self.calls))
        self.assertEqual(self.instances[-1].kwargs["pir_environment"], "staging")
        self.assertIsNotNone(self.instances[-1].access_token)
        self.assertFalse((Path(result["evidence"]) / "pir-broker.json").exists())
        for path in Path(result["evidence"]).iterdir():
            self.assertNotIn(self.instances[-1].access_token, path.read_text(), path.name)

    def test_selftest_rejects_scenario_and_auth_options_before_reading_files(self):
        for option in (["--config", "/does-not-exist"], ["--token-file", "/does-not-exist"],
                       ["--token-env", "PRIVATE_ACCOUNT"], ["--check-config"], ["--keep"]):
            with self.subTest(option=option):
                args = pir.parser().parse_args(["selftest", "--platform", "macos", *option])
                with patch.object(pir, "read_token", side_effect=AssertionError("credential source read")):
                    with self.assertRaisesRegex(ValueError, "selftest"):
                        pir.execute(args, self.Runtime)
        self.assertEqual(self.instances, [])

    def test_selftest_log_capture_failure_is_inconclusive_and_still_stops_runtime(self):
        self.auth_diagnostics["pirEndpoint"] = "https://dbp-staging.duckduckgo.com"
        self.log_error = "cannot capture native logs"
        args = pir.parser().parse_args(["selftest", "--platform", "macos", "--evidence-dir", str(self.directory / "evidence")])
        result = self.execute_args(args)
        self.assertEqual(result["status"], "inconclusive")
        self.assertTrue(result["cleanup"]["stopped"])
        self.assertTrue(result["evidenceErrors"])
        self.assertTrue(all(method == "GET" for method, *_ in self.calls))

    def test_selftest_refuses_an_unexpected_backend_and_still_cleans_up(self):
        args = pir.parser().parse_args(["selftest", "--platform", "macos", "--evidence-dir", str(self.directory / "evidence")])
        result = self.execute_args(args)
        self.assertEqual(result["status"], "inconclusive")
        self.assertIn("backend do not match", result["reason"])
        self.assertTrue(result["cleanup"]["stopped"])
        self.assertTrue(all(method == "GET" for method, *_ in self.calls))

    def test_redaction_handles_nested_echoes_without_changing_json_types(self):
        for token in (self.token, "true", "42"):
            original = dict(echo=token, quoted=json.dumps(token), authenticated=True, count=42)
            clean = pir.Redactor(token).value(original)
            self.assertEqual(clean["echo"], "[REDACTED]")
            self.assertEqual(clean["quoted"], '\"[REDACTED]\"')
            self.assertIs(clean["authenticated"], True)
            self.assertEqual(clean["count"], 42)

    def test_scan_can_supply_token_for_captcha(self):
        result = self.execute(*self.auth_options(opt_out=False))
        self.assertEqual(result["status"], "pass")
        self.assertEqual(self.instances[-1].access_token, self.token)
        self.assertFalse(any("/optouts/" in path for _, path, _, _ in self.calls))

    def test_missing_or_invalid_inputs_never_create_runtime(self):
        cases = [dict(optOut="false"), dict(activityTimeout=float("nan")), dict(activityTimeout=True),
                 dict(brokerFile="absent.json"), dict(token="must-not-live-in-config")]
        for values in cases:
            original = self.config.copy()
            self.config.update(values)
            with self.subTest(values=values), self.assertRaises((ValueError, OSError)):
                pir.execute(self.args(), self.Runtime)
            self.config = original
        self.assertEqual(self.instances, [])

    def test_launch_profile_reaches_runtime_launch_evidence_and_rerun(self):
        profile = self.input_directory / "launch-profile.json"
        profile.write_text('{"featureFlags": {"x": true}}')
        result = self.execute("--launch-profile", str(profile))
        self.assertEqual(result["status"], "pass", result)
        self.assertEqual(self.instances[-1].kwargs["launch_profile"], {"featureFlags": {"x": True}})
        source = dict(reference=str(profile.resolve()), sha256=pir.sha256(profile.read_bytes()))
        self.assertEqual(result["launch"]["launchProfile"]["source"], source)
        self.assertEqual(json.loads((Path(result["evidence"]) / "launch.json").read_text())["launchProfile"]["source"], source)
        self.assertIn(pir.shlex.join(["--launch-profile", str(profile.resolve())]), result["rerun"])
        inline = '{"onboardingCompleted": false}'
        result = self.execute("--launch-profile", inline)
        self.assertEqual(result["launch"]["launchProfile"]["source"], dict(inline={"onboardingCompleted": False}))
        self.assertIn(pir.shlex.join(["--launch-profile", inline]), result["rerun"])

    def test_launch_profile_is_ios_only_and_validated_before_launch(self):
        evidence = str(self.directory / "evidence")
        for argv, message in ((["run", "--platform", "macos", "--config", "/absent.json"], "only to iOS"),
                              (["build", "--platform", "ios"], "only to run, selftest"),
                              (["scheduler", "observe", "--platform", "ios", "--since", "2026-01-01T00:00:00Z",
                                "--job", "a.com", "1"], "only to run, selftest")):
            with self.subTest(argv=argv), self.assertRaisesRegex(ValueError, message):
                pir.execute(pir.parser().parse_args([*argv, "--launch-profile", "{}", "--evidence-dir", evidence]), self.Runtime)
        for profile, message in (('{"internalUser": false}', "internalUser true"), ('{"tabs": []}', "tabs")):
            with self.subTest(profile=profile), self.assertRaisesRegex(ValueError, message):
                pir.execute(self.args("--check-config", "--launch-profile", profile), self.Runtime)
        self.assertEqual(self.instances, [])
        valid = pir.execute(self.args("--check-config", "--launch-profile", '{"onboardingCompleted": false}'), self.Runtime)
        self.assertEqual(valid["launchProfile"], dict(inline={"onboardingCompleted": False}))
        self.assertFalse((self.directory / "evidence").exists())

    def test_optout_can_use_existing_subscription_without_injected_token(self):
        self.configure_auth()
        self.auth_diagnostics.update(authenticated=True, backend="subscription-auth-v2", status="ready", entitled=True)
        result = self.execute("--platform", "macos")
        self.assertEqual(result["status"], "pass", result)
        self.assertIsNone(self.instances[-1].access_token)
        paths = [path for method, path, *_ in self.calls if method == "POST"]
        self.assertIn("/api/debug/runs/run/optouts/record", paths)
        evidence = Path(result["evidence"])
        self.assertEqual(json.loads((evidence / "pir-inputs.json").read_text())["authentication"], "saved-subscription")
        self.assertNotIn("--device", result["rerun"])

    def test_child_broker_optout_passes_on_scan_and_reports_skip(self):
        self.opts_out_in_parent = True
        result = self.execute(*self.auth_options())
        self.assertEqual(result["status"], "pass", result)
        self.assertFalse(any(path.endswith(("/email-confirmation/check", "/continue")) for _, path, *_ in self.calls))
        self.assertIn("PIR opt-out", [item["what"] for item in result["unverified"]])
        self.assertIn("skipped the opt-out", result["reason"])
        self.assertNotIn("selected record opt-out flow confirmed", [check["check"] for check in result["checks"]])

    def test_optout_without_injected_token_requires_ready_saved_subscription_before_scan(self):
        self.configure_auth()
        ready = dict(authenticated=True, backend="subscription-auth-v2", status="ready", entitled=True)
        for change in (dict(authenticated=False, status="unauthenticated", entitled=None),
                       dict(status="notEntitled", entitled=False), dict(status="error", entitled=None),
                       dict(status="bypass"), dict(backend="provided-token"), dict(environment="production"),
                       dict(pirEndpoint="https://wrong.test")):
            with self.subTest(change=change):
                self.calls.clear()
                self.auth_diagnostics = {**ready, **change}
                result = self.execute()
                self.assertEqual(result["status"], "inconclusive")
                self.assertIn("--token-file or --token-env", result["reason"])
                self.assertFalse(any(method == "POST" for method, *_ in self.calls))
                self.assertTrue(self.instances[-1].stopped)

    def test_malformed_endpoint_error_omits_input_url(self):
        self.config["pirEndpoint"] = "https://sensitive-fixture＠backend.test"
        self.args()
        with contextlib.redirect_stderr(io.StringIO()) as output:
            status = pir.main(["run", "--platform", "ios", "--config", str(self.config_file), "--check-config"])
        self.assertEqual(status, 2)
        self.assertNotIn("sensitive-fixture", output.getvalue())
        self.assertIn("pirEndpoint", output.getvalue())

    def test_scan_token_requires_backend_config_and_matching_environment(self):
        token = self.directory / "token"
        token.write_text(self.token)
        with self.assertRaisesRegex(ValueError, "pirEndpoint"):
            pir.execute(self.args("--token-file", str(token)), self.Runtime)
        self.auth_options(False)
        self.config["pirEnvironment"] = "production"
        with self.assertRaisesRegex(ValueError, "must match"):
            pir.execute(self.args("--token-file", str(token)), self.Runtime)
        self.assertEqual(self.instances, [])

    def test_file_and_environment_token_sources_validate_before_launch(self):
        for option in (["--token-file", str(self.directory / "missing")], ["--token-env", "PIR_MISSING_TEST_CREDENTIAL"]):
            with self.subTest(option=option), self.assertRaises((ValueError, OSError)):
                pir.execute(self.args(*option), self.Runtime)
        self.auth_options(False)
        with patch.dict(os.environ, {"PIR_TEST_CREDENTIAL": self.token}):
            result = self.execute("--token-env", "PIR_TEST_CREDENTIAL")
        self.assertEqual(result["status"], "pass")
        self.assertIn("--token-env PIR_TEST_CREDENTIAL", result["rerun"])
        self.assertIn("--device iphone", result["rerun"])

    def test_dry_validation_and_help_need_no_runtime_import(self):
        result = pir.execute(self.args("--check-config"), lambda *_: self.fail("runtime called"))
        self.assertEqual(result["status"], "valid")
        self.assertFalse((self.directory / "evidence").exists())
        with contextlib.redirect_stdout(io.StringIO()) as output, self.assertRaises(SystemExit) as caught:
            pir.main(["--help"])
        self.assertEqual(caught.exception.code, 0)
        self.assertIn("--token-file", output.getvalue())

    def test_evidence_inside_checkout_rejected_before_runtime(self):
        with self.assertRaisesRegex(ValueError, "outside this checkout"):
            pir.execute(self.args("--evidence-dir", str(Path(pir.__file__).resolve().parent / "evidence")), self.Runtime)
        self.assertEqual(self.instances, [])

    def test_repeated_attempts_use_unique_evidence_directories(self):
        one, two = self.execute(), self.execute()
        self.assertNotEqual(one["evidence"], two["evidence"])

    def test_no_match_is_inconclusive_with_final_run_and_owned_cleanup(self):
        self.no_matches = True
        result = self.execute()
        self.assertEqual(result["status"], "inconclusive")
        self.assertIn("no match", result["reason"])
        self.assertTrue((Path(result["evidence"]) / "pir-final-run.json").exists())
        self.assertTrue(self.instances[-1].stopped)

    def test_broker_error_is_failure_even_with_no_results(self):
        self.no_matches, self.error = True, "authentication rejected"
        result = self.execute()
        self.assertEqual(result["status"], "fail")
        self.assertTrue(self.instances[-1].stopped)

    def test_foreign_launch_never_receives_mutation(self):
        self.foreign = True
        result = self.execute(*self.auth_options())
        self.assertEqual(result["status"], "inconclusive")
        self.assertFalse(any(method == "POST" for method, *_ in self.calls))

    def test_incorrect_credential_diagnostics_prevent_scan(self):
        for change in (dict(entitled=True), dict(status="ready"), dict(backend="normal"),
                       dict(pirEndpoint="https://wrong.test"), dict(authenticated=False)):
            self.authenticated = False
            self.calls.clear()
            self.auth_diagnostics = change
            with self.subTest(change=change):
                result = self.execute(*self.auth_options())
                self.assertEqual(result["status"], "inconclusive")
                self.assertFalse(any(path == "/api/debug/scans" for _, path, _, _ in self.calls))

    def test_http_errors_are_failures_and_lost_mutations_are_never_retried(self):
        original = self.handle
        for status in (401, 429, 500, None):
            self.calls.clear()
            def handler(method, path, headers, body):
                if path == "/api/debug/scans":
                    self.calls.append((method, path, headers, body))
                    return status, dict(error="backend failed")
                return original(method, path, headers, body)
            port = self.server(handler)
            self.server_port = port
            with self.subTest(status=status):
                result = self.execute()
                self.assertEqual(result["status"], "fail", result)
                self.assertEqual(sum(path == "/api/debug/scans" for _, path, _, _ in self.calls), 1)
                self.assertTrue(self.instances[-1].stopped)

    def test_log_or_cleanup_failures_prevent_pass(self):
        for kind in ("log_error", "stop_error"):
            setattr(self, kind, "test failure")
            with self.subTest(kind=kind):
                result = self.execute()
                self.assertEqual(result["status"], "inconclusive")
                self.assertTrue(result["evidenceErrors"])
                self.assertTrue(self.instances[-1].stopped)
            setattr(self, kind, None)

    def test_evidence_write_failure_still_stops_owned_runtime(self):
        original_write = pir.Context.write
        def write(context, name, value):
            if name == "pir-final-run.json":
                raise OSError("disk full")
            return original_write(context, name, value)
        with patch.object(pir.Context, "write", write):
            result = self.execute()
        self.assertEqual(result["status"], "inconclusive")
        self.assertTrue(self.instances[-1].stopped)
        self.assertTrue(any("final run" in e for e in result["evidenceErrors"]))
        self.assertEqual(json.loads((Path(result["evidence"]) / "result.json").read_text())["status"], "inconclusive")

    def test_manifest_failures_publish_consistent_inconclusive_report_and_result(self):
        original_write, original_read = pir.Context.write, Path.read_bytes
        for failure in ("write", "hash"):
            def write(context, name, value):
                if failure == "write" and name == "manifest.json":
                    self.assertFalse((context.evidence / "report.md").exists(), "report must wait for its manifest")
                    raise OSError("manifest write failed")
                return original_write(context, name, value)
            def read(path):
                if failure == "hash" and path.name == "pir-broker.json":
                    raise OSError("manifest evidence read failed")
                return original_read(path)
            with self.subTest(failure=failure), patch.object(pir.Context, "write", write), patch.object(Path, "read_bytes", read):
                result = self.execute()
            self.assertTrue(self.instances[-1].stopped)
            evidence = Path(result["evidence"])
            stored = json.loads((evidence / "result.json").read_text())
            report = (evidence / "report.md").read_text()
            self.assertEqual(result["status"], "inconclusive")
            self.assertEqual(stored["status"], result["status"])
            self.assertTrue(report.startswith("# PIR inconclusive\n"))
            self.assertNotIn("# PIR pass", report)
            self.assertIn("manifest", report)
            self.assertFalse((evidence / "manifest.json").exists())

    def test_launch_error_still_collects_logs_and_stops_runtime(self):
        self.launch_error = "stale build"
        result = self.execute()
        self.assertEqual(result["status"], "inconclusive")
        self.assertTrue(self.instances[-1].stopped)
        self.assertEqual(self.calls, [])

    def test_cancellation_stops_owned_runtime_and_writes_result(self):
        for target, name in ((pir, "workflow"), (self.Runtime, "collect_snapshots")):
            with self.subTest(interrupted=name), patch.object(target, name, side_effect=KeyboardInterrupt):
                result = self.execute()
            self.assertEqual(result["status"], "inconclusive")
            self.assertTrue(self.instances[-1].stopped)
            self.assertTrue((Path(result["evidence"]) / "result.json").exists())
        with patch.object(pir, "workflow", side_effect=KeyboardInterrupt):
            self.assertIn("cancelled", self.execute()["reason"])

    def test_build_has_separate_metadata_and_never_launches(self):
        args = pir.parser().parse_args(["build", "--platform", "macos", "--evidence-dir", str(self.directory / "build-evidence")])
        result = pir.execute(args, self.Runtime)
        self.assertEqual(result["status"], "pass")
        self.assertIn("build", result)
        self.assertNotIn("launch", result)
        self.assertEqual(self.calls, [])
        self.assertTrue(self.instances[-1].stopped)

    def test_result_selection_rejects_ambiguous_and_changed_ids(self):
        one, two = dict(id="a", profileUrl="u1"), dict(id="b", profileUrl="u2")
        self.assertEqual(pir.selected(dict(results=[one])), one)
        with self.assertRaisesRegex(pir.Failed, "set profileUrl"):
            pir.selected(dict(results=[one, two]))
        self.assertEqual(pir.selected(dict(results=[one, two]), "u2"), two)
        with self.assertRaisesRegex(pir.Failed, "exactly one"):
            pir.selected(dict(results=[two]), result_id="a")
        with self.assertRaisesRegex(pir.Failed, "ambiguous"):
            pir.selected(dict(results=[one, dict(id="a", profileUrl="u2")]), "u1")

    def test_email_site_optout_errors_are_never_no_match(self):
        runs = [dict(scanErrors=["site error"], results=[]), dict(results=[dict(optOutStatus="failed")]),
                dict(events=[dict(summary="Email confirmation check failed")]), dict(events=[dict(summary="Error: rate limited")]),
                dict(events=[dict(summary="Error: jobTimeout - timed out")]), dict(events=[dict(summary="Error: noActionFound - none")]),
                dict(events=[dict(summary="Error: httpError - HTTP 429"), dict(summary="Error: captchaServiceError - failed")])]
        for run in runs:
            with self.subTest(run=run), self.assertRaises(pir.Failed):
                pir.assert_clean(run)

    def test_broker_errors_end_the_run_as_a_terminal_outcome(self):
        for summary in ("Error: httpError - HTTP 410", "Error: actionFailed - expectation failed"):
            run = dict(scanErrors=["query: site error"], results=[], events=[dict(summary=summary)])
            with self.subTest(summary=summary), self.assertRaisesRegex(pir.BrokerOutcome, summary):
                pir.assert_clean(run)

    def test_202_keeps_polling_and_run_identity_must_match(self):
        calls = []
        def handle(*_):
            calls.append(1)
            return (202, dict(id="run", activity="scan")) if len(calls) == 1 else (200, dict(id="foreign"))
        client = pir.Client(self.directory, self.server(handle), "owner")
        with self.assertRaisesRegex(pir.Failed, "different run"):
            client.idle("run", 2)
        self.assertEqual(len(calls), 2)

    def test_unchanged_polls_saved_once_and_wait_is_bounded(self):
        client = pir.Client(self.directory, self.server(lambda *_: (202, dict(id="run", activity="scan"))), "owner")
        with patch.object(pir.time, "sleep"):
            with self.assertRaisesRegex(pir.Failed, "timed out"):
                client.idle("run", .05)
        self.assertEqual(len(list(self.directory.glob("pir-http-*"))), 1)


if __name__ == "__main__":
    unittest.main()
