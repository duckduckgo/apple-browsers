#!/usr/bin/env python3
"""Render the snapshot tests that failed in one or more xcresult bundles into
a single self-contained HTML page showing the reference, failure and
difference images side by side. Writes nothing when there are no snapshot
failures; otherwise appends `report=<path>` to $GITHUB_OUTPUT when it is set.
"""
from __future__ import annotations

import argparse
import base64
import html
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


IMAGE_KINDS = ("reference", "failure", "difference")
_IMAGE_NAME = re.compile(r"^(reference|failure|difference)(?:_\d+_[0-9A-Fa-f-]+)?\.png$")
_SNAPSHOT_MISMATCH = re.compile(r'Snapshot "([^"]+)" does not match reference\.')
_PRECISION_LINE = re.compile(r"^The (?:percentage|lowest perceptual).*$", re.MULTILINE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xcresults", nargs="+", help="paths to .xcresult bundles; missing ones are skipped")
    parser.add_argument("--output", required=True, help="path of the HTML file to write")
    parser.add_argument("--title", required=True, help="heading shown at the top of the page")
    args = parser.parse_args()

    tests: list[dict] = []
    for xcresult in args.xcresults:
        if not Path(xcresult).is_dir():
            print(f"{xcresult} not found; skipping.", file=sys.stderr)
            continue
        try:
            tests.extend(_collect(xcresult))
        except subprocess.CalledProcessError as error:
            print(
                f"Could not export attachments from {xcresult} (exit {error.returncode}).",
                file=sys.stderr,
            )
            if error.stderr:
                print(error.stderr.rstrip(), file=sys.stderr)
            return 1

    if not tests:
        print("No snapshot failures found; no report written.")
        return 0

    Path(args.output).write_text(_render(args.title, tests))
    snapshot_count = sum(len(t["snapshots"]) for t in tests)
    print(f"Wrote {snapshot_count} snapshot failure(s) from {len(tests)} test(s) to {args.output}")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as f:
            f.write(f"report={args.output}\n")
    return 0


def _collect(xcresult: str) -> list[dict]:
    with tempfile.TemporaryDirectory() as export_dir:
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments",
             "--path", xcresult, "--output-path", export_dir],
            capture_output=True, text=True, check=True,
        )
        manifest_path = Path(export_dir) / "manifest.json"
        if not manifest_path.is_file():
            return []
        manifest = json.loads(manifest_path.read_text())
        failed_tests = _failed_tests(xcresult)

        tests: list[dict] = []
        for entry in manifest:
            test_key = entry.get("testIdentifierURL") or entry["testIdentifier"]
            if failed_tests is not None and test_key not in failed_tests:
                if _has_snapshot_images(entry.get("attachments", [])):
                    print(f"Skipping {entry['testIdentifier']}: its final result is not Failed.")
                continue
            snapshots = _group_snapshots(entry.get("attachments", []), Path(export_dir))
            if not snapshots:
                continue
            details = _mismatch_details(xcresult, entry["testIdentifier"])
            if len(details) == len(snapshots):
                for snapshot, detail in zip(snapshots, details):
                    snapshot.update(detail)
            tests.append({"test_identifier": entry["testIdentifier"], "snapshots": snapshots})
        return tests


def _failed_tests(xcresult: str) -> set[str] | None:
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests",
         "--path", xcresult, "--format", "json"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(
            f"Could not read test results from {xcresult} (exit {result.returncode}); "
            "reporting snapshots from every test, including ones that passed on retry.",
            file=sys.stderr,
        )
        if result.stderr:
            print(result.stderr.rstrip(), file=sys.stderr)
        return None

    failed: set[str] = set()
    for node in _test_cases(json.loads(result.stdout).get("testNodes", [])):
        if node.get("result") == "Failed":
            failed.update(filter(None, (node.get("nodeIdentifierURL"), node.get("nodeIdentifier"))))
    return failed


def _test_cases(nodes: list[dict]):
    for node in nodes:
        if node.get("nodeType") == "Test Case":
            yield node
        else:
            yield from _test_cases(node.get("children", []))


