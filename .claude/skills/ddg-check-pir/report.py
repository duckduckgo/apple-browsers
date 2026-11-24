#!/usr/bin/env python3
"""Writes an HTML report for a batch of ddg-check-pir attempts.

Usage: report.py BATCH [--baseline BASELINE_BATCH]

BATCH is the batch folder whose evidence/ holds one folder per attempt. The report goes to BATCH/report.html and links
snapshots in place, so keep it next to its evidence: snapshots and records show real people's data. The baseline is
remembered in BATCH, so pir.py can refresh the report after each scenario attempt with the same comparison.
"""

import argparse
import collections
import html
import json
import os
import re
import time
from pathlib import Path


def load(path, default=None):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def findings(text):
    """Bullets under the review's "Findings" heading: problems outside what the scenario checks."""
    match = re.search(r"^#+\s*Findings\s*$(.*?)(?=^#+\s|\Z)", text, re.MULTILINE | re.DOTALL)
    return [line.strip()[2:].strip() for line in match.group(1).splitlines() if line.strip().startswith(("- ", "* "))] if match else []


def review(folder):
    try:
        text = (folder / "review.md").read_text()
    except OSError:
        return "not reviewed", ""
    first = next((line.strip().lower() for line in text.splitlines() if line.strip()), "")
    return (first if first in ("confirmed", "disputed", "broker blocked") else "unclear"), text


def summary(folder, result):
    if result.get("command") == "scheduler":
        jobs = (result.get("scheduler") or {}).get("jobs") or []
        counts = collections.Counter(job.get("terminal") or job.get("status") or "missing" for job in jobs)
        return f"{len(jobs)} jobs: " + ", ".join(f"{count} {name}" for name, count in sorted(counts.items()))
    if result.get("command") == "selftest":
        return result.get("reason") or "debug server ready"
    final = load(folder / "pir-final-run.json", {}) or {}
    events = [event.get("summary", "") for event in final.get("events") or [] if event.get("kind") == "History"]
    parts = [f"{len(final.get('results') or [])} match(es)"] if final else []
    for marker in ("Opt-out Confirmed", "Opt-out skipped", "Opt-out Awaiting Email", "Opt-out Started"):
        if any(event.startswith(marker) for event in events):
            parts.append(next(event for event in events if event.startswith(marker)))
            break
    if result.get("brokerError"):
        parts.append(f"broker error: {result['brokerError']}")
    elif result.get("status") != "pass" and result.get("reason"):
        parts.append(result["reason"])
    return "; ".join(parts) or result.get("reason", "")


def attempt(folder):
    result = load(folder / "result.json")
    if not isinstance(result, dict) or result.get("command") == "build":
        return None
    status, text = review(folder)
    started, finished = result.get("startedAt"), result.get("finishedAt")
    broker = (load(folder / "pir-broker.json", {}) or {}).get("url", "") if result.get("command") == "run" else ""
    return dict(folder=folder, result=result, scenario=result.get("scenario") or "", step=result.get("step") or "",
                broker=broker, platform=result.get("platform", ""),
                command=result.get("command", ""), status=result.get("status", ""), expected=result.get("expected", "pass"),
                review=status, verification=text, findings=findings(text),
                summary=summary(folder, result), started=started,
                duration=(finished - started) if started and finished else None)


def key(a):
    """A scenario run is one scenario on one broker and platform; scenario titles repeat across brokers."""
    return (a["scenario"], a["broker"], a["platform"])


def attempts(batch):
    found = [a for a in (attempt(folder) for folder in sorted((batch / "evidence").glob("*")) if folder.is_dir()) if a]
    latest = {}
    for a in found:
        # A step attempt runs only part of a scenario, so it never stands in for the scenario's own run.
        if a["scenario"] and not a["step"] and (key(a) not in latest or (a["started"] or 0) > (latest[key(a)]["started"] or 0)):
            latest[key(a)] = a
    for a in found:
        a["retried"] = bool(a["scenario"]) and not a["step"] and latest[key(a)] is not a
    return sorted(found, key=lambda a: (a["platform"], a["scenario"] == "", a["scenario"], a["broker"], a["started"] or 0))


def duration(seconds):
    if seconds is None:
        return ""
    minutes, seconds = divmod(round(seconds), 60)
    return f"{minutes} m {seconds} s" if minutes else f"{seconds} s"


