#!/bin/bash
set -euo pipefail

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive_checksum="9f7830a54a45699d26e5293de5af0195296369ec55c0e2edd324f17b7ee147dd"
archive_url="https://github.com/nchapman/trafilatura-rs/releases/download/v0.5.0/TrafilaturaFFI.xcframework.zip"
mkdir -p "$package_dir/Vendor"
staging_dir="$(mktemp -d "$package_dir/Vendor/.prepare.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

# An optional local archive allows offline preparation with the same checksum verification.
if [[ $# -gt 0 ]]; then
    cp "$1" "$staging_dir/archive.zip"
else
    curl --fail --location --retry 3 "$archive_url" --output "$staging_dir/archive.zip"
fi
actual_checksum="$(shasum -a 256 "$staging_dir/archive.zip" | awk '{print $1}')"
if [[ "$actual_checksum" != "$archive_checksum" ]]; then
    echo "Trafilatura archive checksum mismatch: $actual_checksum" >&2
    exit 1
fi
unzip -q "$staging_dir/archive.zip" -d "$staging_dir"

# Xcode copies static-library headers into one shared include directory.
# Keep this module map under its own module name so Clibsodium can coexist.
for slice in ios-arm64 ios-arm64_x86_64-simulator macos-arm64_x86_64; do
    headers="$staging_dir/TrafilaturaFFI.xcframework/$slice/Headers"
    mkdir "$headers/TrafilaturaFFI"
    mv "$headers/module.modulemap" "$headers/TrafilaturaFFI.h" "$headers/TrafilaturaFFI/"
done
rm -rf "$package_dir/Vendor/TrafilaturaFFI.xcframework"
mv "$staging_dir/TrafilaturaFFI.xcframework" "$package_dir/Vendor/"
echo "Prepared Trafilatura v0.5.0 with namespaced headers."
