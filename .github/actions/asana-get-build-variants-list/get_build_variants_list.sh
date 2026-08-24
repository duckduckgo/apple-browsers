#!/bin/bash
#
# This scripts fetches Asana tasks from the Origins section defined in the Asana project https://app.asana.com/0/1206716555947156/1206716715679835.
#

set -e -o pipefail

asana_api_url="https://app.asana.com/api/1.0"

# Number of variants that a single job creates. Set VARIANTS_PER_JOB to fine-tune
# the balance between the number of jobs and the duration of each job.
VARIANTS_PER_JOB="${VARIANTS_PER_JOB:-10}"

# Maximum number of jobs that a GitHub Actions matrix supports.
MAX_MATRIX_JOBS=256

if ! [[ "$VARIANTS_PER_JOB" =~ ^[0-9]+$ ]] || [[ "$VARIANTS_PER_JOB" -lt 1 ]]; then
	echo "Error: VARIANTS_PER_JOB must be a positive integer, got '${VARIANTS_PER_JOB}'"
	exit 1
fi

# Create a JSON string with the `origin-variant` pairs from the list of .
_create_origins_and_variants() {
	local response="$1"
	local origin_field="Origin"
	local atb_field="ATB"
	local macos_field="Produce macOS build?"

	# for each element in the data array.
	# filter out element with null `origin` and those starting with `funnel_playstore` (they will never be used for downloading the macOS browser).
	# filter out element with `Produce macOS build?` set to "No".
	# select `origin` and `variant` from the custom_fields response and make a key:value pair structure like {origin: <origin_value>, variant: <variant_value>}.
	# if variant is not null we need to create two entries. One only with `origin` and one with `origin` and `variant`
	# replace the new line with a comma
	# remove the trailing comma at the end of the line.
	jq -c '.data[]
		| select(.custom_fields[] | select(.name == "'"${origin_field}"'") | (.text_value != null and (.text_value | startswith("funnel_playstore") | not)))
		| select(.custom_fields[] | select(.name == "'"${macos_field}"'") | (.enum_value.name != "No"))
		| {origin: (.custom_fields[] | select(.name == "'"${origin_field}"'") | .text_value), variant: (.custom_fields[] | select(.name == "'"${atb_field}"'") | .text_value)}
		| if .variant != null then {origin}, {origin, variant} else {origin} end' <<< "$response"
}

# Fetch all the Asana tasks in the section specified by ORIGIN_ASANA_SECTION_ID for a project.
# This function fetches only uncompleted tasks.
# If there are more than 100 items the function takes care of pagination.
# Returns a JSON string consisting of a list of `origin-variant` pairs concatenated by a comma. Eg. `{"origin":"app","variant":"ab"},{"origin":"app.search","variant":null}`.
_fetch_origin_tasks() {
	# Fetches only tasks that have not been completed yet, includes in the response section name, name of the task and its custom fields.
	local query="completed_since=now&opt_fields=name,custom_fields.id_prefix,custom_fields.name,custom_fields.text_value,custom_fields.enum_value&opt_expand=custom_fields&opt_fields=memberships.section.name&limit=100"

	local url="${asana_api_url}/sections/${ORIGIN_ASANA_SECTION_ID}/tasks?${query}"
	local response
	local origin_variants=()

	# go through all tasks in the section (there may be multiple requests in case there are more than 100 tasks in the section)
	# repeat until no more pages (next_page.uri is null)
	while true; do
		response="$(curl -fLSs "$url" -H "Authorization: Bearer ${ASANA_ACCESS_TOKEN}")"

		# extract the object in the data array and append to result
		origin_variants+=("$(_create_origins_and_variants "$response")")

		# set new URL to next page URL
		url="$(jq -r .next_page.uri <<< "$response")"

		# break on last page
		if [[ "$url" == "null" ]]; then
			break
		fi
	done

	printf "%s\n" "${origin_variants[@]}"
}

# Create a JSON string from the list of ATB items passed.
_create_atb_variant_pairs() {
	local response="$1"

	# read the response raw and format in a compact JSON mode
	# map each element to the structure {variant:<element>}
	# remove the array
	# replace the new line with a comma
	# remove the trailing comma at the end of the line.
	jq -R -c 'split(",")
		| map({variant: .})
		| .[]' <<< "$response"
}

# Fetches all the ATB variants defined in the ATB_ASANA_TASK_ID at the Variants list (comma separated) section.
_fetch_atb_variants() {
	local url="${asana_api_url}/tasks/${ATB_ASANA_TASK_ID}?opt_fields=notes"
	local atb_variants

	# fetches the items
	# read the response raw
	# select only Variants list section
	# output last line of the input to get all the list of variants.
	atb_variants="$(curl -fSsL ${url} \
		-H "Authorization: Bearer ${ASANA_ACCESS_TOKEN}" \
		| jq -r .data.notes \
		| grep -A1 '^Variants list' \
		| tail -1)"

	variants_list=("$(_create_atb_variant_pairs "$atb_variants")")

	printf "%s\n" "${variants_list[@]}"
}

# Group the variants into batches of VARIANTS_PER_JOB items and format them as a
# GitHub Actions matrix. Each matrix entry drives one job that creates all the variants
# of its batch, one by one.
# For more info see https://docs.github.com/en/actions/using-jobs/using-a-matrix-for-your-jobs#example-adding-configurations.
#
# The `variants` value of each entry is the batch encoded as a JSON string, because reusable
# workflow inputs only accept scalar values. The called workflow decodes it.
# Example output for a batch size of 2:
#   {"include":[{"batch":1,"count":2,"variants":"[{\"variant\":\"ab\"},{\"origin\":\"app\"}]"}]}
_create_matrix() {
	local array=("$@")

	printf "%s\n" "${array[@]}" \
		| jq -s -c --argjson size "$VARIANTS_PER_JOB" '
			{include: [
				range(0; length; $size) as $i
				| (.[$i:$i+$size]) as $batch
				| {batch: (($i / $size) + 1), count: ($batch | length), variants: ($batch | tojson)}
			]}'
}

main() {
	local variants=()
	local items=()

	# fetch ATB variants
	variants+=("$(_fetch_atb_variants)")
	# fetch Origin variants
	variants+=("$(_fetch_origin_tasks)")

	while read -r variant; do
		# skip empty lines to keep the JSON payload valid
		[[ -z "$variant" ]] && continue
		items+=("$variant")
	done <<< "$(printf "%s\n" "${variants[@]}")"

	if [[ ${#items[@]} -eq 0 ]]; then
		echo "No variants found"
		exit 1
	fi

	echo "Found ${#items[@]} variants, creating up to ${VARIANTS_PER_JOB} of them per job"

	local matrix
	matrix="$(_create_matrix "${items[@]}")"

	local jobs_count
	jobs_count="$(jq '.include | length' <<< "$matrix")"

	# A GitHub Actions matrix is capped at 256 jobs. Anything above that would be dropped silently.
	if [[ "$jobs_count" -gt "$MAX_MATRIX_JOBS" ]]; then
		echo "Error: ${#items[@]} variants at ${VARIANTS_PER_JOB} per job require ${jobs_count} jobs," \
			"which is more than the ${MAX_MATRIX_JOBS} allowed in a GitHub Actions matrix."
		echo "Raise the variants-per-job input to at least $(( (${#items[@]} + MAX_MATRIX_JOBS - 1) / MAX_MATRIX_JOBS ))."
		exit 1
	fi

	echo "Storing a matrix of ${jobs_count} jobs"
	echo "build-variants=${matrix}" >> "$GITHUB_OUTPUT"
}

main "$@"
