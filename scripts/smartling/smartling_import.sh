#!/bin/bash
set -euo pipefail

DOWNLOAD_DIR="${1:-}"
PLATFORM="${2:-}"

if [ -z "$DOWNLOAD_DIR" ] || [ -z "$PLATFORM" ]; then
	echo "Usage: $0 <download-dir> <iOS|macOS>"
	exit 1
fi

IMPORT_DIR="$(mktemp -d)/smartling_import"
mkdir -p "$IMPORT_DIR"

# Reorganize files into locale folders as expected by loc_import.sh
# Files are downloaded as: name_locale.extension
# Need to reorganize as: locale/name.extension

echo "Reorganizing downloaded files into locale folders..."

for file in "$DOWNLOAD_DIR"/*; do
	if [ -f "$file" ]; then
		filename=$(basename "$file")

		# Extract locale from filename (format: name_locale.extension)
		if [[ "$filename" =~ ^(.+)_([a-z]{2}(-[A-Z]{2})?)\.(.+)$ ]]; then
			base_name="${BASH_REMATCH[1]}"
			locale="${BASH_REMATCH[2]}"
			extension="${BASH_REMATCH[4]}"

			# Create locale directory
			mkdir -p "$IMPORT_DIR/$locale"

			# Copy file with original name (without locale suffix)
			cp "$file" "$IMPORT_DIR/$locale/${base_name}.${extension}"
			echo "  Moved $filename -> $locale/${base_name}.${extension}"
		fi
	fi
done

# Import XLIFF files first
echo "Importing XLIFF files..."
if ls "$IMPORT_DIR"/*/*.xliff >/dev/null 2>&1; then
	# Determine the base name from the first xliff file found
	XLIFF_BASE=""
	for xliff in "$IMPORT_DIR"/*/*.xliff; do
		if [ -f "$xliff" ]; then
			XLIFF_BASE=$(basename "$xliff" .xliff)
			echo "Found XLIFF with base name: $XLIFF_BASE"
			break
		fi
	done

	if [ -n "$XLIFF_BASE" ]; then
		if [ "$PLATFORM" = "iOS" ]; then
			./iOS/scripts/loc_import.sh "$IMPORT_DIR" "$XLIFF_BASE" | xcbeautify
		else
			# macOS import
			./macOS/scripts/loc_import.sh "$IMPORT_DIR" "$XLIFF_BASE" | xcbeautify
		fi
	fi
else
	echo "No XLIFF files found to import"
fi

# Import stringsdict files if present (iOS only)
if [ "$PLATFORM" = "iOS" ]; then
	echo "Checking for stringsdict files..."
	if ls "$IMPORT_DIR"/*/Localizable.stringsdict >/dev/null 2>&1; then
		echo "Importing stringsdict files..."
		./iOS/scripts/loc_import.sh "$IMPORT_DIR" "Localizable" | xcbeautify
	fi
fi

rm -rf "$IMPORT_DIR"
