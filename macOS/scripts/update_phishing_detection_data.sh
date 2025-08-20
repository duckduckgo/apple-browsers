#!/bin/bash
#set -eo pipefail
#
## The following URLs shall match the one in the client.
## Danger checks that the URLs match on every PR. If the code changes, the regex that Danger uses may need an update.
API_URL="https://duckduckgo.com/api/protection"

work_dir="${PWD}/DuckDuckGo/MaliciousSiteProtection"
def_filename="${work_dir}/MaliciousSiteProtectionManager.swift"

old_revision="$(grep "static let embeddedDataRevision =" "${def_filename}" | awk -F '[=,]' '{print $2}' | xargs)"
if [ -z "$old_revision" ]; then
    echo "❌ Could not read embeddedDataRevision"
    exit 1
fi

temp_filename="phishing_data_new_file"

# Initialize variables to track each dataset's revision
phishing_revision=0
malware_revision=0
scam_revision=0

server_revision=$(curl -s "${API_URL}/revision" | jq -r '.revision')
if [ -z "$server_revision" ]; then
    echo "❌ Could not read server revision"
    exit 1
fi

rm -f "$temp_filename"

performUpdate() {
    local threat_type=$1
    local data_type=$2
    local data_path=$3
    capitalized_data_type="$(echo "${data_type}" | awk '{print toupper(substr($0, 1, 1)) substr($0, 2)}')"
    printf "Processing %s\n" "${threat_type}${capitalized_data_type}"

    old_sha="$(grep "static let ${threat_type}Embedded${capitalized_data_type}DataSHA =" "${def_filename}" | awk -F '"' '{print $2}')"
    if [ -z "$old_sha" ]; then
        echo "⚠️ Could not read ${threat_type}Embedded${capitalized_data_type}DataSHA"
        old_sha=""
    fi

    printf "Embedded SHA256: %s\n" "${old_sha}"

    url="${API_URL}/${data_type}?category=${threat_type}"
    printf "Fetching %s\n" "${url}"
    curl --compressed -o "$temp_filename" -H "Cache-Control: no-cache" -s "${url}"
    # Extract the revision from the fetched JSON
    revision=$(jq -r '.revision' "$temp_filename")
    printf "Embedded revision: %s, remote revision: %s\n\n" "${old_revision}" "${revision}"
    # Store the revision for this dataset
    eval "${threat_type}_revision=$revision"

    printf "writing to %s\n" "${data_path}"
    jq -rc '.insert' "$temp_filename" > "$data_path"

    new_sha="$(shasum -a 256 "$data_path" | awk -F ' ' '{print $1}')"

    if [ "$new_sha" != "$old_sha" ]; then
        printf "New SHA256: %s ✨\n" "$new_sha"
    fi

    sed -i '' -e "s/${threat_type}Embedded${capitalized_data_type}DataSHA =.*/${threat_type}Embedded${capitalized_data_type}DataSHA = \"$new_sha\"/g" "${def_filename}"

    # Validate number of records in the data file
    record_count=$(jq 'length' "$data_path")
    if [ "$record_count" -eq 0 ]; then
        echo "⚠️⚠️⚠️: No data at $data_path"
    elif [ "$new_sha" == "$old_sha" ]; then
        printf "🆗 Data not modified. Number of records: %d\n\n" "$record_count"
    else
        printf "✅ %s updated with %d records\n\n" "${threat_type}Embedded${capitalized_data_type}DataSHA" "$record_count"
    fi

    rm -f "$temp_filename"
}

updateRevision() {
    local revision_to_use=$1
    sed -i '' -e "s/embeddedDataRevision = $old_revision/embeddedDataRevision = $revision_to_use/" "${def_filename}"
    printf "Updated revision from %s to %s\n" "$old_revision" "$revision_to_use"
}

if [[ "$old_revision" -lt "$server_revision" ]] || [[ "$*" == *"-f"* ]]; then
    performUpdate phishing hashPrefix "${work_dir}/phishingHashPrefixes.json"
    performUpdate phishing filterSet "${work_dir}/phishingFilterSet.json"

    performUpdate malware hashPrefix "${work_dir}/malwareHashPrefixes.json"
    performUpdate malware filterSet "${work_dir}/malwareFilterSet.json"

    performUpdate scam hashPrefix "${work_dir}/scamHashPrefixes.json"
    performUpdate scam filterSet "${work_dir}/scamFilterSet.json"

    # Find the smallest revision
    min_revision=$phishing_revision
    [ "$malware_revision" -lt "$min_revision" ] && min_revision=$malware_revision
    [ "$scam_revision" -lt "$min_revision" ] && min_revision=$scam_revision

    printf "Using minimum revision: %s (phishing: %s, malware: %s, scam: %s)\n" \
        "$min_revision" "$phishing_revision" "$malware_revision" "$scam_revision"

    updateRevision $min_revision
else
    printf 'Nothing to update\n\n'
fi
