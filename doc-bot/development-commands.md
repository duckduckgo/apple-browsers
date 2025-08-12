---
title: "Development Commands & Build Instructions"
description: "Essential commands for building, testing, and developing the DuckDuckGo browser applications"
keywords: ["build", "development", "commands", "Xcode", "simulator", "testing", "debugging"]
alwaysApply: true
---

# Development Commands & Build Instructions

## Build Commands Overview

### Build Command Structure
All build commands follow this pattern with configurable variables:
```bash
/bin/sh -c 'set -e -o pipefail && xcodebuild <BUILD_FLAGS> <OPTIONS> | xcbeautify'
```

### Standard Build Flags
These flags are used across all builds for optimal performance:
- `ONLY_ACTIVE_ARCH=YES` - Build only for active architecture (speeds up debug builds)
- `DEBUG_INFORMATION_FORMAT=dwarf` - Use DWARF debug format
- `COMPILER_INDEX_STORE_ENABLE=NO` - Disable index store for faster builds
- `-allowProvisioningUpdates` - Allow automatic provisioning profile updates
- `-disableAutomaticPackageResolution` - Disable automatic Swift package resolution
- `-parallelizeTargets` - Build targets in parallel when possible

## iOS Build Commands

### Full iOS Build Command Template
```bash
/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "iOS Browser" \
  -configuration Debug \
  -workspace <WORKSPACE_PATH> \
  -destination "platform=iOS Simulator,id=<SIMULATOR_ID>" \
  -allowProvisioningUpdates \
  -parallelizeTargets \
  -jobs <CPU_CORES> \
  build | xcbeautify'
```

### iOS Build Variables
| Variable | Description | How to Obtain | Example |
|----------|-------------|---------------|---------|
| `WORKSPACE_PATH` | Path to DuckDuckGo.xcworkspace | Find workspace: `find . -name "*.xcworkspace"` | `/Users/daniel/Developer/browser/apple-browsers/DuckDuckGo.xcworkspace` |
| `SIMULATOR_ID` | UUID of iOS simulator | `xcrun simctl list devices \| grep Booted` | `224A5BC3-3638-4B14-9203-1D6CC434ECAD` |
| `CPU_CORES` | Number of parallel jobs | `sysctl -n hw.ncpu` | `12` |

### Example iOS Build (Concrete Values)
```bash
/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "iOS Browser" \
  -configuration Debug \
  -workspace /Users/daniel/Developer/browser/apple-browsers/DuckDuckGo.xcworkspace \
  -destination "platform=iOS Simulator,id=224A5BC3-3638-4B14-9203-1D6CC434ECAD" \
  -allowProvisioningUpdates \
  -parallelizeTargets \
  -jobs 12 \
  build | xcbeautify'
```

## macOS Build Commands

### Full macOS Build Command Template
```bash
/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "macOS Browser" \
  -configuration Debug \
  -workspace <WORKSPACE_PATH> \
  -destination "platform=macOS,arch=<ARCHITECTURE>" \
  -allowProvisioningUpdates \
  -disableAutomaticPackageResolution \
  -parallelizeTargets \
  -jobs <CPU_CORES> \
  build | xcbeautify'
```

### macOS Build Variables
| Variable | Description | How to Obtain | Example |
|----------|-------------|---------------|---------|
| `WORKSPACE_PATH` | Path to DuckDuckGo.xcworkspace | Find workspace: `find . -name "*.xcworkspace"` | `/Users/daniel/Developer/browser/apple-browsers/DuckDuckGo.xcworkspace` |
| `ARCHITECTURE` | Target architecture | `uname -m` | `arm64` (Apple Silicon) or `x86_64` (Intel) |
| `CPU_CORES` | Number of parallel jobs | `sysctl -n hw.ncpu` | `12` |

