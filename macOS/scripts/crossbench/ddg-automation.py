#!/usr/bin/env python3
"""Drive a Review/debug DuckDuckGo build through its local automation server."""

import json
import math
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def base_url(port):
    return "http://127.0.0.1:{}".format(port)


def request(port, method, path, params=None, timeout=60):
    token = os.environ.get("AUTOMATION_TOKEN", "")
    if not token:
        raise RuntimeError("AUTOMATION_TOKEN is required")
    query = urllib.parse.urlencode(params or {})
    url = base_url(port) + path + (("?" + query) if query else "")
    data = b"" if method == "POST" else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        payload = json.load(response)
    if "message" not in payload:
        raise RuntimeError("automation response has no message")
    return payload["message"]


def decode_json_message(message):
    if isinstance(message, str):
        return json.loads(message)
    return message


def request_expect(port, method, path, expected, params=None, timeout=60):
    value = request(port, method, path, params, timeout)
    if value != expected:
        raise RuntimeError(
            "{} returned an unexpected acknowledgement".format(path)
        )


def landed_on(requested, landed):
    if not landed:
        return False
    requested_url = urllib.parse.urlparse(requested)
    landed_url = urllib.parse.urlparse(landed)
    if (
        requested_url.scheme not in ("http", "https")
        or landed_url.scheme not in ("http", "https")
    ):
        return False
    wanted = requested_url.hostname or ""
    actual = landed_url.hostname or ""
    if not wanted or not actual:
        return False
    wanted = wanted.lower()
    actual = actual.lower()
    if wanted.startswith("www."):
        wanted = wanted[4:]
    return actual == wanted or actual.endswith("." + wanted)


def lcp_probe(settle_ms, load_window_ms):
    """Return JS that reads the final buffered LCP inside the load window."""
    return (
        "var settleMs=" + str(int(settle_ms)) + ";"
        "var maxMs=" + str(int(load_window_ms)) + ";"
        "return await new Promise(function(done){"
        "var v=-1,el=null,url=null,size=0;"
        "try{"
        "new PerformanceObserver(function(list){"
        "list.getEntries().forEach(function(e){"
        "if(e.startTime<=maxMs&&e.startTime>v){"
        "v=e.startTime;el=e.element;url=e.url;size=e.size;"
        "}});"
        "}).observe({type:'largest-contentful-paint',buffered:true});"
        "}catch(error){done({ms:-1,loc:location.href,error:String(error)});return;}"
        "setTimeout(function(){done({ms:v,element:el?el.tagName:null,"
        "id:el?el.id:null,url:url,size:size,loc:location.href,"
        "title:document.title});},settleMs);"
        "});"
    )


def check(port):
    try:
        request_expect(
            port, "GET", "/contentBlockerReady", "true", timeout=15
        )
    except Exception as error:  # noqa: BLE001 - command-line boundary
        print("automation check failed: {}".format(error), file=sys.stderr)
        return 1
    return 0


def shutdown(port):
    try:
        request(port, "POST", "/shutdown", timeout=10)
    except (urllib.error.URLError, OSError):
        # The app can close the connection while terminating.
        pass
    except Exception as error:  # noqa: BLE001 - command-line boundary
        print("automation shutdown failed: {}".format(error), file=sys.stderr)
        return 1
    return 0


def emit_measurement(detail, lcp=-1, offsite=1):
    if not isinstance(detail, dict):
        detail = {"error": "invalid automation result"}
    landed_url = detail.get("loc")
    print("detail={}".format(json.dumps(detail, separators=(",", ":"))))
    print("landed_url={}".format(landed_url if isinstance(landed_url, str) else ""))
    print("landed_offsite={}".format(offsite))
    print("lcp_ms={}".format(lcp))


def measure(port, url, settle_ms, load_window_seconds):
    detail = {"error": "measurement did not complete"}
    try:
        # Each app process is fresh, but clearing the active WKWebsiteDataStore
        # also covers persistent state that survives process restarts.
        request_expect(
            port, "POST", "/clearWebsiteData", "done", timeout=30
        )
        request_expect(
            port, "POST", "/navigate", "done", {"url": url}, timeout=30
        )
        time.sleep(load_window_seconds)
        message = request(
            port,
            "POST",
            "/execute",
            {
                "script": lcp_probe(
                    settle_ms, int(load_window_seconds * 1000)
                )
            },
            timeout=max(30, int(settle_ms / 1000) + 15),
        )
        detail = decode_json_message(message)
    except Exception as error:  # noqa: BLE001 - command-line boundary
        detail = {"error": type(error).__name__}
        emit_measurement(detail)
        print("measurement failed: {}".format(error), file=sys.stderr)
        return 1

    if not isinstance(detail, dict):
        emit_measurement({"error": "non-object automation result"})
        return 1

    landed_url = detail.get("loc")
    offsite = not landed_on(url, landed_url)
    lcp = detail.get("ms", -1)
    if detail.get("error"):
        emit_measurement(detail, -1, int(offsite))
        return 1
    if (
        isinstance(lcp, bool)
        or not isinstance(lcp, (int, float))
        or not math.isfinite(lcp)
    ):
        emit_measurement(detail, -2, int(offsite))
        return 1
    if lcp < -1:
        emit_measurement(detail, lcp, int(offsite))
        return 1
    if offsite:
        emit_measurement(detail, -1, 1)
        return 1
    emit_measurement(detail, lcp, 0)
    return 0


USAGE = """usage:
  ddg-automation.py <port> check
  ddg-automation.py <port> shutdown
  ddg-automation.py <port> measure <url> [settle_ms] [load_window_seconds]

AUTOMATION_TOKEN must be present in the environment."""


def main(argv):
    if len(argv) < 3:
        print(USAGE, file=sys.stderr)
        return 2
    port, command = argv[1], argv[2]
    if command == "check":
        return check(port)
    if command == "shutdown":
        return shutdown(port)
    if command == "measure" and len(argv) >= 4:
        settle_ms = float(argv[4]) if len(argv) >= 5 else 600
        load_window = float(argv[5]) if len(argv) >= 6 else 12
        return measure(port, argv[3], settle_ms, load_window)
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
