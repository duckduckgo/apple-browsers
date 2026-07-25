#!/usr/bin/env python3
"""Report the HTTP status of the main-document request from a Chromium NetLog.

Diagnostic companion to debug-netlog.config.hjson. Answers the one question the
in-page JS APIs cannot: did this navigation actually succeed, or is the harness
timing a bot-block page?

NetLog structure we rely on:
  - Events carry a "source" ({"id": N, "type": T}); all events for one URL
    request share a source id.
  - Some event for that source has params.url — the request's URL.
  - The response headers arrive as params.headers, a list whose first entry is
    the raw status line ("HTTP/1.1 403 Forbidden").
That is enough to map source id -> (url, status) without decoding NetLog's event
type constants, which are Chromium-version specific.

NetLog writes incrementally and only closes its JSON array on a clean browser
shutdown, so a truncated file is normal and expected; load_netlog repairs it
rather than failing.

Usage:
  ./debug-parse-netlog.py --netlog path/to/netlog.json [--host reddit.com]
"""

import argparse
import json
import pathlib
import re
import sys
from urllib.parse import urlsplit

STATUS_LINE = re.compile(r"^HTTP/[0-9.]+\s+(\d{3})")


def load_netlog(path: pathlib.Path) -> dict:
    """Parse a NetLog dump, repairing the truncation left by a hard shutdown."""
    text = path.read_text(errors="replace")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    # Drop whatever partial object trails the last complete event, then close
    # the "events" array and the top-level object.
    cut = text.rfind("},")
    if cut == -1:
        raise SystemExit(f"{path}: no complete events found")
    for suffix in ("}]}", "}]}}"):
        try:
            return json.loads(text[: cut + 1] + suffix)
        except json.JSONDecodeError:
            continue
    raise SystemExit(f"{path}: could not repair truncated JSON")


def collect(events: list) -> dict:
    """source id -> {"urls": [...], "statuses": [...]} in event order."""
    by_source: dict = {}
    for event in events:
        if not isinstance(event, dict):
            continue
        source = event.get("source") or {}
        sid = source.get("id")
        if sid is None:
            continue
        params = event.get("params") or {}
        if not isinstance(params, dict):
            continue
        entry = by_source.setdefault(sid, {"urls": [], "statuses": []})
        url = params.get("url")
        if isinstance(url, str) and url not in entry["urls"]:
            entry["urls"].append(url)
        headers = params.get("headers")
        # Chromium emits headers as a list of raw lines, or occasionally as a
        # dict; only the list form carries the status line.
        if isinstance(headers, list) and headers:
            first = headers[0]
            if isinstance(first, str):
                m = STATUS_LINE.match(first.strip())
                if m:
                    entry["statuses"].append(int(m.group(1)))
    return by_source


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--netlog", required=True, type=pathlib.Path)
    ap.add_argument("--host", default="",
                    help="Only report requests whose host contains this string")
    ap.add_argument("--label", default="", help="Prefix for the summary line")
    args = ap.parse_args()

    data = load_netlog(args.netlog)
    events = data.get("events") or []
    by_source = collect(events)

    # A "document" candidate is any request to the target host that produced a
    # status. The main document is the earliest such request; sub-resources and
    # third parties follow it.
    rows = []
    for sid, entry in by_source.items():
        if not entry["statuses"] or not entry["urls"]:
            continue
        url = entry["urls"][0]
        host = urlsplit(url).netloc
        if args.host and args.host not in host:
            continue
        rows.append((sid, url, entry["statuses"]))
    rows.sort(key=lambda r: r[0])

    label = args.label or args.host or "netlog"
    if not rows:
        print(f"{label}: NO STATUS FOUND for host filter {args.host!r} "
              f"({len(events)} events, {len(by_source)} sources)")
        return 0

    statuses = [s for _, _, ss in rows for s in ss]
    worst = max(statuses)
    first_url, first_statuses = rows[0][1], rows[0][2]
    verdict = "BLOCKED/ERROR" if worst >= 400 else "OK"
    print(f"{label}: {verdict} — first={first_statuses} "
          f"all={sorted(set(statuses))} requests={len(rows)}")
    print(f"  first URL: {first_url}")
    for _, url, ss in rows[:8]:
        print(f"    {ss} {url[:120]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
