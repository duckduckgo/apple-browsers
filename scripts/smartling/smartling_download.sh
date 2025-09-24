#!/bin/bash
set -euo pipefail

# Smartling Download Script
# Downloads translations from a Smartling job and imports them
# Supports both iOS and macOS platforms

JOB_ID="$1"
FORCE="${2:-false}"
PLATFORM="$3"

if [ -z "$JOB_ID" ]; then
	echo "Error: Job ID is required"
	echo "Usage: $0 <job-id> [force] <platform>"
	exit 1
fi

if [ -z "$PLATFORM" ]; then
	echo "Error: Platform is required"
	echo "Usage: $0 <job-id> [force] <platform>"
	echo "  platform: iOS or macOS"
	exit 1
fi

echo "Downloading translations for platform: $PLATFORM"

# Create temporary download directory
DOWNLOAD_DIR="$(mktemp -d)/smartling_downloads"
mkdir -p "$DOWNLOAD_DIR"

# Download translated files
echo "Downloading translations from Smartling job $JOB_ID..."
./scripts/smartling/loc_tool.sh download --job-id "$JOB_ID" --out-dir "$DOWNLOAD_DIR"

# Reorganize files into locale folders as expected by loc_import.sh
# Files are downloaded as: name_locale.extension
# Need to reorganize as: locale/name.extension

IMPORT_DIR="$(mktemp -d)/smartling_import"
mkdir -p "$IMPORT_DIR"

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

# Cleanup temporary directories
rm -rf "$DOWNLOAD_DIR" "$IMPORT_DIR"

# Check for deleted translation keys and problematic replacements
echo "Checking for deleted translation keys and value replacements..."

# Run integrity check. Non-zero exit means issues detected
if ! ./scripts/smartling/check_translation_integrity.py; then
	if [ "$FORCE" != "true" ]; then
		./scripts/smartling/smartling_messages.sh download download_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" failed deletions
		git checkout -- .
		exit 1
	else
		echo "⚠️ Proceeding with destructive changes because force=true was set"
	fi
fi

# Commit the imported translations
echo "Committing imported translations..."

# Check if there are any changes to commit
if git diff --quiet && git diff --cached --quiet; then
	echo "No changes to commit"
	# Generate no changes message
	./scripts/smartling/smartling_messages.sh download download_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" no_changes
else
	# Configure Git identity for the commit
	git config user.name "Dax the Duck"
	git config user.email "dax@duckduckgo.com"

	# Add all changes
	git add -A

	# Create commit message
	git commit -m "Import translations from Smartling job $JOB_ID"

	echo "✅ Translations committed successfully"

	# Push the commit to the current branch
	git push origin HEAD
	echo "✅ Changes pushed to current branch"
	
	# Generate success message
	./scripts/smartling/smartling_messages.sh download download_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" success
fi