#!/bin/bash
#
# Updates the DBP broker JSONs embedded in DataBrokerProtectionCore, installing
# only the brokers listed in main_config.json's active_data_brokers.
#
# The apps trust embedded brokers without checking them, so nothing is written
# unless main_config.json is signed by one of the app's production keys and every
# installed broker matches its json_sha256 entry.

DBP_BROKER_URL="https://dbp.duckduckgo.com/dbp/remote/v0?name=all.zip&type=spec"
DBP_MAIN_CONFIG_URL="https://dbp.duckduckgo.com/dbp/remote/v0/main_config.json"
DBP_MAIN_CONFIG_SIGNATURE_URL="https://dbp.duckduckgo.com/dbp/remote/v0/main_config.json.sig"

BROKER_JSON_DIR_RELATIVE_PATH="../../SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON"
SIGNING_KEYS_RELATIVE_PATH="../../SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/bundle-signing-keys.json"

# Succeeds if signature_file is a base64 DER ECDSA signature of main_config by any of the keys, which are base64 SPKI DER, one per line.
verifyMainConfigSignature() {
	local main_config=$1
	local signature_file=$2
	local keys=$3

	local work_dir key
	work_dir=$(mktemp -d)
	tr -d '[:space:]' < "$signature_file" | base64 -d > "${work_dir}/signature.der" 2>/dev/null

	while IFS= read -r key; do
		[[ -n "$key" ]] || continue
		printf '%s' "$key" | base64 -d > "${work_dir}/key.der"
		if openssl dgst -sha256 -verify "${work_dir}/key.der" -keyform DER -signature "${work_dir}/signature.der" "$main_config" >/dev/null 2>&1; then
			rm -rf "$work_dir"
			return 0
		fi
	done <<< "$keys"

	rm -rf "$work_dir"
	return 1
}

# Fails unless every active broker is in source_dir and matches its json_sha256 entry.
verifyBrokerDigests() {
	local source_dir=$1
	local main_config=$2

	local active_brokers
	if ! active_brokers=$(activeBrokerFileNames "$main_config"); then
		printf "Error: could not read active_data_brokers from %s. Aborting.\n" "$main_config"
		return 1
	fi

	local error_found=0
	local file_name file_path expected found
	while IFS= read -r file_name; do
		expected=$(jq -r --arg file_name "$file_name" '.json_sha256[$file_name] // empty' "$main_config")
		found=0
		# installBrokerJSONs copies every file with this name, so check them all
		while IFS= read -r file_path; do
			found=1
			if [[ "$(shasum -a 256 "$file_path" | cut -d ' ' -f 1)" != "$expected" ]]; then
				printf "Error: %s does not match its json_sha256 entry\n" "$file_path"
				error_found=1
			fi
		done < <(find "$source_dir" -name "$file_name")

		if [[ $found -eq 0 ]]; then
			printf "Error: active broker %s is missing from the archive\n" "$file_name"
			error_found=1
		fi
	done <<< "$active_brokers"

	return $error_found
}

activeBrokerFileNames() {
	local main_config=$1

	jq -er '.active_data_brokers | if type == "array" and length > 0 then .[] else error("missing or empty") end' "$main_config"
}

installBrokerJSONs() {
	local source_dir=$1
	local main_config=$2
	local target_dir=$3

	local active_brokers
	if ! active_brokers=$(activeBrokerFileNames "$main_config"); then
		printf "Error: could not read active_data_brokers from %s. Aborting.\n" "$main_config"
		return 1
	fi

	local installed=0
	local skipped_inactive=0
	local file_path file_name

	while IFS= read -r file_path; do
		file_name=$(basename "$file_path")

		if ! printf '%s\n' "$active_brokers" | grep -Fxq "$file_name"; then
			printf "  Skipping %s: not in active_data_brokers\n" "$file_name"
			skipped_inactive=$(( skipped_inactive + 1 ))
			continue
		fi

		cp -f "$file_path" "$target_dir"
		installed=$(( installed + 1 ))
	done < <(find "$source_dir" -name '*.json' | sort)

	printf "Installed: %d, skipped (inactive): %d\n" "$installed" "$skipped_inactive"
}

# Broker names must be unique across all files.
checkUniqueBrokerNames() {
	local dir=$1
	local temp_file
	temp_file=$(mktemp)
	local error_found=0

	find "$dir" -name '*.json' -exec jq -r '.name' {} \; > "$temp_file"

	if sort "$temp_file" | uniq -d | grep -q .; then
		printf "Error: Duplicate broker names found:\n"
		sort "$temp_file" | uniq -d | while read -r name; do
			printf "\nBroker name '%s' found in:\n" "$name"
			find "$dir" -name '*.json' -exec sh -c 'if jq -e --arg name "$1" ".name == \$name" "$2" >/dev/null; then printf "  - %s\n" "$2"; fi' _ "$name" {} \;
		done
		error_found=1
	fi

	rm "$temp_file"
	return $error_found
}

fetchBrokerArchive() {
	local file_url=$1
	local extract_dir=$2

	local archive="${extract_dir}.zip"

	printf "Downloading DBP broker JSONs...\n"
	curl -fsS -L "$file_url" -o "$archive"

	mkdir -p "$extract_dir"
	unzip -o "$archive" -d "$extract_dir" >/dev/null

	# Ignore unrelated files
	find "$extract_dir" -type f -name '*_etag.json' -delete
}

fetchMainConfig() {
	local destination=$1

	printf "Downloading DBP main config...\n"
	curl -fsS -L "$DBP_MAIN_CONFIG_URL" -o "$destination"
	curl -fsS -L "$DBP_MAIN_CONFIG_SIGNATURE_URL" -o "${destination}.sig"
}

main() {
	local script_dir target_dir signing_keys
	script_dir=$(dirname "$(readlink -f "$0")")
	target_dir="${script_dir}/${BROKER_JSON_DIR_RELATIVE_PATH}"
	signing_keys=$(jq -r '.production[]' "${script_dir}/${SIGNING_KEYS_RELATIVE_PATH}")

	printf "Processing DBP broker data: %s\n" "$DBP_BROKER_URL"

	local work_dir
	work_dir=$(mktemp -d)
	trap 'rm -rf "$work_dir"' EXIT

	local extract_dir="${work_dir}/brokers"
	fetchBrokerArchive "$DBP_BROKER_URL" "$extract_dir"

	local main_config="${work_dir}/main_config.json"
	fetchMainConfig "$main_config"

	if ! verifyMainConfigSignature "$main_config" "${main_config}.sig" "$signing_keys"; then
		printf "Error: main_config.json is not signed by any of the app's production keys. Aborting.\n"
		exit 1
	fi

	if ! verifyBrokerDigests "$extract_dir" "$main_config"; then
		printf "Error: broker JSONs do not match main_config.json. Aborting.\n"
		exit 1
	fi

	installBrokerJSONs "$extract_dir" "$main_config" "$target_dir"

	if ! checkUniqueBrokerNames "$target_dir"; then
		printf "Error: Duplicate broker names. Aborting.\n"
		exit 1
	fi

	printf "DBP broker JSON files updated\n\n"
}

# set -e stays scoped here so sourcing from the tests keeps their error handling.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	set -eo pipefail
	main "$@"
fi
