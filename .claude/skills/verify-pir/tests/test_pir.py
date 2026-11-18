"""Standalone PIR workflow tests. No app, simulator or subscription is required."""
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
                           activityTimeout=2, checkpointTimeout=1, emailTimeout=1)
        self.calls = []
        self.instances = []
        self.authenticated = False
        self.opt_status = None
        self.link = False
        self.events = []
        self.token = 'private"\\token/é'
        self.log_error = self.stop_error = self.launch_error = None
        self.no_matches = False
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
                self.access_token = access_token
                test.authenticated = access_token is not None
                if test.launch_error:
                    raise RuntimeError(test.launch_error)
                return dict(instanceID=self.instance, source="source-sha", app="build-path", pid=42)

            def logs(self, path):
                if test.log_error:
                    raise RuntimeError(test.log_error)
                Path(path).write_text("app log " + test.token + " " + json.dumps(test.token))

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
                self.assertTrue(self.authenticated)
            self.event("Scan Started")
            if self.no_matches:
                self.event("No Match")
            return 202, self.run_state()
        if path.endswith("/optouts/record"):
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
            return 200, dict(log=self.token, escaped=json.dumps(self.token))
        return 200, self.run_state()

    def args(self, *extra):
        self.config_file = self.input_directory / "config.json"
        self.config_file.write_text(json.dumps(self.config))
        return pir.parser().parse_args(["run", "--platform", "ios", "--config", str(self.config_file),
                                        "--evidence-dir", str(self.directory / "evidence"), *extra])

    def execute(self, *extra):
        def client(evidence, port, instance, redactor):
            return self.original_client(evidence, self.server_port, instance, redactor)
        with patch.object(pir, "Client", side_effect=client), contextlib.redirect_stdout(io.StringIO()):
            return pir.execute(self.args(*extra), self.Runtime)

    def auth_options(self, opt_out=True):
        self.config.update(optOut=opt_out, emailConfirmation=True, subscriptionEnvironment="staging", pirEnvironment="staging",
                           pirEndpoint="https://backend.test")
        token_file = self.directory / "credential"
        token_file.write_text(self.token + "\n")
        return ["--token-file", str(token_file)]

    def test_scan_without_token_has_no_auth_or_subscription_checkpoint(self):
        result = self.execute()
        self.assertEqual(result["status"], "pass")
        self.assertEqual(result["humanSteps"], [])
        self.assertFalse(any(path == "/api/debug/auth" or "/optouts/" in path for _, path, _, _ in self.calls))
        evidence = Path(result["evidence"])
        self.assertEqual((evidence / "pir-broker.json").read_bytes(), self.broker_bytes)
        self.assertEqual(result["inputs"]["brokerFile"]["sha256"], pir.sha256(self.broker_bytes))
        for name in ("result.json", "report.md", "manifest.json", "pir-final-run.json", "launch.json", "pir-app.log"):
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
            text = file.read_text()
            for form in pir.Redactor(self.token).forms:
                self.assertNotIn(form, text, file.name)

    def test_native_absent_entitlement_field_means_unverified(self):
        snapshot = dict(result=dict(authenticated=True, backend="provided-token", status="credentialProvided",
                                   environment="staging", pirEnvironment="staging", pirEndpoint="https://backend.test"))
        self.auth_options()
        pir.verify_auth(snapshot, self.config, provided=True)
        snapshot["result"]["entitled"] = False
        with self.assertRaises(pir.SetupFailed):
            pir.verify_auth(snapshot, self.config, provided=True)

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
        self.assertFalse(any(path == "/api/debug/auth" for _, path, _, _ in self.calls))
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

    def test_optout_requires_token_or_explicit_interactive_mode_before_runtime(self):
        self.auth_options()
        with self.assertRaisesRegex(ValueError, "interactive-subscription"):
            pir.execute(self.args(), self.Runtime)
        self.assertEqual(self.instances, [])

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

    def test_cancellation_during_logs_still_stops_owned_runtime(self):
        with patch.object(self.Runtime, "logs", side_effect=KeyboardInterrupt):
            result = self.execute()
        self.assertEqual(result["status"], "inconclusive")
        self.assertTrue(self.instances[-1].stopped)

    def test_interactive_subscription_is_explicit_and_requires_fresh_entitlement(self):
        self.auth_options()
        self.auth_diagnostics.update(backend="normal", status="ready", entitled=True)
        def acknowledge(context, instruction, timeout):
            self.authenticated = True
            context.result["humanSteps"].append(dict(status="acknowledged"))
        # Interactive subscription takes place after the scan, before opt-out.
        original_handle = self.handle
        def handle(method, path, headers, body):
            if path == "/api/debug/scans":
                self.assertFalse(self.authenticated)
                self.calls.append((method, path, headers, body))
                self.event("Scan Started")
                return 202, self.run_state()
            return original_handle(method, path, headers, body)
        self.server_port = self.server(handle)
        with patch.object(pir, "checkpoint", side_effect=acknowledge) as paused:
            result = self.execute("--interactive-subscription")
        self.assertEqual(result["status"], "pass", result)
        self.assertEqual(paused.call_count, 1)
        self.assertFalse(any(path == "/api/debug/auth" for _, path, _, _ in self.calls))
        checks = [path for _, path, _, _ in self.calls if path.startswith("/api/debug/prerequisites")]
        self.assertEqual(len(checks), 2)
        self.assertNotEqual(checks[0], checks[1])

    def test_launch_error_still_collects_logs_and_stops_runtime(self):
        self.launch_error = "stale build"
        result = self.execute()
        self.assertEqual(result["status"], "inconclusive")
        self.assertTrue(self.instances[-1].stopped)
        self.assertEqual(self.calls, [])

    def test_cancellation_stops_owned_runtime_and_writes_result(self):
        with patch.object(pir, "workflow", side_effect=KeyboardInterrupt):
            result = self.execute()
        self.assertEqual(result["status"], "inconclusive")
        self.assertIn("cancelled", result["reason"])
        self.assertTrue(self.instances[-1].stopped)
        self.assertTrue((Path(result["evidence"]) / "result.json").exists())

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
                dict(events=[dict(summary="Email confirmation check failed")]), dict(events=[dict(summary="Error: rate limited")])]
        for run in runs:
            with self.subTest(run=run), self.assertRaises(pir.Failed):
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

    def test_manual_checkpoint_ack_cancel_timeout_ignore_stale_ack(self):
        for action in ("acknowledge", "cancel", "timeout"):
            evidence = self.directory / action
            evidence.mkdir()
            (evidence / "ack-old").touch()
            context = pir.Context(evidence)
            def respond(_):
                record = json.loads((evidence / "checkpoint.json").read_text())
                Path(record[action]).touch()
            with contextlib.redirect_stdout(io.StringIO()):
                if action == "timeout":
                    with patch.object(pir.time, "monotonic", side_effect=[0, 2]), self.assertRaises(pir.SetupFailed):
                        pir.checkpoint(context, "test", 1)
                else:
                    with patch.object(pir.time, "sleep", side_effect=respond):
                        if action == "cancel":
                            with self.assertRaises(pir.SetupFailed):
                                pir.checkpoint(context, "test", 1)
                        else:
                            pir.checkpoint(context, "test", 1)
            record = json.loads((evidence / "checkpoint.json").read_text())
            self.assertEqual(record["status"], {"acknowledge": "acknowledged", "cancel": "cancelled", "timeout": "timedOut"}[action])
            self.assertIn("finishedAt", record)
            self.assertEqual(context.result["humanSteps"], [record])


if __name__ == "__main__":
    unittest.main()
