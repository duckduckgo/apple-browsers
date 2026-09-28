#!/bin/bash
#
# Checks that every Swift package target with an asset catalog uses
# AssetCatalogPlugin, which compiles the catalog and generates asset symbols
# for `swift build` (VSCode/Cursor, SourceKit-LSP). Xcode processes catalogs
# itself, so a missing plugin only shows up outside Xcode.
#
# Skipped: packages that don't support macOS (`swift build` can't build them),
# test targets, and catalogs without any assets.
#
# Usage: check_asset_catalog_plugin.sh [repo root]

PACKAGE_DIRS="SharedPackages macOS/LocalPackages iOS/LocalPackages"

# Succeeds when the manifest supports macOS: declares `.macOS(` or no iOS-only platforms list.
supportsMacOS() {
	local manifest=$1

	grep -q '\.macOS(' "$manifest" && return 0
	! grep -q '\.iOS(' "$manifest"
}

# Succeeds when the catalog contains at least one asset (`*.imageset`, `*.colorset`, ...).
hasAssets() {
	local catalog=$1

	[ -n "$(find "$catalog" -type d -name '*set' -print -quit)" ]
}

# Prints the manifest text of the target named `$2`, up to the next target declaration.
targetDeclaration() {
	local manifest=$1
	local target=$2

	# `.plugin(name: …, package: …)` is a plugin usage, not a plugin target declaration.
	awk -v name="name: \"$target\"" '
		/\.(target|testTarget|executableTarget|plugin|binaryTarget)\(/ && !/package:/ { if (found) exit; candidate = 1 }
		candidate && index($0, name) { found = 1 }
		found { print }
	' "$manifest"
}

# Prints `<target>` for each non-test target directory with a catalog that has assets.
targetsWithCatalogs() {
	local package_dir=$1
	local catalog

	[ -d "$package_dir/Sources" ] || return 0
	find "$package_dir/Sources" -type d -name '*.xcassets' -prune | sort | while read -r catalog; do
		hasAssets "$catalog" || continue
		local relative=${catalog#"$package_dir/Sources/"}
		echo "${relative%%/*}"
	done | sort -u
}

# Prints an error for each target in the package that has a catalog but no plugin.
checkPackage() {
	local package_dir=$1
	local manifest="$package_dir/Package.swift"
	local failed=0
	local target

	supportsMacOS "$manifest" || return 0
	for target in $(targetsWithCatalogs "$package_dir"); do
		local declaration
		declaration=$(targetDeclaration "$manifest" "$target")
		if [ -z "$declaration" ]; then
			echo "::error file=$manifest::Can't find target '$target' in $manifest to check that it uses AssetCatalogPlugin."
			failed=1
		elif ! echo "$declaration" | grep -q '\.plugin(name: "AssetCatalogPlugin"'; then
			echo "::error file=$manifest::Target '$target' has an asset catalog but doesn't use AssetCatalogPlugin. Add .plugin(name: \"AssetCatalogPlugin\", package: \"AssetCatalogPlugin\") to its plugins."
			failed=1
		fi
	done
	return $failed
}

main() {
	local root=${1:-.}
	local failed=0
	local dir
	local manifest

	for dir in $PACKAGE_DIRS; do
		[ -d "$root/$dir" ] || continue
		while read -r manifest; do
			checkPackage "$(dirname "$manifest")" || failed=1
		done < <(find "$root/$dir" -name Package.swift -not -path '*/.build/*' | sort)
	done

	if [ $failed -ne 0 ]; then
		echo "See SharedPackages/Infrastructure/AssetCatalogPlugin for details."
		return 1
	fi
	echo "All package targets with asset catalogs use AssetCatalogPlugin."
}

# set -e stays scoped here so sourcing from the tests keeps their error handling.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	set -eo pipefail
	main "$@"
fi
