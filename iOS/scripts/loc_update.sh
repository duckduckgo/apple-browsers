#!/bin/sh
set -e

# Get the directory where the script is stored
script_dir=$(dirname "$(readlink -f "$0")")
base_dir="${script_dir}/.."
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/loc_update.XXXXXX")
tmp_index=0

cleanup() {
	rm -rf "${tmp_dir}"
}
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

update_localizable_strings() {
	source_dir="$1"
	output_dir="$2"
	tmp_index=$((tmp_index + 1))
	tmp_output_dir="${tmp_dir}/${tmp_index}"
	tmp_utf8_strings="${tmp_output_dir}/Localizable-UTF8.strings"
	generated_strings="${tmp_output_dir}/Localizable.strings"
	target_strings="${output_dir}/Localizable.strings"

	echo "Processing ${source_dir}"
	mkdir -p "${tmp_output_dir}"
	if ! find "${source_dir}/" -name "*.swift" -print0 | xargs -0 xcrun extractLocStrings -o "${tmp_output_dir}"; then
		echo "error: Failed to extract localization strings from ${source_dir}" >&2
		return 1
	fi

	if [ ! -f "${generated_strings}" ]; then
		echo "error: extractLocStrings did not generate ${generated_strings}" >&2
		return 1
	fi

	if ! iconv -f UTF-16 -t UTF8 "${generated_strings}" > "${tmp_utf8_strings}"; then
		rm -f "${tmp_utf8_strings}"
		echo "error: Failed to convert ${generated_strings} to UTF-8" >&2
		return 1
	fi

	if [ -f "${target_strings}" ] && cmp -s "${tmp_utf8_strings}" "${target_strings}"; then
		echo "  Localizable.strings unchanged"
		return
	fi

	mkdir -p "${output_dir}"
	mv "${tmp_utf8_strings}" "${target_strings}"
	echo "  Updated ${target_strings}"
}

# Add target sub-directories here when needed
set -- "${base_dir}/DuckDuckGo" "${base_dir}/Widgets" "${base_dir}/PacketTunnelProvider"

for dir in "$@"; do
	update_localizable_strings "${dir}" "${dir}/en.lproj"
done

# Add LocalPackages sub-directories here when needed
set -- "${base_dir}/LocalPackages/SyncUI-iOS/Sources/SyncUI-iOS"

for dir in "$@"; do
	update_localizable_strings "${dir}" "${dir}/Resources/en.lproj"
done
