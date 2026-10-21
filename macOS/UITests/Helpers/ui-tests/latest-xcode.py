#!/usr/bin/env python3
"""Select the newest installed stable Xcode compatible with this host; no OS/Xcode matrix."""
import os
from pathlib import Path
import platform
import plistlib

host = tuple(map(int, platform.mac_ver()[0].split('.')))
candidates = []
for app in Path('/Applications').glob('Xcode*.app'):
    if 'beta' in app.name.lower():
        continue
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    minimum = tuple(map(int, info.get('LSMinimumSystemVersion', '0').split('.')))
    if minimum <= host:
        version = info['CFBundleShortVersionString']
        candidates.append((tuple(map(int, version.split('.'))), app, version))
if not candidates:
    raise SystemExit('No compatible full Xcode installed')
_, app, version = max(candidates)
developer = app / 'Contents/Developer'
if 'GITHUB_ENV' in os.environ:
    with open(os.environ['GITHUB_ENV'], 'a') as stream:
        stream.write('DEVELOPER_DIR=' + str(developer) + '\nCI_XCODE_VERSION=' + version + '\n')
print(developer)