def snapshots(folder):
    files = sorted((folder / "snapshots").glob("*.png"))
    last = {}
    for file in files:
        match = re.match(r"\d+-([A-Za-z]+)-[A-Za-z]+-(before|result|error)\.png$", file.name)
        if match and match.group(2) == "result":
            last[match.group(1)] = file
    errors = [file for file in files if file.name.endswith("-error.png")]
    return sorted(set(last.values()) | set(errors))


def inline(text):
    def prose(part):
        part = html.escape(part)
        part = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", part)
        return re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)",
                      lambda m: f"<a href='{m[2]}'>{m[1]}</a>" if re.match(r"https?:|[^:]*$", m[2]) else m[0], part)

    out, last = [], 0
    for span in re.finditer(r"(`+)(.+?)\1(?!`)", text):
        out.append(prose(text[last:span.start()]))
        out.append(f"<code>{html.escape(span.group(2).strip())}</code>")
        last = span.end()
    out.append(prose(text[last:]))
    return "".join(out)


def markdown(text):
    """Renders the Markdown subset the reviewer writes: headings, paragraphs, nested lists, tables and code."""
    out, paragraph, lists, lines = [], [], [], text.splitlines()

    def close_paragraph():
        if paragraph:
            out.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def close_lists(indent=-1):
        while lists and lists[-1][0] > indent:
            out.append(f"</li></{lists.pop()[1]}>")

    index = 0
    while index < len(lines):
        line = lines[index]
        item = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", line)
        if line.strip().startswith("```"):
            close_paragraph(); close_lists()
            block = []
            index += 1
            while index < len(lines) and not lines[index].strip().startswith("```"):
                block.append(lines[index]); index += 1
            out.append(f"<pre><code>{html.escape(chr(10).join(block))}</code></pre>")
        elif not line.strip():
            close_paragraph()
            if not (index + 1 < len(lines) and re.match(r"^\s+\S", lines[index + 1]) and lists):
                close_lists()
        elif heading := re.match(r"^(#{1,6})\s+(.*)$", line):
            close_paragraph(); close_lists()
            level = min(6, len(heading.group(1)) + 4)
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
        elif line.lstrip().startswith("|") and index + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[index + 1]):
            close_paragraph(); close_lists()
            cells = lambda row: [cell.strip() for cell in row.strip().strip("|").split("|")]
            rows = [cells(line)]
            index += 2
            while index < len(lines) and lines[index].lstrip().startswith("|"):
                rows.append(cells(lines[index])); index += 1
            out.append("<table><tr>" + "".join(f"<th>{inline(c)}</th>" for c in rows[0]) + "</tr>" +
                       "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>" for row in rows[1:]) + "</table>")
            continue
        elif item:
            close_paragraph()
            indent, tag = len(item.group(1)), "ol" if item.group(2)[0].isdigit() else "ul"
            close_lists(indent)
            if lists and lists[-1][0] == indent and lists[-1][1] == tag:
                out.append("</li><li>")
            else:
                if lists and lists[-1][0] == indent:
                    close_lists(indent - 1)
                out.append(f"<{tag}><li>")
                lists.append((indent, tag))
            out.append(inline(item.group(3)))
        elif lists and line.startswith(" "):
            out.append(" " + inline(line.strip()))
        else:
            close_lists()
            paragraph.append(line.strip())
        index += 1
    close_paragraph(); close_lists()
    return "".join(out)


