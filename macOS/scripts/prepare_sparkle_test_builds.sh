#!/bin/bash -x

if ! [[ $common_sh ]]; then
	cwd="$(dirname "${BASH_SOURCE[0]}")"
	source "${cwd}/helpers/common.sh"
fi

# Define paths relative to script location
info_plist="${cwd}/../DuckDuckGo/Info.plist"
build_number_xcconfig="${cwd}/../Configuration/BuildNumber.xcconfig"

#
# Creates or restacks branches for Sparkle update testing:
# 1. outdated: Changes appcast URL
# 2. release: Updates version to VERSION_RELEASE
# 3. phased: Updates version to VERSION_PHASED for phased rollout testing
#
# Usage: prepare_sparkle_test_builds.sh [action] [--branch-prefix=PREFIX]
#   action: 'new' (default), 'restack', 'clean', 'push', or 'generate_appcast'
#   --branch-prefix: Optional prefix for branch names (default: username/)
#

check_command gh
check_command wget
check_command generate_appcast

VERSION_RELEASE=1000
VERSION_PHASED=2000

DEFAULT_PREFIX="$(whoami)/"
DEFAULT_OUTPUT_DIR="${HOME}/Desktop"

# Parse command line arguments
action="new"
branch_prefix="${DEFAULT_PREFIX}"
output_dir="${DEFAULT_OUTPUT_DIR}"
appcast_url=""

# First argument is action
if [[ $# -gt 0 ]]; then
    action="$1"
    shift
fi

# Parse remaining arguments
for arg in "$@"; do
    case $arg in
        --branch-prefix=*)
            branch_prefix="${arg#*=}"
            ;;
        --output-dir=*)
            output_dir="${arg#*=}"
            ;;
        --appcast=*)
            appcast_url="${arg#*=}"
            ;;
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

create_branches() {
    local branch_prefix="$1"
    local appcast_url="$2"

    # Store current branch to return to later
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    echo "Creating branches with prefix: ${branch_prefix}"

    # Branch for outdated URL changes
    branch_outdated="${branch_prefix}outdated"
    echo "Creating branch: ${branch_outdated}"
    git checkout -b "${branch_outdated}"

    # Update Info.plist with the custom feed URL
    plutil -replace SUFeedURL -string "${appcast_url}" "${info_plist}"
    git add "${info_plist}"
    git commit -m "Update SUFeedURL for testing"

    # Branch for regular release
    branch_release="${branch_prefix}release"
    echo "Creating branch: ${branch_release}"
    git checkout -b "${branch_release}"
    sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${VERSION_RELEASE}/" "${build_number_xcconfig}"
    git add "${build_number_xcconfig}"
    git commit -m "Update version to ${VERSION_RELEASE}"

    # Branch for phased rollout
    branch_phased="${branch_prefix}phased"
    echo "Creating branch: ${branch_phased}"
    git checkout -b "${branch_phased}"
    sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${VERSION_PHASED}/" "${build_number_xcconfig}"
    git add "${build_number_xcconfig}"
    git commit -m "Update version to ${VERSION_PHASED}"

    # Return to original branch
    git checkout "${current_branch}"
}

restack_branches() {
    local branch_prefix="$1"

    branch_outdated="${branch_prefix}outdated"
    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    current_branch=$(git rev-parse --abbrev-ref HEAD)

    git rebase --onto "${current_branch}" "${current_branch}" "${branch_outdated}"
    git rebase --onto "${branch_outdated}" "${branch_outdated}" "${branch_release}"
    git rebase --onto "${branch_release}" "${branch_release}" "${branch_phased}"

    git checkout "${current_branch}"
}

clean_branches() {
    local branch_prefix="$1"

    branch_outdated="${branch_prefix}outdated"
    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    echo "Cleaning up branches:"
    echo "- ${branch_outdated}"
    echo "- ${branch_release}"
    echo "- ${branch_phased}"

    # Get the current branch to return to later
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    # Delete each branch if it exists
    for branch in "${branch_outdated}" "${branch_release}" "${branch_phased}"; do
        if git show-ref --verify --quiet "refs/heads/${branch}"; then
            git branch -D "${branch}"
        fi
    done

    # Return to original branch
    git checkout "${current_branch}"
}

push_branches() {
    local branch_prefix="$1"

    branch_outdated="${branch_prefix}outdated"
    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    echo "Pushing branches:"
    echo "- ${branch_outdated}"
    echo "- ${branch_release}"
    echo "- ${branch_phased}"

    # Force push all branches
    for branch in "${branch_outdated}" "${branch_release}" "${branch_phased}"; do
        git push -f origin "${branch}:${branch}"
    done

    # Trigger all builds
    echo "Triggering builds:"
    for branch in "${branch_outdated}" "${branch_release}" "${branch_phased}"; do
        echo "- ${branch}"
        gh workflow run .github/workflows/macos_build_notarized.yml \
            --ref "${branch}" \
            -f release-type=review \
            -f create-dmg=true
    done

    echo "✅ Builds triggered successfully!"
}

