#!/bin/bash

set -euo pipefail

readonly EXPECTED_MAIN_BUNDLE_IDENTIFIER="com.duckduckgo.macos.browser"
readonly -a REQUIRED_ARCHITECTURES=("arm64" "x86_64")

usage() {
	cat <<- EOF
	Usage:
	  $(basename "$0") app <path-to-app> <marketing-version.build-number>
	  $(basename "$0") dmg <path-to-dmg> <marketing-version.build-number>

	Validates a production DuckDuckGo release app or DMG. Release artifacts must:
	  - use the production bundle identifier and expected version
	  - contain arm64 and x86_64 in the main browser executable
	  - have a valid signature and notarization ticket
	  - pass Gatekeeper assessment

	DMG validation also verifies and mounts the image, checks its installation layout,
	and applies the complete app validation to the app inside it.
	EOF
}

die() {
	echo "❌ $*" >&2
	exit 1
}

read_plist_value() {
	local plist_path=$1
	local key=$2

	/usr/libexec/PlistBuddy -c "Print :${key}" "${plist_path}" 2>/dev/null
}

absolute_path() {
	local path=$1
	local directory
	local filename

	directory=$(dirname "${path}")
	filename=$(basename "${path}")
	[[ -e "${path}" ]] || die "Artifact does not exist: ${path}"

	echo "$(cd "${directory}" && pwd -P)/${filename}"
}

validate_app_metadata() {
	local app_path=$1
	local expected_marketing_version=$2
	local expected_build_number=$3
	local plist_path="${app_path}/Contents/Info.plist"
	local actual_bundle_identifier
	local actual_marketing_version
	local actual_build_number
	local executable_name
	local executable_path

	[[ -f "${plist_path}" ]] || die "Required bundle metadata is missing: ${plist_path}"
	plutil -lint "${plist_path}" > /dev/null || die "Invalid property list: ${plist_path}"

	actual_bundle_identifier=$(read_plist_value "${plist_path}" "CFBundleIdentifier") \
		|| die "CFBundleIdentifier is missing from ${plist_path}"
	[[ "${actual_bundle_identifier}" == "${EXPECTED_MAIN_BUNDLE_IDENTIFIER}" ]] \
		|| die "Unexpected bundle identifier: expected ${EXPECTED_MAIN_BUNDLE_IDENTIFIER}, found ${actual_bundle_identifier}"

	actual_marketing_version=$(read_plist_value "${plist_path}" "CFBundleShortVersionString") \
		|| die "CFBundleShortVersionString is missing from ${plist_path}"
	[[ "${actual_marketing_version}" == "${expected_marketing_version}" ]] \
		|| die "Unexpected marketing version in ${plist_path}: expected ${expected_marketing_version}, found ${actual_marketing_version}"

	actual_build_number=$(read_plist_value "${plist_path}" "CFBundleVersion") \
		|| die "CFBundleVersion is missing from ${plist_path}"
	[[ "${actual_build_number}" == "${expected_build_number}" ]] \
		|| die "Unexpected build number in ${plist_path}: expected ${expected_build_number}, found ${actual_build_number}"

	executable_name=$(read_plist_value "${plist_path}" "CFBundleExecutable") \
		|| die "CFBundleExecutable is missing from ${plist_path}"
	executable_path="$(dirname "${plist_path}")/MacOS/${executable_name}"
	[[ -f "${executable_path}" ]] \
		|| die "Bundle executable does not exist: ${executable_path}"
	echo "✅ Production bundle identifier and version are valid"
}

validate_mach_o_architectures() {
	local app_path=$1
	local plist_path="${app_path}/Contents/Info.plist"
	local executable_name
	local executable_path
	local architectures

	executable_name=$(read_plist_value "${plist_path}" "CFBundleExecutable") \
		|| die "CFBundleExecutable is missing from ${plist_path}"
	executable_path="${app_path}/Contents/MacOS/${executable_name}"
	architectures=$(lipo -archs "${executable_path}") \
		|| die "Could not inspect architectures in ${executable_path}"

	if ! lipo "${executable_path}" -verify_arch "${REQUIRED_ARCHITECTURES[@]}"; then
		die "Main browser executable is missing a required architecture: found ${architectures}, expected ${REQUIRED_ARCHITECTURES[*]}"
	fi

	echo "✅ Main browser executable contains ${architectures}"
}

