#!/usr/bin/env python3
"""
Prepare scoped localization files for Smartling upload.

Compares exported XLIFF/stringsdict from HEAD against a baseline export from
the merge base with main. Only new or modified translation units are kept.

Since XLIFF files are generated at export time (not tracked in git), we create
a temporary worktree at the merge base, run the same export there, and diff
the two exports at the translation-unit level. This ensures that strings
discovered at export time (e.g. new keys extracted from Swift code) are
correctly included.

Usage:
    python3 prepare_scoped_upload.py \
        --platform iOS \
        --base-ref origin/main \
        --files en.xliff Localizable.stringsdict

Copyright © 2025 DuckDuckGo. All rights reserved.
Licensed under the Apache License, Version 2.0
"""

import argparse
import atexit
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

# Global worktree path for cleanup on signal/exit
_worktree_to_cleanup: Path | None = None


def _cleanup_on_exit():
    """atexit handler: remove worktree if still present."""
    if _worktree_to_cleanup and _worktree_to_cleanup.exists():
        print("🧹 Cleaning up baseline worktree (atexit)...")
        cleanup_worktree(_worktree_to_cleanup)


def _signal_handler(signum, _frame):
    """Handle SIGINT/SIGTERM: cleanup and exit."""
    if _worktree_to_cleanup and _worktree_to_cleanup.exists():
        print(f"\n🧹 Cleaning up baseline worktree (signal {signum})...")
        cleanup_worktree(_worktree_to_cleanup)
    sys.exit(128 + signum)


atexit.register(_cleanup_on_exit)
signal.signal(signal.SIGINT, _signal_handler)
signal.signal(signal.SIGTERM, _signal_handler)


# ============================================================================
# Git helpers
# ============================================================================

