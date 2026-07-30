#!/usr/bin/env python3
"""Acquire, validate, and normalize a DuckDuckGo Review app for replay CI."""

import argparse
import hashlib
import os
import plistlib
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath


MAX_DOWNLOAD_BYTES = 2 * 1024 * 1024 * 1024
MAX_ARCHIVE_MEMBERS = 100_000
MAX_EXPANDED_BYTES = 4 * 1024 * 1024 * 1024
EXPECTED_BUNDLE_ID = "com.duckduckgo.macos.browser.review"
EXPECTED_TEAM_ID = "HKE973VLUW"


class PreparationError(RuntimeError):
    pass


def safe_archive_path(value: str) -> bool:
    path = PurePosixPath(value)
    return not path.is_absolute() and ".." not in path.parts


def validate_tar_members(archive: tarfile.TarFile) -> None:
    members = archive.getmembers()
    if len(members) > MAX_ARCHIVE_MEMBERS:
        raise PreparationError("archive contains too many members")
    expanded_bytes = 0
    for member in members:
        if not safe_archive_path(member.name):
            raise PreparationError("archive contains an unsafe path")
        if member.issym() or member.islnk():
            target = PurePosixPath(member.name).parent / member.linkname
            if not safe_archive_path(str(target)):
                raise PreparationError("archive contains an unsafe link")
        expanded_bytes += member.size
        if expanded_bytes > MAX_EXPANDED_BYTES:
            raise PreparationError("archive expands beyond the 4 GiB limit")


def validate_zip_members(archive: zipfile.ZipFile) -> None:
    members = archive.infolist()
    if len(members) > MAX_ARCHIVE_MEMBERS:
        raise PreparationError("archive contains too many members")
    expanded_bytes = 0
    for member in members:
        if not safe_archive_path(member.filename):
            raise PreparationError("archive contains an unsafe path")
        mode = member.external_attr >> 16
        if mode & 0o170000 == 0o120000:
            raise PreparationError("ZIP archives containing symlinks are unsupported")
        expanded_bytes += member.file_size
        if expanded_bytes > MAX_EXPANDED_BYTES:
            raise PreparationError("archive expands beyond the 4 GiB limit")


def validate_app_size(app: Path) -> None:
    expanded_bytes = 0
    for root, _, files in os.walk(app, followlinks=False):
        for filename in files:
            expanded_bytes += (Path(root) / filename).stat(
                follow_symlinks=False
            ).st_size
            if expanded_bytes > MAX_EXPANDED_BYTES:
                raise PreparationError("Review app exceeds the 4 GiB limit")


def download_review(url: str, destination: Path) -> None:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "DuckDuckGo-macOS-LCP-CI"},
    )
    downloaded = 0
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            declared_size = response.headers.get("Content-Length")
            if declared_size and int(declared_size) > MAX_DOWNLOAD_BYTES:
                raise PreparationError("Review download exceeds the 2 GiB limit")
            with destination.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    downloaded += len(chunk)
                    if downloaded > MAX_DOWNLOAD_BYTES:
                        raise PreparationError("Review download exceeds the 2 GiB limit")
                    output.write(chunk)
    except urllib.error.URLError as error:
        raise PreparationError("Review download failed") from error
    if downloaded == 0:
        raise PreparationError("Review download was empty")


def outer_apps(root: Path) -> list[Path]:
    apps = []
    for app in root.rglob("*.app"):
        relative = app.relative_to(root)
        if not any(parent.suffix == ".app" for parent in relative.parents):
            apps.append(app)
    return apps


def copy_app(source: Path, destination: Path) -> None:
    subprocess.run(
        ["/usr/bin/ditto", str(source), str(destination)],
        check=True,
    )


