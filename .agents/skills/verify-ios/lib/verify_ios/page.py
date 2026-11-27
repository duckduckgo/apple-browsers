"""`index.html`, the entry point of an attempt folder: one self-contained page a reviewer opens from the PR.

Claim and verdict first, then per device the video and key frames (Before | After for `prove --base`), the checks
with failures first, pixels and wide events, what stays unverified, and the build details with links to the proof
and the raw evidence. Every link is relative, so the page works wherever the whole folder is published; it loads
nothing from elsewhere and runs no script.
"""
import html, json, os, urllib.parse

from . import gallery

STYLE = """
:root { color-scheme: light dark; --bg: #fff; --fg: #1f2328; --muted: #59636e; --line: #d1d9e0; --card: #f6f8fa;
  --link: #0969da; --pass: #1a7f37; --fail: #cf222e; --warn: #9a6700; }
@media (prefers-color-scheme: dark) { :root { --bg: #0d1117; --fg: #e6edf3; --muted: #9198a1; --line: #3d444d;
  --card: #151b23; --link: #4493f8; --pass: #3fb950; --fail: #f85149; --warn: #d29922; } }
body { margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.5 -apple-system, system-ui, sans-serif; }
main { max-width: 1200px; margin: 0 auto; padding: 24px 16px 64px; }
a { color: var(--link); }
h1 { font-size: 24px; line-height: 1.3; margin: 0 0 8px; }
h2 { font-size: 18px; margin: 32px 0 12px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }
h3 { font-size: 16px; margin: 20px 0 8px; }
.muted { color: var(--muted); }
.badges { display: flex; flex-wrap: wrap; gap: 8px; margin: 12px 0; }
.badge { border-radius: 999px; padding: 2px 12px; font-weight: 600; font-size: 13px; border: 1px solid currentColor; }
.pass { color: var(--pass); } .fail { color: var(--fail); } .warn { color: var(--warn); }
.devices { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 16px; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 12px 16px; }
video, .media img { display: block; max-width: 100%; max-height: 480px; border-radius: 6px; background: #000; }
.media img { background: none; }
.strip { overflow-x: auto; } .strip img { max-width: none; max-height: 360px; }
.wide img { max-width: 100%; max-height: none; }
table { border-collapse: collapse; width: 100%; font-size: 14px; }
th, td { text-align: left; padding: 4px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
code { font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; word-break: break-all; }
details { margin: 8px 0; } summary { cursor: pointer; }
ul { padding-left: 20px; }
"""


def _e(text):
    return html.escape(str(text), quote=True)


def _url(*parts):
    return urllib.parse.quote("/".join(p for p in parts if p))


def _link(label, *parts):
    return f'<a href="{_url(*parts)}">{_e(label)}</a>'


def _tone(verdict):
    v = verdict.upper()
    return "pass" if v in ("PASS", "AS EXPECTED") else "fail" if v in ("FAIL", "UNEXPECTED") else "warn"


def _badge(label, verdict):
    return f'<span class="badge {_tone(verdict)}">{_e(label)}: {_e(verdict)}</span>'


def _page(title, claim, rest, badges, body):
    more = "".join(f"<p>{_e(p)}</p>" for p in rest.split("\n\n") if p.strip())
    return (f'<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width, initial-scale=1"><title>{_e(title)}</title>'
            f"<style>{STYLE}</style></head><body><main>\n<p class=\"muted\">{_e(title)}</p><h1>{_e(claim)}</h1>"
            f'<div class="badges">{"".join(badges)}</div>{more}\n{body}\n</main></body></html>\n')


def _doc(mod):
    doc = (getattr(mod, "__doc__", None) or "").strip()
    claim, _, rest = doc.partition("\n")
    return claim or "(the proof has no docstring)", rest.strip()


def _video(attempt, run, dev, video):
    """An inline player for one run's recording, its poster as the still; '' when there is none."""
    if not video or run is None:
        return ""
    poster = os.path.join(attempt, run, dev, gallery.POSTER)
    still = f' poster="{_url(run, dev, gallery.POSTER)}"' if os.path.isfile(poster) else ""
    src = _url(run, dev, video)
    return (f'<video controls preload="metadata" playsinline{still} src="{src}"></video>'
            f'<p><a href="{src}">▶ Watch video</a></p>')


def _image(attempt, rel, alt):
    if not os.path.isfile(os.path.join(attempt, rel)):
        return ""
    return f'<a href="{_url(rel)}"><img src="{_url(rel)}" alt="{_e(alt)}"></a>'


def _checks(rows, failed, head, cells):
    """A table of checks, failures first."""
    rows = sorted(rows, key=lambda r: not failed(r))
    body = "".join("<tr>" + "".join(f'<td class="{tone}">{_e(text)}</td>' for text, tone in cells(r)) + "</tr>"
                   for r in rows)
    return f"<table><tr>{''.join(f'<th>{_e(h)}</th>' for h in head)}</tr>{body}</table>" if rows else "<p>(none)</p>"


