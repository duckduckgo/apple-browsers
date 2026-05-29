#!/usr/bin/env python3
"""
Encode a string (typically the install-page URL) as a QR code and write it to a
PNG file, using only the Python standard library plus the vendored qrcodegen.py.

Usage:
  generate_qr.py <text> <output-path> [scale] [border]

scale  - pixels per QR module (default 8)
border - quiet-zone width in modules on every side (default 4, the spec minimum)

The PNG is 8-bit grayscale: dark modules are black (0), everything else white
(255). We deliberately keep it dark-on-light regardless of theme so it scans
reliably; inverted QR codes confuse some scanners.
"""
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "third_party"))
import qrcodegen  # noqa: E402  (vendored third-party module, see third_party/)


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def _write_png(path: str, pixels: bytes, dimension: int) -> None:
    signature = b"\x89PNG\r\n\x1a\n"
    # Bit depth 8, color type 0 (grayscale), default compression/filter/interlace.
    ihdr = struct.pack(">IIBBBBB", dimension, dimension, 8, 0, 0, 0, 0)

    raw = bytearray()
    for y in range(dimension):
        raw.append(0)  # filter type 0 (None) for this scanline
        raw.extend(pixels[y * dimension:(y + 1) * dimension])

    with open(path, "wb") as f:
        f.write(signature)
        f.write(_png_chunk(b"IHDR", ihdr))
        f.write(_png_chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(_png_chunk(b"IEND", b""))


def main() -> int:
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <text> <output> [scale] [border]", file=sys.stderr)
        return 1

    text, output_path = sys.argv[1], sys.argv[2]
    scale = int(sys.argv[3]) if len(sys.argv) > 3 else 8
    border = int(sys.argv[4]) if len(sys.argv) > 4 else 4

    qr = qrcodegen.QrCode.encode_text(text, qrcodegen.QrCode.Ecc.MEDIUM)
    modules = qr.get_size()
    dimension = (modules + border * 2) * scale

    pixels = bytearray([255]) * (dimension * dimension)  # start all-white
    for y in range(modules):
        for x in range(modules):
            if not qr.get_module(x, y):
                continue
            top = (y + border) * scale
            left = (x + border) * scale
            for dy in range(scale):
                start = (top + dy) * dimension + left
                pixels[start:start + scale] = b"\x00" * scale

    _write_png(output_path, bytes(pixels), dimension)
    return 0


if __name__ == "__main__":
    sys.exit(main())
