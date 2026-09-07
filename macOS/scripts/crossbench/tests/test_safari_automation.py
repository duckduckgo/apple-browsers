#!/usr/bin/env python3
"""Pure unit tests for Safari replay helper behavior."""

import importlib.util
import io
import pathlib
import unittest
import urllib.error
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock


ROOT = pathlib.Path(__file__).parents[1]
MODULE_PATH = ROOT / "safari-automation.py"
SPEC = importlib.util.spec_from_file_location("safari_automation", MODULE_PATH)
SAFARI_AUTOMATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SAFARI_AUTOMATION)

PROXY_PATH = ROOT / "httpproxy.py"
PROXY_SPEC = importlib.util.spec_from_file_location("httpproxy", PROXY_PATH)
HTTP_PROXY = importlib.util.module_from_spec(PROXY_SPEC)
PROXY_SPEC.loader.exec_module(HTTP_PROXY)


class LandingTests(unittest.TestCase):

    def test_accepts_apex_and_subdomain(self):
        self.assertTrue(
            SAFARI_AUTOMATION.landed_on(
                "https://apple.com", "https://www.apple.com/shop"
            )
        )
        self.assertTrue(
            SAFARI_AUTOMATION.landed_on(
                "https://apple.com", "https://support.apple.com/"
            )
        )

    def test_rejects_offsite_and_non_http_pages(self):
        self.assertFalse(
            SAFARI_AUTOMATION.landed_on(
                "https://apple.com", "https://notapple.com/"
            )
        )
        self.assertFalse(
            SAFARI_AUTOMATION.landed_on(
                "https://apple.com", "safari-resource://certificate-error"
            )
        )

    def test_new_session_requests_insecure_cert_acceptance(self):
        with mock.patch.object(
            SAFARI_AUTOMATION,
            "request",
            side_effect=[
                {"value": {"sessionId": "session"}},
                {"value": {"width": 1366, "height": 768}},
            ],
        ) as request:
            self.assertEqual(
                SAFARI_AUTOMATION.new_session("8790"), "session"
            )
        body = request.call_args_list[0].args[3]
        self.assertIs(
            body["capabilities"]["alwaysMatch"]["acceptInsecureCerts"], True
        )
        self.assertEqual(
            body["capabilities"]["alwaysMatch"]["pageLoadStrategy"], "none"
        )

    def test_set_window_size_requires_exact_outer_dimensions(self):
        with mock.patch.object(
            SAFARI_AUTOMATION,
            "request",
            return_value={"value": {"width": 1366, "height": 768}},
        ) as request:
            SAFARI_AUTOMATION.set_window_size("8790", "session", 1366, 768)
        self.assertEqual(
            request.call_args.args[3], {"width": 1366, "height": 768}
        )

    def test_set_window_size_rejects_clamped_dimensions(self):
        with mock.patch.object(
            SAFARI_AUTOMATION,
            "request",
            return_value={"value": {"width": 1024, "height": 768}},
        ):
            with self.assertRaisesRegex(RuntimeError, "window size mismatch"):
                SAFARI_AUTOMATION.set_window_size(
                    "8790", "session", 1366, 768
                )

    def test_measurement_transport_failure_is_nonzero_with_parseable_output(self):
        stdout = io.StringIO()
        with mock.patch.object(
            SAFARI_AUTOMATION,
            "new_session",
            side_effect=OSError("driver unavailable"),
        ), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            status = SAFARI_AUTOMATION.measure(
                "8790", "https://apple.com", 0, 0
            )
        self.assertEqual(status, 1)
        self.assertIn("detail=", stdout.getvalue())
        self.assertIn("lcp_ms=-1", stdout.getvalue())

    def test_measurement_without_landing_url_is_nonzero(self):
        stdout = io.StringIO()
        response = {"value": {"ms": 25, "loc": ""}}
        with mock.patch.object(
            SAFARI_AUTOMATION, "new_session", return_value="session"
        ), mock.patch.object(
            SAFARI_AUTOMATION, "request", return_value=response
        ), mock.patch.object(
            SAFARI_AUTOMATION, "delete_session"), mock.patch.object(
            SAFARI_AUTOMATION.time, "sleep"), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            status = SAFARI_AUTOMATION.measure(
                "8790", "https://apple.com", 0, 0
            )
        self.assertEqual(status, 1)
        self.assertIn("landed_url=", stdout.getvalue())

    def test_measurement_with_non_numeric_lcp_is_nonzero(self):
        stdout = io.StringIO()
        response = {
            "value": {"ms": "not-a-number", "loc": "https://apple.com/"}
        }
        with mock.patch.object(
            SAFARI_AUTOMATION, "new_session", return_value="session"
        ), mock.patch.object(
            SAFARI_AUTOMATION, "request", return_value=response
        ), mock.patch.object(
            SAFARI_AUTOMATION, "delete_session"
        ), mock.patch.object(
            SAFARI_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            status = SAFARI_AUTOMATION.measure(
                "8790", "https://apple.com", 0, 0
            )
        self.assertEqual(status, 1)
        self.assertIn("lcp_ms=-1", stdout.getvalue())

    def test_measurement_without_finalized_lcp_is_successful(self):
        stdout = io.StringIO()
        response = {"value": {"ms": -1, "loc": "https://apple.com/"}}
        with mock.patch.object(
            SAFARI_AUTOMATION, "new_session", return_value="session"
        ), mock.patch.object(
            SAFARI_AUTOMATION, "request", return_value=response
        ), mock.patch.object(
            SAFARI_AUTOMATION, "delete_session"
        ), mock.patch.object(
            SAFARI_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            status = SAFARI_AUTOMATION.measure(
                "8790", "https://apple.com", 0, 12
            )
        self.assertEqual(status, 0)
        self.assertIn("lcp_ms=-1", stdout.getvalue())
        self.assertIn("landed_url=https://apple.com/", stdout.getvalue())

    def test_probe_enforces_load_window(self):
        probe = SAFARI_AUTOMATION.lcp_probe(600, 12000)
        self.assertIn("maxMs=12000", probe)
        self.assertIn("e.startTime<=maxMs", probe)
        self.assertIn("done({ms:v,", probe)

    def test_measurement_with_non_finite_lcp_is_nonzero(self):
        stdout = io.StringIO()
        response = {"value": {"ms": float("inf"), "loc": "https://apple.com/"}}
        with mock.patch.object(
            SAFARI_AUTOMATION, "new_session", return_value="session"
        ), mock.patch.object(
            SAFARI_AUTOMATION, "request", return_value=response
        ), mock.patch.object(
            SAFARI_AUTOMATION, "delete_session"
        ), mock.patch.object(
            SAFARI_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            status = SAFARI_AUTOMATION.measure(
                "8790", "https://apple.com", 0, 12
            )
        self.assertEqual(status, 1)
        self.assertIn("lcp_ms=-1", stdout.getvalue())

    def test_offsite_measurement_is_nonzero(self):
        stdout = io.StringIO()
        response = {
            "value": {"ms": 25, "loc": "https://certificate-error.test/"}
        }
        with mock.patch.object(
            SAFARI_AUTOMATION, "new_session", return_value="session"
        ), mock.patch.object(
            SAFARI_AUTOMATION, "request", return_value=response
        ), mock.patch.object(
            SAFARI_AUTOMATION, "delete_session", return_value=True
        ), mock.patch.object(
            SAFARI_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            status = SAFARI_AUTOMATION.measure(
                "8790", "https://apple.com", 0, 12
            )
        self.assertEqual(status, 1)
        self.assertIn("landed_offsite=1", stdout.getvalue())
        self.assertIn("lcp_ms=-1", stdout.getvalue())

    def test_session_deletion_failure_is_nonzero(self):
        stdout = io.StringIO()
        response = {"value": {"ms": 25, "loc": "https://apple.com/"}}
        with mock.patch.object(
            SAFARI_AUTOMATION, "new_session", return_value="session"
        ), mock.patch.object(
            SAFARI_AUTOMATION, "request", return_value=response
        ), mock.patch.object(
            SAFARI_AUTOMATION, "delete_session", return_value=False
        ), mock.patch.object(
            SAFARI_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            status = SAFARI_AUTOMATION.measure(
                "8790", "https://apple.com", 0, 12
            )
        self.assertEqual(status, 1)

    def test_check_fails_when_session_cannot_be_deleted(self):
        with mock.patch.object(
            SAFARI_AUTOMATION, "new_session", return_value="session"
        ), mock.patch.object(
            SAFARI_AUTOMATION, "delete_session", return_value=False
        ):
            self.assertEqual(SAFARI_AUTOMATION.check("8790"), 1)


class ProxyParsingTests(unittest.TestCase):

    def test_authority_defaults_and_explicit_ports(self):
        self.assertEqual(
            HTTP_PROXY.split_authority("example.com", 443),
            ("example.com", 443),
        )
        self.assertEqual(
            HTTP_PROXY.split_authority("example.com:8443", 443),
            ("example.com", 8443),
        )

    def test_ipv6_authority(self):
        self.assertEqual(
            HTTP_PROXY.split_authority("[::1]:8443", 443),
            ("::1", 8443),
        )


if __name__ == "__main__":
    unittest.main()


class WebDriverErrorReportingTests(unittest.TestCase):
    """A 404 alone cannot be acted on; the body says which failure it was."""

    def _raise_http_error(self, body):
        error = urllib.error.HTTPError(
            "http://127.0.0.1:8790/session/abc/execute/async",
            404,
            "Not Found",
            {},
            io.BytesIO(body),
        )
        self.addCleanup(error.close)
        return error

    def test_http_error_names_the_endpoint_and_webdriver_reason(self):
        payload = b'{"value":{"error":"no such window","message":"context died"}}'
        with mock.patch.object(
            SAFARI_AUTOMATION.urllib.request,
            "urlopen",
            side_effect=self._raise_http_error(payload),
        ):
            with self.assertRaises(OSError) as raised:
                SAFARI_AUTOMATION.request(
                    "8790", "POST", "/session/abc/execute/async", {}
                )
        message = str(raised.exception)
        self.assertIn("POST /session/abc/execute/async", message)
        self.assertIn("404", message)
        self.assertIn("no such window", message)

    def test_unreadable_body_still_reports_status_and_endpoint(self):
        class Unreadable(io.BytesIO):
            def read(self, *args):
                raise OSError("stream closed")

        error = urllib.error.HTTPError(
            "http://127.0.0.1:8790/session/abc/url",
            404,
            "Not Found",
            {},
            Unreadable(b""),
        )
        with mock.patch.object(
            SAFARI_AUTOMATION.urllib.request, "urlopen", side_effect=error
        ):
            with self.assertRaises(OSError) as raised:
                SAFARI_AUTOMATION.request("8790", "POST", "/session/abc/url", {})
        message = str(raised.exception)
        self.assertIn("POST /session/abc/url", message)
        self.assertIn("404", message)

    def test_measure_surfaces_the_enriched_message_and_still_prints_output(self):
        payload = b'{"value":{"error":"invalid session id"}}'
        stdout = io.StringIO()
        stderr = io.StringIO()
        with mock.patch.object(
            SAFARI_AUTOMATION, "new_session", return_value="abc"
        ), mock.patch.object(
            SAFARI_AUTOMATION.urllib.request,
            "urlopen",
            side_effect=self._raise_http_error(payload),
        ), mock.patch.object(
            SAFARI_AUTOMATION, "delete_session", return_value=True
        ), redirect_stdout(stdout), redirect_stderr(stderr):
            status = SAFARI_AUTOMATION.measure(
                "8790", "https://walmart.com", 0, 0
            )
        self.assertEqual(status, 1)
        self.assertIn("invalid session id", stderr.getvalue())
        self.assertIn("lcp_ms=-1", stdout.getvalue())