wait_for_builds() {
    local branch_prefix="$1"

    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    echo "Checking build status for branches:"
    echo "- ${branch_release}"
    echo "- ${branch_phased}"

    # Check if all builds have completed
    while true; do
        all_completed=true
        failed_builds=()

        for branch in "${branch_release}" "${branch_phased}"; do
            status=$(gh run list --workflow=macos_build_notarized.yml --branch="${branch}" --limit=1 --json status --jq '.[0].status')

            if [[ "$status" == "completed" ]]; then
                conclusion=$(gh run list --workflow=macos_build_notarized.yml --branch="${branch}" --limit=1 --json conclusion --jq '.[0].conclusion')
                if [[ "$conclusion" != "success" ]]; then
                    failed_builds+=("${branch}")
                fi
            else
                all_completed=false
                break
            fi
        done

        if $all_completed; then
            break
        fi

        echo "Waiting for builds to complete..."
        sleep 30
    done

    if [ ${#failed_builds[@]} -eq 0 ]; then
        echo "✅ All builds completed successfully!"
        return 0
    else
        echo "❌ Some builds failed. To rerun failed builds, use:"
        for branch in "${failed_builds[@]}"; do
            echo "gh workflow run .github/workflows/macos_build_notarized.yml --ref ${branch} -f release-type=review -f create-dmg=true"
        done
        return 1
    fi
}

download_builds() {
    local branch_prefix="$1"
    local temp_dir="$2"

    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    echo "Downloading builds to ${temp_dir}"

    # Get S3 URLs for RELEASE and PHASED builds
    for branch in "${branch_release}" "${branch_phased}"; do
        echo "Getting S3 URL for ${branch}..."
        run_id=$(gh run list --workflow=macos_build_notarized.yml --branch="${branch}" --limit=1 --json databaseId --jq '.[0].databaseId')
        s3_url=$(gh run view "${run_id}" --log | grep -o "s3://[^ ]*\.dmg" | tail -n 1)

        if [[ -z "${s3_url}" ]]; then
            echo "❌ Failed to get S3 URL for ${branch}"
            return 1
        fi

        # Convert S3 URL to HTTPS URL
        https_url="https://staticcdn.duckduckgo.com/${s3_url#s3://ddg-staticcdn/}"
        output_file="${temp_dir}/$(basename "${s3_url}")"

        # Skip if file already exists
        if [[ -f "${output_file}" ]]; then
            echo "✅ File already exists: ${output_file}"
            continue
        fi

        echo "Downloading ${https_url}..."
        if ! wget -O "${output_file}" "${https_url}"; then
            echo "❌ Failed to download build for ${branch}"
            return 1
        fi
    done

    echo "✅ All builds downloaded successfully to ${temp_dir}"
    return 0
}

generate_appcast() {
    local branch_prefix="$1"

    # Check for key file first
    key_file="${output_dir}/key-file"
    if [[ ! -f "${key_file}" ]]; then
        echo "❌ Key file not found at ${key_file}"
        echo "Please place the key file in ${output_dir}"
        exit 1
    fi

    # Create temporary directory for downloads
    temp_dir="${output_dir}/updates"
    mkdir -p "${temp_dir}"

    # Check if files already exist
    if ls "${temp_dir}"/*.dmg 1> /dev/null 2>&1; then
        echo "✅ DMG files already exist in ${temp_dir}, skipping download"
    else
        # First wait for all builds to complete
        if ! wait_for_builds "${branch_prefix}"; then
            exit 1
        fi

        # Download all builds
        if ! download_builds "${branch_prefix}" "${temp_dir}"; then
            exit 1
        fi
    fi

    # Generate appcast
    echo "Generating appcast..."
    if ! generate_appcast -o "${temp_dir}/appcast.xml" \
        --ed-key-file "${key_file}" \
        --versions "${VERSION_RELEASE},${VERSION_PHASED}" \
        "${temp_dir}"; then
        echo "❌ Failed to generate appcast"
        exit 1
    fi

    echo "✅ Appcast generated successfully at ${temp_dir}/appcast.xml"
}

# Define branch names
branch_outdated="${branch_prefix}outdated"
branch_release="${branch_prefix}release"
branch_phased="${branch_prefix}phased"

# Check if branches exist
branches_exist() {
    git show-ref --verify --quiet "refs/heads/${branch_outdated}" && \
    git show-ref --verify --quiet "refs/heads/${branch_release}" && \
    git show-ref --verify --quiet "refs/heads/${branch_phased}"
}

if [[ "${action}" == "clean" ]]; then
    clean_branches "${branch_prefix}"
elif [[ "${action}" == "push" ]]; then
    if ! branches_exist; then
        echo "Missing branches. Cannot push."
        exit 1
    fi
    push_branches "${branch_prefix}"
elif [[ "${action}" == "generate_appcast" ]]; then
    if ! branches_exist; then
        echo "Missing branches. Cannot generate appcast."
        exit 1
    fi
    generate_appcast "${branch_prefix}"
elif branches_exist; then
    if [[ "${action}" == "new" ]]; then
        read -rp "Branches already exist. Restack them? (y/n): " restack
        if [[ "${restack}" == "y" ]]; then
            restack_branches "${branch_prefix}"
        else
            echo "Operation cancelled."
            exit 0
        fi
    elif [[ "${action}" == "restack" ]]; then
        restack_branches "${branch_prefix}"
    else
        echo "Invalid action: ${action}. Use 'new', 'restack', 'clean', 'push', or 'generate_appcast'."
        exit 1
    fi
else
    if [[ "${action}" == "new" ]]; then
        if [[ -z "${appcast_url}" ]]; then
            echo "Error: --appcast parameter is required for 'new' action"
            exit 1
        fi
        create_branches "${branch_prefix}" "${appcast_url}"
    elif [[ "${action}" == "restack" ]]; then
        echo "Branches do not exist. Cannot restack."
        exit 1
    else
        echo "Invalid action: ${action}. Use 'new', 'restack', 'clean', 'push', or 'generate_appcast'."
        exit 1
    fi
fi
