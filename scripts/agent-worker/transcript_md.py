#!/usr/bin/env python3
"""Write transcript.md, the agent's full session as readable Markdown, from Claude Code's session files.

Usage: transcript_md.py <result.json> <claude projects dir> <evidence dir>

Finds the session named in result.json under the projects dir, writes transcript.md with the main
session and then each subagent's, and copies the raw .jsonl files to transcript/ next to it. Long tool
output is cut so the page stays readable. Both go to evidence behind SSO; the log gets counts only
"""

import glob
import json
import os
import shutil
import sys

LIMIT = 4000


def cut(text, limit=LIMIT):
    text = text if isinstance(text, str) else json.dumps(text, indent=2, ensure_ascii=False)
    return text if len(text) <= limit else text[:limit] + f"\n... ({len(text) - limit} more characters)"


def fence(text):
    # A fence longer than any backtick run inside, so tool output can't close it
    ticks = "```"
    while ticks in text:
        ticks += "`"
    return f"{ticks}\n{text}\n{ticks}"


def result_text(content):
    if isinstance(content, list):
        return "\n".join(c.get("text", "") if isinstance(c, dict) and c.get("type") == "text"
                         else f"[{c.get('type', '?')}]" if isinstance(c, dict) else str(c) for c in content)
    return content if isinstance(content, str) else json.dumps(content, ensure_ascii=False)


def render(path):
    md = []
    with open(path, errors="replace") as f:
        for line in f:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            msg = entry.get("message")
            if entry.get("type") not in ("user", "assistant") or not isinstance(msg, dict):
                continue
            role, content = msg.get("role", entry["type"]), msg.get("content")
            if isinstance(content, str):
                content = [{"type": "text", "text": content}]
            for block in content or []:
                if not isinstance(block, dict):
                    continue
                kind = block.get("type")
                if kind == "text" and block.get("text", "").strip():
                    md += [f"### {'Prompt' if role == 'user' else 'Claude'}", "", block["text"].strip(), ""]
                elif kind == "thinking" and block.get("thinking", "").strip():
                    md += ["### Thinking", "", "\n".join("> " + l for l in block["thinking"].strip().splitlines()), ""]
                elif kind == "tool_use":
                    md += [f"### Tool: {block.get('name', '?')}", "", fence(cut(block.get("input"))), ""]
                elif kind == "tool_result":
                    label = "Result (error)" if block.get("is_error") else "Result"
                    md += [f"#### {label}", "", fence(cut(result_text(block.get("content")))), ""]
    return md


def main():
    src, projects, evidence = sys.argv[1:4]
    try:
        with open(src) as f:
            session = json.load(f).get("session_id") or ""
    except Exception:
        session = ""
    main_files = glob.glob(os.path.join(projects, "*", f"{session}.jsonl")) if session else []
    if not main_files:
        print("no transcript found")
        return
    subagents = sorted(glob.glob(os.path.join(projects, "*", session, "subagents", "*.jsonl")))

    md = ["# Transcript", "",
          f"The agent's session, then {len(subagents)} subagent session(s). Tool output over {LIMIT} characters is cut; "
          "the raw .jsonl files in transcript/ have everything.", "", "## Main session", ""]
    md += render(main_files[0])
    for path in subagents:
        md += [f"## Subagent {os.path.splitext(os.path.basename(path))[0]}", ""] + render(path)
    with open(os.path.join(evidence, "transcript.md"), "w") as f:
        f.write("\n".join(md))

    raw = os.path.join(evidence, "transcript")
    os.makedirs(raw, exist_ok=True)
    shutil.copy(main_files[0], os.path.join(raw, "session.jsonl"))
    for path in subagents:
        shutil.copy(path, os.path.join(raw, os.path.basename(path)))
    print(f"transcript: main session and {len(subagents)} subagent(s)")


if __name__ == "__main__":
    main()
