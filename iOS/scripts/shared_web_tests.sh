#!/bin/sh

# If we're not in python 3.9, switch to it
if ! python3 --version | grep -q "3.9"; then
    # If we have 3.9 installed don't call remotely.
    if ! brew list python@3.9 >/dev/null 2>&1; then
        brew install python@3.9
    fi
    # shellcheck source=/dev/null
    /opt/homebrew/bin/python3.9 -m venv /tmp/venv39 && [ -f /tmp/venv39/bin/activate ] && . /tmp/venv39/bin/activate
fi

# Check that we have Rust installed:
if ! command -v cargo > /dev/null 2>&1; then
    echo "‼️ Error: Rust is not installed. Please install Rust from https://rustup.rs/"
    exit 1
fi

# Check that we have npm installed:
if ! command -v npm > /dev/null 2>&1; then
    echo "‼️ Error: Node is not installed. Please install nvm https://github.com/nvm-sh/nvm"
    exit 1
fi

# Check if the required iOS platform is already downloaded
if ! xcodebuild -showsdks | grep -q 18.2; then
    xcodebuild -downloadPlatform iOS -buildVersion 18.2
fi

# Check for --clean flag
if [ "$1" = "--clean" ]; then
    echo "Clearing tmp directory"
    rm -rf tmp
fi

# Ensure we have a tmp directory
mkdir -p tmp

# Ensure we have the app built, note we use the .maestro/common.sh but don't depend on maestro
# Create a hash of all the files in the iOS/ source directory to reduce the build overhead.
# Pass --clean to clear out this caching.
IOS_HASH_FILE="$(pwd)/tmp/ios_source_hash.txt"
find iOS -type f -name '*.swift' 2>/dev/null | sort | xargs cat 2>/dev/null | sha256sum > "$IOS_HASH_FILE"

# Check if the hash file exists and compare it with the current hash
if [ -f "$IOS_HASH_FILE" ] && cmp -s "$IOS_HASH_FILE" "$IOS_HASH_FILE.old"; then
    echo "iOS source files have not changed, skipping build."
else
    echo "iOS source files have changed, building app."
    if [ -z "$PROJECT_ROOT" ]; then
        PROJECT_ROOT="$(realpath "$(dirname "$0")"/../..)"
    fi
    export PROJECT_ROOT
    # shellcheck source=/dev/null
    . .maestro/common.sh
    build_app
    cp "$IOS_HASH_FILE" "$IOS_HASH_FILE.old"
fi

# Prepare the simulator — terminate any running DuckDuckGo instance but keep
# the booted simulator and its cached content-blocker rules intact.  The
# previous `simctl erase all` destroyed all warm state, forcing ddgdriver to
# re-create the simulator, re-install the app, and re-compile content blocker
# rules from scratch on every WPT attempt — which regularly exceeded the 30s
# WPT init timeout on CI runners.
echo "Preparing simulator"
APP_BUNDLE_ID="com.duckduckgo.mobile.ios"
TARGET_DEVICE="${TARGET_DEVICE:-iPhone-16}"
TARGET_OS="${TARGET_OS:-iOS-18-2}"
SIM_NAME="${TARGET_DEVICE} ${TARGET_OS} (webdriver)"

# Find or create the webdriver simulator
UDID=$(xcrun simctl list devices -j 2>/dev/null \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
for runtime, devs in data.get('devices', {}).items():
    if '${TARGET_OS}' in runtime:
        for d in devs:
            if d.get('name') == '${SIM_NAME}' and d.get('isAvailable'):
                print(d['udid']); exit()
" 2>/dev/null)

if [ -z "$UDID" ]; then
    echo "Creating simulator: $SIM_NAME"
    UDID=$(xcrun simctl create "$SIM_NAME" \
        "com.apple.CoreSimulator.SimDeviceType.${TARGET_DEVICE}" \
        "com.apple.CoreSimulator.SimRuntime.${TARGET_OS}")
fi
echo "Using simulator: $UDID"

# Boot if not already booted
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator 2>/dev/null || true

# Terminate any leftover app instance but don't uninstall
xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" 2>/dev/null || true

# Pre-install the app so ddgdriver doesn't have to
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$(pwd)/DerivedData/}"
APP_PATH="${DERIVED_DATA_PATH}Build/Products/Debug-iphonesimulator/DuckDuckGo.app"
if [ -d "$APP_PATH" ]; then
    echo "Pre-installing app from $APP_PATH"
    xcrun simctl install "$UDID" "$APP_PATH" || true

    # Set automation defaults before launch
    xcrun simctl spawn "$UDID" defaults write "$APP_BUNDLE_ID" isUITesting -bool true || true
    xcrun simctl spawn "$UDID" defaults write "$APP_BUNDLE_ID" isOnboardingCompleted -string true || true
    xcrun simctl spawn "$UDID" defaults write "$APP_BUNDLE_ID" automationPort -int 8557 || true

    # Launch once to let content blocker rules compile, then terminate
    echo "Pre-warming app (content blocker compilation)..."
    xcrun simctl launch "$UDID" "$APP_BUNDLE_ID" isUITesting true || true
    WARMUP_ATTEMPTS=0
    while [ $WARMUP_ATTEMPTS -lt 60 ]; do
        READY=$(curl -s --max-time 1 "http://[::1]:8557/contentBlockerReady" 2>/dev/null \
          | python3 -c "import sys,json; print(json.load(sys.stdin).get('message',''))" 2>/dev/null || echo "")
        if [ "$READY" = "true" ]; then
            echo "Content blocker ready after $WARMUP_ATTEMPTS attempts"
            break
        fi
        WARMUP_ATTEMPTS=$((WARMUP_ATTEMPTS + 1))
        sleep 0.5
    done
    if [ $WARMUP_ATTEMPTS -ge 60 ]; then
        echo "Warning: content blocker warmup timed out, proceeding anyway"
    fi
    xcrun simctl terminate "$UDID" "$APP_BUNDLE_ID" 2>/dev/null || true
    sleep 1
else
    echo "Warning: app not found at $APP_PATH, skipping pre-warm"
fi

export DERIVED_DATA_PATH

# Clone the shared-web-tests repo
cd tmp || exit

if [ ! -d "shared-web-tests" ]; then
    git clone --recurse-submodules git@github.com:duckduckgo/shared-web-tests.git
fi
cd shared-web-tests || exit

# Build the test suite
if ! npm run build; then
    echo "‼️ Error: npm build failed."
    return 1
fi

# Install the hosts file for the web driver server
if ! grep -q "Start web-platform-tests hosts" /etc/hosts; then
    echo "Installing hosts, sudo required"
    sudo -- sh -c 'npm run install-hosts'
else
    echo "Hosts already installed, skipping"
fi

echo "Starting test run:"
DERIVED_DATA_PATH="$(pwd)/../../DerivedData/"
export DERIVED_DATA_PATH
npm run test | tee "../../tmp/test_out_$(date +"%Y%m%d_%H%M%S").log"
cd ../.. || exit
# Deactivate the Python virtual environment
if [ -n "$VIRTUAL_ENV" ]; then
    echo "Deactivating Python virtual environment"
    deactivate
fi