def _items(title, items, tone=""):
    if not items:
        return ""
    head = f'<p class="{tone}"><strong>{_e(title)}</strong></p>' if title else ""
    return head + "<ul>" + "".join(f"<li>{_e(i)}</li>" for i in items) + "</ul>"


def _telemetry(attempt, run, dev):
    """Pixels and wide events one device's run saw, collapsed, with links to the raw files."""
    out = []
    for name, label, row in (("pixels.json", "Pixels", lambda p: (p.get("name"), p.get("status"), p.get("time"))),
                             ("wide-events.json", "Wide events",
                              lambda w: ((w.get("feature") or {}).get("name"), (w.get("feature") or {}).get("status"),
                                         (w.get("meta") or {}).get("type")))):
        path = os.path.join(attempt, run or "", dev, name)
        try:
            with open(path) as f:
                items = json.load(f)
        except (OSError, ValueError):
            continue
        rows = "".join("<tr>" + "".join(f"<td><code>{_e(v or '')}</code></td>" for v in row(i)) + "</tr>" for i in items)
        out.append(f"<details><summary>{label} ({len(items)}), {_link(name, run, dev, name)}</summary>"
                   f"<table>{rows}</table></details>")
    return "".join(out)


def _evidence_links(attempt, run, dev):
    names = ("transcript.jsonl", "app.log", "final-snapshot.txt", "result.json", "pixels.ndjson")
    links = [_link(n, run, dev, n) for n in names if os.path.isfile(os.path.join(attempt, run or "", dev, n))]
    return f'<p class="muted">Raw: {", ".join(links)}</p>' if links else ""


def proof_page(mod, m, results, attempt):
    """The page for one `prove` attempt (`m` is its manifest)."""
    claim, rest = _doc(mod)
    runs = [r for r in results if r["device"] != "-"]
    label = lambda r: ("INCONCLUSIVE" if r["status"] == "error" and (r.get("reason") or "").startswith("setup")
                       else r["status"].upper())
    badges = [_badge(gallery.NAMES.get(r["device"], r["device"]), label(r)) for r in results]
    body = []
    if os.path.isfile(os.path.join(attempt, gallery.DEVICES)):
        body.append(f'<h2>Devices</h2><div class="media">{_image(attempt, gallery.DEVICES, "Final screen per device")}</div>')
    body.append('<h2>Video and key frames</h2><div class="devices">')
    for r in runs:
        dev = r["device"]
        strip = _image(attempt, f"{dev}/{gallery.KEY_FRAMES}", f"Key frames on {dev}") or \
            _image(attempt, f"{dev}/final.png", f"Final screen on {dev}")
        body.append(f'<div class="card media"><h3>{_e(gallery.NAMES.get(dev, dev))}</h3>'
                    f'{_video(attempt, "", dev, r.get("video"))}<div class="strip">{strip}</div></div>')
    body.append("</div><h2>Checks</h2>")
    for r in results:
        body.append(f'<h3>{_e(r["device"])}: <span class="{_tone(label(r))}">{_e(label(r))}</span></h3>'
                    + (f'<p>{_e(r["reason"])}</p>' if r.get("reason") else "")
                    + _checks(r.get("checks") or [], lambda c: not c["ok"], ("Check", "Result"),
                              lambda c: ((c["check"], ""), ("pass", "pass") if c["ok"] else ("fail", "fail")))
                    + _items("Problems (cleanup or evidence)", r.get("problems"), "warn")
                    + _items("Warnings: actions that changed nothing", r.get("warnings"))
                    + _items("Notes", r.get("notes")))
    body.append("<h2>Pixels and wide events</h2>")
    body += [f"<h3>{_e(r['device'])}</h3>{_telemetry(attempt, '', r['device']) or '<p>(none recorded)</p>'}"
             f"{_evidence_links(attempt, '', r['device'])}" for r in runs]
    unverified = [f"{r['device']}: {u['what']}: {u['why']}" for r in runs for u in r.get("unverified") or []]
    body.append("<h2>Unverified</h2>" + (_items("", unverified) or "<p>(none)</p>"))
    built = m.get("appBuild") or {}
    details = [f"Revision <code>{_e(m['revision'][:12])}</code> on <code>{_e(m['branch'])}</code>"
               + (" (uncommitted changes)" if m["dirty"] else " (clean)"),
               f"App build <code>{_e((built.get('sha256') or '?')[:16])}…</code>, built from this source; running "
               "binary per device: " + ", ".join(f"{_e(d)} <code>{_e((s or '?')[:16])}…</code>" for d, s in m["launched"].items()),
               "Devices: " + ", ".join(f"{_e(d)} ({_e(s['type'])}, {_e(s['runtime'].rsplit('.', 1)[-1])})"
                                       for d, s in m["simulators"].items()),
               f"Evidence: {_e(m['evidenceKind'])}",
               "Pinned flags: " + (", ".join(f"<code>{_e(k)}={_e(v)}</code>" for k, v in m["flags"].items()) or "(none)")]
    if m.get("profile"):
        details.append(f"Launch profile: <code>{_e(json.dumps(m['profile'], sort_keys=True))}</code>")
    details += [f"Capture conditions, {_e(d)}: " + _e(", ".join(f"{k} {v}" for k, v in (c or {}).items() if k != "window"))
                for d, c in m["capture"].items() if c]
    details += [f"Rerun: <code>{_e(m['rerun'])}</code>",
                f"{_link('proof.py', m['proof'])} · {_link('report.md', 'report.md')} · {_link('manifest.json', 'manifest.json')}"]
    body.append("<h2>Details</h2><ul>" + "".join(f"<li>{d}</li>" for d in details) + "</ul>")
    return _page("verify-ios proof", claim, rest, badges, "\n".join(body))