### Example macOS Build (Concrete Values)
```bash
/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "macOS Browser" \
  -configuration Debug \
  -workspace /Users/daniel/Developer/browser/apple-browsers/DuckDuckGo.xcworkspace \
  -destination "platform=macOS,arch=arm64" \
  -allowProvisioningUpdates \
  -disableAutomaticPackageResolution \
  -parallelizeTargets \
  -jobs 12 \
  build | xcbeautify'
```

## Available Schemes
- `iOS Browser` - Main iOS browser app
- `macOS Browser` - Main macOS browser app (also referenced as "DuckDuckGo" in some contexts)
- `iOS Unit Tests` - iOS test suite
- `macOS Unit Tests` - macOS test suite

## Environment Detection Script
Use this script to automatically detect your build environment:
```bash
#!/bin/bash
# Auto-detect build environment variables

# Find workspace
WORKSPACE=$(find . -name "DuckDuckGo.xcworkspace" | head -1)
echo "Workspace: ${WORKSPACE}"

# Get CPU cores
CORES=$(sysctl -n hw.ncpu)
echo "CPU Cores: ${CORES}"

# Get architecture
ARCH=$(uname -m)
echo "Architecture: ${ARCH}"

# Find booted iOS simulator
SIMULATOR_ID=$(xcrun simctl list devices | grep -E "iPhone.*Booted" | head -1 | grep -oE "[A-F0-9-]{36}")
if [ -z "$SIMULATOR_ID" ]; then
    # Find any available simulator if none booted
    SIMULATOR_ID=$(xcrun simctl list devices | grep -E "iPhone" | head -1 | grep -oE "[A-F0-9-]{36}")
fi
echo "Simulator ID: ${SIMULATOR_ID:-none found}"

# Generate iOS build command
if [ -n "$WORKSPACE" ] && [ -n "$SIMULATOR_ID" ]; then
    echo ""
    echo "Generated iOS Build Command:"
    echo "/bin/sh -c 'set -e -o pipefail && xcodebuild ONLY_ACTIVE_ARCH=YES DEBUG_INFORMATION_FORMAT=dwarf COMPILER_INDEX_STORE_ENABLE=NO -scheme \"iOS Browser\" -configuration Debug -workspace ${WORKSPACE} -destination \"platform=iOS Simulator,id=${SIMULATOR_ID}\" -allowProvisioningUpdates -parallelizeTargets -jobs ${CORES} build | xcbeautify'"
fi

# Generate macOS build command
if [ -n "$WORKSPACE" ]; then
    echo ""
    echo "Generated macOS Build Command:"
    echo "/bin/sh -c 'set -e -o pipefail && xcodebuild ONLY_ACTIVE_ARCH=YES DEBUG_INFORMATION_FORMAT=dwarf COMPILER_INDEX_STORE_ENABLE=NO -scheme \"macOS Browser\" -configuration Debug -workspace ${WORKSPACE} -destination \"platform=macOS,arch=${ARCH}\" -allowProvisioningUpdates -disableAutomaticPackageResolution -parallelizeTargets -jobs ${CORES} build | xcbeautify'"
fi
```

## Simulator Management

### List Available Simulators
```bash
# Get list of available iOS simulators
xcrun simctl list devices available

# Get specific simulator info
xcrun simctl list devices | grep "iPhone 15"
```

### Simulator Operations
```bash
# Boot a simulator
xcrun simctl boot "iPhone 15 Pro"

# Shutdown a simulator
xcrun simctl shutdown "iPhone 15 Pro"

# Reset simulator
xcrun simctl erase "iPhone 15 Pro"
```

## Testing Commands

### Unit Tests
```bash
# Run iOS tests
xcodebuild test \
  -scheme "iOS Browser" \
  -workspace DuckDuckGo.xcworkspace \
  -destination "platform=iOS Simulator,name=iPhone 15 Pro" \
  -only-testing:DuckDuckGoTests

# Run macOS tests
xcodebuild test \
  -scheme "DuckDuckGo" \
  -workspace DuckDuckGo.xcworkspace \
  -destination "platform=macOS" \
  -only-testing:UnitTests
```

