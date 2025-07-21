#!/bin/sh

# Get the directory where the script is stored
script_dir=$(dirname "$(readlink -f "$0")")
ios_dir="${script_dir}/.."

echo "Updating..."
"${script_dir}/loc_update.sh"

echo "Exporting..."
loc_path="${script_dir}/assets/loc"
rm -r "$loc_path"

# Save current directory to return to it later
current_dir=$(pwd)

# Change to iOS directory and explicitly specify the iOS project
# This ensures only iOS strings are exported when running from repository root
# Only change directory if we're not already in the iOS directory
if [ "$(pwd)" != "$ios_dir" ]; then
    cd "$ios_dir"
fi

xcodebuild -exportLocalizations -project "DuckDuckGo-iOS.xcodeproj" -localizationPath "$loc_path" -sdk iphoneos -exportLanguage en

# Return to original directory if we changed it
if [ "$(pwd)" != "$current_dir" ]; then
    cd "$current_dir"
fi

open "${loc_path}/en.xcloc/Localized Contents"
