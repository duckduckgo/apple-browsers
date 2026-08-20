#!/usr/bin/env python3
"""Unit tests for the DuckDuckGo automation client."""

import importlib.util
import io
import os
import pathlib
import unittest
import urllib.error
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock


ROOT = pathlib.Path(__file__).parents[1]
MODULE_PATH = ROOT / "ddg-automation.py"
SPEC = importlib.util.spec_from_file_location("ddg_automation", MODULE_PATH)
DDG_AUTOMATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DDG_AUTOMATION)


class DDGAutomationTests(unittest.TestCase):
    def test_request_uses_bearer_token_without_putting_it_in_url(self):
        response = mock.MagicMock()
        response.__enter__.return_value = io.BytesIO(
            b'{"message":"true","requestPath":"/contentBlockerReady"}'
        )
        with mock.patch.dict(
            os.environ, {"AUTOMATION_TOKEN": "private-token"}
        ), mock.patch.object(
            DDG_AUTOMATION.urllib.request,
            "urlopen",
            return_value=response,
        ) as urlopen:
            self.assertEqual(
                DDG_AUTOMATION.request(
                    "8788", "GET", "/contentBlockerReady"
                ),
                "true",
            )
        request = urlopen.call_args.args[0]
        self.assertEqual(
            request.get_header("Authorization"), "Bearer private-token"
        )
        self.assertNotIn("private-token", request.full_url)

    def test_request_percent_encodes_script_spaces(self):
        response = mock.MagicMock()
        response.__enter__.return_value = io.BytesIO(
            b'{"message":"null","requestPath":"/execute"}'
        )
        with mock.patch.dict(
            os.environ, {"AUTOMATION_TOKEN": "private-token"}
        ), mock.patch.object(
            DDG_AUTOMATION.urllib.request,
            "urlopen",
            return_value=response,
        ) as urlopen:
            DDG_AUTOMATION.request(
                "8788",
                "POST",
                "/execute",
                {"script": "return 1 + 1"},
            )

        request = urlopen.call_args.args[0]
        self.assertIn("script=return%201%20%2B%201", request.full_url)
        self.assertNotIn("script=return+1", request.full_url)

    def test_measure_clears_state_before_navigation(self):
        calls = []

        def request(_port, method, path, params=None, timeout=60):
            calls.append((method, path, params))
            if path == "/execute":
                return '{"ms":321,"loc":"https://www.apple.com/"}'
            return "done"

        stdout = io.StringIO()
        with mock.patch.object(
            DDG_AUTOMATION, "request", side_effect=request
        ), mock.patch.object(
            DDG_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout):
            status = DDG_AUTOMATION.measure(
                "8788", "https://apple.com", 0, 12
            )

        self.assertEqual(status, 0)
        self.assertEqual(
            [(method, path) for method, path, _ in calls],
            [
                ("POST", "/clearWebsiteData"),
                ("POST", "/navigate"),
                ("POST", "/execute"),
            ],
        )
        self.assertIn("landed_offsite=0", stdout.getvalue())
        self.assertIn("lcp_ms=321", stdout.getvalue())

    def test_check_requires_a_selected_tab_not_just_compiled_rules(self):
        calls = []

        def request(_port, method, path, params=None, timeout=60):
            calls.append(path)
            if path == "/getWindowHandle":
                raise urllib.error.HTTPError(
                    "http://[::1]:8788" + path, 400, "Bad Request", {}, None
                )
            return "true"

        with mock.patch.object(
            DDG_AUTOMATION, "request", side_effect=request
        ), redirect_stderr(io.StringIO()):
            status = DDG_AUTOMATION.check("8788")

        self.assertEqual(status, 1)
        self.assertEqual(calls, ["/contentBlockerReady", "/getWindowHandle"])

    def test_check_passes_once_a_tab_handle_exists(self):
        def request(_port, _method, path, params=None, timeout=60):
            return "true" if path == "/contentBlockerReady" else "tab-uuid"

        with mock.patch.object(DDG_AUTOMATION, "request", side_effect=request):
            self.assertEqual(DDG_AUTOMATION.check("8788"), 0)

    def test_check_rejects_an_empty_tab_handle(self):
        def request(_port, _method, path, params=None, timeout=60):
            return "true" if path == "/contentBlockerReady" else ""

        with mock.patch.object(
            DDG_AUTOMATION, "request", side_effect=request
        ), redirect_stderr(io.StringIO()):
            self.assertEqual(DDG_AUTOMATION.check("8788"), 1)

    def test_probe_enforces_twelve_second_window(self):
        probe = DDG_AUTOMATION.lcp_probe(600, 12000)
        self.assertIn("maxMs=12000", probe)
        self.assertIn("e.startTime<=maxMs", probe)
        self.assertIn("buffered:true", probe)

    def test_probe_captures_bounded_page_state(self):
        probe = DDG_AUTOMATION.lcp_probe(600, 12000)
        for field in (
            "resourceCount",
            "resourceFinished",
            "resourceEncodedBytes",
            "navigationResponseEnd",
            "readyState",
            "ytInitialData",
            "ytdAppChildCount",
            "richGrid",
        ):
            self.assertIn(field, probe)
        self.assertNotIn("resources.map", probe)

    def test_measure_requires_successful_setup_acknowledgements(self):
        for failed_path in ("/clearWebsiteData", "/navigate"):
            with self.subTest(failed_path=failed_path):
                def request(_port, _method, path, params=None, timeout=60):
                    if path == failed_path:
                        return "false"
                    return "done"

                stdout = io.StringIO()
                with mock.patch.object(
                    DDG_AUTOMATION, "request", side_effect=request
                ), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
                    status = DDG_AUTOMATION.measure(
                        "8788", "https://apple.com", 0, 12
                    )
                self.assertEqual(status, 1)
                self.assertIn("lcp_ms=-1", stdout.getvalue())

    def test_landing_requires_http_or_https(self):
        self.assertFalse(
            DDG_AUTOMATION.landed_on(
                "https://apple.com", "file://apple.com/private"
            )
        )
        self.assertFalse(
            DDG_AUTOMATION.landed_on(
                "file://apple.com/private", "https://apple.com/"
            )
        )

    def test_structured_probe_error_fails_measurement(self):
        stdout = io.StringIO()
        with mock.patch.object(
            DDG_AUTOMATION,
            "request",
            side_effect=[
                "done",
                "done",
                '{"ms":12,"loc":"https://apple.com/","error":"probe failed"}',
            ],
        ), mock.patch.object(
            DDG_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout):
            status = DDG_AUTOMATION.measure(
                "8788", "https://apple.com", 0, 12
            )
        self.assertEqual(status, 1)
        self.assertIn("lcp_ms=-1", stdout.getvalue())

    def test_offsite_result_is_structured_and_fails(self):
        stdout = io.StringIO()
        with mock.patch.object(
            DDG_AUTOMATION,
            "request",
            side_effect=["done", "done", '{"ms":5,"loc":"about:blank"}'],
        ), mock.patch.object(
            DDG_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            status = DDG_AUTOMATION.measure(
                "8788", "https://apple.com", 0, 12
            )
        self.assertEqual(status, 1)
        self.assertIn("landed_offsite=1", stdout.getvalue())
        self.assertIn("lcp_ms=-1", stdout.getvalue())

    def test_transport_failure_still_emits_all_fields(self):
        stdout = io.StringIO()
        with mock.patch.object(
            DDG_AUTOMATION, "request", side_effect=OSError("unavailable")
        ), redirect_stdout(stdout), redirect_stderr(io.StringIO()):
            status = DDG_AUTOMATION.measure(
                "8788", "https://apple.com", 0, 12
            )
        self.assertEqual(status, 1)
        for field in ("detail=", "landed_url=", "landed_offsite=", "lcp_ms="):
            self.assertEqual(stdout.getvalue().count(field), 1)

    def test_unfinalized_lcp_is_a_valid_measurement_attempt(self):
        stdout = io.StringIO()
        with mock.patch.object(
            DDG_AUTOMATION,
            "request",
            side_effect=[
                "done",
                "done",
                '{"ms":-1,"loc":"https://apple.com/"}',
            ],
        ), mock.patch.object(
            DDG_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout):
            status = DDG_AUTOMATION.measure(
                "8788", "https://apple.com", 0, 12
            )
        self.assertEqual(status, 0)
        self.assertIn("lcp_ms=-1", stdout.getvalue())

    def test_lcp_below_unfinalized_sentinel_fails(self):
        stdout = io.StringIO()
        with mock.patch.object(
            DDG_AUTOMATION,
            "request",
            side_effect=[
                "done",
                "done",
                '{"ms":-2,"loc":"https://apple.com/"}',
            ],
        ), mock.patch.object(
            DDG_AUTOMATION.time, "sleep"
        ), redirect_stdout(stdout):
            status = DDG_AUTOMATION.measure(
                "8788", "https://apple.com", 0, 12
            )
        self.assertEqual(status, 1)
        self.assertIn("lcp_ms=-2", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
