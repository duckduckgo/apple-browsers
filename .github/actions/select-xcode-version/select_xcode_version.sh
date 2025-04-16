#!/bin/bash
#
# This script selects the Xcode version based on the provided argument or the .xcode-version file.

set -e -o pipefail

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

    echo "xcode-version=$XCODE_VERSION" >> "$GITHUB_OUTPUT"
    
    XCODE_PATH="/Applications/Xcode_${XCODE_VERSION}.app/Contents/Developer"
    if [ ! -d "$XCODE_PATH" ]; then
      echo "::error::Xcode version $XCODE_VERSION not found at $XCODE_PATH"
      exit 1
    fi
    
    echo "Selecting Xcode version $XCODE_VERSION"
    sudo xcode-select -s "$XCODE_PATH"
}

main() {
    select_xcode_version "$1"
}

main "$@"