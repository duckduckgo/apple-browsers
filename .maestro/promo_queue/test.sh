#!/bin/zsh

set -eu

start_epoch=$(date +%s)
script_dir=${0:A:h}
repo_root=${script_dir:h:h}
workspace_path="$repo_root/DuckDuckGo.xcworkspace"
derived_data_path="$repo_root/.promo-queue-derived-data"
scheme="iOS Browser Alpha"
configuration="Alpha Debug"
expected_bundle_id="com.duckduckgo.mobile.ios.alpha"
run_stamp=$(date -u +%Y%m%dT%H%M%SZ)
artifact_root=${PROMO_QUEUE_ARTIFACT_ROOT:-"$script_dir/artifacts/team-$run_stamp"}
setup_log="$artifact_root/setup.log"

mkdir -p "$artifact_root/xcodebuildmcp" "$artifact_root/devices"
exec > >(tee "$setup_log") 2>&1

finish() {
    exit_status=$?
    trap - EXIT
    elapsed_seconds=$(( $(date +%s) - start_epoch ))
    print -- "Setup and suite elapsed seconds: $elapsed_seconds"
    print -- "Exit status: $exit_status"
    print -- "Artifacts: $artifact_root"
    print -- "Fresh Maestro simulators were retained for inspection; the next run replaces them."
    exit "$exit_status"
}

trap finish EXIT

for required_command in xcodebuildmcp maestro python3 curl git shasum; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        print -u2 -- "Required command is not installed: $required_command"
        exit 2
    fi
done

if [[ ! -d "$workspace_path" ]]; then
    print -u2 -- "Workspace not found: $workspace_path"
    exit 2
fi

print -- "Promo Queue branch: $(git -C "$repo_root" branch --show-current)"
print -- "Promo Queue build SHA: $(git -C "$repo_root" rev-parse HEAD)"
print -- "Workspace: $workspace_path"
print -- "Scheme/configuration: $scheme / $configuration"

device_catalog=$(maestro list-devices --platform ios 2>&1)
print -r -- "$device_catalog" >"$artifact_root/devices/catalog.log"

supports_device() {
    local device_model=$1
    local device_os=$2

    print -r -- "$device_catalog" | awk -v model="$device_model" -v os="$device_os" '
        $1 == model && index($0, os) { found = 1 }
        END { exit found ? 0 : 1 }
    '
}

select_device_set() {
    local candidate_os
    local device_model
    local all_supported
    local -a candidate_oses
    local -a candidate_models

    if [[ -n ${PROMO_QUEUE_DEVICE_OS:-} ]]; then
        candidate_oses=("$PROMO_QUEUE_DEVICE_OS")
    else
        # Prefer the runtime used to certify these flows, then supported newer quartets.
        candidate_oses=(iOS-18-6 iOS-26-4 iOS-26-5 iOS-27-0)
    fi

    for candidate_os in "${candidate_oses[@]}"; do
        if [[ "$candidate_os" == iOS-18-* ]]; then
            candidate_models=(iPhone-16-Pro iPhone-16-Pro-Max iPhone-16e iPhone-16-Plus)
        else
            candidate_models=(iPhone-17-Pro iPhone-17-Pro-Max iPhone-17e iPhone-Air)
        fi

        all_supported=true
        for device_model in "${candidate_models[@]}"; do
            if ! supports_device "$device_model" "$candidate_os"; then
                all_supported=false
                break
            fi
        done

        if [[ "$all_supported" == true ]]; then
            selected_device_os=$candidate_os
            device_models=("${candidate_models[@]}")
            return 0
        fi
    done

    return 1
}

typeset selected_device_os=""
typeset -a device_models
typeset -a device_ids

if ! select_device_set; then
    print -u2 -- "No supported four-iPhone Maestro device set is installed."
    print -u2 -- "Available devices were recorded at $artifact_root/devices/catalog.log"
    exit 2
fi

if [[ "$selected_device_os" != iOS-18-6 ]]; then
    print -- "Warning: using $selected_device_os because the certified iOS-18-6 quartet is unavailable."
fi
print -- "Creating fresh simulators on $selected_device_os"

