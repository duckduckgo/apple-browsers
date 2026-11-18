#!/usr/bin/env python3
"""Prepare the pinned local PIR dashboard and DEBUG preferences. Requires Python 3.12+."""

import argparse
import hashlib
import http.server
import os
from pathlib import Path
import plistlib
import subprocess
import tarfile
import time
import urllib.parse


FE_REVISION = "a0dd559389494beee5ff612fc1491176084f5b66"
FE_RUN = "1834799"
ARCHIVE_SHA256 = "d52e1adda0a56f9aa6de1deb1dde3ee249db28468173c1599ee7a3477dbc6ee6"
CONFIG_SUITE = "HKE973VLUW.com.duckduckgo.macos.browser.app-configuration.debug"
DBP_SUITE = "HKE973VLUW.com.duckduckgo.macos.browser.dbp.debug"
LOCAL_VERSION_KEY = "macos.browser.data-broker-protection.LastLocalVersionChecked"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def group_domain(suite):
    return Path.home() / "Library/Group Containers" / suite / "Library/Preferences" / suite


def standard_domain(bundle):
    container = Path.home() / "Library/Containers" / bundle / "Data/Library/Preferences" / bundle
    return container if Path(str(container) + ".plist").exists() else bundle


def read_domain(domain):
    result = subprocess.run(["defaults", "export", str(domain), "-"], capture_output=True)
    if result.returncode:
        path = Path(domain) if Path(domain).is_absolute() else Path.home() / "Library/Preferences" / domain
        try:
            Path(str(path) + ".plist").stat()
        except FileNotFoundError:
            return {}
        raise subprocess.CalledProcessError(result.returncode, result.args, stderr=result.stderr)
    return plistlib.loads(result.stdout)


def write_value(domain, key, value):
    if isinstance(value, bool):
        run("defaults", "write", str(domain), key, "-bool", str(value).lower())
    elif isinstance(value, bytes):
        run("defaults", "write", str(domain), key, "-data", value.hex())
    elif isinstance(value, list):
        run("defaults", "write", str(domain), key, "-array", *value)
    elif isinstance(value, float):
        run("defaults", "write", str(domain), key, "-float", str(value))
    elif isinstance(value, int):
        run("defaults", "write", str(domain), key, "-int", str(value))
    else:
        run("defaults", "write", str(domain), key, "-string", str(value))


def url_archive(url):
    return plistlib.dumps({
        "$version": 100000,
        "$archiver": "NSKeyedArchiver",
        "$top": {"root": plistlib.UID(1)},
        "$objects": ["$null", {"NS.base": plistlib.UID(0), "$class": plistlib.UID(3),
                                "NS.relative": plistlib.UID(2)}, url,
                     {"$classname": "NSURL", "$classes": ["NSURL", "NSObject"]}],
    }, fmt=plistlib.FMT_BINARY)


def prepare_artifact(cache):
    archive = cache / "artifact/build-output.tar.gz"
    if not archive.exists():
        run("gh", "run", "download", FE_RUN, "--repo", "duckduckgo/static-pages",
            "--name", "build-output", "--dir", str(archive.parent),
            env={**os.environ, "GH_HOST": "dub.duckduckgo.com"})
    with archive.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    if digest != ARCHIVE_SHA256:
        raise ValueError(f"Unexpected FE archive SHA256: {digest}")
    output = cache / "out"
    marker = output / ".verified-artifact"
    if not marker.exists() or marker.read_text() != digest:
        output.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive) as tar:
            names = {member.name.removeprefix("./") for member in tar.getmembers()}
            if not {"dbp.html", "dbp/dashboard.html"}.issubset(names):
                raise ValueError("FE archive is missing the dashboard export")
            if not any(name.startswith("_next/") for name in names):
                raise ValueError("FE archive is missing Next assets")
            if not any(name.startswith("static-assets/") for name in names):
                raise ValueError("FE archive is missing static assets")
            tar.extractall(output, filter="data")
        marker.write_text(digest)
    return output


