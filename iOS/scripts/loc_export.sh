#!/bin/sh

# Get the directory where the script is stored
script_dir=$(dirname "$(readlink -f "$0")")
ios_dir="${script_dir}/.."

# Source the common functions
. "${script_dir}/../../scripts/loc_export_common.sh"

echo "Updating..."
"${script_dir}/loc_update.sh"

echo "Exporting..."
loc_path="${script_dir}/assets/loc"
rm -r "$loc_path"

# Run xcodebuild in the iOS directory to ensure only iOS strings are exported
run_in_directory "$ios_dir" xcodebuild -exportLocalizations -project "DuckDuckGo-iOS.xcodeproj" -localizationPath "$loc_path" -sdk iphoneos -exportLanguage en

open "${loc_path}/en.xcloc/Localized Contents"
