#!/usr/bin/env python3
"""Drive a Review/debug DuckDuckGo build through its local automation server."""

import base64
import json
import math
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def base_url(port):
    host = os.environ.get("DDG_AUTOMATION_HOST", "::1")
    if ":" in host and not host.startswith("["):
        host = "[{}]".format(host)
    return "http://{}:{}".format(host, port)


def request(port, method, path, params=None, timeout=60):
    token = os.environ.get("AUTOMATION_TOKEN", "")
    if not token:
        raise RuntimeError("AUTOMATION_TOKEN is required")
    query = urllib.parse.urlencode(
        params or {}, quote_via=urllib.parse.quote
    )
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
        "setTimeout(function(){"
        "var result={ms:v,element:el?el.tagName:null,id:el?el.id:null,"
        "url:url,size:size,loc:location.href,title:document.title};"
        "try{"
        "var resources=performance.getEntriesByType('resource');"
        "var encoded=0,decoded=0,finished=0,maxEnd=0;"
        "for(var i=0;i<resources.length;i++){"
        "encoded+=resources[i].encodedBodySize||0;"
        "decoded+=resources[i].decodedBodySize||0;"
        "if(resources[i].responseEnd>0)finished++;"
        "if(resources[i].responseEnd>maxEnd)maxEnd=resources[i].responseEnd;"
        "}"
        "var navigations=performance.getEntriesByType('navigation');"
        "var nav=navigations.length?navigations[0]:null;"
        "var app=document.querySelector('ytd-app');"
        "var richGrid=document.querySelector('ytd-rich-grid-renderer');"
        "var titleContainer=document.getElementById('title-container');"
        "var richStyle=richGrid?getComputedStyle(richGrid):null;"
        "var titleStyle=titleContainer?getComputedStyle(titleContainer):null;"
        "var richRect=richGrid?richGrid.getBoundingClientRect():null;"
        "var titleRect=titleContainer?titleContainer.getBoundingClientRect():null;"
        "result.readyState=document.readyState;"
        "result.visibilityState=document.visibilityState;"
        "result.documentHidden=document.hidden;"
        "result.hasFocus=document.hasFocus();"
        "result.innerWidth=window.innerWidth;"
        "result.innerHeight=window.innerHeight;"
        "result.devicePixelRatio=window.devicePixelRatio;"
        "result.resourceCount=resources.length;"
        "result.resourceFinished=finished;"
        "result.resourceEncodedBytes=encoded;"
        "result.resourceDecodedBytes=decoded;"
        "result.maxResourceEnd=Math.round(maxEnd);"
        "result.navigationResponseEnd=nav?Math.round(nav.responseEnd):null;"
        "result.domContentLoadedEnd=nav?Math.round(nav.domContentLoadedEventEnd):null;"
        "result.loadEventEnd=nav?Math.round(nav.loadEventEnd):null;"
        "result.scriptCount=document.scripts.length;"
        "result.styleSheetCount=document.styleSheets.length;"
        "result.bodyChildCount=document.body?document.body.childElementCount:0;"
        "result.ytInitialData=typeof window.ytInitialData!=='undefined';"
        "result.ytdApp=!!app;"
        "result.ytdAppChildCount=app?app.childElementCount:0;"
        "result.richGrid=!!richGrid;"
        "result.richGridChildCount=richGrid?richGrid.childElementCount:0;"
        "result.richItemCount=document.querySelectorAll('ytd-rich-item-renderer').length;"
        "result.richGridTextLength=richGrid?(richGrid.textContent||'').length:0;"
        "result.richGridWidth=richRect?Math.round(richRect.width):0;"
        "result.richGridHeight=richRect?Math.round(richRect.height):0;"
        "result.richGridDisplay=richStyle?richStyle.display:null;"
        "result.richGridVisibility=richStyle?richStyle.visibility:null;"
        "result.richGridOpacity=richStyle?richStyle.opacity:null;"
        "result.titleContainer=!!titleContainer;"
        "result.titleTextLength=titleContainer?(titleContainer.textContent||'').length:0;"
        "result.titleWidth=titleRect?Math.round(titleRect.width):0;"
        "result.titleHeight=titleRect?Math.round(titleRect.height):0;"
        "result.titleDisplay=titleStyle?titleStyle.display:null;"
        "result.titleVisibility=titleStyle?titleStyle.visibility:null;"
        "result.titleOpacity=titleStyle?titleStyle.opacity:null;"
        "}catch(error){result.stateError=String(error);}"
        "done(result);},settleMs);"
        "});"
    )


def screenshot(port, out_path):
    """Save a PNG of the current webview for diagnostics.

    Deliberately not part of measure(): capturing costs an IPC round trip and
    an image encode, and the harness runs this between repetitions only, so a
    diagnostic can never inflate the interval it is meant to explain.
    """
    message = request(port, "GET", "/screenshot", timeout=60)
    data = base64.b64decode(message)
    with open(out_path, "wb") as handle:
        handle.write(data)
    print("screenshot: {} bytes={}".format(out_path, len(data)))
    return 0


def check(port):
    try:
        request_expect(
            port, "GET", "/contentBlockerReady", "true", timeout=15
        )
        # Compiled rules do not imply a window exists, and every other endpoint
        # resolves its target through the selected tab, so a nil tab fails both
        # /navigate and /clearWebsiteData. /getWindowHandle asks exactly that
        # question: it answers HTTP 400 until the first tab is selected.
        handle = request(port, "GET", "/getWindowHandle", timeout=15)
        if not isinstance(handle, str) or not handle:
            raise RuntimeError("/getWindowHandle returned no tab handle")
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
  ddg-automation.py <port> screenshot <out_path>

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
    if command == "screenshot" and len(argv) >= 4:
        return screenshot(port, argv[3])
    if command == "measure" and len(argv) >= 4:
        settle_ms = float(argv[4]) if len(argv) >= 5 else 600
        load_window = float(argv[5]) if len(argv) >= 6 else 12
        return measure(port, argv[3], settle_ms, load_window)
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
