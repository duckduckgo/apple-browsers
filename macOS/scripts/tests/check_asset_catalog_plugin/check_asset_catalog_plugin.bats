#!/usr/bin/env bats

setup() {
	local scripts_dir
	scripts_dir="$( cd "$( dirname "$BATS_TEST_FILENAME" )/../.." >/dev/null 2>&1 && pwd )"
	source "$scripts_dir/check_asset_catalog_plugin.sh"

	ROOT="$BATS_TEST_TMPDIR/repo"
	PACKAGE="$ROOT/SharedPackages/Feature"
	mkdir -p "$PACKAGE/Sources/Feature"
}

# writeManifest <platforms> <plugins line or empty>
writeManifest() {
	local platforms=$1
	local plugins=$2

	cat > "$PACKAGE/Package.swift" <<MANIFEST
let package = Package(
    name: "Feature",
    platforms: [ $platforms ],
    targets: [
        .target(
            name: "Feature",
            resources: [.process("Assets.xcassets")],
            $plugins
        ),
        .testTarget(
            name: "FeatureTests",
            dependencies: ["Feature"]
        ),
    ]
)
MANIFEST
}

addAsset() {
	mkdir -p "$PACKAGE/Sources/$1/Assets.xcassets/Icon.imageset"
}

PLUGIN='plugins: [.plugin(name: "AssetCatalogPlugin", package: "AssetCatalogPlugin")]'

@test "passes when the target with a catalog uses the plugin" {
	writeManifest '.macOS("12.3")' "$PLUGIN"
	addAsset Feature

	run main "$ROOT"
	[ "$status" -eq 0 ]
}

@test "fails when the target with a catalog doesn't use the plugin" {
	writeManifest '.macOS("12.3")' ""
	addAsset Feature

	run main "$ROOT"
	[ "$status" -eq 1 ]
	[[ "${lines[0]}" == *"Target 'Feature' has an asset catalog but doesn't use AssetCatalogPlugin"* ]]
}

@test "fails when only a later target uses the plugin" {
	writeManifest '.macOS("12.3")' ""
	addAsset Feature
	echo '// .target(name: "Other", plugins: [.plugin(name: "AssetCatalogPlugin", package: "AssetCatalogPlugin")])' >> "$PACKAGE/Package.swift"

	run main "$ROOT"
	[ "$status" -eq 1 ]
}

@test "skips iOS-only packages" {
	writeManifest '.iOS("15.0")' ""
	addAsset Feature

	run main "$ROOT"
	[ "$status" -eq 0 ]
}

@test "checks packages supporting both iOS and macOS" {
	writeManifest '.iOS("15.0"), .macOS("12.3")' ""
	addAsset Feature

	run main "$ROOT"
	[ "$status" -eq 1 ]
}

@test "skips catalogs without assets" {
	writeManifest '.macOS("12.3")' ""
	mkdir -p "$PACKAGE/Sources/Feature/Assets.xcassets"

	run main "$ROOT"
	[ "$status" -eq 0 ]
}

@test "fails when the catalog's target isn't declared in the manifest" {
	writeManifest '.macOS("12.3")' "$PLUGIN"
	addAsset Unknown

	run main "$ROOT"
	[ "$status" -eq 1 ]
	[[ "${lines[0]}" == *"Can't find target 'Unknown'"* ]]
}