### UI Tests
```bash
# Run iOS UI tests
xcodebuild test \
  -scheme "iOS Browser" \
  -workspace DuckDuckGo.xcworkspace \
  -destination "platform=iOS Simulator,name=iPhone 15 Pro" \
  -only-testing:UITests

# Run macOS UI tests
xcodebuild test \
  -scheme "DuckDuckGo" \
  -workspace DuckDuckGo.xcworkspace \
  -destination "platform=macOS" \
  -only-testing:UITests
```

## Development Setup

### Prerequisites
```bash
# Install Xcode Command Line Tools
xcode-select --install

# Install Ruby dependencies (for Fastlane)
bundle install

# Install xcbeautify for prettier build output
brew install xcbeautify
```

### Project Setup
```bash
# Open the workspace (not individual projects)
open DuckDuckGo.xcworkspace

# Or from command line
xed DuckDuckGo.xcworkspace
```

## Code Quality

### SwiftLint
```bash
# Run SwiftLint on the project
swiftlint

# Auto-fix SwiftLint issues
swiftlint --fix

# Run SwiftLint on specific files
swiftlint --path iOS/DuckDuckGo/
```

### Code Formatting
```bash
# Format Swift files (if using swift-format)
swift-format --in-place --recursive iOS/DuckDuckGo/
swift-format --in-place --recursive macOS/DuckDuckGo/
```

## Debugging

### Build Analysis
```bash
# Analyze build times
xcodebuild -workspace DuckDuckGo.xcworkspace \
  -scheme "iOS Browser" \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 15 Pro" \
  OTHER_SWIFT_FLAGS="-Xfrontend -debug-time-function-bodies" \
  build | xcbeautify
```

### Clean Build
```bash
# Clean build folder
xcodebuild clean \
  -workspace DuckDuckGo.xcworkspace \
  -scheme "iOS Browser"

# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/
```

## Fastlane Commands

### iOS Fastlane
```bash
cd iOS/fastlane
bundle exec fastlane ios build_debug
bundle exec fastlane ios test
bundle exec fastlane ios build_release
```

### macOS Fastlane
```bash
cd macOS/fastlane
bundle exec fastlane mac build_debug
bundle exec fastlane mac test
bundle exec fastlane mac build_release
```

## Troubleshooting

### Common Issues
```bash
# If build fails with "No such module" errors
# Clean and rebuild the project
xcodebuild clean -workspace DuckDuckGo.xcworkspace -scheme "iOS Browser"
xcodebuild build -workspace DuckDuckGo.xcworkspace -scheme "iOS Browser"

# If simulator crashes or is unresponsive
xcrun simctl shutdown all
xcrun simctl erase all
```

### Reset Development Environment
```bash
# Clean all build artifacts
rm -rf ~/Library/Developer/Xcode/DerivedData/
rm -rf ~/Library/Caches/org.swift.swiftpm/

# Reset Xcode
sudo xcode-select --reset
```

## Performance Analysis

### Build Performance
```bash
# Measure build time
time xcodebuild -workspace DuckDuckGo.xcworkspace \
  -scheme "iOS Browser" \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=iPhone 15 Pro" \
  build
```

### Memory Usage
```bash
# Monitor memory usage during build
top -pid $(pgrep xcodebuild) -l 1
```

## Development Tips

### Efficient Development
- Always use the workspace file, not individual projects
- Keep simulators booted for faster testing
- Use parallel builds (`-parallelizeTargets`) for faster compilation
- Enable "Build Active Architecture Only" in debug builds
- Use `xcbeautify` for cleaner build output

### Environment Variables
```bash
# Set environment variables for development
export FASTLANE_SKIP_UPDATE_CHECK=1
export FASTLANE_HIDE_CHANGELOG=1
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```