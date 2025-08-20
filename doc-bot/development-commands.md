---
title: "Development Commands & Build Instructions"
description: "Essential commands for building, testing, and developing the DuckDuckGo browser applications"
keywords: ["build", "development", "commands", "Xcode", "simulator", "testing", "debugging"]
alwaysApply: true
---

# Development Commands & Build Instructions

## 📋 When to Use This Document

Use these instructions when you need to:
- Build the iOS Browser app for testing or development
- Build the macOS Browser app for testing or development
- Verify that code changes compile successfully
- Prepare the app for testing or debugging
- Understand build failures and how to fix them

## 🚦 Golden Rules for Building

### ✅ ALWAYS DO THESE
1. **Use the full shell wrapper**: `/bin/sh -c 'set -e -o pipefail && xcodebuild ... | xcbeautify'`
2. **Detect environment first**: Never hardcode paths or simulator IDs
3. **Check exit codes**: Ensure the build succeeded before proceeding
4. **Use absolute paths**: Always use full paths for workspace files
5. **Include xcbeautify**: Output is unreadable without it

### ❌ NEVER DO THESE
1. **Never use `-jobs` flag**: It's been removed from all commands
2. **Never skip xcbeautify**: Raw xcodebuild output is nearly impossible to parse
3. **Never use .xcodeproj files**: Always use .xcworkspace
4. **Never hardcode simulator IDs**: They change between systems
5. **Never ignore build failures**: Always check and handle errors

## 🔍 Phase 1: Environment Detection

### Pre-Flight Checks
Before building, validate your environment:

```bash
# 1. Verify you're in the project directory
ls -la | grep DuckDuckGo.xcworkspace
# Expected: DuckDuckGo.xcworkspace directory exists

# 2. Check Xcode command line tools
xcodebuild -version
# Expected: Xcode version output (e.g., "Xcode 15.0")

# 3. Verify xcbeautify is installed
which xcbeautify
# Expected: Path to xcbeautify (e.g., "/opt/homebrew/bin/xcbeautify")
# If missing: brew install xcbeautify
```

### Required Variables to Detect

| Variable | Purpose | Detection Command | Expected Format |
|----------|---------|-------------------|-----------------|
| `WORKSPACE_PATH` | Full path to .xcworkspace | `pwd` + `find . -name "DuckDuckGo.xcworkspace"` | `/Users/.../DuckDuckGo.xcworkspace` |
| `SIMULATOR_ID` | iOS Simulator UUID | `xcrun simctl list devices \| grep iPhone` | `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX` |
| `ARCHITECTURE` | Mac CPU type | `uname -m` | `arm64` or `x86_64` |

### Detection Commands

```bash
# Step 1: Get workspace path
WORKSPACE_DIR=$(pwd)
WORKSPACE_FILE=$(find . -name "DuckDuckGo.xcworkspace" | head -1)
WORKSPACE_PATH="${WORKSPACE_DIR}/${WORKSPACE_FILE#./}"
echo "Workspace: ${WORKSPACE_PATH}"

# Step 2: Get architecture (for macOS builds)
ARCHITECTURE=$(uname -m)
echo "Architecture: ${ARCHITECTURE}"

# Step 3: Find iOS simulator (for iOS builds)
SIMULATOR_ID=$(xcrun simctl list devices | grep -E "iPhone.*\([A-F0-9-]{36}\)" | head -1 | grep -oE "[A-F0-9-]{36}")
echo "Simulator ID: ${SIMULATOR_ID}"
```

## 🏗️ Phase 2: Build Execution

### iOS Build Command Template

Replace the placeholders with your detected values:

```bash
/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "iOS Browser" \
  -configuration Debug \
  -workspace <REPLACE_WITH_WORKSPACE_PATH> \
  -destination "platform=iOS Simulator,id=<REPLACE_WITH_SIMULATOR_ID>" \
  -allowProvisioningUpdates \
  -parallelizeTargets \
  build | xcbeautify'
```

### macOS Build Command Template

Replace the placeholders with your detected values:

```bash
/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "macOS Browser" \
  -configuration Debug \
  -workspace <REPLACE_WITH_WORKSPACE_PATH> \
  -destination "platform=macOS,arch=<REPLACE_WITH_ARCHITECTURE>" \
  -allowProvisioningUpdates \
  -disableAutomaticPackageResolution \
  -parallelizeTargets \
  build | xcbeautify'
```

### Complete Working Examples

