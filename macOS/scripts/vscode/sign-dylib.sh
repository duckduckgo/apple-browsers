#!/usr/bin/env bash
#
# Signs the DuckDuckGoBrowserDynamic library built by `swift build` and the frameworks it loads
# with the identity of the host app (see make-host-app.sh).
#
# The host app is signed with the hardened runtime and has system extension entitlements, so it can only
# load code signed by the same team: library validation can't be disabled for it.

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [--products PATH]

Signs libDuckDuckGoBrowserDynamic.dylib and the frameworks next to it with the host app's identity.

Options:
  --products PATH  swift build products directory (default: macOS/.build/DuckDuckGo/out/Products/Debug)
  -h, --help       Show this help message
EOF
}

script_dir="$(cd "$(dirname "$0")" && pwd)"
package_dir="$(cd "${script_dir}/../../DuckDuckGo" && pwd)"
build_dir="$(cd "${package_dir}/.." && pwd)/.build"
products="${build_dir}/DuckDuckGo/out/Products/Debug"
identity_file="${build_dir}/vscode-host/identity"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --products) products="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

if [[ ! -f "$identity_file" ]]; then
    echo "Host app identity not found; run make-host-app.sh first"
    exit 1
fi
identity="$(cat "$identity_file")"

dylib="${products}/libDuckDuckGoBrowserDynamic.dylib"
# Only the frameworks the library links; some products (e.g. static xcframeworks) aren't valid bundles to sign.
for name in $(otool -L "$dylib" | sed -n 's#^[[:space:]]*@rpath/\([^/]*\)\.framework/.*#\1#p' | sort -u); do
    codesign --force --sign "$identity" --timestamp=none "${products}/${name}.framework"
done
codesign --force --sign "$identity" --timestamp=none "$dylib"
echo "Signed ${dylib} (${identity})"