def details(a, report_dir):
    e, result, folder = html.escape, a["result"], a["folder"]
    out = []
    if result.get("reason"):
        out.append(f"<p>{e(result['reason'])}</p>")
    if result.get("checks"):
        out.append("<h4>Checks</h4><ul>" + "".join(
            f"<li class={'pass' if c.get('passed') else 'fail'}>{'PASS' if c.get('passed') else 'FAIL'}: {e(c.get('check', ''))}</li>"
            for c in result["checks"]) + "</ul>")
    if result.get("unverified"):
        out.append("<h4>Unverified</h4><ul>" + "".join(
            f"<li>{e(u.get('what', ''))}: {e(u.get('reason', ''))}</li>" for u in result["unverified"]) + "</ul>")
    final = load(folder / "pir-final-run.json", {}) or {}
    history = [ev for ev in final.get("events") or [] if ev.get("kind") == "History"]
    if history:
        out.append("<h4>History</h4><ul>" + "".join(
            f"<li><code>{e(ev.get('timestamp', ''))}</code> {e(ev.get('summary', ''))}</li>" for ev in history) + "</ul>")
    jobs = (result.get("scheduler") or {}).get("jobs") or []
    if jobs:
        out.append("<h4>Jobs</h4><table><tr><th>Broker</th><th>Query</th><th>Terminal</th><th>Started</th><th>Finished</th></tr>" +
                   "".join(f"<tr><td>{e(str(j.get('brokerURL', '')))}</td><td>{e(str(j.get('profileQueryId', '')))}</td>"
                           f"<td>{e(str(j.get('terminal') or j.get('reason') or ''))}</td><td>{e(str(j.get('startedAt', '')))}</td>"
                           f"<td>{e(str(j.get('finishedAt', '')))}</td></tr>" for j in jobs) + "</table>")
    images = snapshots(folder)
    if images:
        out.append("<h4>Snapshots</h4><div class=shots>" + "".join(
            f"<a href='{e(os.path.relpath(p, report_dir))}'><img loading=lazy src='{e(os.path.relpath(p, report_dir))}' "
            f"alt='{e(p.name)}'><span>{e(p.name)}</span></a>" for p in images) + "</div>")
    if a["verification"]:
        out.append(f"<h4>Review</h4><div class=review>{markdown(a['verification'])}</div>")
    link = os.path.relpath(folder, report_dir)
    out.append(f"<p><a href='{e(link)}/report.md'>report.md</a> · <a href='{e(link)}'>evidence folder</a></p>")
    return "".join(out)


def compare(a, baseline):
    if not a["scenario"]:
        return "", ""
    previous = baseline.get(key(a))
    if previous is None:
        return "no baseline", "new"
    changed = [label for label, field in (("verdict", "status"), ("review", "review"), ("result", "summary"))
               if a[field] != previous[field]]
    text = f"{previous['status']} / {previous['review']}: {previous['summary']}"
    return text, ("changed: " + ", ".join(changed)) if changed else "same"


PLATFORM_NAMES = {"ios": "iOS", "macos": "macOS"}
ICONS = {
    "ok": "<circle cx='8' cy='8' r='8'/><path d='M4.5 8.3l2.3 2.3 4.7-4.9' fill='none' stroke='#fff' stroke-width='1.9' stroke-linecap='round' stroke-linejoin='round'/>",
    "fail": "<circle cx='8' cy='8' r='8'/><path d='M5.3 5.3l5.4 5.4M10.7 5.3l-5.4 5.4' stroke='#fff' stroke-width='1.9' stroke-linecap='round'/>",
    "warn": "<path d='M8 1.2l7.2 13.3H.8z'/><path d='M8 6v4' stroke='#fff' stroke-width='1.8' stroke-linecap='round'/><circle cx='8' cy='12.3' r='1' fill='#fff'/>",
    "none": "<path d='M4.5 8h7' stroke='currentColor' stroke-width='1.6' stroke-linecap='round'/>",
}


def scenario_parts(scenario):
    """Scenarios are named "<scenario file>: <title>"; older attempts may carry the title alone."""
    file, separator, title = scenario.partition(": ")
    return (file, title) if separator else ("Other scenarios", scenario)


def icon(state, label=""):
    return (f"<svg class='icon {state}' viewBox='0 0 16 16' role='img' aria-label='{html.escape(label or state)}'>"
            f"<title>{html.escape(label or state)}</title>{ICONS[state]}</svg>")