#### iOS Build (Real Values)
```bash
/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "iOS Browser" \
  -configuration Debug \
  -workspace /Users/daniel/Developer/browser/apple-browsers/DuckDuckGo.xcworkspace \
  -destination "platform=iOS Simulator,id=6E6A828D-8C2C-4409-8E56-753DB02090F7" \
  -allowProvisioningUpdates \
  -parallelizeTargets \
  build | xcbeautify'
```

#### macOS Build (Real Values)
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
  build | xcbeautify'
```

## ✅ Phase 3: Build Verification

### Signs of Success
- Command exits with code 0
- Last line contains "BUILD SUCCEEDED"
- No error messages in red
- Build time is within expected range (see performance table below)

### Signs of Failure
- Command exits with non-zero code
- Output contains "BUILD FAILED"
- Red error messages appear
- Build hangs for more than 15 minutes

### Performance Expectations

| Build Type | Expected Duration | Action if Exceeded |
|------------|------------------|-------------------|
| First build | 5-10 minutes | Normal - downloading dependencies |
| Subsequent build | 1-3 minutes | Check for errors in output |
| Clean build | 3-5 minutes | Normal - rebuilding everything |
| Incremental | 10-30 seconds | Normal for small changes |
| Hanging >15 min | Abnormal | Cancel and check for issues |

## 🔧 Error Recovery

### If Build Fails - Immediate Actions

1. **Check the error message** - Last few red lines usually indicate the issue
2. **Clean and retry**:
   ```bash
   xcodebuild clean -workspace <WORKSPACE_PATH> -scheme "iOS Browser"
   # Then retry the build command
   ```
3. **If "No such module" errors**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/
   # Then retry the build command
   ```
4. **If simulator issues**:
   ```bash
   # List available simulators and pick a different one
   xcrun simctl list devices
   ```

### Common Problems and Solutions

| Problem | Diagnosis Command | Solution |
|---------|------------------|----------|
| No workspace found | `ls *.xcworkspace` | Ensure you're in project root directory |
| Simulator not found | `xcrun simctl list devices` | Pick a different simulator ID from the list |
| "Command not found: xcbeautify" | `which xcbeautify` | Install: `brew install xcbeautify` |
| Build hangs | Check Activity Monitor | Kill xcodebuild process and retry |
| "No such module" | Check package resolution | Clean DerivedData and rebuild |
| Provisioning errors | Check Xcode account | May need manual Xcode intervention |

## 🤖 Complete Automation Script

Use this script for reliable, automated builds:

```bash
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
```

## 📊 Build Flag Reference

Understanding what each flag does:

| Flag | Purpose | Impact |
|------|---------|--------|
| `ONLY_ACTIVE_ARCH=YES` | Build only for current architecture | 50% faster builds |
| `DEBUG_INFORMATION_FORMAT=dwarf` | Use DWARF debug symbols | Smaller build size |
| `COMPILER_INDEX_STORE_ENABLE=NO` | Skip code indexing | Faster builds |
| `-allowProvisioningUpdates` | Auto-update certificates | Prevents signing failures |
| `-disableAutomaticPackageResolution` | Skip package updates | Faster, more stable |
| `-parallelizeTargets` | Build targets in parallel | Uses all CPU cores |
| `-scheme` | Which app to build | Selects iOS or macOS |
| `-configuration` | Debug or Release | Debug = faster, Release = optimized |
| `-destination` | Where to run | Simulator/device/Mac |

## 📚 Additional Resources

### Available Schemes
- `iOS Browser` - Main iOS app
- `macOS Browser` - Main macOS app (sometimes called "DuckDuckGo")
- `iOS Unit Tests` - iOS test suite
- `macOS Unit Tests` - macOS test suite

### Useful Commands
```bash
# List all schemes
xcodebuild -list -workspace DuckDuckGo.xcworkspace

# List all simulators
xcrun simctl list devices

# Clean everything
rm -rf ~/Library/Developer/Xcode/DerivedData/

# Open workspace in Xcode
open DuckDuckGo.xcworkspace
```

## ✅ Task Completion Checklist

Before considering the build task complete, verify:

- [ ] Build command executed without errors
- [ ] "BUILD SUCCEEDED" message appeared
- [ ] Exit code was 0
- [ ] Build time was within expected range
- [ ] No unresolved errors in output
- [ ] If requested, both iOS and macOS builds completed

## 🚨 Critical Warnings

### For Release Builds
If building for release/production, change `-configuration Debug` to `-configuration Release`

### For Device Builds
If building for a physical iOS device (not simulator), you'll need:
- Device UUID instead of simulator ID
- Valid provisioning profiles
- Device connected and trusted

### For CI/Automation
- Always check exit codes
- Implement timeouts (15 minutes max)
- Log full output for debugging
- Clean build environment between runs