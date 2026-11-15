#!/usr/bin/env python3
"""The agent's plan for evidence: which tests to run and a Maestro flow to record, checked before the build.

Usage:
  evidence_plan.py extract <repo dir> <evidence dir>
  evidence_plan.py excluded <evidence dir>   (after changes.patch is written)

extract moves .agent-evidence/tests.txt, flow.yaml and excluded.txt out of the checkout so they never go
into the patch. Accepted ones are saved to evidence for the verify job. Rejected ones are dropped and the
reason goes to plan-notes.txt and summary.md, so a bad flow never stops the build or tests

excluded.txt lists tests the agent took out of tests.txt as unrelated failures, one "<test id>: <reason>" per line.
An exclusion only stands when the patch doesn't mention the test's class, so the agent can't drop a test
for code it changed. Rejected ones go back into tests.txt. verify.md shows the rest under Excluded tests
"""

import os
import re
import shutil
import sys

AGENT_DIR = ".agent-evidence"
APP_ID = "com.duckduckgo.mobile.ios"
MAX_TESTS = 5
MAX_FLOW_BYTES = 20000
# xcodebuild -only-testing form: Target, Target/Class or Target/Class/testMethod
TEST_ID = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(/[A-Za-z_][A-Za-z0-9_]*){0,2}")
# Maestro commands that drive the UI. Commands that run scripts, load other files or reach the network
# (runScript, evalScript, runFlow, addMedia, openLink, setLocation) aren't allowed
COMMANDS = {
    "launchApp", "stopApp", "killApp", "clearState", "tapOn", "doubleTapOn", "longPressOn", "inputText",
    "eraseText", "pressKey", "back", "hideKeyboard", "scroll", "scrollUntilVisible", "swipe",
    "assertVisible", "assertNotVisible", "waitForAnimationToEnd", "extendedWaitUntil", "takeScreenshot",
    "startRecording", "stopRecording", "setOrientation", "copyTextFrom", "pasteText",
}
COMMAND_LINE = re.compile(r"- ([A-Za-z]+)\s*(:.*)?")


def check_flow(text):
    """None if the flow looks runnable, else why not"""
    if "---" not in text.splitlines():
        return "no '---' line between the header and the commands"
    header, _, body = text.partition("\n---")
    if not re.search(rf"^appId:\s*{re.escape(APP_ID)}\s*$", header, re.M):
        return f"the header must be 'appId: {APP_ID}'"
    commands = []
    for n, line in enumerate(body.splitlines()[1:], 2):
        if not line.strip() or line.lstrip().startswith("#") or line.startswith((" ", "\t")):
            continue
        m = COMMAND_LINE.fullmatch(line.rstrip())
        if not m:
            return f"line {n} after '---' isn't a '- command' line"
        if m.group(1) not in COMMANDS:
            return f"command '{m.group(1)}' isn't allowed"
        commands.append(m.group(1))
    if not commands:
        return "no commands"
    if "startRecording" in commands and "stopRecording" not in commands:
        return "startRecording without stopRecording"
    return None


def extract(repo, evidence):
    src = os.path.join(repo, AGENT_DIR)
    notes = []
    tests_path, flow_path = os.path.join(src, "tests.txt"), os.path.join(src, "flow.yaml")

    tests = []
    if os.path.isfile(tests_path):
        with open(tests_path, errors="replace") as f:
            lines = [l.strip().removeprefix("-only-testing:") for l in f.read(5000).splitlines() if l.strip()]
        tests = [l for l in lines if TEST_ID.fullmatch(l)][:MAX_TESTS]
        if len(tests) < len(lines):
            notes.append(f"Dropped {len(lines) - len(tests)} test line(s) that weren't test IDs or were over {MAX_TESTS}.")
    if tests:
        with open(os.path.join(evidence, "tests.txt"), "w") as f:
            f.write("\n".join(tests) + "\n")

    flow = False
    if os.path.isfile(flow_path):
        if os.path.getsize(flow_path) > MAX_FLOW_BYTES:
            notes.append("The Maestro flow was dropped: it's over 20 KB.")
        else:
            with open(flow_path, errors="replace") as f:
                text = f.read()
            problem = check_flow(text)
            if problem:
                notes.append(f"The Maestro flow was dropped: {problem}.")
            else:
                shutil.copyfile(flow_path, os.path.join(evidence, "flow.yaml"))
                flow = True

    excluded_path = os.path.join(src, "excluded.txt")
    if os.path.isfile(excluded_path):
        with open(excluded_path, errors="replace") as f:
            raw = f.read(5000)
        with open(os.path.join(evidence, "excluded.txt"), "w") as f:
            f.write(raw)

    if os.path.isdir(src):
        shutil.rmtree(src)
    if notes:
        with open(os.path.join(evidence, "plan-notes.txt"), "w") as f:
            f.write("\n".join(f"- {n}" for n in notes) + "\n")
    with open(os.path.join(evidence, "summary.md"), "a") as f:
        f.write("\n## Evidence plan\n\n")
        f.write(("Tests: " + ", ".join(f"`{t}`" for t in tests)) if tests else "Tests: none")
        f.write("\n\nMaestro flow: " + ("yes, see flow.yaml" if flow else "none") + "\n")
        for note in notes:
            f.write(f"\n{note}\n")
    print(f"evidence plan: {len(tests)} test(s), flow {'yes' if flow else 'no'}, {len(notes)} note(s)")


def excluded(evidence):
    """Keep exclusions whose class the patch doesn't mention; put the others back into tests.txt"""
    path = os.path.join(evidence, "excluded.txt")
    if not os.path.isfile(path):
        return
    with open(path, errors="replace") as f:
        lines = [l.strip() for l in f.read(5000).splitlines() if l.strip()]
    with open(os.path.join(evidence, "changes.patch"), errors="replace") as f:
        patch = f.read()
    tests_path = os.path.join(evidence, "tests.txt")
    tests = open(tests_path).read().split() if os.path.isfile(tests_path) else []
    kept, notes = [], []
    for line in lines[:MAX_TESTS]:
        test, _, reason = line.partition(":")
        test, reason = test.strip(), " ".join(reason.split())[:300]
        if not TEST_ID.fullmatch(test) or "/" not in test or not reason:
            notes.append(f"Ignored an exclusion that wasn't '<test id>: <reason>': {line[:100]}")
            continue
        # The test class, and the class it tests by naming convention (FooTests tests Foo)
        cls = test.split("/")[1]
        hit = next((n for n in (cls, cls.removesuffix("Tests")) if n and re.search(rf"\b{re.escape(n)}\b", patch)), None)
        if hit:
            notes.append(f"Put `{test}` back into the tests: the change touches `{hit}`, so it can't be excluded.")
            if test not in tests:
                tests.append(test)
            continue
        kept.append(f"{test}: {reason}")
    if kept:
        with open(path, "w") as f:
            f.write("\n".join(kept) + "\n")
    else:
        os.remove(path)
    if tests:
        with open(tests_path, "w") as f:
            f.write("\n".join(tests) + "\n")
    if notes:
        with open(os.path.join(evidence, "plan-notes.txt"), "a") as f:
            f.write("\n".join(f"- {n}" for n in notes) + "\n")
    with open(os.path.join(evidence, "summary.md"), "a") as f:
        f.write("\nExcluded tests: " + (", ".join(f"`{k.split(':')[0]}`" for k in kept) or "none") + "\n")
        for n in notes:
            f.write(f"\n{n}\n")
    print(f"excluded tests: {len(kept)} kept, {len(notes)} note(s)")


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "extract":
        extract(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == "excluded":
        excluded(sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
