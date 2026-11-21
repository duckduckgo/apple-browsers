"""Tests for fixture pages and live hosts: serving the fixture for a run, which hosts count as live, and what the report
says about them. Loopback only: no app, build, VM or network.
Run: python3 -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import os
import socket
import sys
import tempfile
import unittest
import urllib.request

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "scripts"))
import harness  # noqa: E402


def listening(port):
    with socket.socket() as s:
        return s.connect_ex(("127.0.0.1", port)) == 0


class HostTests(unittest.TestCase):
    def test_only_network_urls_have_a_host(self):
        self.assertEqual(harness.host_of("https://duck.ai/chat?x=1"), "duck.ai")
        self.assertEqual(harness.host_of("http://127.0.0.1:8123/index.html"), "127.0.0.1")
        for url in ("duck://newtab", "about:blank", "data:text/html,hi", "not a url"):
            self.assertIsNone(harness.host_of(url), url)

    def test_local_hosts_are_never_undeclared(self):
        self.assertEqual(harness.undeclared({"127.0.0.1", "localhost", "::1"}, []), [])

    def test_a_live_entry_covers_its_host_and_subdomains_only(self):
        hosts = {"duck.ai", "api.duck.ai", "evilduck.ai", "duckduckgo.com"}
        self.assertEqual(harness.undeclared(hosts, ["duck.ai"]), ["duckduckgo.com", "evilduck.ai"])

    def test_evidence_kind(self):
        self.assertEqual(harness.evidence_kind([], {"127.0.0.1"}), "no live hosts observed")
        self.assertEqual(harness.evidence_kind(["duck.ai"], {"127.0.0.1", "duck.ai"}), "live: duck.ai")
        self.assertEqual(harness.evidence_kind([], {"duckduckgo.com"}), "live: duckduckgo.com")
        self.assertTrue(harness.evidence_kind([], None).startswith("unknown: hosts not collected"))


class ReportTests(unittest.TestCase):
    def report(self, hosts, live):
        rec = harness.Record()
        rec.checks, rec.app_running, rec.hosts = [("t", True, None, "unchanged")], True, hosts
        return harness.report("x", rec, dict(live=live), tempfile.mkdtemp())

    def test_an_undeclared_live_host_is_a_bold_warning_not_a_failure(self):
        text = self.report({"127.0.0.1", "duckduckgo.com"}, [])
        warnings = text.split("Warnings:\n")[1].split("\n\n")[0]
        self.assertIn("- **Undeclared live host: duckduckgo.com** (not in LIVE)", warnings)
        self.assertNotIn("127.0.0.1", warnings)
        self.assertIn("**PASS**", text)
        self.assertIn("- Evidence: live: duckduckgo.com\n", text)

    def test_a_declared_live_host_is_listed_not_flagged(self):
        text = self.report({"127.0.0.1", "duckduckgo.com"}, ["duckduckgo.com"])
        self.assertNotIn("Undeclared", text)
        self.assertIn("- Hosts the app loaded: 127.0.0.1, duckduckgo.com\n", text)
        self.assertIn("- Evidence: live: duckduckgo.com\n", text)

    def test_no_live_hosts_observed(self):
        text = self.report({"127.0.0.1"}, [])
        self.assertIn("- Evidence: no live hosts observed\n", text)
        self.assertNotIn("Warnings:", text)

    def test_without_automation_hosts_are_unknown_not_local(self):
        text = self.report(None, [])
        self.assertIn("- Hosts the app loaded: (not collected: AUTOMATION is off)\n", text)
        self.assertNotIn("no live hosts observed", text)


class HostCollectionTests(unittest.TestCase):
    def test_urls_read_navigated_and_swept_at_the_end_are_collected(self):
        rec = harness.Record()
        rec.phase = "proof"
        mac = harness.Mac("t", tempfile.mkdtemp(), rec, automation=True)
        # As the AutomationServer answers: "/" escaped as "\/".
        sweep = r'"https:\/\/duckduckgo.com\/ https:\/\/improving.duckduckgo.com\/t\/x?a=1 duck:\/\/player"'
        answers = {"navigate": (0, "true"), "url": (0, "https://example.com/page"), "eval": (0, sweep)}
        mac._sh = lambda command, *a: answers[a[0]] if command == "web" else (0, "yes")
        mac.navigate("http://127.0.0.1:1/index.html")
        mac.url()
        harness._finish(mac, rec, mac.evidence)
        self.assertEqual(rec.hosts, {"127.0.0.1", "example.com", "duckduckgo.com", "improving.duckduckgo.com"})

    def test_a_failed_sweep_is_a_problem(self):
        rec = harness.Record()
        rec.phase = "proof"
        mac = harness.Mac("t", tempfile.mkdtemp(), rec, automation=True)
        mac._sh = lambda command, *a: (2, "NO AUTOMATION") if command == "web" else (0, "yes")
        harness._finish(mac, rec, mac.evidence)
        self.assertTrue(any("hosts of the last page not read" in p for p in rec.problems))


class FixtureTests(unittest.TestCase):
    def test_tokens_are_fresh_and_prefixed(self):
        mac = harness.Mac("t", tempfile.mkdtemp(), harness.Record())
        a, b = mac.token("demo"), mac.token("demo")
        self.assertNotEqual(a, b)
        self.assertTrue(a.startswith("demo-"))

    def test_the_fixture_serves_the_token_page_and_its_target_then_stops_at_cleanup(self):
        rec = harness.Record()
        rec.phase = "proof"
        mac = harness.Mac("t", tempfile.mkdtemp(), rec)
        mac._sh = lambda command, *a: (0, "yes")
        url = mac.fixture_url("a b&c")
        port = mac._fixture.port
        self.assertEqual(url, f"http://127.0.0.1:{port}/index.html?token=a%20b%26c")
        with urllib.request.urlopen(url, timeout=5) as r:
            self.assertIn(b'id="token"', r.read())
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/target.html", timeout=5) as r:
            self.assertIn(b"target page", r.read())
        self.assertIs(mac.fixture_url("x") and mac._fixture.port, port)   # one server per run
        harness._finish(mac, rec, mac.evidence)
        self.assertFalse(listening(port))
        self.assertEqual(rec.problems, [])
        self.assertIn("GET /target.html", open(os.path.join(mac.evidence, "fixture.log")).read())

    def test_it_never_listens_beyond_loopback(self):
        mac = harness.Mac("t", tempfile.mkdtemp(), harness.Record())
        mac.fixture_url("x")
        try:
            self.assertEqual(mac._fixture.server.server_address[0], "127.0.0.1")
        finally:
            mac._fixture.stop()


if __name__ == "__main__":
    unittest.main()
