#!/usr/bin/env bash
###############################################################################
#
# Several simulator runtimes (18.4, 18.5, 26.0) ship without the Swift
# overlay libswiftWebKit.dylib. This script copies the missing dylib from the
# runtime into $BUILT_PRODUCTS_DIR so the app can launch under those sims.
# Delete the script once Apple ships corrected runtimes.
###############################################################################
set -euo pipefail

readonly DYLIB_NAME="libswiftWebKit.dylib"

###############################################################################
# 1. Guard – run only for *iphonesimulator* builds
###############################################################################

if [[ "${PLATFORM_NAME:-}" != "iphonesimulator" ]]; then
    echo "ℹ️  Skipping $DYLIB_NAME workaround – PLATFORM_NAME='${PLATFORM_NAME:-unset}'"
    exit 0
fi

###############################################################################
# 2. Validate TARGET_DEVICE_OS_VERSION is available
###############################################################################

if [[ -z "${TARGET_DEVICE_OS_VERSION:-}" ]]; then
    echo "❌ TARGET_DEVICE_OS_VERSION environment variable is not set" >&2
    exit 1
fi

echo "ℹ️  Target device OS version: $TARGET_DEVICE_OS_VERSION"

###############################################################################
# 3. Configuration for supported versions (Bash 3.x compatible)
###############################################################################

get_build_id_for_version() {
    case "$1" in
        18.4*) echo "22E238" ;;
        18.5*) echo "22F77" ;;
        *) return 1 ;;
    esac
}

get_runtime_dylib_path() {
    local version="$1"
    local build_id
    
    build_id="$(get_build_id_for_version "$version")" || return 1
    
    echo "/Library/Developer/CoreSimulator/Volumes/iOS_${build_id}/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS ${version}.simruntime/Contents/Resources/RuntimeRoot/System/Cryptexes/OS/usr/lib/swift/$DYLIB_NAME"
}

###############################################################################
# 4. Check if workaround is needed and find the dylib
###############################################################################

find_matching_runtime() {
    local target_version="$1"
    local runtime_path
    
    runtime_path="$(get_runtime_dylib_path "$target_version")" || {
        return 1
    }
    
    if [[ -f "$runtime_path" ]]; then
        echo "$runtime_path"
        return 0
    else
        echo "⚠️  Runtime dylib not found at: $runtime_path" >&2
        echo "⚠️  Make sure iOS ${target_version%.*} simulator runtime is installed" >&2
        return 1
    fi
}

RUNTIME_DYLIB="$(find_matching_runtime "$TARGET_DEVICE_OS_VERSION")" || {
    echo "✅ Runtime iOS $TARGET_DEVICE_OS_VERSION doesn't require $DYLIB_NAME workaround"
    exit 0
}

###############################################################################
# 5. Validate environment and paths
###############################################################################

if [[ -z "${BUILT_PRODUCTS_DIR:-}" ]]; then
    echo "❌ BUILT_PRODUCTS_DIR environment variable is not set" >&2
    exit 1
fi

if [[ ! -d "$BUILT_PRODUCTS_DIR" ]]; then
    echo "❌ Build products directory does not exist: $BUILT_PRODUCTS_DIR" >&2
    exit 1
fi

###############################################################################
# 6. Copy the overlay into the build products directory
###############################################################################

DESTINATION="$BUILT_PRODUCTS_DIR/$DYLIB_NAME"

# Skip if files are identical
if [[ -f "$DESTINATION" ]] && cmp -s "$RUNTIME_DYLIB" "$DESTINATION"; then
    echo "ℹ️  $DYLIB_NAME already exists and is identical"
    exit 0
fi

echo "🏗️  Copying $RUNTIME_DYLIB → $DESTINATION"

if /bin/cp -f "$RUNTIME_DYLIB" "$DESTINATION" && /bin/chmod 644 "$DESTINATION"; then
    echo "✅ Successfully applied $DYLIB_NAME workaround for iOS $TARGET_DEVICE_OS_VERSION"
else
    echo "❌ Failed to copy $DYLIB_NAME" >&2
    exit 1
fi