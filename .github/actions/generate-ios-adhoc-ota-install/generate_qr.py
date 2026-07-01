#!/usr/bin/env python3
"""
Encode a string (typically the install-page URL) as a QR code PNG.

Usage:
  generate_qr.py <text> <output-path> [scale] [border]

scale  - pixels per QR module (default 8)
border - quiet-zone width in modules on every side (default 4, the spec minimum)

Requires segno (see requirements.txt). The PNG is dark-on-light regardless of
theme so it scans reliably; inverted QR codes confuse some scanners. Medium
error correction balances size against resilience to a scuffed screen/camera.
"""
import sys

import segno


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <text> <output> [scale] [border]", file=sys.stderr)
        return 1

    text, output_path = sys.argv[1], sys.argv[2]
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    border = int(sys.argv[4]) if len(sys.argv) > 4 else 4

    segno.make(text, error="m").save(output_path, scale=scale, border=border)
    return 0


if __name__ == "__main__":
    sys.exit(main())
