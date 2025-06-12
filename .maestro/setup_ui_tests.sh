#!/bin/zsh

### Set up environment for UI testing

source $(dirname $0)/common.sh

## Functions

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --phone        Set up for iPhone testing"
    echo "  --ipad         Set up for iPad testing"
    echo "  --skip-build   Skip building the app"
    echo "  --rebuild      Clean and rebuild the app"
    echo
    echo "If neither --phone nor --ipad is specified, you will be prompted to choose."
    echo
}

check_maestro() {

    local command_name="maestro"
    local known_version="1.39.13"

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
skip_build=0
rebuild=0
device_type=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-build)
            skip_build=1 ;;
        --rebuild)
            rebuild=1 ;;
        --phone)
            device_type="phone" ;;
        --ipad)
            device_type="ipad" ;;
        --help|-h)
            show_usage
            exit 0 ;;
        *)
            echo "‼️ Unknown option: $1"
            show_usage
            exit 1 ;;
    esac
    shift
done

# Exit if no device type specified
if [ -z "$device_type" ]; then
    echo "‼️ Device type must be specified."
    echo
    show_usage
    exit 1
fi

# Configure device settings based on selection
# These names need to match the friendly name in xcrun simctl list
# They match the CI devices so please don't change unless the device and os version in CI are also available
case $device_type in
    "phone")
        target_device="iPhone 16"
        target_os="iOS-18-2"
        echo "📱 Configured for iPhone testing"
        ;;
    "ipad")
        target_device="iPad (10th generation)" # "iPad-10th-generation"
        target_os="iOS-18-2"
        echo "📟 Configured for iPad testing"
        ;;
    *)
        echo "‼️ Invalid device type. Must be 'phone' or 'ipad'."
        exit 1 ;;
esac

# Update destination format for xcodebuild
destination_device="${target_device//-/ }"
destination_os_version="${target_os#iOS-}"
destination_os_version="${destination_os_version//-/.}"

echo "ℹ️ Using device: $destination_device, OS: $destination_os_version"

# Local build function that uses our configured device settings
build_app_with_device() {
    if [ -d "$derived_data_path" ] && [ "$1" -eq "0" ]; then
        echo "⚠️ Removing previously created $derived_data_path"
        rm -rf $derived_data_path
    else
        echo "ℹ️ Not cleaning derived data at $derived_data_path"
    fi

    echo "⏲️ Building the app for $destination_device"
    set -o pipefail && xcodebuild -project "$project_root"/iOS/DuckDuckGo-iOS.xcodeproj \
                                  -scheme "iOS Browser" \
                                  -destination "platform=iOS Simulator,name=$destination_device,OS=$destination_os_version" \
                                  -derivedDataPath "$derived_data_path" \
                                  -skipPackagePluginValidation \
                                  -skipMacroValidation \
                                  ONLY_ACTIVE_ARCH=NO | tee xcodebuild.log
    if [ $? -ne 0 ]; then
        echo "‼️ Unable to build app into $derived_data_path"
        exit 1
    fi
}

if [ "$skip_build" -eq 1 ]; then
    echo "Skipping build"
else
    # Update app_location based on device type for iPad builds
    if [ "$device_type" = "ipad" ]; then
        app_location="$derived_data_path/Build/Products/Debug-iphonesimulator/DuckDuckGo.app"
    fi
    
    echo "ℹ️ Building app with device $device_type"
    build_app_with_device $rebuild
fi

echo "ℹ️ Closing all simulators"

killall Simulator

echo "ℹ️ Starting simulator for maestro"

# Convert friendly device name to simctl format (remove brackets, convert spaces to hyphens)
simctl_device_name=$(echo "$target_device" | sed 's/[()]//g' | sed 's/ /-/g')
echo "ℹ️ Converted device name: '$target_device' -> '$simctl_device_name'"

device_uuid=$(xcrun simctl create "$target_device $target_os (maestro)" "com.apple.CoreSimulator.SimDeviceType.$simctl_device_name" "com.apple.CoreSimulator.SimRuntime.$target_os")
if [ $? -ne 0 ]; then
    echo "‼️ Unable to create simulator for $target_device and $target_os"
    exit 1
fi

echo "📱 Using simulator $device_uuid"

xcrun simctl boot $device_uuid
if [ $? -ne 0 ]; then
    echo "‼️ Unable to boot simulator"
    exit 1
fi

echo "ℹ️ Setting device locale to en_US"

xcrun simctl spawn $device_uuid defaults write "Apple Global Domain" AppleLanguages -array en
if [ $? -ne 0 ]; then
    echo "‼️ Unable to set preferred language"
    exit 1
fi

echo "ℹ️ Setting device region to en_US"

xcrun simctl spawn $device_uuid defaults write "Apple Global Domain" AppleLocale -string en_US
if [ $? -ne 0 ]; then
    echo "‼️ Unable to set region"
    exit 1
fi

echo "ℹ️ Opening simulator"

open -a Simulator

echo "ℹ️ Installing from $app_location"

xcrun simctl install booted $app_location
if [ $? -ne 0 ]; then
    echo "‼️ Unable to install app from $app_location"
    exit 1
fi

echo "$device_uuid" > $device_uuid_path

# Store device type for use in test runs
echo "$device_type" > $device_type_path
echo "ℹ️ Device type '$device_type' stored in $device_type_path"

echo
echo "✅ Environment ready for running UI tests."
echo
