#!/bin/bash

# Get the directory where the script is stored
script_dir=$(dirname "$(readlink -f "$0")")

# Define the source and destination variables
source="$script_dir/assets/Swift File For Package.xctemplate"
destination="/Applications/Xcode.app/Contents/Developer/Library/Xcode/Templates/File Templates/MultiPlatform/Source/Swift File For Package.xctemplate"

# Create a symbolic link
ln -sFn "$source" "$destination"

# Check if the symlink was created successfully
if [[ ! -L "$destination" ]]; then
	echo "Symlink creation failed."
	exit 1
fi

echo "Symlink created successfully."