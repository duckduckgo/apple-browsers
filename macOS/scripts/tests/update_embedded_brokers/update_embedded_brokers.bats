#!/usr/bin/env bats

setup() {
	local scripts_dir
	scripts_dir="$( cd "$( dirname "$BATS_TEST_FILENAME" )/../.." >/dev/null 2>&1 && pwd )"
	source "$scripts_dir/update_embedded_brokers.sh"

	SOURCE_DIR="$BATS_TEST_TMPDIR/incoming"
	TARGET_DIR="$BATS_TEST_TMPDIR/embedded"
	MAIN_CONFIG="$BATS_TEST_TMPDIR/main_config.json"
	mkdir -p "$SOURCE_DIR" "$TARGET_DIR"

	SIGNING_KEYS_SWIFT="$scripts_dir/$SIGNING_KEYS_RELATIVE_PATH"
	SIGNING_FIXTURES="$scripts_dir/../../SharedPackages/DataBrokerProtectionCore/Tests/DataBrokerProtectionCoreTests/BundleResources/BrokerBundleSigning"
}

generateKey() {
	local name=$1

	openssl ecparam -name prime256v1 -genkey -noout -out "$BATS_TEST_TMPDIR/$name.pem"
	openssl ec -in "$BATS_TEST_TMPDIR/$name.pem" -pubout -outform DER 2>/dev/null | base64 | tr -d '\n'
}

sign() {
	local name=$1
	local file=$2

	openssl dgst -sha256 -sign "$BATS_TEST_TMPDIR/$name.pem" "$file" | base64 | tr -d '\n' > "$file.sig"
}

writeSignedMainConfig() {
	jq -n '{active_data_brokers: ["a.com.json"], json_sha256: {}, manifest_version: 1790906518}' > "$MAIN_CONFIG"
}

writeDigestMainConfig() {
	local digest=$1

	jq -n --arg digest "$digest" \
		'{active_data_brokers: ["active.com.json"], json_sha256: {"active.com.json": $digest}}' > "$MAIN_CONFIG"
}

writeBroker() {
	local file_path=$1
	local name=$2
	local version=$3

	jq -n --arg name "$name" --arg version "$version" \
		'{name: $name, version: $version, removedAt: null}' > "$file_path"
}

writeMainConfig() {
	jq -n --args '{active_data_brokers: $ARGS.positional, test_data_brokers: []}' "$@" > "$MAIN_CONFIG"
}

@test "activeBrokerFileNames: lists the active broker file names" {
	writeMainConfig "a.com.json" "b.com.json"

	run activeBrokerFileNames "$MAIN_CONFIG"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "a.com.json" ]
	[ "${lines[1]}" = "b.com.json" ]
}

@test "activeBrokerFileNames: fails when the key is missing or empty" {
	echo '{"test_data_brokers": ["a.com.json"]}' > "$MAIN_CONFIG"
	run activeBrokerFileNames "$MAIN_CONFIG"
	[ "$status" -ne 0 ]

	writeMainConfig
	run activeBrokerFileNames "$MAIN_CONFIG"
	[ "$status" -ne 0 ]
}

@test "installBrokerJSONs: installs brokers in the active list" {
	writeBroker "$SOURCE_DIR/active.com.json" "Active" "0.2.0"
	writeMainConfig "active.com.json"

	run installBrokerJSONs "$SOURCE_DIR" "$MAIN_CONFIG" "$TARGET_DIR"
	[ "$status" -eq 0 ]
	[ -f "$TARGET_DIR/active.com.json" ]
}

@test "installBrokerJSONs: does not install brokers withheld from the active list" {
	local withheld=(
		"publicdatacheck.com.json"
		"publicrecordreports.com.json"
		"searchpublicrecords.com.json"
		"vehiclerelatedrecords.com.json"
	)
	for file_name in "${withheld[@]}"; do
		writeBroker "$SOURCE_DIR/$file_name" "${file_name%.json}" "0.2.0"
	done
	writeBroker "$SOURCE_DIR/spyfly.com.json" "SpyFly" "0.2.0"
	writeMainConfig "spyfly.com.json"

	run installBrokerJSONs "$SOURCE_DIR" "$MAIN_CONFIG" "$TARGET_DIR"
	[ "$status" -eq 0 ]
	[ -f "$TARGET_DIR/spyfly.com.json" ]
	for file_name in "${withheld[@]}"; do
		[ ! -f "$TARGET_DIR/$file_name" ]
	done
}

