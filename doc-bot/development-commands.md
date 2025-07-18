---
title: "Development Commands & Build Instructions"
description: "Essential commands for building, testing, and developing the DuckDuckGo browser applications"
keywords: ["build", "development", "commands", "Xcode", "simulator", "testing", "debugging"]
alwaysApply: false
---

# Development Commands & Build Instructions

## Build Commands

### iOS Build
```bash
# Build iOS Browser in Xcode
xcodebuild ONLY_ACTIVE_ARCH=YES DEBUG_INFORMATION_FORMAT=dwarf COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "iOS Browser" \
  -configuration Debug \
  -workspace DuckDuckGo.xcworkspace \
  -destination "platform=iOS Simulator,name=iPhone 15 Pro" \
  -allowProvisioningUpdates \
  -disableAutomaticPackageResolution \
  -parallelizeTargets \
  -jobs 14 \
  build | xcbeautify
```

### macOS Build
```bash
# Build macOS Browser in Xcode
xcodebuild ONLY_ACTIVE_ARCH=YES DEBUG_INFORMATION_FORMAT=dwarf COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "DuckDuckGo" \
  -configuration Debug \
  -workspace DuckDuckGo.xcworkspace \
  -destination "platform=macOS" \
  -allowProvisioningUpdates \
  -disableAutomaticPackageResolution \
  -parallelizeTargets \
  -jobs 14 \
  build | xcbeautify
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

This guide provides the essential commands needed for efficient development of the DuckDuckGo browser applications. 