validate_code_signing() {
	local app_path=$1

	codesign --verify --strict --verbose=2 "${app_path}" \
		|| die "Code signature validation failed for ${app_path}"

	spctl --assess --type execute --verbose=4 "${app_path}" \
		|| die "Gatekeeper assessment failed for ${app_path}"
	xcrun stapler validate "${app_path}" \
		|| die "Notarization ticket validation failed for ${app_path}"

	echo "✅ Signature, Gatekeeper assessment, and notarization ticket are valid"
}

validate_app() {
	local app_path=$1
	local expected_version=$2
	local expected_marketing_version
	local expected_build_number

	[[ -d "${app_path}" ]] || die "App bundle does not exist: ${app_path}"
	[[ "${expected_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
		|| die "Expected version must use marketing-version.build-number format: ${expected_version}"

	expected_marketing_version=${expected_version%.*}
	expected_build_number=${expected_version##*.}

	echo "Validating production release app: ${app_path}"
	echo "Expected version: ${expected_marketing_version} (${expected_build_number})"

	validate_app_metadata "${app_path}" "${expected_marketing_version}" "${expected_build_number}"
	validate_mach_o_architectures "${app_path}"
	validate_code_signing "${app_path}"

	echo "✅ Production release app validation passed"
}

cleanup_dmg_mount() {
	local mount_point=$1
	local is_mounted=$2

	if [[ "${is_mounted}" == "true" ]]; then
		hdiutil detach "${mount_point}" -quiet \
			|| hdiutil detach "${mount_point}" -force -quiet \
			|| true
	fi
	rm -rf "${mount_point}"
}

validate_dmg() {
	local dmg_path=$1
	local expected_version=$2
	local mount_point
	local is_mounted=false
	local app_path

	[[ -f "${dmg_path}" ]] || die "DMG does not exist: ${dmg_path}"

	echo "Validating production release DMG: ${dmg_path}"
	hdiutil verify "${dmg_path}" > /dev/null || die "DMG verification failed for ${dmg_path}"
	echo "✅ DMG image verification passed"

	mount_point=$(mktemp -d "/tmp/duckduckgo-release-dmg.XXXXXX")
	trap 'cleanup_dmg_mount "${mount_point}" "${is_mounted}"' EXIT

	hdiutil attach \
		-readonly \
		-nobrowse \
		-noautoopen \
		-mountpoint "${mount_point}" \
		"${dmg_path}" > /dev/null \
		|| die "Could not mount ${dmg_path}"
	is_mounted=true

	app_path="${mount_point}/DuckDuckGo.app"
	[[ -d "${app_path}" ]] || die "DMG does not contain DuckDuckGo.app at its top level"
	[[ -L "${mount_point}/Applications" ]] || die "DMG does not contain an Applications drop link"
	[[ "$(readlink "${mount_point}/Applications")" == "/Applications" ]] \
		|| die "DMG Applications drop link does not point to /Applications"
	echo "✅ DMG installation layout is valid"

	validate_app "${app_path}" "${expected_version}"

	cleanup_dmg_mount "${mount_point}" "${is_mounted}"
	trap - EXIT
	echo "✅ Production release DMG validation passed"
}

main() {
	local mode=${1:-}
	local artifact_path=${2:-}
	local expected_version=${3:-}

	if [[ $# -ne 3 ]]; then
		usage
		exit 1
	fi

	artifact_path=$(absolute_path "${artifact_path}")

	case "${mode}" in
		app)
			validate_app "${artifact_path}" "${expected_version}"
			;;
		dmg)
			validate_dmg "${artifact_path}" "${expected_version}"
			;;
		*)
			usage
			die "Unknown validation mode: ${mode}"
			;;
	esac
}

main "$@"