@test "installBrokerJSONs: does not install brokers absent from every list" {
	writeBroker "$SOURCE_DIR/unknown.com.json" "Unknown" "0.2.0"
	writeBroker "$SOURCE_DIR/active.com.json" "Active" "0.2.0"
	writeMainConfig "active.com.json"

	run installBrokerJSONs "$SOURCE_DIR" "$MAIN_CONFIG" "$TARGET_DIR"
	[ "$status" -eq 0 ]
	[ ! -f "$TARGET_DIR/unknown.com.json" ]
}

@test "installBrokerJSONs: fails without copying anything when the config is unusable" {
	writeBroker "$SOURCE_DIR/active.com.json" "Active" "0.2.0"
	echo 'not json' > "$MAIN_CONFIG"

	run installBrokerJSONs "$SOURCE_DIR" "$MAIN_CONFIG" "$TARGET_DIR"
	[ "$status" -ne 0 ]
	[ ! -f "$TARGET_DIR/active.com.json" ]
}

@test "fetchBrokerArchive: extracts the archive layout and drops the etag files" {
	local archive_root="$BATS_TEST_TMPDIR/dbp-json/data/json"
	mkdir -p "$archive_root"
	writeBroker "$archive_root/active.com.json" "Active" "0.2.0"
	writeBroker "$archive_root/withheld.com.json" "Withheld" "0.2.0"
	echo '{}' > "$archive_root/active.com_etag.json"
	writeMainConfig "active.com.json"
	( cd "$BATS_TEST_TMPDIR" && zip -qr archive.zip dbp-json )

	run fetchBrokerArchive "file://$BATS_TEST_TMPDIR/archive.zip" "$BATS_TEST_TMPDIR/extracted"
	[ "$status" -eq 0 ]
	[ -z "$(find "$BATS_TEST_TMPDIR/extracted" -name '*_etag.json')" ]

	run installBrokerJSONs "$BATS_TEST_TMPDIR/extracted" "$MAIN_CONFIG" "$TARGET_DIR"
	[ "$status" -eq 0 ]
	[ -f "$TARGET_DIR/active.com.json" ]
	[ ! -f "$TARGET_DIR/withheld.com.json" ]
}

@test "checkUniqueBrokerNames: passes when every broker name is unique" {
	writeBroker "$TARGET_DIR/a.com.json" "A" "0.2.0"
	writeBroker "$TARGET_DIR/b.com.json" "B" "0.2.0"

	run checkUniqueBrokerNames "$TARGET_DIR"
	[ "$status" -eq 0 ]
}

@test "checkUniqueBrokerNames: fails and names the duplicate" {
	writeBroker "$TARGET_DIR/a.com.json" "Same Name" "0.2.0"
	writeBroker "$TARGET_DIR/b.com.json" "Same Name" "0.2.0"

	run checkUniqueBrokerNames "$TARGET_DIR"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Same Name"* ]]
}

@test "signingKeys: reads one key per environment from the app's built-in keys" {
	run signingKeys "$SIGNING_KEYS_SWIFT" production
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	printf '%s' "${lines[0]}" | base64 -d | openssl pkey -pubin -inform DER -noout

	run signingKeys "$SIGNING_KEYS_SWIFT" staging
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	printf '%s' "${lines[0]}" | base64 -d | openssl pkey -pubin -inform DER -noout
}

@test "verifyMainConfigSignature: accepts the dbp-api fixture signed with the staging key" {
	run verifyMainConfigSignature "$SIGNING_FIXTURES/main_config.json" "$SIGNING_FIXTURES/main_config.json.sig" "$(signingKeys "$SIGNING_KEYS_SWIFT" staging)"
	[ "$status" -eq 0 ]

	run verifyMainConfigSignature "$SIGNING_FIXTURES/main_config.json" "$SIGNING_FIXTURES/main_config.json.sig" "$(signingKeys "$SIGNING_KEYS_SWIFT" production)"
	[ "$status" -ne 0 ]
}

