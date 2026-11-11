#!/usr/bin/env python3
"""Run the same metadata server exported by the App Store Debug menu."""

import json
from pathlib import Path
import runpy
import tempfile
import textwrap


def main():
    root = Path(__file__).resolve().parents[1]
    source = root / "macOS/DuckDuckGo/Updates/Sparkle/UpdatesDebugMenu.swift"
    text = source.read_text()
    marker = '\nprivate enum AppStoreTestingResources {\n    static let serverScript = #"""\n'
    if text.count(marker) != 1:
        raise RuntimeError("Expected one canonical App Store server literal.")
    body, separator, _ = text.split(marker, 1)[1].partition('\n    """#\n')
    if not separator or r"\#(" in body:
        raise RuntimeError("The App Store server literal has an unsupported delimiter or interpolation.")
    script = textwrap.dedent(body)
    configuration = root / "macOS/Configuration"
    version = (configuration / "Version.xcconfig").read_text().split("=", 1)[1].strip()
    build = int((configuration / "BuildNumber.xcconfig").read_text().split("=", 1)[1].strip())
    with tempfile.TemporaryDirectory(prefix="ddg-appstore-metadata-") as temporary:
        exported = Path(temporary) / "appstore-metadata-server.py"
        exported.write_text(script)
        exported.with_name("appstore-test-settings.json").write_text(json.dumps({
            "installed_version": version,
            "installed_build": build,
        }))
        runpy.run_path(str(exported), run_name="__main__")


if __name__ == "__main__":
    main()
