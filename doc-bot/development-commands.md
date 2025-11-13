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
Before building, validate your environment.

**Example:** See [pre-flight-checks.sh](development-commands/pre-flight-checks.sh)

### Required Variables to Detect

| Variable | Purpose | Detection Command | Expected Format |
|----------|---------|-------------------|-----------------|
| `WORKSPACE_PATH` | Full path to .xcworkspace | `pwd` + `find . -name "DuckDuckGo.xcworkspace"` | `/Users/.../DuckDuckGo.xcworkspace` |
| `SIMULATOR_ID` | iOS Simulator UUID | `xcrun simctl list devices \| grep iPhone` | `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX` |
| `ARCHITECTURE` | Mac CPU type | `uname -m` | `arm64` or `x86_64` |

### Detection Commands

**Example:** See [environment-detection.sh](development-commands/environment-detection.sh)

## 🏗️ Phase 2: Build Execution

### iOS Build Command Template

Replace the placeholders with your detected values.

**Example:** See [ios-build-template.sh](development-commands/ios-build-template.sh)

### macOS Build Command Template

Replace the placeholders with your detected values.

**Example:** See [macos-build-template.sh](development-commands/macos-build-template.sh)

### Complete Working Examples

#### iOS Build (Real Values)
**Example:** See [ios-build-example.sh](development-commands/ios-build-example.sh)

#### macOS Build (Real Values)
**Example:** See [macos-build-example.sh](development-commands/macos-build-example.sh)

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
2. **Clean and retry:** See [error-recovery-clean.sh](development-commands/error-recovery-clean.sh)
3. **If "No such module" errors:** See [error-recovery-derived-data.sh](development-commands/error-recovery-derived-data.sh)
4. **If simulator issues:** See [error-recovery-simulator.sh](development-commands/error-recovery-simulator.sh)

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

Use this script for reliable, automated builds.

**Example:** See [complete-automation-script.sh](development-commands/complete-automation-script.sh)

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

### Useful Commands
**Example:** See [useful-commands.sh](development-commands/useful-commands.sh)

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
