#!/usr/bin/env python3

import importlib.util
import tarfile
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROGRAM = ROOT / "prepare-ddg-review.py"
SPEC = importlib.util.spec_from_file_location("prepare_ddg_review", PROGRAM)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


class PrepareDDGReviewTests(unittest.TestCase):
    def test_archive_paths_must_be_relative_and_contained(self) -> None:
        self.assertTrue(MODULE.safe_archive_path("DuckDuckGo Review.app/a"))
        self.assertFalse(MODULE.safe_archive_path("/tmp/escape"))
        self.assertFalse(MODULE.safe_archive_path("../escape"))
        self.assertFalse(MODULE.safe_archive_path("app/../../escape"))

    def test_tar_validation_rejects_parent_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive_path = Path(directory) / "unsafe.tar"
            with tarfile.open(archive_path, "w") as archive:
                archive.addfile(tarfile.TarInfo("../escape"))
            with tarfile.open(archive_path) as archive:
                with self.assertRaises(MODULE.PreparationError):
                    MODULE.validate_tar_members(archive)

    def test_direct_app_is_the_single_input_not_its_contents(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "DuckDuckGo Review.app"
            executable = app / "Contents" / "MacOS" / "DuckDuckGo Review"
            executable.parent.mkdir(parents=True)
            executable.write_text("fake")

            self.assertEqual(MODULE.find_input(root), app)

    def test_multiple_archives_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "one.tar.xz").write_text("one")
            (root / "two.dmg").write_text("two")

            with self.assertRaises(MODULE.PreparationError):
                MODULE.find_input(root)


if __name__ == "__main__":
    unittest.main()
