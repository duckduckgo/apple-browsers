#!/bin/zsh

### Set up environment for UI testing

source $(dirname $0)/common.sh

## Functions

check_maestro() {

    local command_name="maestro"
    local known_version="1.40.3"

    if command -v $command_name > /dev/null 2>&1; then
      local version_output=$($command_name -v 2>&1 | tail -n 1)

      local command_version=$(echo $version_output | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

      if [[ $command_version == $known_version ]]; then
        echo "ℹ️ maestro version matches: $command_version"
      else
        echo "‼️ maestro version does not match. Expected: $known_version, Got: $command_version"
        exit 1
      fi
    else
      echo "‼️ maestro not found install using the following commands:"
      echo
      echo "curl -Ls \"https://get.maestro.mobile.dev\" | bash"
      echo "brew tap facebook/fb"
      echo "brew install facebook/fb/idb-companion"
      echo
      exit 1
    fi
}

## Main Script

echo
echo "ℹ️  Checking environment for UI testing with maestro"

check_maestro
check_command xcodebuild
check_command xcrun

echo "✅ Expected commands available"
echo

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-build)
            skip_build=1 ;;
        --rebuild)
            rebuild=1 ;;
        *)
    esac
    shift
done

echo "ℹ️ Closing all simulators"

killall Simulator

# Function to create or get simulator
create_or_get_simulator() {
    local device_name=$1
    local device_type=$2
    local simulator_name="$device_name $target_os (maestro)"
    
    echo "ℹ️ Checking for existing $device_name simulator" >&2
    
    local existing_uuid=$(xcrun simctl list devices | grep "$simulator_name" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1)
    
    if [ -n "$existing_uuid" ]; then
        echo "ℹ️ Found existing $device_name simulator: $existing_uuid" >&2
        echo "$existing_uuid"
    else
        echo "ℹ️ Creating new $device_name simulator for maestro" >&2
        local new_uuid=$(xcrun simctl create "$simulator_name" "com.apple.CoreSimulator.SimDeviceType.$device_type" "com.apple.CoreSimulator.SimRuntime.$target_os")
        if [ $? -ne 0 ]; then
            echo "‼️ Unable to create $device_name simulator" >&2
            exit 1
        fi
        echo "$new_uuid"
    fi
}

# Create both iPhone and iPad simulators
echo "ℹ️ Setting up simulators for Maestro tests"

# Create iPhone simulator
iphone_uuid=$(create_or_get_simulator "$target_device" "$target_device")
echo "📱 iPhone simulator: $iphone_uuid"

# Create iPad simulator  
ipad_uuid=$(create_or_get_simulator "iPad-10th-generation" "iPad-10th-generation")
echo "📱 iPad simulator: $ipad_uuid"

# Use iPhone as default for building
device_uuid=$iphone_uuid

# Build the app after we have the simulator
if [ -n "$skip_build" ]; then
    echo "Skipping build"
else
    # Export the device UUID so build_app can use it
    export MAESTRO_DEVICE_UUID=$device_uuid
    build_app $rebuild
fi

# Function to boot and configure a simulator
boot_and_configure_simulator() {
    local uuid=$1
    local device_name=$2
    
    echo "ℹ️ Booting $device_name simulator"
    xcrun simctl boot $uuid
    if [ $? -ne 0 ]; then
        echo "⚠️  $device_name might already be booted, continuing..."
    fi
    
    echo "ℹ️ Setting $device_name locale to en_US"
    xcrun simctl spawn $uuid defaults write "Apple Global Domain" AppleLanguages -array en
    if [ $? -ne 0 ]; then
        echo "‼️ Unable to set preferred language for $device_name"
        exit 1
    fi
    
    xcrun simctl spawn $uuid defaults write "Apple Global Domain" AppleLocale -string en_US
    if [ $? -ne 0 ]; then
        echo "‼️ Unable to set region for $device_name"
        exit 1
    fi
    
    echo "ℹ️ Installing app on $device_name"
    xcrun simctl install $uuid $app_location
    if [ $? -ne 0 ]; then
        echo "‼️ Unable to install app on $device_name"
        exit 1
    fi
}

# Boot and configure both simulators
boot_and_configure_simulator $iphone_uuid "iPhone"
boot_and_configure_simulator $ipad_uuid "iPad"

# Open Simulator app
open -a Simulator

# Save both UUIDs for run_ui_tests.sh to use
echo "$iphone_uuid" > $device_uuid_path
echo "$ipad_uuid" > "${device_uuid_path%.txt}_ipad.txt"

echo
echo "✅ Environment ready for running UI tests."
echo
