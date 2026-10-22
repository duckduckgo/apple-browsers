#!/bin/bash
# Build test/server targets once with the same native Xcode used by their consumers.
set -euo pipefail
runner_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
macos_dir="$(cd "$runner_dir/../../.." && pwd)"
distribution="${1:?Usage: build.sh dmg|appstore DERIVED_DATA [xcodebuild settings...]}"
derived_data="${2:?Missing DerivedData path}"
shift 2
scheme='macOS UI Test Artifacts'
extra=()
if [[ "$distribution" == appstore ]]; then
    scheme+=' App Store'
    extra+=(UI_TESTS_TARGET_APP=sandbox)
elif [[ "$distribution" != dmg ]]; then
    echo 'Expected dmg or appstore' >&2
    exit 1
fi
architecture=(ONLY_ACTIVE_ARCH=YES)
if [[ -n "${UI_TEST_ARTIFACT_ARCHS:-}" ]]; then
    architecture=(ONLY_ACTIVE_ARCH=NO "ARCHS=$UI_TEST_ARTIFACT_ARCHS")
fi
cd "$macos_dir"
# Native compilers select versioned package manifests with different dependencies.
# Let SwiftPM resolve that graph instead of forcing the app compiler's lockfile.
# Xcode <27 also crashes when older manifests see surplus pins in newer lockfiles:
# https://developer.apple.com/forums/thread/773478
xcode_major=$(xcrun xcodebuild -version | awk '/^Xcode / { split($2, version, "."); print version[1] }')
if (( xcode_major < 27 )); then
    repo_root=$(git rev-parse --show-toplevel)
    saved_locks=$(mktemp -d)
    lockfiles=()
    restore_locks() {
        for lockfile in ${lockfiles[@]+"${lockfiles[@]}"}; do
            cp -p "$saved_locks/$lockfile" "$repo_root/$lockfile"
        done
        rm -rf "$saved_locks"
    }
    trap restore_locks EXIT
    while IFS= read -r -d '' lockfile; do
        [[ -f "$repo_root/$lockfile" ]] || continue
        mkdir -p "$saved_locks/$(dirname "$lockfile")"
        cp -p "$repo_root/$lockfile" "$saved_locks/$lockfile"
        lockfiles+=("$lockfile")
        rm "$repo_root/$lockfile"
    done < <(git -C "$repo_root" ls-files -z -- 'SharedPackages/**/Package.resolved' 'macOS/**/Package.resolved')
fi
xcrun xcodebuild build-for-testing \
    -project DuckDuckGo-macOS.xcodeproj \
    -scheme "$scheme" \
    -configuration Review \
    -derivedDataPath "$derived_data" \
    -destination 'platform=macOS' \
    -enableCodeCoverage NO \
    -skipPackagePluginValidation -skipMacroValidation \
    TEST_TARGET_NAME= "${architecture[@]}" \
    ${extra[@]+"${extra[@]}"} "$@"
