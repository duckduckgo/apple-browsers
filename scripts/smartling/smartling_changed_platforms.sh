#!/bin/bash
set -euo pipefail

# Prints the platforms whose English strings changed between two commits, as a JSON array, e.g. ["iOS","macOS"].
# A string catalog (.xcstrings) counts only when a key, its English value or its comment changed, so translation
# imports and release merge-backs that only change other languages don't count. Any change to an English .strings
# or .stringsdict file, a storyboard or a xib counts.
# Both commits must be in the repository; a partial clone fetches the catalogs it compares.
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

# The keys, English values and comments of a string catalog at a commit, or nothing if the file isn't there.
english_strings() {
	git show "$1:$2" 2>/dev/null \
		| jq -S '.sourceLanguage as $source | .strings | map_values({comment, shouldTranslate, source: .localizations[$source]})' \
		|| true
}

english_changed() {
	local file="$1"
	[[ "$file" == *.xcstrings ]] || return 0
	[ "$(english_strings "$BASE" "$file")" != "$(english_strings "$HEAD" "$file")" ]
}

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
	if english_changed "$file"; then
		echo "English strings changed: $file" >&2
		for platform in "${platforms[@]}"; do
			declare "$platform=true"
		done
	fi
done < <(git diff --name-only --no-renames "$BASE" "$HEAD")

jq -cn --argjson ios "$ios" --argjson macos "$macos" \
	'[if $ios then "iOS" else empty end, if $macos then "macOS" else empty end]'