def fetch_base_ref(base_ref: str):
    """Fetch the base ref to ensure it's up to date before computing merge base."""
    parts = base_ref.split('/', 1)
    if len(parts) == 2:
        remote, branch = parts
        print(f"📡 Fetching {remote}/{branch} to ensure baseline is current...")
        result = subprocess.run(
            ['git', 'fetch', remote, branch],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(f"Failed to fetch {base_ref}: {result.stderr.strip()}")
    else:
        print(f"⚠️  base-ref '{base_ref}' is not remote-qualified; skipping fetch")


def get_merge_base(base_ref: str) -> str:
    """Get the merge base between base_ref and HEAD."""
    result = subprocess.run(
        ['git', 'merge-base', base_ref, 'HEAD'],
        capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


# ============================================================================
# Baseline export via worktree
# ============================================================================

def export_baseline(platform: str, merge_base_sha: str) -> Path:
    """Create a worktree at merge_base_sha and run the platform export.

    Returns the worktree path. Caller is responsible for cleanup.
    Raises RuntimeError if the baseline export fails.
    """
    global _worktree_to_cleanup

    worktree_dir = Path(tempfile.mkdtemp(prefix='smartling_baseline_'))
    _worktree_to_cleanup = worktree_dir
    print(f"📂 Creating baseline worktree at {merge_base_sha[:10]}...")

    subprocess.run(
        ['git', 'worktree', 'add', '--detach', str(worktree_dir), merge_base_sha],
        check=True, capture_output=True, text=True,
    )

    # Initialize submodules in the worktree (export scripts may depend on them)
    subprocess.run(
        ['git', 'submodule', 'update', '--init', '--recursive'],
        cwd=str(worktree_dir), capture_output=True, text=True,
    )

    export_script = worktree_dir / platform / 'scripts' / 'loc_export.sh'
    if not export_script.exists():
        raise RuntimeError(
            f"Baseline export script not found at {export_script}. "
            f"Cannot scope upload without a baseline export."
        )

    print(f"🔨 Running baseline export for {platform}...")
    env = os.environ.copy()
    # Suppress `open` commands that the export scripts call at the end
    env['__CF_USER_TEXT_ENCODING'] = env.get('__CF_USER_TEXT_ENCODING', '0x1F5:0x0:0x0')

    result = subprocess.run(
        ['bash', '-c', f'set -e -o pipefail; cd "{worktree_dir}" && ./{platform}/scripts/loc_export.sh 2>&1 | xcbeautify 2>/dev/null'],
        env=env, capture_output=True, text=True, timeout=600,
    )

    if result.returncode != 0:
        stderr_tail = ''
        if result.stderr:
            stderr_tail = '\n'.join(result.stderr.strip().split('\n')[-5:])
        raise RuntimeError(
            f"Baseline export failed (exit {result.returncode}). "
            f"Cannot scope upload without a successful baseline.\n{stderr_tail}"
        )

    return worktree_dir


def resolve_baseline_files(worktree_dir: Path, platform: str, head_files: list[Path]) -> dict[str, bytes | None]:
    """Find baseline equivalents of the HEAD export files in the worktree.

    Returns {filename: bytes_or_None}.
    """
    baseline = {}
    for head_file in head_files:
        filename = head_file.name

        # Search known export output locations
        candidates = []
        if platform == 'iOS':
            candidates = [
                worktree_dir / 'iOS' / 'scripts' / 'assets' / 'loc' / 'en.xcloc' / 'Localized Contents' / filename,
                worktree_dir / 'iOS' / 'DuckDuckGo' / 'en.lproj' / filename,
            ]
        elif platform == 'macOS':
            candidates = [
                worktree_dir / 'macOS' / 'scripts' / 'assets' / 'loc' / filename,
            ]

        found = None
        for candidate in candidates:
            if candidate.exists():
                found = candidate.read_bytes()
                print(f"   📄 Baseline found: {candidate.relative_to(worktree_dir)}")
                break

        baseline[filename] = found

    return baseline


def cleanup_worktree(worktree_dir: Path):
    """Remove the temporary worktree."""
    try:
        subprocess.run(
            ['git', 'worktree', 'remove', '--force', str(worktree_dir)],
            capture_output=True, text=True,
        )
    except Exception:
        # Fallback: just delete the directory
        shutil.rmtree(worktree_dir, ignore_errors=True)


# ============================================================================
# XLIFF Scoping
# ============================================================================

XLIFF_NS = 'urn:oasis:names:tc:xliff:document:1.2'


def parse_xliff_units(xliff_bytes: bytes) -> dict[str, str]:
    """Parse XLIFF and return {unit_id: source_text} for all trans-units."""
    root = ET.fromstring(xliff_bytes)
    units = {}
    for tu in root.iter(f'{{{XLIFF_NS}}}trans-unit'):
        unit_id = tu.get('id', '')
        source_el = tu.find(f'{{{XLIFF_NS}}}source')
        source_text = source_el.text or '' if source_el is not None else ''
        units[unit_id] = source_text
    return units


def filter_xliff(current_bytes: bytes, base_bytes: bytes | None) -> tuple[bytes | None, int, int]:
    """Filter XLIFF to only contain new or modified trans-units.

    Returns (filtered_bytes, total_units, kept_units).
    filtered_bytes is None if no units remain.
    """
    base_units = parse_xliff_units(base_bytes) if base_bytes else {}
    current_units = parse_xliff_units(current_bytes)

    changed_ids = set()
    for unit_id, source_text in current_units.items():
        if unit_id not in base_units or base_units[unit_id] != source_text:
            changed_ids.add(unit_id)

    if not changed_ids:
        return None, len(current_units), 0

    # Filter the XLIFF tree: remove unchanged trans-units
    ET.register_namespace('', XLIFF_NS)
    root = ET.fromstring(current_bytes)

    for body in root.iter(f'{{{XLIFF_NS}}}body'):
        for tu in list(body.iter(f'{{{XLIFF_NS}}}trans-unit')):
            if tu.get('id', '') not in changed_ids:
                # Walk tree to find actual parent and remove
                for parent in root.iter():
                    if tu in list(parent):
                        parent.remove(tu)
                        break

    # Remove empty groups
    for body in root.iter(f'{{{XLIFF_NS}}}body'):
        for group in list(body.iter(f'{{{XLIFF_NS}}}group')):
            if not list(group.iter(f'{{{XLIFF_NS}}}trans-unit')):
                for parent in root.iter():
                    if group in list(parent):
                        parent.remove(group)
                        break

    # Remove empty file blocks
    for file_el in list(root.iter(f'{{{XLIFF_NS}}}file')):
        body = file_el.find(f'{{{XLIFF_NS}}}body')
        if body is not None and not list(body):
            root.remove(file_el)

    output = ET.tostring(root, encoding='unicode', xml_declaration=True)
    return output.encode('utf-8'), len(current_units), len(changed_ids)


# ============================================================================
# Stringsdict Scoping
# ============================================================================

def filter_stringsdict(current_bytes: bytes, base_bytes: bytes | None) -> tuple[bytes | None, int, int]:
    """Filter stringsdict to only contain new or modified entries.

    Returns (filtered_bytes, total_entries, kept_entries).
    filtered_bytes is None if no entries remain.
    """
    current_dict = plistlib.loads(current_bytes)
    base_dict = plistlib.loads(base_bytes) if base_bytes else {}

    changed_keys = set()
    for key, value in current_dict.items():
        if key not in base_dict or base_dict[key] != value:
            changed_keys.add(key)

    if not changed_keys:
        return None, len(current_dict), 0

    filtered = {k: v for k, v in current_dict.items() if k in changed_keys}
    output = plistlib.dumps(filtered, fmt=plistlib.FMT_XML)
    return output, len(current_dict), len(changed_keys)


# ============================================================================
# Main
# ============================================================================

def scope_file(
    file_path: Path,
    baseline_data: bytes | None,
    output_dir: Path,
) -> tuple[Path | None, int]:
    """Scope a single file against its baseline.

    Returns (output_path_or_None, kept_unit_count).
    """
    current_bytes = file_path.read_bytes()

    suffix = file_path.suffix.lower()
    if suffix == '.xliff':
        filtered, total, kept = filter_xliff(current_bytes, baseline_data)
    elif suffix == '.stringsdict':
        filtered, total, kept = filter_stringsdict(current_bytes, baseline_data)
    else:
        print(f"⚠️  Unsupported file type: {file_path.name}, passing through unchanged")
        out_path = output_dir / file_path.name
        out_path.write_bytes(current_bytes)
        return out_path, 0

    print(f"📊 {file_path.name}: {kept}/{total} units changed")

    if filtered is None:
        return None, 0

    out_path = output_dir / file_path.name
    out_path.write_bytes(filtered)
    return out_path, kept


def main():
    parser = argparse.ArgumentParser(description='Prepare scoped upload files')
    parser.add_argument('--platform', required=True, choices=['iOS', 'macOS'],
                        help='Platform (iOS or macOS)')
    parser.add_argument('--base-ref', default='origin/main',
                        help='Git ref to compare against (default: origin/main)')
    parser.add_argument('--files', nargs='+', required=True,
                        help='Exported localization files from HEAD to scope')
    args = parser.parse_args()

    files = [Path(f) for f in args.files]
    for f in files:
        if not f.exists():
            print(f"❌ File not found: {f}")
            sys.exit(1)

    global _worktree_to_cleanup

    # Step 1: Fetch base ref and compute merge base
    fetch_base_ref(args.base_ref)
    merge_base = get_merge_base(args.base_ref)
    print(f"🔀 Merge base: {merge_base[:10]}")

    # Step 2: Create worktree and run baseline export
    worktree_dir = None
    try:
        worktree_dir = export_baseline(args.platform, merge_base)

        # Step 3: Resolve baseline files
        print("🔍 Resolving baseline files...")
        baseline = resolve_baseline_files(worktree_dir, args.platform, files)

        # Step 4: Diff and filter
        output_dir = Path(tempfile.mkdtemp(prefix='smartling_scoped_'))
        print(f"📁 Output directory: {output_dir}")

        scoped_files = []
        total_units = 0
        for file_path in files:
            baseline_data = baseline.get(file_path.name)
            if baseline_data is None:
                print(f"   ℹ️  No baseline for {file_path.name} — treating all units as new")
            result_path, kept = scope_file(file_path, baseline_data, output_dir)
            if result_path:
                scoped_files.append(result_path)
                total_units += kept

        if not scoped_files:
            print("⚠️  No translatable changes found on this branch relative to base.")
            print("SCOPED_FILES=")
            print("SCOPED_UNIT_COUNT=0")
            sys.exit(1)

        # Output paths and counts for consumption by shell scripts
        paths_str = ' '.join(str(p) for p in scoped_files)
        print(f"SCOPED_FILES={paths_str}")
        print(f"SCOPED_UNIT_COUNT={total_units}")
        print(f"\n✅ Prepared {len(scoped_files)} scoped file(s), {total_units} translation unit(s) for upload")

    finally:
        # Step 5: Cleanup worktree
        if worktree_dir and worktree_dir.exists():
            print("🧹 Cleaning up baseline worktree...")
            cleanup_worktree(worktree_dir)
            _worktree_to_cleanup = None


if __name__ == '__main__':
    main()
