"""The feature map holds only maintained files: each one the index lists exists, follows the contract, and has a
worked proof in examples/; each file in features/ is listed. A heading-only file fails here. shared-steps.md documents
the steps, not a feature, so it is outside the contract."""
import os
import re
import unittest

SKILL = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
FEATURES = os.path.join(SKILL, "features")
CONTRACT = ["Sub-features", "How to get to it (user POV)", "Driving it with verify-ios", "Gotchas"]
NOT_FEATURES = {"README.md", "shared-steps.md"}


def read(name):
    with open(os.path.join(FEATURES, name)) as f:
        return f.read()


def listed():
    """The files the index's Features section links to, in order."""
    section = read("README.md").split("\n## Features\n", 1)[1].split("\n## ", 1)[0]
    return re.findall(r"\]\(\./([\w-]+\.md)\)", section)


def problems(text):
    found = []
    if not text.startswith("# "):
        found.append("doesn't start with an H1")
    h2s = re.findall(r"^## (.+)$", text, re.M)
    if h2s != CONTRACT:
        found.append(f"H2s are {h2s}, not {CONTRACT}")
        return found
    intro = text.split("\n## ", 1)[0].split("\n", 1)[1].strip()
    if not intro:
        found.append("no paragraph of user-visible behavior under the H1")
    sections = dict(zip(h2s, re.split(r"^## .+$", text, flags=re.M)[1:]))
    ids = re.findall(r"^- `([a-z0-9-]+)`", sections["Sub-features"], re.M)
    if not ids:
        found.append("Sub-features lists no `id`")
    for bullet in re.findall(r"^- .*$", sections["Sub-features"], re.M):
        if not re.match(r"- `[a-z0-9-]+`", bullet):
            found.append(f"sub-feature doesn't start with an `id` in lowercase and hyphens: {bullet}")
    if len(ids) != len(set(ids)):
        found.append(f"duplicate sub-feature ids: {ids}")
    # verify-macos-browser also requires each id in both How to get to it and Driving it; the iOS maps describe
    # their entry points by device and state, not by id, so that check isn't ported yet.
    if not sections["Driving it with verify-ios"].strip().startswith("Preconditions:"):
        found.append("Driving it with verify-ios doesn't start with Preconditions:")
    for example in re.findall(r"`examples/(t\d+_\w+\.py)`", text) or ["(none named)"]:
        if not os.path.exists(os.path.join(SKILL, "examples", example)):
            found.append(f"worked proof examples/{example} doesn't exist")
    if not sections["Gotchas"].strip():
        found.append("Gotchas is empty")
    return found


class FeatureMap(unittest.TestCase):
    def test_index_and_folder_match(self):
        files = sorted(f for f in os.listdir(FEATURES) if f.endswith(".md") and f not in NOT_FEATURES)
        self.assertEqual(sorted(listed()), files, "every features/*.md is listed in README.md, and only those")
        self.assertEqual(len(listed()), len(set(listed())), "a file is listed twice")

    def test_every_listed_file_follows_the_contract(self):
        for name in listed():
            with self.subTest(name):
                self.assertEqual(problems(read(name)), [])

    def test_sub_feature_ids_are_unique_across_the_map(self):
        ids = [i for n in listed() for i in re.findall(r"^- `([a-z0-9-]+)`", read(n).split("## How to get", 1)[0], re.M)]
        self.assertEqual(len(ids), len(set(ids)), ids)

    def test_a_heading_only_file_fails(self):
        self.assertTrue(problems("# Tabs\n\n" + "".join(f"## {h}\n\n" for h in CONTRACT)))

    def test_a_sub_feature_without_a_valid_id_fails(self):
        text = read(listed()[0])
        for bad in ["- duckai history", "- `duckai_send` sends"]:
            with self.subTest(bad):
                broken = text.replace("## Sub-features\n\n", f"## Sub-features\n\n{bad}\n", 1)
                self.assertIn(f"sub-feature doesn't start with an `id` in lowercase and hyphens: {bad}", problems(broken))

    def test_a_map_with_no_worked_proof_fails(self):
        text = read(listed()[0])
        stripped = re.sub(r"`examples/t\d+_\w+\.py`", "an example", text)
        self.assertIn("worked proof examples/(none named) doesn't exist", problems(stripped))

    def test_a_map_naming_a_missing_proof_fails(self):
        text = read(listed()[0]) + "\nSee `examples/t99_missing.py`.\n"
        self.assertIn("worked proof examples/t99_missing.py doesn't exist", problems(text))


if __name__ == "__main__":
    unittest.main()
