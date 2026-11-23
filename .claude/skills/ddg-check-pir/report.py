#!/usr/bin/env python3
"""Writes an HTML report for a batch of verify-pir attempts.

Usage: report.py BATCH [--baseline BASELINE_BATCH]

BATCH is the batch folder whose evidence/ holds one folder per attempt. The report goes to BATCH/report.html and links
snapshots in place, so keep it next to its evidence: snapshots and records show real people's data.
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


def review(folder):
    try:
        text = (folder / "verification.md").read_text()
    except OSError:
        return "not reviewed", ""
    first = next((line.strip().lower() for line in text.splitlines() if line.strip()), "")
    return (first if first in ("confirmed", "disputed") else "unclear"), text


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
    return dict(folder=folder, result=result, scenario=result.get("scenario") or "", platform=result.get("platform", ""),
                command=result.get("command", ""), status=result.get("status", ""), review=status, verification=text,
                summary=summary(folder, result), started=started,
                duration=(finished - started) if started and finished else None)


def attempts(batch):
    found = [attempt(folder) for folder in sorted((batch / "evidence").glob("*")) if folder.is_dir()]
    return sorted((a for a in found if a), key=lambda a: (a["platform"], a["scenario"] == "", a["scenario"], a["started"] or 0))


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
    parts = re.split(r"(`[^`]*`)", text)
    out = []
    for part in parts:
        if part.startswith("`") and part.endswith("`") and len(part) > 1:
            out.append(f"<code>{html.escape(part[1:-1])}</code>")
            continue
        part = html.escape(part)
        part = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", part)
        part = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r"<a href='\2'>\1</a>", part)
        out.append(part)
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
    previous = baseline.get((a["scenario"], a["platform"]))
    if previous is None:
        return "no baseline", "new"
    changed = [label for label, key in (("verdict", "status"), ("review", "review"), ("result", "summary"))
               if a[key] != previous[key]]
    text = f"{previous['status']} / {previous['review']}: {previous['summary']}"
    return text, ("changed: " + ", ".join(changed)) if changed else "same"


def render(batch, rows, baseline=None):
    e, report_dir = html.escape, batch
    by_baseline = {}
    for row in baseline or []:
        if row["scenario"]:
            by_baseline.setdefault((row["scenario"], row["platform"]), row)
    fingerprints = sorted({(r["result"].get("launch") or {}).get("sourceSHA256", "")[:12] for r in rows} - {""})
    starts = [r["started"] for r in rows if r["started"]]
    items, panels, selected, attention, pending = [], [], None, [], []
    PLATFORM_NAMES = {"ios": "iOS", "macos": "macOS"}
    current_platform = None
    for number, r in enumerate(rows, 1):
        if r["platform"] != current_platform:
            current_platform = r["platform"]
            items.append(f"<tr class=group id=group-{e(current_platform)}><th colspan=4>"
                         f"{e(PLATFORM_NAMES.get(current_platform, current_platform or 'Other'))}</th></tr>")
        before, change = compare(r, by_baseline) if baseline is not None else ("", "")
        reasons = ([r["status"]] if r["status"] != "pass" else []) + \
                  ([r["review"]] if r["review"] not in ("confirmed", "not reviewed") else []) + \
                  ([change] if change.startswith(("changed", "new")) else [])
        if r["scenario"] and reasons:
            attention.append((number, r, reasons))
        if r["scenario"] and r["review"] == "not reviewed":
            pending.append((number, r))
        flagged = r["review"] in ("disputed", "unclear") or change.startswith("changed") or r["status"] != "pass"
        if selected is None and flagged:
            selected = number
        title = r["scenario"] or f"({r['command']})"
        badges = (f"<span class='badge {e(r['status'])}'>{e(r['status'])}</span>"
                  f"<span class='badge {e(r['review'].replace(' ', '-'))}'>{e(r['review'])}</span>" +
                  (f"<span class='badge changed'>{e(change)}</span>" if change.startswith(("changed", "new")) else ""))
        items.append(f"<tr data-n={number} class='{'flag' if flagged else ''}'><td>{number}</td>"
                     f"<td><b>{e(title)}</b><br>{badges}</td>"
                     f"<td>{e(r['summary'])}</td><td class=muted>{e(duration(r['duration']))}</td></tr>")
        compared = (f"<p><b>Baseline:</b> {e(before)} <b>{e(change)}</b></p>" if baseline is not None and r["scenario"] else "")
        panels.append(f"<section class=attempt id=a{number}><h2>#{number} {e(title)} <span class=muted>{e(PLATFORM_NAMES.get(r['platform'], r['platform']))}</span></h2>"
                      f"<p>{badges} <span class=muted>{e(duration(r['duration']))} · {e(r['folder'].name)}</span></p>"
                      f"<p>{e(r['summary'])}</p>{compared}{details(r, report_dir)}</section>")
    when = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime(min(starts))) if starts else ""
    scenario_runs = [r for r in rows if r["scenario"]]
    extra = len(rows) - len(scenario_runs)
    extra_note = f" Also {extra} attempt(s) without a scenario, listed last." if extra else ""
    link = lambda n, r: f"<a href='#a{n}' data-go={n}>#{n} {e(r['scenario'])} ({e(PLATFORM_NAMES.get(r['platform'], r['platform']))})</a>"
    platform_counts = " · ".join(
        f"{e(PLATFORM_NAMES.get(p, p))}: {sum(r['platform'] == p for r in scenario_runs)} runs, "
        f"{sum(r['platform'] == p for _, r, _ in attention)} need attention"
        for p in sorted({r['platform'] for r in scenario_runs}))
    pending_note = ("<p class=pending>Review pending: " + ", ".join(link(n, r) for n, r in pending) + "</p>") if pending else ""
    if not scenario_runs:
        banner = f"<div class='banner warn'><b>No scenario runs in this batch.</b>{e(extra_note)}</div>"
    elif attention:
        by_platform = collections.defaultdict(list)
        for n, r, why in attention:
            by_platform[r["platform"]].append(f"<li>{link(n, r)}: {e(', '.join(why))}</li>")
        banner = (f"<div class='banner attn'><b>Needs attention: {len(attention)} of {len(scenario_runs)} scenario runs.</b>"
                  f"{e(extra_note)}" + "".join(
                      f"<p class=platform>{e(PLATFORM_NAMES.get(p, p))}</p><ul>{''.join(lines)}</ul>"
                      for p, lines in sorted(by_platform.items())) + f"{pending_note}</div>")
    elif pending:
        banner = (f"<div class='banner warn'><b>No problems found, but {len(pending)} of {len(scenario_runs)} scenario runs "
                  f"still need a review.</b>{e(extra_note)}{pending_note}</div>")
    else:
        banner = (f"<div class='banner ok'><b>All {len(scenario_runs)} scenario runs passed and their reviews confirmed them"
                  f"{' with no change from the baseline' if baseline is not None else ''}.</b>{e(extra_note)}</div>")
    return f"""<!doctype html>
