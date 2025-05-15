#!/bin/bash

set -eo pipefail

# Get the directory where the script is stored
script_dir=$(dirname "$(readlink -f "$0")")
base_dir="${script_dir}/.."

# The following URLs shall match the ones in AppConfigurationURLprovider.swift.
# Danger checks that the URLs match on every PR. If the code changes, the regex that Danger uses may need an update.
TDS_URL="https://staticcdn.duckduckgo.com/trackerblocking/v6/current/macos-tds.json"
CONFIG_URL="https://staticcdn.duckduckgo.com/trackerblocking/config/v4/macos-config.json"

DBP_BROKER_URL="https://dbp.duckduckgo.com/dbp/remote/v0?name=all.zip&type=combined"

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

# If -c is passed, then check the URLs in the Configuration files are correct.
if [ "$1" == "-c" ]; then
	grep http "$base_dir/DuckDuckGo/Application/AppConfigurationURLProvider.swift" | while read -r line
	do
		# if trimmed line begins with "case" then check the url in the line and ensure
		# it matches the expected url.
		if [[ $line =~ ^\s*case ]]; then
			# Get URL from line and remove quotes
			url=$(echo "$line" | awk '{print $4}' | sed 's/^"//' | sed 's/"$//')
			case_name=$(echo "$line" | awk '{print $2}')
			if [ "$case_name" == "trackerDataSet" ] && [ "$url" != "$TDS_URL" ]; then
				echo "Error: $url does not match $TDS_URL"
				exit 1
			elif [ "$case_name" == "privacyConfiguration" ] && [ "$url" != "$CONFIG_URL" ]; then
				echo "Error: $url does not match $CONFIG_URL"
				exit 1
			fi
		fi
	done

	exit 0
fi

temp_filename="embedded_new_file"
temp_etag_filename="embedded_new_etag"

rm -f "$temp_filename"
rm -f "$temp_etag_filename"

performUpdate() {
	local file_url=$1
	local provider_path=$2
	local data_path=$3
	printf "Processing: %s\n" "${file_url}"

	if test ! -f "$data_path"; then
		printf "Error: %s does not exist\n" "${data_path}"
		exit 1
	fi

	if test ! -f "$provider_path"; then
		printf "Error: %s does not exist\n" "${provider_path}"
		exit 1
	fi

	old_etag=$(grep 'public static let embeddedDataETag' "${provider_path}" | awk -F '\\\\"' '{print $2}')
	old_sha=$(grep 'public static let embeddedDataSHA' "${provider_path}" | awk -F '"' '{print $2}')

	printf "Existing ETag: %s\n" "${old_etag}"
	printf "Existing SHA256: %s\n" "${old_sha}"

	curl -s -o "$temp_filename" -H "If-None-Match: \"${old_etag}\"" --etag-save "$temp_etag_filename" "${file_url}"

	if test -f "$temp_filename"; then
		new_etag=$(< "$temp_etag_filename" awk -F '"' '{print $2}')
		new_sha=$(shasum -a 256 "$temp_filename" | awk -F ' ' '{print $1}')

		printf "New ETag: %s\n" "$new_etag"
		printf "New SHA256: %s\n" "$new_sha"

		sed -i '' "s/$old_etag/$new_etag/g" "${provider_path}"
		sed -i '' "s/$old_sha/$new_sha/g" "${provider_path}"

		cp -f "$temp_filename" "$data_path"

		printf 'Files updated\n\n'
	else
		printf 'Nothing to update\n\n'
	fi

	rm -f "$temp_filename"
	rm -f "$temp_etag_filename"
}

performDBPBrokerUpdate() {
	local file_url=$1
	local target_dir=$2

	printf "Processing DBP broker data: %s\n" "${file_url}"

	local dbp_zip="dbp_broker_data.zip"
	local dbp_extract_dir="dbp_broker_data"

	if [ -z "$DBP_API_AUTH_TOKEN" ]; then
		printf "Error: DBP_API_AUTH_TOKEN is not set. Aborting.\n"
		exit 1
	fi

	printf "Downloading DBP broker JSONs...\n"
	curl -s -H "Authorization: Bearer $DBP_API_AUTH_TOKEN" -L "$file_url" -o "$dbp_zip"

	rm -rf "$dbp_extract_dir"
	mkdir "$dbp_extract_dir"

	unzip -o "$dbp_zip" -d "$dbp_extract_dir" >/dev/null

	# Ignore unrelated files
	find "$dbp_extract_dir" -type f -name '*_etag.json' -delete

	find "$dbp_extract_dir" -name '*.json' -exec cp {} "$target_dir" \;

	printf "DBP broker JSON files updated\n\n"

	rm -rf "$dbp_zip" "$dbp_extract_dir"
}

performUpdate $TDS_URL \
		"$base_dir/DuckDuckGo/ContentBlocker/AppTrackerDataSetProvider.swift" \
		"$base_dir/DuckDuckGo/ContentBlocker/trackerData.json"
performUpdate $CONFIG_URL \
		"$base_dir/DuckDuckGo/ContentBlocker/AppPrivacyConfigurationDataProvider.swift" \
		"$base_dir/DuckDuckGo/ContentBlocker/macos-config.json"

performDBPBrokerUpdate "$DBP_BROKER_URL" \
		"$base_dir/../SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/"

# Check for unique broker names after all updates
if ! checkUniqueBrokerNames "$base_dir/../SharedPackages/DataBrokerProtectionCore/Sources/DataBrokerProtectionCore/BundleResources/JSON/"; then
	printf "Error: Duplicate broker names. Aborting.\n"
	exit 1
fi