@test "verifyMainConfigSignature: accepts a signature from any of the keys" {
	local key other_key
	key=$(generateKey signer)
	other_key=$(generateKey other)
	writeSignedMainConfig
	sign signer "$MAIN_CONFIG"
	printf '\n' >> "$MAIN_CONFIG.sig"

	run verifyMainConfigSignature "$MAIN_CONFIG" "$MAIN_CONFIG.sig" "$(printf '%s\n%s' "$other_key" "$key")"
	[ "$status" -eq 0 ]
}

@test "verifyMainConfigSignature: rejects a tampered config" {
	local key
	key=$(generateKey signer)
	writeSignedMainConfig
	sign signer "$MAIN_CONFIG"
	jq -c '.manifest_version = 9999999999' "$MAIN_CONFIG" > "$MAIN_CONFIG.tmp" && mv "$MAIN_CONFIG.tmp" "$MAIN_CONFIG"

	run verifyMainConfigSignature "$MAIN_CONFIG" "$MAIN_CONFIG.sig" "$key"
	[ "$status" -ne 0 ]
}

@test "verifyMainConfigSignature: rejects a signature from another key" {
	local other_key
	generateKey signer >/dev/null
	other_key=$(generateKey other)
	writeSignedMainConfig
	sign signer "$MAIN_CONFIG"

	run verifyMainConfigSignature "$MAIN_CONFIG" "$MAIN_CONFIG.sig" "$other_key"
	[ "$status" -ne 0 ]
}

@test "verifyMainConfigSignature: rejects a missing, empty or malformed signature" {
	local key
	key=$(generateKey signer)
	writeSignedMainConfig

	run verifyMainConfigSignature "$MAIN_CONFIG" "$MAIN_CONFIG.sig" "$key"
	[ "$status" -ne 0 ]

	: > "$MAIN_CONFIG.sig"
	run verifyMainConfigSignature "$MAIN_CONFIG" "$MAIN_CONFIG.sig" "$key"
	[ "$status" -ne 0 ]

	echo 'not a signature' > "$MAIN_CONFIG.sig"
	run verifyMainConfigSignature "$MAIN_CONFIG" "$MAIN_CONFIG.sig" "$key"
	[ "$status" -ne 0 ]
}

@test "verifyMainConfigSignature: rejects everything when there are no keys" {
	generateKey signer >/dev/null
	writeSignedMainConfig
	sign signer "$MAIN_CONFIG"

	run verifyMainConfigSignature "$MAIN_CONFIG" "$MAIN_CONFIG.sig" ""
	[ "$status" -ne 0 ]
}

@test "verifyBrokerDigests: passes when active brokers match json_sha256" {
	writeBroker "$SOURCE_DIR/active.com.json" "Active" "0.2.0"
	writeBroker "$SOURCE_DIR/inactive.com.json" "Inactive" "0.2.0"
	writeDigestMainConfig "$(shasum -a 256 "$SOURCE_DIR/active.com.json" | cut -d ' ' -f 1)"

	run verifyBrokerDigests "$SOURCE_DIR" "$MAIN_CONFIG"
	[ "$status" -eq 0 ]
}

@test "verifyBrokerDigests: fails when an active broker does not match json_sha256" {
	writeBroker "$SOURCE_DIR/active.com.json" "Active" "0.2.0"
	writeDigestMainConfig "$(shasum -a 256 "$SOURCE_DIR/active.com.json" | cut -d ' ' -f 1)"
	writeBroker "$SOURCE_DIR/active.com.json" "Tampered" "0.2.0"

	run verifyBrokerDigests "$SOURCE_DIR" "$MAIN_CONFIG"
	[ "$status" -ne 0 ]
	[[ "$output" == *"active.com.json"* ]]
}

@test "verifyBrokerDigests: fails when an active broker has no json_sha256 entry" {
	writeBroker "$SOURCE_DIR/active.com.json" "Active" "0.2.0"
	writeMainConfig "active.com.json"

	run verifyBrokerDigests "$SOURCE_DIR" "$MAIN_CONFIG"
	[ "$status" -ne 0 ]
}

@test "verifyBrokerDigests: passes for the dbp-api fixture brokers" {
	cp "$SIGNING_FIXTURES"/*.com.json "$SOURCE_DIR"
	jq '.active_data_brokers = ["anywho.com.json", "verecor.com.json"]' "$SIGNING_FIXTURES/main_config.json" > "$MAIN_CONFIG"

	run verifyBrokerDigests "$SOURCE_DIR" "$MAIN_CONFIG"
	[ "$status" -eq 0 ]
}
