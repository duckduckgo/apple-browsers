#!/usr/bin/env python3
"""Pure unit tests for Safari replay helper behavior."""

import importlib.util
import io
import pathlib
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).with_name("safari-automation.py")
SPEC = importlib.util.spec_from_file_location("safari_automation", MODULE_PATH)
SAFARI_AUTOMATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SAFARI_AUTOMATION)

PROXY_PATH = pathlib.Path(__file__).with_name("httpproxy.py")
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
            return_value={"value": {"sessionId": "session"}},
        ) as request:
            self.assertEqual(
                SAFARI_AUTOMATION.new_session("8790"), "session"
            )
        body = request.call_args.args[3]
        self.assertIs(
            body["capabilities"]["alwaysMatch"]["acceptInsecureCerts"], True
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
