#!/bin/bash
set -euo pipefail

# Prints the platforms whose English strings changed between two commits, as a JSON array, e.g. ["iOS","macOS"].
# A string catalog (.xcstrings) counts only when a key, its English value or its comment changed, so translation
# imports and release merge-backs that only change other languages don't count. Any change to an English .strings
# or .stringsdict file, a storyboard or a xib counts.
# Both commits must be in the repository; a partial clone fetches the catalogs it compares.
# Any error reading the commits or a catalog fails the script, so a failure never looks like "no change".
# The paths here are also the `paths` filter in .github/workflows/smartling_on_merge.yml: keep them in sync.

usage() {
	echo "Usage: $0 <base commit> <head commit>" >&2
	exit 1
}

BASE="${1:-}"
HEAD="${2:-}"
[ -n "$BASE" ] && [ -n "$HEAD" ] || usage

STRING_SOURCES='(/en\.lproj/|\.xcstrings$|\.storyboard$|\.xib$)'
SHARED_STRING_SOURCES='^SharedPackages/.*(/en\.lproj/|\.xcstrings$)'

# The keys, English values and comments of a string catalog at a commit, or nothing if the commit doesn't have it.
# The commit's tree is local, so a missing file is told apart from a catalog that couldn't be fetched.
english_strings() {
	local listed catalog
	listed="$(git ls-tree --name-only "$1" -- "$2")" || return 1
	[ -n "$listed" ] || return 0
	catalog="$(git show "$1:$2")" || return 1
	jq -S '.sourceLanguage as $source | .strings | map_values({comment, shouldTranslate, source: .localizations[$source]})' \
		<<< "$catalog"
}

changed_files="$(git diff --name-only --no-renames "$BASE" "$HEAD")"
ios=false
macos=false
while IFS= read -r file; do
	if [[ "$file" =~ ^iOS/.*$STRING_SOURCES ]]; then
		platforms=(ios)
	elif [[ "$file" =~ ^macOS/.*$STRING_SOURCES ]]; then
		platforms=(macos)
	elif [[ "$file" =~ $SHARED_STRING_SOURCES ]]; then
		platforms=(ios macos)
	else
		continue
	fi
	if [[ "$file" == *.xcstrings ]]; then
		base_strings="$(english_strings "$BASE" "$file")"
		head_strings="$(english_strings "$HEAD" "$file")"
		[ "$base_strings" != "$head_strings" ] || continue
	fi
	echo "English strings changed: $file" >&2
	for platform in "${platforms[@]}"; do
		declare "$platform=true"
	done
done <<< "$changed_files"

jq -cn --argjson ios "$ios" --argjson macos "$macos" \
	'[if $ios then "iOS" else empty end, if $macos then "macOS" else empty end]'
