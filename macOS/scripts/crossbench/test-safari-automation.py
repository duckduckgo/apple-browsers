#!/usr/bin/env python3
"""Pure unit tests for Safari replay helper behavior."""

import importlib.util
import pathlib
import unittest
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
