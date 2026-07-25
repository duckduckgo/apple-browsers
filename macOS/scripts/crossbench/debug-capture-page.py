#!/usr/bin/env python3
"""Load ONE page in Chrome on the runner and capture what it actually sees.

Diagnostic-only companion to test-chrome.sh. Several sites in the navToLCP list
yield no LCP on a GitHub-hosted runner (reddit.com, yelp.com, tripadvisor.com,
indeed.com produce no PageLoadMetrics slice at all; weather.com/yahoo.com produce
an unfinalized -1). The benchmark can't distinguish "the site is slow", "the LCP
window was too short" and "the runner is being served a bot-block page", because
it only ever looks at the trace metric.

This script answers that by recording the page itself:
  - screenshot.png              — what the viewport actually shows
  - page-info.json              — final URL, title, HTTP status, source excerpt,
                                  and the LCP the standard JS API reports

The JS LCP read is deliberately the same PerformanceObserver the Safari harness
uses, so a page can be checked for "does it have ANY largest-contentful-paint
entry" independently of the Perfetto/trace_processor path Chrome normally uses.

Run under crossbench's poetry env so selenium is importable, e.g.
  cd ~/Developer/crossbench-upstream && poetry run python <path>/debug-capture-page.py \
      --site reddit.com --out-dir /tmp/capture
"""

import argparse
import json
import pathlib
import time

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service

CHROME_BIN = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Same flags test-chrome.sh runs the benchmark with, so the page is served the
# same browser fingerprint. Tracing/profiling flags are omitted: this captures
# the page, it does not measure it.
CHROME_FLAGS = (
    "--no-default-browser-check",
    "--disable-component-update",
    "--disable-sync",
    "--no-first-run",
    "--disable-search-engine-choice-screen",
    "--disable-crashpad-metrics",
    "--disable-background-timer-throttling",
    "--disable-renderer-backgrounding",
    "--disable-field-trial-config",
    "--window-size=1500,1000",
    "--disable-extensions",
)

# Drains buffered largest-contentful-paint entries. buffered:true backfills
# entries that fired before the observer existed; takeRecords() drains them
# synchronously, so this works as a one-shot read with no await.
LCP_JS = """
const times = [];
const record = (e) => times.push(e.startTime || e.renderTime || e.loadTime || 0);
const obs = new PerformanceObserver((list) => list.getEntries().forEach(record));
obs.observe({ type: "largest-contentful-paint", buffered: true });
obs.takeRecords().forEach(record);
obs.disconnect();
const nav = performance.getEntriesByType("navigation")[0] || {};
return {
  lcp_count: times.length,
  lcp_ms: times.length ? Math.max(...times) : -1,
  response_status: nav.responseStatus === undefined ? null : nav.responseStatus,
  dom_content_loaded_ms: nav.domContentLoadedEventEnd || null,
  transfer_size: nav.transferSize === undefined ? null : nav.transferSize,
};
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", required=True, help="Domain or URL, e.g. reddit.com")
    ap.add_argument("--out-dir", required=True, help="Directory for screenshot + json")
    ap.add_argument("--wait", type=float, default=20.0,
                    help="Seconds to settle after navigation before capturing")
    ap.add_argument("--driver", default="", help="Optional chromedriver path")
    args = ap.parse_args()

    url = args.site if "://" in args.site else f"https://{args.site}"
    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    options = Options()
    options.binary_location = CHROME_BIN
    for flag in CHROME_FLAGS:
        options.add_argument(flag)

    # Explicit driver path when given, otherwise let Selenium Manager resolve a
    # chromedriver matching the installed Chrome.
    driver = (webdriver.Chrome(service=Service(args.driver), options=options)
              if args.driver else webdriver.Chrome(options=options))

    info: dict = {"requested_url": url, "wait_seconds": args.wait}
    try:
        driver.set_page_load_timeout(60)
        try:
            driver.get(url)
        except Exception as exc:  # navigation timeout is itself a finding
            info["navigation_error"] = f"{type(exc).__name__}: {exc}"

        # Settle: LCP can keep updating well after load on ad-heavy pages.
        time.sleep(args.wait)

        info["final_url"] = driver.current_url
        info["title"] = driver.title
        try:
            info["metrics"] = driver.execute_script(LCP_JS)
        except Exception as exc:
            info["metrics_error"] = f"{type(exc).__name__}: {exc}"

        source = driver.page_source or ""
        info["source_length"] = len(source)
        info["source_head"] = source[:3000]

        driver.save_screenshot(str(out_dir / "screenshot.png"))
    finally:
        driver.quit()

    (out_dir / "page-info.json").write_text(json.dumps(info, indent=2))

    # Console summary — the artifact has the detail, this makes the log readable.
    metrics = info.get("metrics") or {}
    print(f"requested : {info['requested_url']}")
    print(f"final URL : {info.get('final_url')}")
    print(f"title     : {info.get('title')!r}")
    print(f"HTTP      : {metrics.get('response_status')}")
    print(f"source    : {info['source_length']} bytes")
    print(f"LCP (JS)  : {metrics.get('lcp_ms')} ms from {metrics.get('lcp_count')} entry(ies)")
    if "navigation_error" in info:
        print(f"NAV ERROR : {info['navigation_error']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
