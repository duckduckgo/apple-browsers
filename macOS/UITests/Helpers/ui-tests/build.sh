#!/bin/bash
# One build graph lets Xcode schedule the app and test targets and share package products.
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
cd "$macos_dir"
xcrun xcodebuild build-for-testing \
    -project DuckDuckGo-macOS.xcodeproj \
    -scheme "$scheme" \
    -configuration Review \
    -derivedDataPath "$derived_data" \
    -destination 'platform=macOS' \
    -enableCodeCoverage NO \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation -skipMacroValidation \
    ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' \
    ${extra[@]+"${extra[@]}"} "$@"
