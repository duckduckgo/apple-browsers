if [[ -z "$BUILD_ROOT" ]]; then
  echo "BUILD_ROOT not specified, please run from Xcode"
  exit 1
fi

if [ "$CONFIGURATION" = "Release" ] || [ "$ENABLE_PREVIEWS" = "YES" ]; then exit 0; fi

LINTER_BASE="$BUILD_ROOT/../.."
LINTER=`find "$LINTER_BASE" | grep "\-macos/bin/swiftlint$"`

if [[ ! -f "$LINTER" ]]; then
  echo "swiftlint binary was not found - check project configuration"
  exit 1
fi

find "$SRCROOT" -type d -name ".build" -prune -o -name "Package.swift" -prune -o -name "*.swift" -print | xargs "$LINTER"
