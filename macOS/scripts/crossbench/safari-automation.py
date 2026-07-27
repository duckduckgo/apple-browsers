#!/usr/bin/env python3
"""Minimal Safari WebDriver client for replayed LCP measurement."""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def base_url(port):
    return "http://127.0.0.1:{}".format(port)


def request(port, method, path, body=None, timeout=60):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        base_url(port) + path, data=data, method=method
    )
    if data is not None:
        req.add_header("Content-Type", "application/json; charset=utf-8")
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.load(response)


def new_session(port):
    response = request(
        port,
        "POST",
        "/session",
        {
            "capabilities": {
                "alwaysMatch": {
                    "browserName": "safari",
                    "acceptInsecureCerts": True,
                }
            }
        },
    )
    value = response.get("value", response)
    session_id = value.get("sessionId") or response.get("sessionId")
    if not session_id:
        raise RuntimeError(
            "new-session response has no sessionId: {}".format(response)
        )
    return session_id


def delete_session(port, session_id):
    try:
        request(port, "DELETE", "/session/{}".format(session_id), timeout=15)
    except (urllib.error.URLError, OSError):
        pass


def lcp_probe(settle_ms):
    return (
        "var done=arguments[arguments.length-1];"
        "var v=-1,el=null,url=null,size=0;"
        "try{new PerformanceObserver(function(list){"
        "list.getEntries().forEach(function(e){"
        "if(e.startTime>v){v=e.startTime;el=e.element;url=e.url;size=e.size;}"
        "});}).observe({type:'largest-contentful-paint',buffered:true});}"
        "catch(err){done(-1);return;}"
        "setTimeout(function(){done(v<0?-1:{ms:v,"
        "element:el?el.tagName:null,id:el?el.id:null,url:url,size:size,"
        "loc:location.href,title:document.title});},"
        + str(int(settle_ms))
        + ");"
    )


def landed_on(requested, landed):
    """Return whether the landed host is the requested host or its subdomain."""
    if not landed:
        return False
    requested_host = urllib.parse.urlparse(requested).hostname or ""
    landed_host = urllib.parse.urlparse(landed).hostname or ""
    if not requested_host or not landed_host:
        return False
    requested_host = requested_host.removeprefix("www.").lower()
    landed_host = landed_host.lower()
    return (
        landed_host == requested_host
        or landed_host.endswith("." + requested_host)
    )


def check(port):
    session_id = None
    try:
        session_id = new_session(port)
        return 0
    except (urllib.error.URLError, OSError, urllib.error.HTTPError) as error:
        print(
            "Safari session creation failed: {}".format(error),
            file=sys.stderr,
        )
        return 1
    finally:
        if session_id:
            delete_session(port, session_id)


def measure(port, url, settle_ms, load_window_seconds):
    session_id = None
    detail = -1
    try:
        session_id = new_session(port)
        request(
            port,
            "POST",
            "/session/{}/timeouts".format(session_id),
            {"script": 30000},
            timeout=15,
        )
        request(
            port,
            "POST",
            "/session/{}/url".format(session_id),
            {"url": url},
            timeout=60,
        )
        time.sleep(load_window_seconds)
        response = request(
            port,
            "POST",
            "/session/{}/execute/async".format(session_id),
            {"script": lcp_probe(settle_ms), "args": []},
            timeout=60,
        )
        detail = response.get("value")
    except (urllib.error.URLError, OSError, urllib.error.HTTPError) as error:
        print("measurement failed for {}: {}".format(url, error), file=sys.stderr)
    finally:
        if session_id:
            delete_session(port, session_id)

    lcp_ms = detail.get("ms", -1) if isinstance(detail, dict) else -1
    landed_url = detail.get("loc", "") if isinstance(detail, dict) else ""
    offsite = bool(landed_url) and not landed_on(url, landed_url)
    if offsite:
        lcp_ms = -1
        print(
            "measurement landed off-site for {}: {!r}".format(url, landed_url),
            file=sys.stderr,
        )

    print("detail={}".format(json.dumps(detail)))
    print("landed_url={}".format(landed_url))
    print("landed_offsite={}".format(1 if offsite else 0))
    print("lcp_ms={}".format(lcp_ms))
    return 0


USAGE = (
    "usage:\n"
    "  safari-automation.py DRIVER_PORT check\n"
    "  safari-automation.py DRIVER_PORT measure URL [SETTLE_MS] [WINDOW_SECONDS]"
)


def main(argv):
    if len(argv) < 3:
        print(USAGE, file=sys.stderr)
        return 2
    port, command = argv[1:3]
    arguments = argv[3:]
    if command == "check":
        return check(port)
    if command == "measure" and arguments:
        settle_ms = float(arguments[1]) if len(arguments) > 1 else 600
        window = float(arguments[2]) if len(arguments) > 2 else 12
        return measure(port, arguments[0], settle_ms, window)
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