def render(batch, rows, baseline=None):
    """Shows scenario runs only; selftests and other attempts without a scenario are setup, not results."""
    e, report_dir = html.escape, batch
    rows = [r for r in rows if r["scenario"]]
    by_baseline = {}
    for row in baseline or []:
        if row["scenario"] and not row["retried"] and not row["step"]:
            by_baseline[key(row)] = row
    fingerprints = sorted({(r["result"].get("launch") or {}).get("sourceSHA256", "")[:12] for r in rows} - {""})
    starts = [r["started"] for r in rows if r["started"]]
    panels, attention, pending, blocked = [], [], [], []
    for number, r in enumerate(rows, 1):
        r["number"] = number
        before, change = compare(r, by_baseline) if baseline is not None and not r["retried"] else ("", "")
        r["change"], r["known"] = change, False
        previous = by_baseline.get(key(r)) if baseline is not None else None
        known = previous is not None and previous["review"] == r["review"] == "disputed"
        r["known"] = known
        as_expected = r["status"] == r["expected"]
        worse = previous is not None and ((previous["status"] == previous["expected"] and not as_expected) or
                                          (previous["review"] == "confirmed" and r["review"] in ("disputed", "unclear")))
        # A changed result alone is drift for the comparison to explain, not a problem.
        reasons = ([f"expected {r['expected']}, got {r['status']}"] if not as_expected else []) + \
                  ([r["review"]] if r["review"] in ("disputed", "unclear") and not known else []) + \
                  (["worse than the baseline"] if worse else [])
        counted = bool(r["scenario"]) and not r["retried"] and not r["step"]
        if counted and reasons:
            attention.append(r)
        if counted and r["review"] == "not reviewed":
            pending.append(r)
        if counted and r["review"] == "broker blocked":
            blocked.append(r)
        r["reasons"] = reasons
        r["state"] = "fail" if reasons else ("warn" if r["review"] != "confirmed" or known else "ok")
        file, title = scenario_parts(r["scenario"]) if r["scenario"] else ("", f"({r['command']})")
        r["file"], r["title"] = file, title
        verdict = (f"expected {r['expected']}, got {r['status']}" if r["expected"] != "pass" or not as_expected else r["status"])
        r["line"] = (f"step: {r['step']} · " if r["step"] else "") + f"{verdict} · {r['review']}" + \
            (f" · {len(r['findings'])} finding(s)" if r["findings"] else "")
        found = ("<h4>Findings</h4><ul>" + "".join(f"<li>{inline(f)}</li>" for f in r["findings"]) + "</ul>") if r["findings"] else ""
        why = (f"<p class='why status'>{icon(r['state'])}<span>{e('; '.join(reasons))}</span></p>" if reasons else
               f"<p class='why status'>{icon(r['state'])}<span>{'dispute already in the baseline' if known else e(r['line'])}</span></p>")
        compared = (f"<p><b>Baseline:</b> {e(before)} <b>{e(change)}</b></p>" if baseline is not None and counted else "")
        retried = "<p class=muted>A later attempt of this scenario replaces this one.</p>" if r["retried"] else ""
        broker = f" · {e(r['broker'])}" if r["broker"] and r["broker"] != file else ""
        panels.append(f"<section class=attempt id=a{number}><h2>#{number} {e(title)}{broker} "
                      f"<span class=muted>{e(PLATFORM_NAMES.get(r['platform'], r['platform']))}</span></h2>"
                      f"<p class=muted>{e(file)} · {e(r['line'])} · {e(duration(r['duration']))} · {e(r['folder'].name)}</p>"
                      f"{why}{retried}<p>{e(r['summary'])}</p>{compared}{found}{details(r, report_dir)}</section>")

    scenario_runs = [r for r in rows if r["scenario"] and not r["retried"]]
    platforms = sorted({r["platform"] for r in scenario_runs}) or sorted({r["platform"] for r in rows})
    sections = collections.OrderedDict()
    for r in sorted(scenario_runs, key=lambda r: (r["file"] == "Other scenarios", r["file"], r["started"] or 0)):
        sections.setdefault(r["file"], collections.OrderedDict()).setdefault((r["title"], r["broker"]), {})[r["platform"]] = r
    retries = collections.defaultdict(list)
    for r in rows:
        if r["retried"]:
            retries[key(r)].append(r)
    worst = lambda states: "fail" if "fail" in states else ("warn" if "warn" in states else "ok")

    def cell(r):
        if r is None:
            return f"<td class='cell empty'>{icon('none', 'not run')}</td>"
        earlier = retries.get(key(r), [])
        tries = (" <span class=muted>(" + ", ".join(f"<a href='#a{x['number']}' data-go={x['number']}>retry #{x['number']}</a>"
                                                   for x in earlier) + ")</span>") if earlier else ""
        return (f"<td class='cell {r['state']}' data-n={r['number']}><div class=status>{icon(r['state'], r['line'])}"
                f"<div><b>#{r['number']}</b> {e(r['line'])}{tries}<div class=muted>{e(r['summary'])}</div></div></div></td>")

    matrix = []
    for file, scenarios in sections.items():
        states = [r["state"] for platforms_runs in scenarios.values() for r in platforms_runs.values()]
        matrix.append(f"<tr class=group><th colspan={len(platforms) + 1}><span class=status>{icon(worst(states))}{e(file)}</span></th></tr>")
        for (title, broker), runs in scenarios.items():
            label = e(title) + (f" <span class=muted>· {e(broker)}</span>" if broker and broker != file else "")
            matrix.append(f"<tr><td class=title>{label}</td>" + "".join(cell(runs.get(p)) for p in platforms) + "</tr>")
    head = "<tr><th>Scenario</th>" + "".join(f"<th>{e(PLATFORM_NAMES.get(p, p))}</th>" for p in platforms) + "</tr>"

    link = lambda r: (f"<a href='#a{r['number']}' data-go={r['number']}>#{r['number']} {e(r['title'])}"
                      f"{' · ' + e(r['broker']) if r['broker'] and r['broker'] != r['file'] else ''} "
                      f"({e(PLATFORM_NAMES.get(r['platform'], r['platform']))})</a>")
    tally = " · ".join(f"{e(PLATFORM_NAMES.get(p, p))} " + " ".join(
        f"<span class=count>{icon(state)}{sum(r['platform'] == p and r['state'] == state for r in scenario_runs)}</span>"
        for state in ("ok", "warn", "fail")) for p in platforms)
    pending_note = ("<p class=pending>Review pending: " + ", ".join(link(r) for r in pending) + "</p>") if pending else ""
    blocked_note = ("<p class=pending>Blocked by the broker, so not exercised; rerun or use another broker: " +
                    ", ".join(link(r) for r in blocked) + "</p>") if blocked else ""
    with_findings = [r for r in scenario_runs if r["findings"]]
    finding_count = sum(len(r["findings"]) for r in with_findings)
    findings_note = ("<details class=findings><summary><span class=status>" + icon("warn") +
                     f"<b>Findings outside the scenarios: {finding_count}</b></span></summary><ul>" +
                     "".join(f"<li>{link(r)}: {inline(f)}</li>" for r in with_findings for f in r["findings"]) + "</ul></details>") if with_findings else ""
    if not scenario_runs:
        banner = f"<div class='banner warn'><div class=status>{icon('warn')}<b>No scenario runs in this batch.</b></div></div>"
    elif attention:
        banner = (f"<details class='banner attn' open><summary><span class=status>{icon('fail')}<b>Needs attention: {len(attention)} of "
                  f"{len(scenario_runs)} scenario runs.</b></span></summary><ul>" +
                  "".join(f"<li>{link(r)}: {e(', '.join(r['reasons']))}</li>" for r in attention) +
                  f"</ul>{pending_note}{blocked_note}</details>{findings_note}")
    elif pending:
        banner = (f"<details class='banner warn' open><summary><span class=status>{icon('warn')}<b>No problems found, but {len(pending)} of "
                  f"{len(scenario_runs)} scenario runs still need a review.</b></span></summary>{pending_note}{blocked_note}</details>{findings_note}")
    elif blocked:
        banner = (f"<details class='banner warn' open><summary><span class=status>{icon('warn')}<b>No problems found, but {len(blocked)} of "
                  f"{len(scenario_runs)} scenario runs were blocked by the broker.</b></span></summary>{blocked_note}</details>{findings_note}")
    elif any(r["known"] for r in scenario_runs):
        known_runs = [r for r in scenario_runs if r["known"]]
        banner = (f"<details class='banner warn' open><summary><span class=status>{icon('warn')}<b>No new problems, but {len(known_runs)} of "
                  f"{len(scenario_runs)} scenario runs keep a dispute from the baseline.</b></span></summary><ul>" +
                  "".join(f"<li>{link(r)}</li>" for r in known_runs) + f"</ul></details>{findings_note}")
    else:
        drifted = sum(r["change"] != "same" for r in scenario_runs)
        against = ("" if baseline is None else " with no change from the baseline" if not drifted else
                   f"; {drifted} are new or changed since the baseline")
        banner = (f"<div class='banner ok'><div class=status>{icon('ok')}<b>All {len(scenario_runs)} scenario runs got their expected verdict and were confirmed"
                  f"{against}.</b></div></div>{findings_note}")
    first = attention[0]["number"] if attention else (scenario_runs[0]["number"] if scenario_runs else 1)
    when = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(min(starts))) if starts else ""
    return f"""<!doctype html>
<html lang=en><head><meta charset=utf-8><meta name=viewport content="width=device-width, initial-scale=1">
<meta name=color-scheme content="light dark">
<title>PIR batch {e(batch.name)}</title>
<style>
:root {{ color-scheme:light dark; --bg:#fff; --fg:#1d1d1f; --muted:#6e6e73; --line:#d2d2d7; --flag:#fff4e5; --sel:#e8f0fe; --pass:#1a7f37; --fail:#c62828; --warn:#b26a00; --link:#0b57d0; --code:#f2f2f7; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#1c1c1e; --fg:#f2f2f7; --muted:#a1a1a6; --line:#3a3a3c; --flag:#3a2a10; --sel:#1f3a5f; --pass:#4caf50; --fail:#ef5350; --warn:#ffb74d; --link:#8ab4f8; --code:#2c2c2e; }} }}
* {{ box-sizing:border-box; }} a {{ color:var(--link); }}
code {{ font:12px/1.4 ui-monospace, SFMono-Regular, Menlo, monospace; background:var(--code); padding:1px 5px; border-radius:4px;
       border:1px solid var(--line); overflow-wrap:anywhere; }}
pre {{ background:var(--code); border:1px solid var(--line); border-radius:6px; padding:10px 12px; overflow:auto; }}
pre code {{ background:none; border:0; padding:0; white-space:pre; overflow-wrap:normal; }}
body {{ background:var(--bg); color:var(--fg); font:14px/1.45 -apple-system, system-ui, sans-serif; margin:0; display:flex; flex-direction:column; height:100vh; }}
header {{ padding:12px 16px; border-bottom:1px solid var(--line); }} header h1 {{ font-size:18px; margin:0 0 4px; }}
.muted, header p {{ color:var(--muted); }} header p {{ margin:2px 0; font-size:13px; }}
main {{ display:grid; grid-template-columns:minmax(460px, 52%) 1fr; flex:1; min-height:0; }}
#list {{ overflow:auto; border-right:1px solid var(--line); }} #detail {{ overflow:auto; padding:0 20px 40px; }}
table {{ border-collapse:collapse; width:100%; }} th, td {{ border-bottom:1px solid var(--line); padding:6px 8px; text-align:left; vertical-align:top; }}
table.matrix {{ table-layout:fixed; }} table.matrix td {{ overflow-wrap:anywhere; }} table.matrix td.title {{ width:34%; font-weight:500; }}
td.cell[data-n] {{ cursor:pointer; font-size:13px; }} td.cell.fail {{ background:var(--flag); }} td.cell.active {{ background:var(--sel); outline:2px solid var(--fg); outline-offset:-2px; }}
tr.group th {{ position:sticky; top:0; background:var(--bg); font-size:15px; padding-top:14px; z-index:1; }}
.icon {{ width:16px; height:16px; flex:none; }}
.status {{ display:flex; align-items:flex-start; gap:8px; }} .status > .icon {{ margin-top:2px; }}
th .status {{ align-items:center; }} th .status > .icon {{ margin-top:0; }}
.count {{ display:inline-flex; align-items:center; gap:3px; margin-right:8px; vertical-align:middle; }}
.icon.ok {{ fill:var(--pass); }} .icon.fail {{ fill:var(--fail); }} .icon.warn {{ fill:var(--warn); }} .icon.none {{ color:var(--muted); }}
.banner {{ margin:10px 0 2px; padding:8px 12px; border-radius:8px; border:1px solid var(--line); }} .banner ul {{ margin:4px 0 0; padding-left:20px; }}
.pending {{ color:var(--muted); margin:6px 0 0; }} .banner.warn {{ border-color:var(--warn); }} .banner.ok {{ border-color:var(--pass); }}
.banner.attn {{ border-color:var(--fail); background:var(--flag); }}
details.banner > summary, details.findings > summary {{ cursor:pointer; list-style:none; }}
details.banner > summary::-webkit-details-marker, details.findings > summary::-webkit-details-marker {{ display:none; }}
details.banner > summary::after, details.findings > summary::after {{ content:"Show"; margin-left:auto; color:var(--link); font-size:12px; }}
details[open].banner > summary::after, details[open].findings > summary::after {{ content:"Hide"; }}
summary .status {{ align-items:center; }} summary .status > .icon {{ margin-top:0; }} details > summary {{ display:flex; align-items:center; }}
.findings {{ margin:8px 0 2px; padding:8px 12px; border-radius:8px; border:1px solid var(--warn); }} .findings ul {{ margin:4px 0 0; padding-left:44px; }} .banner ul {{ padding-left:44px; }} .why {{ font-weight:500; }}
.pass {{ color:var(--pass); }} .fail {{ color:var(--fail); }}
.shots {{ display:flex; flex-wrap:wrap; gap:12px; }} .shots a {{ width:320px; color:var(--muted); font-size:12px; }}
.shots img {{ width:100%; border:1px solid var(--line); }} .review {{ border-left:3px solid var(--line); padding-left:12px; }}
.js .attempt {{ display:none; }} .js .attempt.active {{ display:block; }}
@media (max-width: 800px) {{ body {{ display:block; height:auto; }} main {{ display:block; }} #list {{ max-height:50vh; }} }}
</style></head><body>
<header><h1>PIR batch {e(batch.name)}</h1>
<p>Started {e(when)} · {tally} · source {e(', '.join(fingerprints))}</p>
<p>Select a result or use the arrow keys. Snapshots and records show real people's data. Keep this report local.</p>
{banner}</header>
<main><div id=list><table class=matrix>{head}{''.join(matrix)}</table></div><div id=detail>{''.join(panels)}</div></main>
<script>
document.documentElement.classList.add("js");
const cells = [...document.querySelectorAll("#list [data-n]")];
function show(n) {{
  cells.forEach(c => c.classList.toggle("active", c.dataset.n == n));
  document.querySelectorAll(".attempt").forEach(p => p.classList.toggle("active", p.id == "a" + n));
  document.getElementById("detail").scrollTop = 0;
  const cell = cells.find(c => c.dataset.n == n); if (cell) cell.scrollIntoView({{block: "nearest"}});
  history.replaceState(null, "", "#a" + n);
}}
cells.forEach(c => c.addEventListener("click", event => {{ if (!event.target.closest("a")) show(c.dataset.n); }}));
document.querySelectorAll("[data-go]").forEach(a => a.addEventListener("click", event => {{ event.preventDefault(); show(a.dataset.go); }}));
document.addEventListener("keydown", event => {{
  const current = cells.findIndex(c => c.classList.contains("active"));
  const step = {{ArrowDown: 1, ArrowRight: 1, j: 1, ArrowUp: -1, ArrowLeft: -1, k: -1}}[event.key];
  if (!step) return;
  event.preventDefault();
  const next = cells[Math.min(cells.length - 1, Math.max(0, current + step))];
  if (next) show(next.dataset.n);
}});
const fromHash = location.hash.match(/^#a(\\d+)$/);
show(fromHash ? fromHash[1] : {first});
</script>
</body></html>
"""


