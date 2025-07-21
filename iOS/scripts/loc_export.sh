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

# Change to iOS directory if we're not already there
# This ensures only iOS strings are exported when running from repository root
if [ "$(pwd)" = "$ios_dir" ]; then
    # Already in the correct directory, no change needed
    xcodebuild -exportLocalizations -project "DuckDuckGo-iOS.xcodeproj" -localizationPath "$loc_path" -sdk iphoneos -exportLanguage en
else
    # Change to iOS directory for the export
    cd "$ios_dir"
    xcodebuild -exportLocalizations -project "DuckDuckGo-iOS.xcodeproj" -localizationPath "$loc_path" -sdk iphoneos -exportLanguage en
    # Return to the original directory
    cd "$current_dir"
fi

open "${loc_path}/en.xcloc/Localized Contents"