def _has_snapshot_images(attachments: list[dict]) -> bool:
    return any(_IMAGE_NAME.match(a.get("suggestedHumanReadableName", "")) for a in attachments)


def _group_snapshots(attachments: list[dict], export_dir: Path) -> list[dict]:
    by_repetition: dict[int, list[tuple[str, dict]]] = {}
    for attachment in attachments:
        match = _IMAGE_NAME.match(attachment.get("suggestedHumanReadableName", ""))
        if not match:
            continue
        repetition = attachment.get("repetitionNumber", 1)
        by_repetition.setdefault(repetition, []).append((match.group(1), attachment))
    if not by_repetition:
        return []

    images = sorted(
        by_repetition[min(by_repetition)],
        key=lambda item: (item[1].get("timestamp", 0), IMAGE_KINDS.index(item[0])),
    )

    snapshots: list[dict] = []
    current: dict = {}
    for kind, attachment in images:
        if kind in current or (kind == "reference" and current):
            snapshots.append({"images": current})
            current = {}
        current[kind] = _read_base64(export_dir / attachment["exportedFileName"])
    if current:
        snapshots.append({"images": current})
    return snapshots


def _mismatch_details(xcresult: str, test_identifier: str) -> list[dict]:
    result = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "test-details",
         "--path", xcresult, "--test-id", test_identifier, "--format", "json"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(
            f"Could not read snapshot details for {test_identifier} in {xcresult} "
            f"(exit {result.returncode}); using unnamed comparisons.",
            file=sys.stderr,
        )
        if result.stderr:
            print(result.stderr.rstrip(), file=sys.stderr)
        return []

    details: list[dict] = []
    seen: set[str] = set()
    for message in _node_names(json.loads(result.stdout).get("testRuns", [])):
        match = _SNAPSHOT_MISMATCH.search(message)
        if not match or match.group(1) in seen:
            continue
        seen.add(match.group(1))
        details.append({
            "name": match.group(1),
            "summary": "\n".join(_PRECISION_LINE.findall(message)),
        })
    return details


def _node_names(nodes: list[dict]):
    for node in nodes:
        yield node.get("name", "")
        yield from _node_names(node.get("children", []))


def _read_base64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


_STYLE = """
:root { color-scheme: light dark; --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --border: #d1d9e0; --card: #f6f8fa; --link: #0969da; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #0d1117; --fg: #f0f6fc; --muted: #9198a1; --border: #3d444d; --card: #151b23; --link: #4493f8; }
}
html { scroll-padding-top: 16px; }
body { margin: 0; background: var(--bg); color: var(--fg);
       font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; }
.layout { display: grid; grid-template-columns: 300px minmax(0, 1fr); }
nav { position: sticky; top: 0; height: 100vh; overflow-y: auto; box-sizing: border-box; padding: 16px;
      border-right: 1px solid var(--border); background: var(--card); }
nav ol { list-style: none; margin: 0; padding: 0; }
nav > ol > li { margin: 0 0 12px; }
nav ol ol { margin: 2px 0 0 12px; }
nav a { color: var(--link); text-decoration: none; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; overflow-wrap: anywhere; }
nav a:hover { text-decoration: underline; }
nav a.test { font-weight: 600; }
nav .suite { display: block; font-weight: 400; color: var(--muted); }
nav .suite:empty { display: none; }
nav ol ol a { color: var(--muted); }
main { padding: 16px; min-width: 0; }
h1 { font-size: 20px; margin: 0 0 4px; }
p.meta { color: var(--muted); margin: 0 0 16px; }
details.test { border-top: 1px solid var(--border); padding: 8px 0; }
details.test > summary { cursor: pointer; }
h2 { display: inline; font-size: 16px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; word-break: break-all; }
.count { color: var(--muted); font-size: 12px; margin-left: 8px; }
section.snapshot { background: var(--card); border: 1px solid var(--border); border-radius: 8px; padding: 12px; margin: 12px 0; }
h3 { font-size: 14px; margin: 0 0 4px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; word-break: break-all; }
pre { color: var(--muted); margin: 0 0 8px; white-space: pre-wrap; font-size: 12px; }
.images { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; }
figure { margin: 0; }
figcaption { font-weight: 600; margin-bottom: 4px; }
figure img { display: block; width: 100%; height: auto; border: 1px solid var(--border); background: repeating-conic-gradient(#8883 0% 25%, transparent 0% 50%) 50% / 16px 16px; }
@media (max-width: 900px) {
  .layout { grid-template-columns: 1fr; }
  nav { position: static; height: auto; max-height: 40vh; border-right: 0; border-bottom: 1px solid var(--border); }
  .images { grid-template-columns: 1fr; }
}
"""


