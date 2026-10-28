#!/bin/bash
set -euo pipefail

# Smartling Download Script
# Downloads translations from a Smartling job and imports them
# Supports both iOS and macOS platforms

JOB_ID="$1"
PLATFORM="$2"
ALLOW_UNFINISHED="${3:-false}"

if [ -z "$JOB_ID" ]; then
	echo "Error: Job ID is required"
	echo "Usage: $0 <job-id> <platform>"
	exit 1
fi

if [ -z "$PLATFORM" ]; then
	echo "Error: Platform is required"
	echo "Usage: $0 <job-id> <platform>"
	echo "  platform: iOS or macOS"
	exit 1
fi

echo "Downloading translations for platform: $PLATFORM"

# Create temporary download directory
DOWNLOAD_DIR="$(mktemp -d)/smartling_downloads"
mkdir -p "$DOWNLOAD_DIR"

# Download translated files
ALLOW_FLAG=""
if [ "$ALLOW_UNFINISHED" = "true" ]; then
	echo "⚠️  allow-unfinished enabled: downloading even if the Smartling job is not COMPLETED"
	ALLOW_FLAG="--allow-unfinished"
fi
echo "Downloading translations from Smartling job $JOB_ID..."
./scripts/smartling/loc_tool.sh download --job-id "$JOB_ID" --out-dir "$DOWNLOAD_DIR" $ALLOW_FLAG || download_failed=1

# Handle download failure gracefully and set step outputs
if [ "${download_failed:-0}" = "1" ]; then
	./scripts/smartling/smartling_messages.sh download download_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" failed
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "download_result=failed" >> "$GITHUB_OUTPUT"
	fi
	exit 0
fi

./scripts/smartling/smartling_import.sh "$DOWNLOAD_DIR" "$PLATFORM"

# Cleanup temporary directories
rm -rf "$DOWNLOAD_DIR"

# Check for deleted translation keys and problematic replacements
echo "Checking for deleted translation keys and value replacements..."

# Run integrity check. Non-zero exit means issues detected
if ! ./scripts/smartling/check_translation_integrity.py; then
	echo "⚠️ Detected deletions or problematic replacements in translations"
	echo "Creating a new PR with these changes instead of applying them directly"

	# Create a new branch for the changes
	CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	NEW_BRANCH_NAME="smartling-deletions-${JOB_ID}-$(date +%Y%m%d-%H%M%S)"

	echo "Creating new branch: $NEW_BRANCH_NAME"
	git checkout -b "$NEW_BRANCH_NAME"

	# Commit the changes to the new branch
	git config user.name "Dax the Duck"
	git config user.email "dax@duckduckgo.com"

	# Reset any non-localization files (e.g., Package.resolved, build artifacts)
	echo "Cleaning non-localization files from working tree..."
	git restore --staged --worktree -- . ':(exclude)**/*.strings' ':(exclude)**/*.stringsdict' ':(exclude)**/*.xcstrings'

	git add -A -- ':(glob)**/*.strings' ':(glob)**/*.stringsdict' ':(glob)**/*.xcstrings'
	git commit -m "Smartling translations with deletions/replacements from job $JOB_ID"

	# Push the new branch
	git push origin "$NEW_BRANCH_NAME"

	# Create the PR using the new script
	./scripts/smartling/smartling_create_deletions_pr.sh "$NEW_BRANCH_NAME" "$CURRENT_BRANCH" "$JOB_ID" "$PLATFORM" "$SMARTLING_PROJECT_ID"

	# Switch back to original branch and clean up working directory
	git checkout "$CURRENT_BRANCH"
	git checkout -- .

	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "download_result=deletions_pr_created" >> "$GITHUB_OUTPUT"
		echo "new_branch_name=$NEW_BRANCH_NAME" >> "$GITHUB_OUTPUT"
	fi

	# Generate message about PR creation
	./scripts/smartling/smartling_messages.sh download download_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" deletions_pr_created "$NEW_BRANCH_NAME"

	exit 0
fi

# Commit the imported translations
echo "Committing imported translations..."

# Check if there are any changes to commit
if git diff --quiet && git diff --cached --quiet; then
	echo "No changes to commit"
	# Generate no changes message
	./scripts/smartling/smartling_messages.sh download download_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" no_changes
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "download_result=no_changes" >> "$GITHUB_OUTPUT"
	fi
	exit 0
else
	# Configure Git identity for the commit
	git config user.name "Dax the Duck"
	git config user.email "dax@duckduckgo.com"

	# Reset any non-localization files (e.g., Package.resolved, build artifacts)
	echo "Cleaning non-localization files from working tree..."
	git restore --staged --worktree -- . ':(exclude)**/*.strings' ':(exclude)**/*.stringsdict' ':(exclude)**/*.xcstrings'

	# Add only localization files (including deletions)
	git add -A -- ':(glob)**/*.strings' ':(glob)**/*.stringsdict' ':(glob)**/*.xcstrings'

	# Create commit message
	git commit -m "Import translations from Smartling job $JOB_ID"

	echo "✅ Translations committed successfully"

	# Push the commit to the current branch
	git push origin HEAD
	echo "✅ Changes pushed to current branch"
	
	# Generate success message
	./scripts/smartling/smartling_messages.sh download download_message.txt "$PLATFORM" "$JOB_ID" "$SMARTLING_PROJECT_ID" success
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "download_result=success" >> "$GITHUB_OUTPUT"
	fi
	exit 0
fi