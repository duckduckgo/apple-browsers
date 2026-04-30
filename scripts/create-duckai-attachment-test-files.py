#!/usr/bin/env python3

import argparse
from pathlib import Path
import zipfile


FREE_MAX_BYTES = 5_242_880
PAID_MAX_BYTES = 26_214_400


def pdf_text(text):
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def create_pdf(page_count, target_size=None):
    objects = []

    kids = " ".join(f"{3 + index * 2} 0 R" for index in range(page_count))
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objects.append(f"<< /Type /Pages /Count {page_count} /Kids [{kids}] >>".encode("ascii"))

    for page_index in range(page_count):
        page_number = page_index + 1
        page_object = 3 + page_index * 2
        content_object = page_object + 1
        page = (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            f"/Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> "
            f"/Contents {content_object} 0 R >>"
        )
        text = pdf_text(f"Duck.ai attachment test file - page {page_number} of {page_count}")
        stream = f"BT /F1 18 Tf 72 720 Td ({text}) Tj ET".encode("ascii")
        content = b"<< /Length " + str(len(stream)).encode("ascii") + b" >>\nstream\n" + stream + b"\nendstream"
        objects.append(page.encode("ascii"))
        objects.append(content)

    output = bytearray(b"%PDF-1.4\n")
    offsets = []

    for index, obj in enumerate(objects, start=1):
        offsets.append(len(output))
        output.extend(f"{index} 0 obj\n".encode("ascii"))
        output.extend(obj)
        output.extend(b"\nendobj\n")

    xref_offset = len(output)
    output.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    output.extend(b"0000000000 65535 f \n")
    for offset in offsets:
        output.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    output.extend(
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref_offset}\n%%EOF\n".encode("ascii")
    )

    if target_size is not None and len(output) < target_size:
        output.extend(b"\n% padding\n")
        output.extend(b"0" * (target_size - len(output)))

    return bytes(output)


def write_file(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def create_files(output_dir):
    output_dir.mkdir(parents=True, exist_ok=True)

    files = {
        "01-valid-small.pdf": create_pdf(page_count=1),
        "02-valid-free-max-pages-15.pdf": create_pdf(page_count=15),
        "03-over-free-page-limit-16.pdf": create_pdf(page_count=16),
        "04-over-pro-page-limit-51.pdf": create_pdf(page_count=51),
        "05-over-free-size-5mb.pdf": create_pdf(page_count=1, target_size=FREE_MAX_BYTES + 1),
        "06-over-paid-size-25mb.pdf": create_pdf(page_count=1, target_size=PAID_MAX_BYTES + 1),
        "07-unsupported-text-file.txt": b"This text file should be rejected because Duck.ai document attachment currently supports PDF only.\n",
    }

    for filename, content in files.items():
        write_file(output_dir / filename, content)

    readme = """Duck.ai attachment manual test files

01-valid-small.pdf
- Should attach for all tiers.

02-valid-free-max-pages-15.pdf
- Should attach for Free, Plus, and Pro.

03-over-free-page-limit-16.pdf
- Should be rejected on Free.
- Should attach for Plus and Pro.

04-over-pro-page-limit-51.pdf
- Should be rejected on all tiers.

05-over-free-size-5mb.pdf
- Should be rejected on Free.
- Should attach for Plus and Pro if total file budget is still available.

06-over-paid-size-25mb.pdf
- Should be rejected on all tiers.

07-unsupported-text-file.txt
- Should be unavailable or rejected because only application/pdf is supported.

For the independent-counter check on Free/GPT-5 Mini, attach 3 images from Photos and 3 valid PDFs in one prompt.
"""
    (output_dir / "README.txt").write_text(readme, encoding="utf-8")
    return sorted([*files.keys(), "README.txt"])


def zip_files(output_dir, filenames):
    zip_path = output_dir.with_suffix(".zip")
    if zip_path.exists():
        zip_path.unlink()

    with zipfile.ZipFile(zip_path, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
        for filename in filenames:
            archive.write(output_dir / filename, arcname=filename)

    return zip_path


def main():
    parser = argparse.ArgumentParser(description="Create Duck.ai attachment manual test files.")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path.home() / "Desktop" / "DuckAI Attachment Test Files",
        help="Directory to create. Existing directory will be replaced.",
    )
    parser.add_argument("--no-zip", action="store_true", help="Skip creating a zip next to the output directory.")
    args = parser.parse_args()

    output_dir = args.output.expanduser().resolve()
    filenames = create_files(output_dir)

    print(f"Created {output_dir}")
    for filename in filenames:
        file_path = output_dir / filename
        print(f"{file_path.name}\t{file_path.stat().st_size} bytes")

    if not args.no_zip:
        zip_path = zip_files(output_dir, filenames)
        print(f"Created {zip_path}")


if __name__ == "__main__":
    main()
