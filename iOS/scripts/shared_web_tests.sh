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

# Ensure the simulator is in a clean state
echo "Cleaning simulator"
killall Simulator || true
xcrun simctl erase all || true

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