_SCRIPT = """
function openTarget() {
  const target = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
  const details = target && target.closest("details");
  if (!details || details.open) return;
  details.open = true;
  target.scrollIntoView();
}
addEventListener("hashchange", openTarget);
openTarget();
"""


def _render(title: str, tests: list[dict]) -> str:
    snapshot_count = sum(len(t["snapshots"]) for t in tests)
    for test_index, test in enumerate(tests, start=1):
        test["anchor"] = f"test-{test_index}"
        for snapshot_index, snapshot in enumerate(test["snapshots"], start=1):
            snapshot["anchor"] = f"test-{test_index}-snapshot-{snapshot_index}"
            snapshot.setdefault("name", f"Snapshot {snapshot_index}")

    parts = [
        "<!doctype html>",
        '<html lang="en"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1">',
        f"<title>{html.escape(title)}</title>",
        f"<style>{_STYLE}</style>",
        '</head><body><div class="layout">',
        _sidebar(tests),
        "<main>",
        f"<h1>{html.escape(title)}</h1>",
        f'<p class="meta">{snapshot_count} snapshot(s) failed in {len(tests)} test(s).</p>',
    ]
    parts.extend(_test_section(test) for test in tests)
    parts.append(f"</main></div><script>{_SCRIPT}</script></body></html>")
    return "\n".join(parts) + "\n"


def _sidebar(tests: list[dict]) -> str:
    parts = ['<nav aria-label="Failed tests"><ol>']
    for test in tests:
        suite, _, test_name = test["test_identifier"].rpartition("/")
        parts.append(
            f'<li><a class="test" href="#{test["anchor"]}">'
            f'<span class="suite">{html.escape(suite)}</span>{html.escape(test_name)}</a>'
            f'<span class="count">{len(test["snapshots"])}</span><ol>'
        )
        for snapshot in test["snapshots"]:
            parts.append(f'<li><a href="#{snapshot["anchor"]}">{html.escape(snapshot["name"])}</a></li>')
        parts.append("</ol></li>")
    parts.append("</ol></nav>")
    return "".join(parts)


def _test_section(test: dict) -> str:
    parts = [
        f'<details class="test" id="{test["anchor"]}" open><summary>'
        f'<h2>{html.escape(test["test_identifier"])}</h2>'
        f'<span class="count">{len(test["snapshots"])} snapshot(s)</span></summary>'
    ]
    parts.extend(_snapshot_section(snapshot) for snapshot in test["snapshots"])
    parts.append("</details>")
    return "".join(parts)


def _snapshot_section(snapshot: dict) -> str:
    parts = [f'<section class="snapshot" id="{snapshot["anchor"]}">', f"<h3>{html.escape(snapshot['name'])}</h3>"]
    if snapshot.get("summary"):
        parts.append(f"<pre>{html.escape(snapshot['summary'])}</pre>")
    parts.append('<div class="images">')
    for kind in IMAGE_KINDS:
        data = snapshot["images"].get(kind)
        if data is None:
            continue
        parts.append(
            f"<figure><figcaption>{kind.capitalize()}</figcaption>"
            f'<img width="360" alt="{kind}" src="data:image/png;base64,{data}"></figure>'
        )
    parts.append("</div></section>")
    return "".join(parts)


if __name__ == "__main__":
    sys.exit(main())
