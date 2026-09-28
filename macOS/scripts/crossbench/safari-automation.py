#!/usr/bin/env python3
"""Minimal Safari WebDriver client for replayed LCP measurement."""

import json
import math
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
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        # WebDriver maps unrelated conditions onto the same status: a browsing
        # context that died and a session the driver has dropped are both 404.
        # The response body is what distinguishes them, and they need different
        # fixes, so fold it into the message rather than letting HTTPError
        # stringify to a bare "HTTP Error 404: Not Found". OSError keeps this
        # catchable by the existing handlers, since URLError derives from it.
        try:
            body = error.read().decode("utf-8", "replace").strip()[:500]
        except OSError:
            body = ""
        raise OSError(
            "{} {} -> HTTP {} {}{}".format(
                method,
                path,
                error.code,
                error.reason,
                ": " + body if body else "",
            )
        ) from error


def new_session(port, window_width=1366, window_height=768):
    response = request(
        port,
        "POST",
        "/session",
        {
            "capabilities": {
                "alwaysMatch": {
                    "browserName": "safari",
                    "acceptInsecureCerts": True,
                    "pageLoadStrategy": "none",
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
    set_window_size(port, session_id, window_width, window_height)
    return session_id


def delete_session(port, session_id):
    try:
        request(port, "DELETE", "/session/{}".format(session_id), timeout=15)
        return True
    except (urllib.error.URLError, OSError, urllib.error.HTTPError) as error:
        print(
            "Safari session deletion failed: {}".format(error),
            file=sys.stderr,
        )
        return False


def set_window_size(port, session_id, width, height):
    response = request(
        port,
        "POST",
        "/session/{}/window/rect".format(session_id),
        {"width": int(width), "height": int(height)},
        timeout=15,
    )
    rect = response.get("value", response)
    if rect.get("width") != int(width) or rect.get("height") != int(height):
        raise RuntimeError(
            "Safari window size mismatch: requested {}x{}, got {}x{}".format(
                width, height, rect.get("width"), rect.get("height")
            )
        )


def lcp_probe(settle_ms, load_window_ms):
    return (
        "var done=arguments[arguments.length-1];"
        "var v=-1,el=null,url=null,size=0,maxMs="
        + str(int(load_window_ms))
        + ";"
        "try{new PerformanceObserver(function(list){"
        "list.getEntries().forEach(function(e){"
        "if(e.startTime<=maxMs&&e.startTime>v){"
        "v=e.startTime;el=e.element;url=e.url;size=e.size;}"
        "});}).observe({type:'largest-contentful-paint',buffered:true});}"
        "catch(err){done({error:String(err),ms:-1,loc:location.href});return;}"
        "setTimeout(function(){done({ms:v,"
        "element:el?el.tagName:null,id:el?el.id:null,url:url,size:size,"
        "loc:location.href,title:document.title});},"
        + str(int(settle_ms))
        + ");"
    )


def landed_on(requested, landed):
    """Return whether the landed host is the requested host or its subdomain."""
    if not landed:
        return False
    requested_url = urllib.parse.urlparse(requested)
    landed_url = urllib.parse.urlparse(landed)
    if (
        requested_url.scheme not in {"http", "https"}
        or landed_url.scheme not in {"http", "https"}
    ):
        return False
    requested_host = requested_url.hostname or ""
    landed_host = landed_url.hostname or ""
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
    status = 0
    try:
        session_id = new_session(port)
    except (urllib.error.URLError, OSError, urllib.error.HTTPError) as error:
        print(
            "Safari session creation failed: {}".format(error),
            file=sys.stderr,
        )
        status = 1
    finally:
        if session_id and not delete_session(port, session_id):
            status = 1
    return status


def measure(
    port,
    url,
    settle_ms,
    load_window_seconds,
    window_width=1366,
    window_height=768,
):
    session_id = None
    detail = -1
    failed = False
    try:
        session_id = new_session(port, window_width, window_height)
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
            {
                "script": lcp_probe(
                    settle_ms, float(load_window_seconds) * 1000
                ),
                "args": [],
            },
            timeout=60,
        )
        detail = response.get("value")
    except (urllib.error.URLError, OSError, urllib.error.HTTPError) as error:
        print("measurement failed for {}: {}".format(url, error), file=sys.stderr)
        failed = True
    except Exception as error:  # Surface malformed WebDriver responses as failures.
        print("measurement failed for {}: {}".format(url, error), file=sys.stderr)
        failed = True
    finally:
        if session_id and not delete_session(port, session_id):
            failed = True

    lcp_ms = detail.get("ms", -1) if isinstance(detail, dict) else -1
    landed_url = detail.get("loc", "") if isinstance(detail, dict) else ""
    if not failed and isinstance(detail, dict) and detail.get("error"):
        print(
            "measurement probe failed for {}: {}".format(
                url, detail["error"]
            ),
            file=sys.stderr,
        )
        failed = True
    if not failed and (
        not isinstance(lcp_ms, (int, float))
        or isinstance(lcp_ms, bool)
        or not math.isfinite(lcp_ms)
        or lcp_ms < -1
    ):
        print(
            "measurement produced an invalid LCP value for {}: {!r}".format(
                url, lcp_ms
            ),
            file=sys.stderr,
        )
        lcp_ms = -1
        failed = True
    offsite = bool(landed_url) and not landed_on(url, landed_url)
    if offsite:
        lcp_ms = -1
        print(
            "measurement landed off-site for {}: {!r}".format(url, landed_url),
            file=sys.stderr,
        )
        failed = True

    if not failed and not landed_url:
        print(
            "measurement produced no landing URL for {}".format(url),
            file=sys.stderr,
        )
        failed = True

    print("detail={}".format(json.dumps(detail)))
    print("landed_url={}".format(landed_url))
    print("landed_offsite={}".format(1 if offsite else 0))
    print("lcp_ms={}".format(lcp_ms))
    return 1 if failed else 0


USAGE = (
    "usage:\n"
    "  safari-automation.py DRIVER_PORT check\n"
    "  safari-automation.py DRIVER_PORT measure URL [SETTLE_MS] [WINDOW_SECONDS] "
    "[WINDOW_WIDTH] [WINDOW_HEIGHT]"
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
        window_width = int(arguments[3]) if len(arguments) > 3 else 1366
        window_height = int(arguments[4]) if len(arguments) > 4 else 768
        return measure(
            port,
            arguments[0],
            settle_ms,
            window,
            window_width,
            window_height,
        )
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