<html lang=en><head><meta charset=utf-8><meta name=viewport content="width=device-width, initial-scale=1">
<meta name=color-scheme content="light dark">
<title>PIR batch {e(batch.name)}</title>
<style>
:root {{ color-scheme:light dark; --bg:#fff; --fg:#1d1d1f; --muted:#6e6e73; --line:#d2d2d7; --flag:#fff4e5; --sel:#e8f0fe; --pass:#1a7f37; --fail:#c62828; --warn:#b26a00; --link:#0b57d0; --code:#f2f2f7; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#1c1c1e; --fg:#f2f2f7; --muted:#a1a1a6; --line:#3a3a3c; --flag:#3a2a10; --sel:#1f3a5f; --pass:#4caf50; --fail:#ef5350; --warn:#ffb74d; --link:#8ab4f8; --code:#2c2c2e; }} }}
* {{ box-sizing:border-box; }} a {{ color:var(--link); }} code {{ background:var(--code); padding:0 3px; border-radius:3px; }}
body {{ background:var(--bg); color:var(--fg); font:14px/1.45 -apple-system, system-ui, sans-serif; margin:0; }}
header {{ padding:12px 16px; border-bottom:1px solid var(--line); }} header h1 {{ font-size:18px; margin:0 0 4px; }}
.muted, header p {{ color:var(--muted); }} header p {{ margin:2px 0; font-size:13px; }}
body {{ display:flex; flex-direction:column; height:100vh; }} main {{ display:grid; grid-template-columns:minmax(420px, 46%) 1fr; flex:1; min-height:0; }}
#list {{ overflow:auto; border-right:1px solid var(--line); }} #detail {{ overflow:auto; padding:0 20px 40px; }}
table {{ border-collapse:collapse; width:100%; }} th, td {{ border-bottom:1px solid var(--line); padding:6px 8px; text-align:left; vertical-align:top; }}
#list tr[data-n] {{ cursor:pointer; }} #list tr.flag {{ background:var(--flag); }} #list tr.active {{ background:var(--sel); outline:2px solid var(--fg); outline-offset:-2px; }}
table.attempts {{ table-layout:fixed; }} table.attempts td {{ overflow-wrap:anywhere; }}
.banner {{ margin:10px 0 2px; padding:8px 12px; border-radius:8px; border:1px solid var(--line); }} .banner ul {{ margin:4px 0 0; padding-left:20px; max-height:9.5em; overflow:auto; }}
.pending {{ color:var(--muted); margin:6px 0 0; }} .banner.warn {{ border-color:var(--warn); background:none; }} .banner.ok {{ border-color:var(--pass); }} .banner.ok b {{ color:var(--pass); }} .banner.attn {{ border-color:var(--fail); background:var(--flag); }} .banner.attn > b {{ color:var(--fail); }}
tr.group th {{ position:sticky; top:0; background:var(--bg); font-size:15px; padding-top:12px; z-index:1; }}
.banner p.platform {{ margin:6px 0 0; font-weight:600; }}
.badge {{ display:inline-block; white-space:nowrap; font-size:11px; padding:0 6px; margin:2px 4px 0 0; border-radius:8px; border:1px solid var(--line); }}
.badge.pass, .badge.confirmed {{ color:var(--pass); }} .badge.fail, .badge.disputed {{ color:var(--fail); }}
.badge.inconclusive, .badge.changed {{ color:var(--warn); }} .pass {{ color:var(--pass); }} .fail {{ color:var(--fail); }}
.shots {{ display:flex; flex-wrap:wrap; gap:12px; }} .shots a {{ width:320px; color:var(--muted); font-size:12px; }}
.shots img {{ width:100%; border:1px solid var(--line); }} .review {{ border-left:3px solid var(--line); padding-left:12px; }}
pre {{ white-space:pre-wrap; }} .js .attempt {{ display:none; }} .js .attempt.active {{ display:block; }}
@media (max-width: 800px) {{ body {{ display:block; height:auto; }} main {{ display:block; }} #list {{ max-height:45vh; }} }}
</style></head><body>
<header><h1>PIR batch {e(batch.name)}</h1>
<p>Started {e(when)} · {platform_counts} · source {e(', '.join(fingerprints))}</p>
<p>Select an attempt or use the arrow keys. Snapshots and records show real people's data. Keep this report local.</p>
{banner}</header>
<main><div id=list><table class=attempts><colgroup><col style='width:2.5em'><col style='width:48%'><col><col style='width:5.5em'></colgroup>{''.join(items)}</table></div><div id=detail>{''.join(panels)}</div></main>
<script>
document.documentElement.classList.add("js");
const rows = [...document.querySelectorAll("#list tr[data-n]")];
function show(n) {{
  rows.forEach(r => r.classList.toggle("active", r.dataset.n == n));
  document.querySelectorAll(".attempt").forEach(p => p.classList.toggle("active", p.id == "a" + n));
  document.getElementById("detail").scrollTop = 0;
  const row = rows.find(r => r.dataset.n == n); if (row) row.scrollIntoView({{block: "nearest"}});
  history.replaceState(null, "", "#a" + n);
}}
rows.forEach(r => r.addEventListener("click", () => show(r.dataset.n)));
document.querySelectorAll("[data-go]").forEach(a => a.addEventListener("click", event => {{ event.preventDefault(); show(a.dataset.go); }}));
document.addEventListener("keydown", event => {{
  const current = rows.findIndex(r => r.classList.contains("active"));
  const step = {{ArrowDown: 1, j: 1, ArrowUp: -1, k: -1}}[event.key];
  if (!step) return;
  event.preventDefault();
  const next = rows[Math.min(rows.length - 1, Math.max(0, current + step))];
  if (next) show(next.dataset.n);
}});
const fromHash = location.hash.match(/^#a(\\d+)$/);
show(fromHash ? fromHash[1] : {selected or 1});
</script>
</body></html>
"""


def main(argv=None):
    cli = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    cli.add_argument("batch", type=Path)
    cli.add_argument("--baseline", type=Path, help="earlier batch folder to compare by scenario title and platform")
    args = cli.parse_args(argv)
    batch = args.batch.expanduser().resolve()
    if not (batch / "evidence").is_dir():
        cli.error(f"{batch} has no evidence folder")
    baseline = attempts(args.baseline.expanduser().resolve()) if args.baseline else None
    out = batch / "report.html"
    out.write_text(render(batch, attempts(batch), baseline))
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