BASELINE_FILE = ".report-baseline"


def write(batch, baseline_dir=None):
    out = batch / "report.html"
    page = render(batch, attempts(batch), attempts(baseline_dir) if baseline_dir else None)
    # Attempts can finish together, so a reader never sees a half-written page.
    temporary = out.with_name(f".report-{os.getpid()}.html")
    temporary.write_text(page)
    os.replace(temporary, out)
    return out


def refresh(batch):
    """Rewrites the report of a batch that ddg-check-pir just added an attempt to, keeping its saved baseline."""
    saved = (batch / BASELINE_FILE).read_text().strip() if (batch / BASELINE_FILE).is_file() else ""
    baseline_dir = Path(saved) if saved and (Path(saved) / "evidence").is_dir() else None
    return write(batch, baseline_dir)


def main(argv=None):
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    cli.add_argument("batch", type=Path)
    cli.add_argument("--baseline", type=Path, help="earlier batch folder to compare by scenario title and platform")
    args = cli.parse_args(argv)
    batch = args.batch.expanduser().resolve()
    if not (batch / "evidence").is_dir():
        cli.error(f"{batch} has no evidence folder")
    baseline_dir = None
    if args.baseline:
        baseline_dir = args.baseline.expanduser().resolve()
        if not (baseline_dir / "evidence").is_dir():
            cli.error(f"baseline {baseline_dir} has no evidence folder")
        if not any(r["scenario"] for r in attempts(baseline_dir)):
            cli.error(f"baseline {baseline_dir} has no scenario runs")
        (batch / BASELINE_FILE).write_text(f"{baseline_dir}\n")
    else:
        (batch / BASELINE_FILE).unlink(missing_ok=True)
    print(write(batch, baseline_dir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
