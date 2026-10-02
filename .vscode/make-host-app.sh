#!/usr/bin/env bash
#
# Builds the host app used to run the browser from VSCode/Cursor.
#
# The host app is the Xcode-built "macOS Browser" Debug app (Info.plist, entitlements, bundle resources,
# embedded frameworks and login items) with its executable replaced by .vscode/launcher/launcher.c,
# which loads the DuckDuckGoBrowserDynamic library built by `swift build`. Swift code changes only need
# `swift build`; the host app is rebuilt when its non-Swift inputs change.

set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [--force] [--dylib PATH]

Builds macOS/.build/vscode-host/DuckDuckGo.app for running the browser from VSCode/Cursor.

Options:
  --force        Rebuild the host app even if its inputs didn't change
  --dylib PATH   Default DuckDuckGoBrowserDynamic library to load
                 (the DDG_BROWSER_DYLIB environment variable overrides it at launch)
  -h, --help     Show this help message
EOF
}

script_dir="$(cd "$(dirname "$0")" && pwd)"
package_dir="$(cd "${script_dir}/../macOS/DuckDuckGo" && pwd)"
macos_dir="$(cd "${package_dir}/.." && pwd)"
# Build output lives outside the package folder: Xcode scans the package folder it has open.
work_dir="${macos_dir}/.build/vscode-host"
# Outside the repo: Xcode shows the package checkouts in DerivedData as nested repositories otherwise.
derived_data="${HOME}/Library/Developer/Xcode/DerivedData/vscode-host-$(echo "$package_dir" | shasum | cut -c1-8)"
host_app="${work_dir}/DuckDuckGo.app"
stamp_file="${work_dir}/inputs.sha"
dylib="${macos_dir}/.build/DuckDuckGo/out/Products/Debug/libDuckDuckGoBrowserDynamic.dylib"
force=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force=1 ;;
        --dylib) dylib="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

# Swift sources live in the dylib; everything else ends up in the host app.
inputs_hash() {
    local paths=(DuckDuckGo DuckDuckGoAppBundle Configuration DuckDuckGo-macOS.xcodeproj/project.pbxproj)
    local exclude=(":(exclude,glob)DuckDuckGo/**/*.swift")
    {
        git -C "$macos_dir" ls-files -s -- "${paths[@]}" "${exclude[@]}"
        git -C "$macos_dir" diff HEAD -- "${paths[@]}" "${exclude[@]}"
        cat "${script_dir}/launcher/launcher.c" "$0"
        echo "$dylib"
    } | shasum | cut -d' ' -f1
}

mkdir -p "$work_dir"
hash="$(inputs_hash)"
if [[ $force -eq 0 && -d "$host_app" && -f "$stamp_file" && "$(cat "$stamp_file")" == "$hash" ]]; then
    echo "Host app is up to date: ${host_app}"
    exit 0
fi

# Shows build progress; the full log is kept in xcodebuild.log.
show_progress() {
    if command -v xcbeautify > /dev/null; then
        xcbeautify --disable-logging
        return
    fi
    # Without xcbeautify: one short line per build step ("SwiftCompile [VPNAppState]"), errors and the result.
    sed -l -n -E \
        -e "s/^([A-Za-z]+) .* \(in target '([^']+)' from project .*/\1 [\2]/p" \
        -e "/error:|\*\* BUILD/p" | uniq
}

build_log="${work_dir}/xcodebuild.log"
echo "Building the host app with Xcode (full log: ${build_log})…"
set +e
xcodebuild -project "${macos_dir}/DuckDuckGo-macOS.xcodeproj" \
    -scheme "macOS Browser" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    -onlyUsePackageVersionsFromResolvedFile \
    build 2>&1 | tee "$build_log" | show_progress
build_status=${PIPESTATUS[0]}
set -e
if [[ $build_status -ne 0 ]]; then
    echo "Xcode build failed, see ${build_log}"
    exit 1
fi
built_app="${derived_data}/Build/Products/Debug/DuckDuckGo.app"

echo "Assembling ${host_app}…"
rm -rf "$host_app"
ditto "$built_app" "$host_app"
# The browser code comes from the dylib; drop the copies Xcode linked into the app.
rm -f "${host_app}/Contents/MacOS/DuckDuckGo.debug.dylib" "${host_app}/Contents/MacOS/__preview.dylib"
xcrun clang -O2 -o "${host_app}/Contents/MacOS/DuckDuckGo" \
    -DDDG_DEFAULT_BROWSER_DYLIB="\"${dylib}\"" \
    "${script_dir}/launcher/launcher.c"

# Re-sign with the identity and entitlements Xcode used. The app has system extension entitlements, so the
# hardened runtime doesn't allow disable-library-validation: sign-dylib.sh signs the swift build output with
# the same identity instead, so library validation passes.
identity="$(codesign -dvv "$built_app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
identity="${identity:--}"
entitlements="${work_dir}/entitlements.plist"
codesign -d --entitlements - --xml "$built_app" > "$entitlements" 2>/dev/null || true
if [[ -s "$entitlements" ]]; then
    codesign --force --sign "$identity" --entitlements "$entitlements" --options runtime --timestamp=none "$host_app"
else
    codesign --force --sign "$identity" --options runtime --timestamp=none "$host_app"
fi
echo "$identity" > "${work_dir}/identity"

echo "$hash" > "$stamp_file"
echo "Host app is ready: ${host_app} (signed with: ${identity})"
