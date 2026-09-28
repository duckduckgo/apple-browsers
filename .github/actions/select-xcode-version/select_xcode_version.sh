#!/bin/bash
#
# This script selects the Xcode version based on the provided argument or the .xcode-version file.
#
# The name of the Xcode app is different on each type of runner. GitHub-hosted runners install
# "Xcode_26.4.app", and self-hosted runners install "Xcode-26.4.1.app", which always contains the
# patch component. Thus this script accepts both separators, and a version without a patch
# component matches the highest patch version that is installed.

set -e -o pipefail

# Prints the path to the Xcode app that matches the given version, or nothing if there is no match.
find_xcode_app() {
    local version="$1"
    local app
    local -a candidates=("/Applications/Xcode_${version}.app" "/Applications/Xcode-${version}.app")

    # If the version has no patch component, also accept any patch version, the highest one first.
    if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
      shopt -s nullglob
      local -a patch_candidates=(/Applications/Xcode[_-]"${version}".[0-9]*.app)
      shopt -u nullglob

      if [ ${#patch_candidates[@]} -gt 0 ]; then
        while IFS= read -r app; do
          candidates+=("$app")
        done < <(printf '%s\n' "${patch_candidates[@]}" | sort -Vr)
      fi
    fi

    for app in "${candidates[@]}"; do
      if [ -d "$app/Contents/Developer" ]; then
        echo "$app"
        return
      fi
    done
}

select_xcode_version() {
    # Use the first argument as the Xcode version, if provided.
    if [ -n "$1" ]; then
      XCODE_VERSION="$1"
      echo "Using provided Xcode version: $XCODE_VERSION"
    else
      # Otherwise, read from the .xcode-version file at the repository root.
      VERSION_FILE="$GITHUB_WORKSPACE/.xcode-version"
      if [ ! -f "$VERSION_FILE" ]; then
        echo "::error::No version provided and .xcode-version file not found"
        exit 1
      fi
      
      XCODE_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
      echo "Using Xcode version from file: $XCODE_VERSION"
    fi

    XCODE_APP=$(find_xcode_app "$XCODE_VERSION")
    if [ -z "$XCODE_APP" ]; then
      echo "::error::Xcode version $XCODE_VERSION not found in /Applications"
      exit 1
    fi

    # Report the version that is installed, which can contain a patch component.
    RESOLVED_VERSION=$(basename "$XCODE_APP" .app)
    RESOLVED_VERSION="${RESOLVED_VERSION#Xcode[_-]}"
    echo "xcode-version=$RESOLVED_VERSION" >> "$GITHUB_OUTPUT"

    XCODE_PATH="$XCODE_APP/Contents/Developer"
    echo "Selecting Xcode version $RESOLVED_VERSION at $XCODE_PATH"
    sudo xcode-select -s "$XCODE_PATH"
}

main() {
    select_xcode_version "$1"
}

main "$@"