def comparison_page(mod, cmp, devices, attempt):
    """The page for a `prove --base` attempt (`cmp` is comparison.json, `devices` the per-device outcomes)."""
    claim, rest = _doc(mod)
    before, after = cmp["before"], cmp["after"]
    badges = [_badge(gallery.NAMES.get(d, d), o["verdict"]) for d, o in devices.items()]
    base = (f"<p>Before is the base build <code>{_e(cmp['base']['sha'][:12])}</code> (from <code>{_e(cmp['base']['ref'])}"
            "</code>); after is this checkout.</p>")
    body = [base, "<h2>Before and after</h2>"]
    for dev, o in devices.items():
        grid = _image(attempt, gallery.before_after(dev), f"Before and after on {dev}")
        videos = "".join(f'<div class="card media"><h3>{side}</h3>{_video(attempt, run, dev, o[key].get("video")) or "<p>(no video)</p>"}</div>'
                         for side, run, key in (("Before (base build)", before, "before"), ("After (this checkout)", after, "after")))
        body.append(f'<h3>{_e(gallery.NAMES.get(dev, dev))}</h3><div class="media wide">{grid}</div>'
                    f'<div class="devices">{videos}</div>')
    body.append("<h2>Checks</h2>")
    for dev, o in devices.items():
        body.append(f'<h3>{_e(dev)}: <span class="{_tone(o["verdict"])}">{_e(o["verdict"])}</span></h3>'
                    + (f'<p>{_e(o["reason"])}</p>' if o.get("reason") else "")
                    + _checks(o["rows"], lambda r: r["judged"] != "as expected",
                              ("Check", "Base build should", "Before", "After", "Judged"),
                              lambda r: ((r["check"], ""), (r["base"], ""), (r["before"], _tone(r["before"])),
                                         (r["after"], _tone(r["after"])),
                                         (r["judged"], "pass" if r["judged"] == "as expected" else "fail")))
                    + _items("Problems (cleanup or evidence)",
                             [f"{s}: {p}" for s in ("before", "after") for p in o[s].get("problems") or []], "warn"))
    body.append(_items("Problems (base worktree, images or page)", cmp["problems"], "warn"))
    body.append("<h2>Pixels and wide events (this checkout)</h2>")
    body += [f"<h3>{_e(dev)}</h3>{_telemetry(attempt, after, dev) or '<p>(none recorded)</p>'}" for dev in devices]
    unverified = [f"{dev}: {u['what']}: {u['why']}" for dev, o in devices.items() for u in o["after"].get("unverified") or []]
    unverified += [f"{dev}: {r['check']}: not observed on both runs" for dev, o in devices.items()
                   for r in o["rows"] if r["judged"] == "not shown"]
    body.append("<h2>Unverified</h2>" + (_items("", unverified) or "<p>(none)</p>"))
    runs = [f"Base run: {_link('page', before, 'index.html')}, {_link('report.md', before, 'report.md')}"
            if before else "Base run: none", f"This checkout: {_link('page', after, 'index.html')}, "
            f"{_link('report.md', after, 'report.md')}" if after else "This checkout: not run"]
    details = runs + [f"The base revision was built and proved in its own worktree with this checkout's skill and proof "
                      f"({_link('base-run.log', 'base-run.log')})"]
    details += [f"Capture conditions, {_e(d)}: " + (_e("differ: " + ", ".join(o["captureDiffers"])) if o["captureDiffers"]
                                                    else "same on both runs") for d, o in devices.items()]
    details += [f"Rerun: <code>{_e(cmp['rerun'])}</code>",
                f"{_link('proof.py', 'proof.py')} · {_link('report.md', 'report.md')} · "
                f"{_link('comparison.json', 'comparison.json')}"]
    body.append("<h2>Details</h2><ul>" + "".join(f"<li>{d}</li>" for d in details) + "</ul>")
    return _page("verify-ios before and after", claim, rest, badges, "\n".join(body))