for device_model in "${device_models[@]}"; do
    device_log="$artifact_root/devices/$device_model.log"
    maestro start-device \
        --force-create \
        --platform ios \
        --device-model "$device_model" \
        --device-os "$selected_device_os" \
        --device-locale en_US 2>&1 | tee "$device_log"
    device_status=${pipestatus[1]}
    if (( device_status != 0 )); then
        print -u2 -- "Failed to create $device_model on $selected_device_os"
        exit "$device_status"
    fi

    device_id=$(sed -nE 's/.*UUID ([0-9A-Fa-f-]{36}).*/\1/p' "$device_log" | tail -n 1 | tr '[:lower:]' '[:upper:]')
    if [[ -z "$device_id" ]]; then
        print -u2 -- "Maestro did not report a simulator UUID for $device_model"
        exit 1
    fi
    device_ids+=("$device_id")
    print -- "$device_model: $device_id"
done

primary_device_id=${device_ids[1]}
build_attempt=1
build_status=1

while (( build_attempt <= 2 )); do
    build_result="$artifact_root/xcodebuildmcp/build-and-run-attempt-$build_attempt.json"
    print -- "Building, installing, and launching the Alpha app on $primary_device_id (attempt $build_attempt of 2)"
    xcodebuildmcp simulator build-and-run \
        --workspace-path "$workspace_path" \
        --scheme "$scheme" \
        --configuration "$configuration" \
        --simulator-id "$primary_device_id" \
        --derived-data-path "$derived_data_path" \
        --output json | tee "$build_result"
    build_status=${pipestatus[1]}
    if (( build_status == 0 )); then
        break
    fi

    if (( build_attempt == 2 )) || ! grep -Eq 'IXErrorDomain|Failed to (create|locate) promise' "$build_result"; then
        exit "$build_status"
    fi

    print -- "Build succeeded but the simulator install was transiently unavailable; retrying."
    sleep 2
    (( build_attempt += 1 ))
done

app_path_result="$artifact_root/xcodebuildmcp/app-path.json"
xcodebuildmcp simulator get-app-path \
    --workspace-path "$workspace_path" \
    --scheme "$scheme" \
    --configuration "$configuration" \
    --platform "iOS Simulator" \
    --simulator-id "$primary_device_id" \
    --derived-data-path "$derived_data_path" \
    --output json | tee "$app_path_result"
app_path_status=${pipestatus[1]}
if (( app_path_status != 0 )); then
    exit "$app_path_status"
fi

app_path=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["data"]["artifacts"]["appPath"])' "$app_path_result")
if [[ ! -d "$app_path" ]]; then
    print -u2 -- "Built app was not found: $app_path"
    exit 1
fi

bundle_result="$artifact_root/xcodebuildmcp/bundle-id.json"
xcodebuildmcp simulator get-app-bundle-id \
    --app-path "$app_path" \
    --output json | tee "$bundle_result"
bundle_status=${pipestatus[1]}
if (( bundle_status != 0 )); then
    exit "$bundle_status"
fi

actual_bundle_id=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["data"]["artifacts"]["bundleId"])' "$bundle_result")
if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
    print -u2 -- "Unexpected bundle identifier: $actual_bundle_id"
    exit 1
fi
print -- "Verified app: $app_path"
print -- "Verified bundle identifier: $actual_bundle_id"

install_app() {
    local target_device_id=$1
    local attempt=1
    local install_status
    local install_result

    while (( attempt <= 3 )); do
        install_result="$artifact_root/xcodebuildmcp/install-$target_device_id-attempt-$attempt.json"
        print -- "Installing on $target_device_id (attempt $attempt of 3)"
        xcodebuildmcp simulator install \
            --simulator-id "$target_device_id" \
            --app-path "$app_path" \
            --output json | tee "$install_result"
        install_status=${pipestatus[1]}
        if (( install_status == 0 )); then
            return 0
        fi

        if (( attempt < 3 )); then
            print -- "Install failed; retrying the transient simulator operation."
            sleep 2
        fi
        (( attempt += 1 ))
    done

    return "$install_status"
}

for target_index in 2 3 4; do
    install_app "${device_ids[$target_index]}"
done

# Make the Simulator frontend visible for a local developer watching the run.
xcodebuildmcp simulator-management open --output json \
    | tee "$artifact_root/xcodebuildmcp/open-simulator.json"
open_status=${pipestatus[1]}
if (( open_status != 0 )); then
    exit "$open_status"
fi

device_csv=${(j:,:)device_ids}
print -- "Running one Promo Queue flow per fresh simulator: $device_csv"

set +e
PROMO_QUEUE_DEVICE_ID="$device_csv" \
PROMO_QUEUE_ARTIFACT_ROOT="$artifact_root/maestro" \
    "$script_dir/run_with_fixtures.sh" \
    --shard-split=4 \
    "$script_dir"
suite_status=$?
set -e

exit "$suite_status"
