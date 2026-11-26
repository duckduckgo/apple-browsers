"""The feature map holds only maintained files: each one the index lists exists, follows the contract, and has a
worked proof in examples/; each file in features/ is listed. A heading-only file fails here."""
import os
import re
import unittest

SKILL = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
FEATURES = os.path.join(SKILL, "features")
CONTRACT = ["Sub-features", "How to get to it (user POV)", "Driving it", "Gotchas"]


def read(name):
    with open(os.path.join(FEATURES, name)) as f:
        return f.read()


def listed():
    """The files the index's Features section links to, in order."""
    section = read("README.md").split("\n## Features\n", 1)[1]
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
    if len(ids) != len(set(ids)):
        found.append(f"duplicate sub-feature ids: {ids}")
    for i in ids:
        if f"`{i}`" not in sections["How to get to it (user POV)"] or f"`{i}`" not in sections["Driving it"]:
            found.append(f"`{i}` isn't covered in both How to get to it and Driving it")
    if not sections["Driving it"].strip().startswith("Preconditions:"):
        found.append("Driving it doesn't start with Preconditions:")
    for example in re.findall(r"`examples/(t\d+_\w+\.py)`", text) or ["(none named)"]:
        if not os.path.exists(os.path.join(SKILL, "examples", example)):
            found.append(f"worked proof examples/{example} doesn't exist")
    if not sections["Gotchas"].strip():
        found.append("Gotchas is empty")
    return found


class FeatureMap(unittest.TestCase):
    def test_index_and_folder_match(self):
        files = sorted(f for f in os.listdir(FEATURES) if f.endswith(".md") and f != "README.md")
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


if __name__ == "__main__":
    unittest.main()
