#!/usr/bin/env python3
"""Point the DEBUG browser at a PIR dashboard and privacy configuration for assisted opt-out testing."""

import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import time
import urllib.parse


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


def https_url(value):
    url = urllib.parse.urlsplit(value)
    if url.scheme != "https" or not url.hostname:
        raise argparse.ArgumentTypeError(f"not an HTTPS URL: {value}")
    return value


def prepare(args):
    changes = [
        (group_domain(CONFIG_SUITE), "isInternalUser", True),
        (group_domain(CONFIG_SUITE), "CustomConfigurationURL.privacyConfiguration",
         url_archive(args.privacy_config_url)),
        (group_domain(DBP_SUITE), "urlType", "custom"),
        (group_domain(DBP_SUITE), "customURLValue", args.dashboard_url),
        (group_domain(DBP_SUITE), "dbp.debug.testBrokerURLs", ["beenverified.com"]),
    ]
    if args.refresh_bundled_brokers:
        changes.append((group_domain(DBP_SUITE), "dbp.lastBrokerJSONUpdateCheckTimestamp", None))
        for bundle in ("com.duckduckgo.macos.browser.debug",
                       "com.duckduckgo.macos.DBP.backgroundAgent.debug"):
            changes.append((standard_domain(bundle), LOCAL_VERSION_KEY, None))
    if any(isinstance(domain, Path) and not domain.parent.is_dir() for domain, _, _ in changes):
        raise SystemExit("Launch and quit the DEBUG browser once before preparing")
    backup = []
    for domain, key, _ in changes:
        values = read_domain(domain)
        previous = {"domain": str(domain), "key": key, "present": key in values}
        if key in values:
            previous["value"] = values[key]
        backup.append(previous)
    args.backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path = args.backup_dir / f"preferences-before-{time.time_ns()}.plist"
    backup_path.write_bytes(plistlib.dumps(backup))
    os.chmod(backup_path, 0o600)
    for domain, key, value in changes:
        if value is None:
            if key in read_domain(domain):
                run("defaults", "delete", str(domain), key)
        else:
            write_value(domain, key, value)
    print(f"Dashboard: {args.dashboard_url}\nPreference backup: {backup_path}")
    print("Launch the DEBUG browser with -privacyConfigURL and the same privacy-configuration URL.")


def restore(args):
    for entry in plistlib.loads(args.backup.read_bytes()):
        if entry["present"]:
            write_value(entry["domain"], entry["key"], entry["value"])
        elif entry["key"] in read_domain(entry["domain"]):
            run("defaults", "delete", entry["domain"], entry["key"])
    print("Restored only the preference keys recorded in the backup.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparser = subparsers.add_parser("prepare")
    subparser.add_argument("privacy_config_url", type=https_url)
    subparser.add_argument("dashboard_url", type=https_url)
    subparser.add_argument("--refresh-bundled-brokers", action="store_true")
    subparser.add_argument("--backup-dir", type=Path,
                           default=Path.home() / "Library/Application Support/pir-assisted-testing")
    subparser.set_defaults(action=prepare)
    subparser = subparsers.add_parser("restore")
    subparser.add_argument("backup", type=Path)
    subparser.set_defaults(action=restore)
    args = parser.parse_args()
    args.action(args)


if __name__ == "__main__":
    main()