def prepare(args):
    url = urllib.parse.urlsplit(args.privacy_config_url)
    if url.scheme != "https" or not url.hostname:
        raise ValueError("Provide an HTTPS privacy-configuration URL")
    output = prepare_artifact(args.cache_dir)
    changes = [
        (group_domain(CONFIG_SUITE), "isInternalUser", True),
        (group_domain(CONFIG_SUITE), "CustomConfigurationURL.privacyConfiguration",
         url_archive(args.privacy_config_url)),
        (group_domain(DBP_SUITE), "urlType", "custom"),
        (group_domain(DBP_SUITE), "customURLValue", f"http://127.0.0.1:{args.port}/dbp"),
        (group_domain(DBP_SUITE), "dbp.debug.testBrokerURLs", ["beenverified.com"]),
    ]
    if args.refresh_bundled_brokers:
        changes.append((group_domain(DBP_SUITE), "dbp.lastBrokerJSONUpdateCheckTimestamp", None))
        for bundle in ("com.duckduckgo.macos.browser.debug",
                       "com.duckduckgo.macos.DBP.backgroundAgent.debug"):
            changes.append((standard_domain(bundle), LOCAL_VERSION_KEY, None))
    backup = []
    for domain, key, _ in changes:
        values = read_domain(domain)
        previous = {"domain": str(domain), "key": key, "present": key in values}
        if key in values:
            previous["value"] = values[key]
        backup.append(previous)
    backup_path = args.cache_dir / f"preferences-before-{time.time_ns()}.plist"
    backup_path.write_bytes(plistlib.dumps(backup))
    os.chmod(backup_path, 0o600)
    for domain, key, value in changes:
        if value is None:
            if key in read_domain(domain):
                run("defaults", "delete", str(domain), key)
        else:
            write_value(domain, key, value)
    print(f"FE revision: {FE_REVISION}\nExport: {output}\nPreference backup: {backup_path}")
    print(f"Serve with: {Path(__file__)} serve --cache-dir {args.cache_dir} --port {args.port}")
    print("Launch the DEBUG browser separately with -privacyConfigURL and the same URL.")


def restore(args):
    for entry in plistlib.loads(args.backup.read_bytes()):
        if entry["present"]:
            write_value(entry["domain"], entry["key"], entry["value"])
        elif entry["key"] in read_domain(entry["domain"]):
            run("defaults", "delete", entry["domain"], entry["key"])
    print("Restored only the preference keys recorded in the backup.")


class ExportHandler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        parsed = urllib.parse.urlsplit(self.path)
        html_path = parsed.path.rstrip("/") + ".html"
        if not Path(self.translate_path(parsed.path)).is_file() and Path(self.translate_path(html_path)).is_file():
            self.path = urllib.parse.urlunsplit(("", "", html_path, parsed.query, ""))
        return super().send_head()


def serve(args):
    output = args.cache_dir / "out"
    if not (output / ".verified-artifact").exists():
        raise ValueError("Run prepare before serving")
    handler = lambda *a, **kw: ExportHandler(*a, directory=str(output), **kw)
    with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        print(f"Serving http://127.0.0.1:{args.port}/dbp", flush=True)
        server.serve_forever()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command, action in (("prepare", prepare), ("serve", serve)):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--cache-dir", type=Path, default=Path("/tmp/pir-assisted-testing"))
        subparser.add_argument("--port", type=int, default=8765)
        subparser.set_defaults(action=action)
        if command == "prepare":
            subparser.add_argument("privacy_config_url")
            subparser.add_argument("--refresh-bundled-brokers", action="store_true")
    subparser = subparsers.add_parser("restore")
    subparser.add_argument("backup", type=Path)
    subparser.set_defaults(action=restore)
    args = parser.parse_args()
    args.action(args)


if __name__ == "__main__":
    main()
