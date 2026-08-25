#!/usr/bin/env python3

import importlib.util
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock


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

    def test_tar_validation_rejects_too_many_members(self) -> None:
        archive = mock.Mock()
        archive.getmembers.return_value = [
            tarfile.TarInfo("one"),
            tarfile.TarInfo("two"),
        ]

        with mock.patch.object(MODULE, "MAX_ARCHIVE_MEMBERS", 1):
            with self.assertRaisesRegex(
                MODULE.PreparationError, "too many members"
            ):
                MODULE.validate_tar_members(archive)

    def test_tar_validation_rejects_excessive_expanded_size(self) -> None:
        member = tarfile.TarInfo("large")
        member.size = 2
        archive = mock.Mock()
        archive.getmembers.return_value = [member]

        with mock.patch.object(MODULE, "MAX_EXPANDED_BYTES", 1):
            with self.assertRaisesRegex(
                MODULE.PreparationError, "expands beyond"
            ):
                MODULE.validate_tar_members(archive)

    def test_zip_validation_rejects_too_many_members(self) -> None:
        archive = mock.Mock()
        archive.infolist.return_value = [
            zipfile.ZipInfo("one"),
            zipfile.ZipInfo("two"),
        ]

        with mock.patch.object(MODULE, "MAX_ARCHIVE_MEMBERS", 1):
            with self.assertRaisesRegex(
                MODULE.PreparationError, "too many members"
            ):
                MODULE.validate_zip_members(archive)

    def test_zip_validation_rejects_excessive_expanded_size(self) -> None:
        member = zipfile.ZipInfo("large")
        member.file_size = 2
        archive = mock.Mock()
        archive.infolist.return_value = [member]

        with mock.patch.object(MODULE, "MAX_EXPANDED_BYTES", 1):
            with self.assertRaisesRegex(
                MODULE.PreparationError, "expands beyond"
            ):
                MODULE.validate_zip_members(archive)

    def test_app_validation_rejects_excessive_size(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "DuckDuckGo Review.app"
            app.mkdir()
            (app / "large").write_bytes(b"xx")

            with mock.patch.object(MODULE, "MAX_EXPANDED_BYTES", 1):
                with self.assertRaisesRegex(
                    MODULE.PreparationError, "exceeds"
                ):
                    MODULE.validate_app_size(app)

    def test_direct_app_size_is_validated_before_copying(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "DuckDuckGo Review.app"
            destination = root / "destination"
            app.mkdir()
            destination.mkdir()

            with mock.patch.object(
                MODULE,
                "validate_app_size",
                side_effect=MODULE.PreparationError("too large"),
            ) as validate:
                with mock.patch.object(MODULE, "copy_app") as copy:
                    with self.assertRaises(MODULE.PreparationError):
                        MODULE.extract_source(app, destination)

            validate.assert_called_once_with(app)
            copy.assert_not_called()

    def test_dmg_app_size_is_validated_before_copying(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "review.dmg"
            destination = root / "destination"
            app = destination / "mounted" / "DuckDuckGo Review.app"
            source.touch()
            destination.mkdir()

            with mock.patch.object(MODULE.tarfile, "is_tarfile", return_value=False):
                with mock.patch.object(MODULE.zipfile, "is_zipfile", return_value=False):
                    with mock.patch.object(
                        MODULE.subprocess,
                        "run",
                        return_value=mock.Mock(returncode=0),
                    ):
                        with mock.patch.object(
                            MODULE, "outer_apps", return_value=[app]
                        ):
                            with mock.patch.object(
                                MODULE,
                                "validate_app_size",
                                side_effect=MODULE.PreparationError("too large"),
                            ) as validate:
                                with mock.patch.object(MODULE, "copy_app") as copy:
                                    with self.assertRaises(MODULE.PreparationError):
                                        MODULE.extract_source(source, destination)

            validate.assert_called_once_with(app)
            copy.assert_not_called()

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
