"""Tests for the live PIR proof that need no simulator.
Run: python3 -m unittest discover -s .claude/skills/verify-pir/tests -p 'test_*.py'
"""
import json, os, sys, tempfile, unittest
from pathlib import Path

VERIFY_IOS = Path(__file__).resolve().parents[2] / "verify-ios"
sys.dont_write_bytecode = True
sys.path[:0] = [str(VERIFY_IOS / "lib"), str(VERIFY_IOS / "tests")]
from test_tool import TMP, FakeDevice  # noqa: E402  sets VERIFY_IOS_HOME before verify_ios loads
from verify_ios import env, harness  # noqa: E402


class LivePIRTests(unittest.TestCase):
    """Exercises the proof against a real local HTTP server."""

    def setUp(self):
        import importlib.util
        self.path = Path(__file__).resolve().parents[1] / "pir.py"
        spec = importlib.util.spec_from_file_location("pir_proof_test", self.path)
        self.pir = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.pir)
        self.directory = tempfile.TemporaryDirectory(dir=TMP)
        self.addCleanup(self.directory.cleanup)

    def test_missing_identity_does_not_claim_cleanup_success_for_running_app(self):
        d = FakeDevice()
        d.identity = lambda: dict(ok=False, reason="parse failed")
        d.driver = type("Driver", (), {"state": lambda _: 4})()
        ios = harness.Ios("iphone", tempfile.mkdtemp(dir=TMP), device_obj=d)
        with self.assertRaisesRegex(env.Failed, "unverified"):
            self.pir.stop_test_app(ios)

    def test_failed_termination_is_an_evidence_problem(self):
        fake = FakeDevice()
        fake.identity = lambda: dict(ok=False, pid=123)
        fake.driver = type("Driver", (), {"state": lambda _: 4})()
        ios = harness.Ios("iphone", self.directory.name, device_obj=fake)
        ios.on_cleanup("stop the PIR test app", lambda: self.pir.stop_test_app(ios))
        self.assertTrue(any("refusing to terminate" in p for p in ios._run_cleanups()))

    def test_refuses_duplicate_result_id_even_with_unique_profile_url(self):
        run = dict(results=[dict(id="same", profileUrl="other"), dict(id="same", profileUrl="expected")])
        with self.assertRaisesRegex(env.Failed, "ambiguous"):
            self.pir.selected(run, "expected")

    def test_opt_out_needs_one_record_or_a_profile_url_to_choose(self):
        one, two = dict(id="a", profileUrl="u1"), dict(id="b", profileUrl="u2")
        self.assertEqual(self.pir.selected(dict(results=[one])), one)
        with self.assertRaisesRegex(env.Failed, "set profileUrl"):
            self.pir.selected(dict(results=[one, two]))
        self.assertEqual(self.pir.selected(dict(results=[one, two]), "u2"), two)
        with self.assertRaisesRegex(env.Failed, "exactly one"):
            self.pir.selected(dict(results=[two]), result_id="a")

    def test_scan_email_site_and_optout_errors_never_become_no_match(self):
        runs = [dict(scanErrors=["site error"], results=[]),
                dict(results=[dict(optOutStatus="failed")]),
                dict(events=[dict(summary="Email confirmation check failed")]),
                dict(events=[dict(summary="Error: rate limited")])]
        for run in runs:
            with self.subTest(run=run), self.assertRaises(env.Failed):
                self.pir.assert_clean(run)

    def server(self, handler):
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        import threading
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass
            def handle_request(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length)) if length else None
                status, response = handler(self.command, self.path, self.headers, body)
                data = json.dumps(response).encode()
                self.send_response(status)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            do_GET = do_POST = handle_request
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        def stop():
            server.shutdown()
            server.server_close()
            thread.join(2)
        self.addCleanup(stop)
        return server.server_port

    def test_http_prerequisite_correlates_fresh_checks_and_refuses_foreign_owner(self):
        from urllib.parse import parse_qs, urlsplit
        checks = []
        def handle(method, path, headers, body):
            check = parse_qs(urlsplit(path).query)["checkID"][0]
            checks.append(check)
            return 200, dict(checkID=check, instanceID="owner", result=dict(status="ready"))
        port = self.server(handle)
        client = self.pir.Client(self.directory.name, port, "owner")
        with self.assertRaises(env.SetupFailed):
            client.request("POST", "/api/debug/scans", {})
        first, second = client.prerequisite(), client.prerequisite()
        self.assertNotEqual(first["checkID"], second["checkID"])
        self.assertTrue(client.owned)
        with self.assertRaisesRegex(env.SetupFailed, "another launch"):
            self.pir.Client(self.directory.name, port, "foreign").prerequisite()

    def test_http_202_is_not_completion_and_poll_checks_run_identity(self):
        calls = []
        def handle(method, path, headers, body):
            calls.append(path)
            if len(calls) == 1:
                return 202, dict(id="run", activity="scan")
            return 200, dict(id="other", results=[])
        client = self.pir.Client(self.directory.name, self.server(handle), "owner")
        with self.assertRaisesRegex(env.Failed, "different run"):
            client.idle("run", 2)
        self.assertEqual(len(calls), 2)
        self.assertEqual(len(os.listdir(self.directory.name)), 2)

    def test_unchanged_polls_are_saved_once(self):
        states = iter(["scan", "scan", "scan", None])
        def handle(method, path, headers, body):
            return 200, dict(id="run", activity=next(states), results=[])
        client = self.pir.Client(self.directory.name, self.server(handle), "owner")
        client.idle("run", 5)
        self.assertEqual(len(os.listdir(self.directory.name)), 2)

    def test_missing_inputs_rejected_before_any_device_work(self):
        from unittest.mock import patch
        with patch.dict(os.environ, {"PIR_PROOF_INPUT": "/nonexistent/pir.json"}):
            _, problems = harness.load(str(self.path))
        self.assertTrue(any("proof configuration" in p for p in problems))

    def flow(self, opt_out):
        from unittest.mock import patch
        from urllib.parse import parse_qs, urlsplit
        events, requests = [], []
        state = {"ack": False, "status": None, "link": False}
        expected = dict(name="Expected", addresses=["Test City"])
        def result():
            return dict(id="record", profileQuery="query", hasEmailConfirmationLink=state["link"],
                        optOutStatus=state["status"], **expected)
        def run():
            return dict(id="run", results=[result()], scanErrors=[], events=list(events))
        def event(summary):
            events.append(dict(kind="History", summary=summary, profileQuery="query"))
        def handle(method, path, headers, body):
            requests.append((method, path))
            self.assertEqual(headers.get("X-PIR-Debug-Instance"), "owner")
            if path.startswith("/api/debug/prerequisites"):
                check = parse_qs(urlsplit(path).query)["checkID"][0]
                return 200, dict(checkID=check, instanceID="owner", checkedAt="now", debugRunnerReady=True, result=dict(
                    status="ready" if state["ack"] else "unauthenticated", authenticated=state["ack"], environment="staging", pirEnvironment="staging", pirEndpoint="https://backend.test"))
            if path == "/api/debug/scans":
                self.assertFalse(state["ack"], "the scan runs before the subscription step")
                event("Scan Started")
                return 202, run()
            if path.endswith("/optouts/record"):
                self.assertTrue(state["ack"], "the opt-out waits for the subscription step")
                state["status"] = "awaitingEmailConfirmation"
                event("Opt-out Started")
                return 202, run()
            if path.endswith("/email-confirmation/check"):
                state["link"] = True
                return 202, run()
            if path.endswith("/continue"):
                self.assertTrue(state["link"])
                state["status"] = "confirmed"
                event("Opt-out Confirmed")
                return 202, run()
            return 200, run()
        port = self.server(handle)
        config = dict(optOut=opt_out, emailConfirmation=True, subscriptionEnvironment="staging", pirEnvironment="staging",
                      checkpointTimeout=1, activityTimeout=2, emailTimeout=2, pirEndpoint="https://backend.test")
        for key in ("brokerFile", "profileFile", "expectedFile", "configurationFile"):
            path = Path(self.directory.name) / key
            path.write_text('{"version":"test"}')
            config[key] = str(path)
        config["configurationSHA256"] = env.sha256(config["configurationFile"])
        config["inputHashes"] = {k: env.sha256(config[k]) for k in ("brokerFile", "profileFile", "expectedFile")}
        config["brokerBytes"] = Path(config["brokerFile"]).read_bytes()
        broker = dict(name="Test", version="test")
        fake = FakeDevice()
        fake.identity = lambda: dict(pid=123, ok=True)
        fake.driver = type("Driver", (), {"state": lambda _: 4 if fake.fg else 1})()
        fake.terminate = lambda: setattr(fake, "fg", False)
        def logs(path):
            Path(path).write_text("PIR test log")
        fake.app_logs = logs
        ios = harness.Ios("iphone", self.directory.name, device_obj=fake)
        def fresh(ios):
            self.assertFalse(state["ack"])
            ios.reset()
        def acknowledge(*_):
            state["ack"] = True
        ios.inputs = (config, broker, {}, expected)
        original_client = self.pir.Client
        with patch.object(self.pir, "checkpoint", side_effect=acknowledge) as checkpoint, \
             patch.object(self.pir, "Client", side_effect=lambda evidence: original_client(evidence, port, "owner")), \
             patch.object(self.pir, "INSTANCE", "owner"), patch.object(self.pir, "PORT", port), \
             patch.object(self.pir.steps, "fresh_start", side_effect=fresh):
            self.pir.run(ios)
            self.assertEqual(harness._verdict(ios)[0], "pass")
            self.assertEqual(ios._run_cleanups(), [])
        self.assertEqual(json.loads(Path(self.directory.name, "pir-final-run.json").read_text()), run())
        self.assertFalse(fake.fg, "owned app must terminate even when simulator is retained")
        return ios, requests, checkpoint.call_count

    def test_full_email_flow_keeps_one_attempt_and_requires_link_before_continue(self):
        ios, requests, checkpoints = self.flow(opt_out=True)
        self.assertEqual(checkpoints, 1)
        self.assertTrue(any(c["check"] == "selected record has an email confirmation link" for c in ios.checks))
        self.assertTrue(any(p.endswith("/continue") for m, p in requests))

    def test_scan_only_needs_no_subscription_and_submits_no_opt_out(self):
        ios, requests, checkpoints = self.flow(opt_out=False)
        self.assertEqual(checkpoints, 0)
        self.assertFalse(any("/optouts/" in p for m, p in requests))
        self.assertTrue(any(c["check"] == "scan found 1 record(s) the app matched to the profile" for c in ios.checks))
        self.assertIn("PIR opt-out", [u["what"] for u in ios.unverified_items])

    def test_checkpoint_acknowledgement_and_cancellation_are_recorded_as_human_steps(self):
        from unittest.mock import patch
        for cancel in (False, True):
            evidence = tempfile.mkdtemp(dir=TMP)
            ios = harness.Ios("iphone", evidence, device_obj=FakeDevice())
            def respond(_):
                record = json.loads(Path(evidence, "checkpoint.json").read_text())
                Path(record["cancel" if cancel else "acknowledge"]).touch()
            with patch.object(self.pir.time, "sleep", side_effect=respond):
                if cancel:
                    with self.assertRaises(env.SetupFailed):
                        self.pir.checkpoint(ios, "test", 1)
                else:
                    self.pir.checkpoint(ios, "test", 1)
            record = json.loads(Path(evidence, "checkpoint.json").read_text())
            self.assertEqual(record["status"], "cancelled" if cancel else "acknowledged")
            self.assertIn("finishedAt", record)
            self.assertEqual(ios.human_steps, [record])

    def test_checkpoint_timeout_is_inconclusive_and_stale_ack_is_ignored(self):
        from unittest.mock import patch
        evidence = tempfile.mkdtemp(dir=TMP)
        Path(evidence, "ack-old").touch()
        ios = harness.Ios("iphone", evidence, device_obj=FakeDevice())
        with patch.object(self.pir.time, "monotonic", side_effect=[0, 2]):
            with self.assertRaises(env.SetupFailed):
                self.pir.checkpoint(ios, "test", 1)
        self.assertEqual(json.loads(Path(evidence, "checkpoint.json").read_text())["status"], "timedOut")


if __name__ == "__main__":
    unittest.main()