def extract_source(source: Path, destination: Path) -> None:
    if source.is_dir() and source.suffix == ".app":
        validate_app_size(source)
        copy_app(source, destination / source.name)
        return
    if tarfile.is_tarfile(source):
        with tarfile.open(source) as archive:
            validate_tar_members(archive)
            archive.extractall(destination)
        return
    if zipfile.is_zipfile(source):
        with zipfile.ZipFile(source) as archive:
            validate_zip_members(archive)
        subprocess.run(
            ["/usr/bin/ditto", "-x", "-k", str(source), str(destination)],
            check=True,
        )
        return

    mountpoint = destination / "mounted"
    mountpoint.mkdir()
    attached = subprocess.run(
        [
            "/usr/bin/hdiutil",
            "attach",
            "-readonly",
            "-nobrowse",
            "-mountpoint",
            str(mountpoint),
            str(source),
        ],
        text=True,
        capture_output=True,
    )
    if attached.returncode != 0:
        raise PreparationError("Review input is not a supported app archive or DMG")
    try:
        apps = outer_apps(mountpoint)
        if len(apps) != 1:
            raise PreparationError("Review DMG must contain exactly one outer app")
        validate_app_size(apps[0])
        copy_app(apps[0], destination / apps[0].name)
    finally:
        subprocess.run(
            ["/usr/bin/hdiutil", "detach", str(mountpoint)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def command_output(command: list[str]) -> str:
    result = subprocess.run(
        command,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        raise PreparationError(f"{Path(command[0]).name} validation failed")
    return result.stdout + result.stderr


def validate_app(app: Path) -> tuple[str, str, str, str]:
    plist = app / "Contents" / "Info.plist"
    try:
        with plist.open("rb") as source:
            metadata = plistlib.load(source)
    except (OSError, plistlib.InvalidFileException) as error:
        raise PreparationError("Review app has no valid Info.plist") from error

    bundle_id = metadata.get("CFBundleIdentifier")
    version = metadata.get("CFBundleShortVersionString")
    build = metadata.get("CFBundleVersion")
    executable = metadata.get("CFBundleExecutable")
    if bundle_id != EXPECTED_BUNDLE_ID:
        raise PreparationError("Review app has an unexpected bundle identifier")
    if not all(
        isinstance(value, str) and value
        for value in (version, build, executable)
    ):
        raise PreparationError("Review app metadata is incomplete")
    if "/" in executable or not (app / "Contents" / "MacOS" / executable).is_file():
        raise PreparationError("Review app executable is missing or unsafe")

    command_output(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)]
    )
    signature = command_output(
        ["/usr/bin/codesign", "-dvvv", str(app)]
    )
    team_id = ""
    for line in signature.splitlines():
        if line.startswith("TeamIdentifier="):
            team_id = line.partition("=")[2]
            break
    if team_id != EXPECTED_TEAM_ID:
        raise PreparationError("Review app has an unexpected signing team")
    command_output(
        ["/usr/sbin/spctl", "--assess", "--type", "execute", str(app)]
    )
    return bundle_id, version, build, team_id


def find_input(input_directory: Path) -> Path:
    apps = outer_apps(input_directory)
    if apps:
        if len(apps) != 1:
            raise PreparationError("expected exactly one Review app")
        return apps[0]
    files = [path for path in input_directory.rglob("*") if path.is_file()]
    if len(files) != 1:
        raise PreparationError("expected exactly one Review archive")
    return files[0]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def write_report(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    report = ["DuckDuckGo Review validation"]
    try:
        args.input_directory.mkdir(parents=True, exist_ok=True)
        review_url = os.environ.get("REVIEW_BUILD_URL", "")
        if review_url:
            downloaded = args.input_directory / "downloaded-review"
            download_review(review_url, downloaded)
            source = downloaded
            report.append("source: supplied URL")
        else:
            source = find_input(args.input_directory)
            report.append("source: trusted workflow artifact")

        with tempfile.TemporaryDirectory() as directory:
            extraction = Path(directory)
            extract_source(source, extraction)
            apps = outer_apps(extraction)
            if len(apps) != 1:
                raise PreparationError("Review input must contain exactly one outer app")
            app = apps[0]
            bundle_id, version, build, team_id = validate_app(app)
            args.output.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(
                [
                    "/usr/bin/tar",
                    "-cJf",
                    str(args.output),
                    "-C",
                    str(app.parent),
                    app.name,
                ],
                check=True,
            )

        digest = sha256(args.output)
        report.extend(
            [
                "status: ok",
                f"bundle_id: {bundle_id}",
                f"version: {version}",
                f"build: {build}",
                f"team_id: {team_id}",
                f"archive_sha256: {digest}",
            ]
        )
        write_report(args.report, report)
        print("\n".join(report))
        return 0
    except (
        OSError,
        PreparationError,
        subprocess.SubprocessError,
        tarfile.TarError,
        ValueError,
        zipfile.BadZipFile,
    ) as error:
        report.extend(
            [
                "status: error",
                f"reason: {str(error)[:500]}",
                "action: verify the Review URL or rebuild the signed Review artifact",
            ]
        )
        write_report(args.report, report)
        print("\n".join(report), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
