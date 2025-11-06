#!/bin/bash
set -e  # Exit on any error

echo "🔍 Phase 1: Environment Detection"
echo "================================="

# Detect workspace
WORKSPACE_DIR=$(pwd)
WORKSPACE_FILE=$(find . -name "DuckDuckGo.xcworkspace" | head -1)
if [ -z "$WORKSPACE_FILE" ]; then
    echo "❌ Error: No DuckDuckGo.xcworkspace found"
    echo "Make sure you're in the project root directory"
    exit 1
fi
WORKSPACE="${WORKSPACE_DIR}/${WORKSPACE_FILE#./}"
echo "✅ Workspace: ${WORKSPACE}"

# Detect architecture
ARCH=$(uname -m)
echo "✅ Architecture: ${ARCH}"

# Find iOS simulator
SIMULATOR_ID=$(xcrun simctl list devices | grep -E "iPhone.*\([A-F0-9-]{36}\)" | head -1 | grep -oE "[A-F0-9-]{36}")
if [ -z "$SIMULATOR_ID" ]; then
    echo "⚠️  Warning: No iOS simulator found"
    echo "iOS build will be skipped"
else
    echo "✅ Simulator ID: ${SIMULATOR_ID}"
fi

# Check xcbeautify
if ! command -v xcbeautify &> /dev/null; then
    echo "❌ Error: xcbeautify not found"
    echo "Install with: brew install xcbeautify"
    exit 1
fi
echo "✅ xcbeautify: installed"

echo ""
echo "🏗️  Phase 2: Building Apps"
echo "========================"

# Build iOS if simulator available
if [ -n "$SIMULATOR_ID" ]; then
    echo ""
    echo "📱 Building iOS Browser..."
    /bin/sh -c "set -e -o pipefail && xcodebuild \
      ONLY_ACTIVE_ARCH=YES \
      DEBUG_INFORMATION_FORMAT=dwarf \
      COMPILER_INDEX_STORE_ENABLE=NO \
      -scheme 'iOS Browser' \
      -configuration Debug \
      -workspace ${WORKSPACE} \
      -destination 'platform=iOS Simulator,id=${SIMULATOR_ID}' \
      -allowProvisioningUpdates \
      -parallelizeTargets \
      build | xcbeautify"
    echo "✅ iOS Browser built successfully"
fi

# Build macOS
echo ""
echo "💻 Building macOS Browser..."
/bin/sh -c "set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme 'macOS Browser' \
  -configuration Debug \
  -workspace ${WORKSPACE} \
  -destination 'platform=macOS,arch=${ARCH}' \
  -allowProvisioningUpdates \
  -disableAutomaticPackageResolution \
  -parallelizeTargets \
  build | xcbeautify"
echo "✅ macOS Browser built successfully"

echo ""
echo "🎉 All builds completed successfully!"

