#!/bin/bash -x

#
# Creates or restacks branches for Sparkle update testing:
# 1. outdated: Changes appcast URL to point to your test server
# 2. release: Updates version to VERSION_RELEASE (1000)
# 3. phased: Updates version to VERSION_PHASED (2000) for phased rollout testing
#
# Usage: prepare_sparkle_test_builds.sh [action] [--branch-prefix=PREFIX] [--output-dir=DIR] [--appcast=URL] [--key-file=PATH]
#
# Actions:
#   new (default): Create new branches for testing
#     Required: --appcast=URL
#     Optional: --branch-prefix=PREFIX
#   restack: Restack existing branches on top of current branch
#     Required: --branch-prefix=PREFIX
#   clean: Delete all test branches
#     Required: --branch-prefix=PREFIX
#   push: Push branches and trigger builds
#     Required: --branch-prefix=PREFIX
#   generate_appcast: Generate appcast.xml with test builds
#     Required: --branch-prefix=PREFIX
#     Optional: --output-dir=DIR, --key-file=PATH
#
# Options:
#   --branch-prefix: Prefix for branch names (default: username/)
#   --output-dir: Directory for appcast.xml and builds (default: ~/Desktop)
#   --appcast: Custom appcast URL for testing (required for 'new' action)
#   --key-file: Key file for signing appcast (default: output-dir/key-file)
#
# Example workflow:
#   1. ./prepare_sparkle_test_builds.sh new --branch-prefix=test/ --appcast=https://test.example.com/appcast.xml
#   2. ./prepare_sparkle_test_builds.sh push --branch-prefix=test/
#   3. ./prepare_sparkle_test_builds.sh generate_appcast --branch-prefix=test/ --output-dir=~/Desktop/test-updates
#      Note: Place the key-file in ~/Desktop/test-updates or specify its location with --key-file
#   4. Upload appcast.xml to your test server
#   5. Download and test the outdated build
#

if ! [[ $common_sh ]]; then
	cwd="$(dirname "${BASH_SOURCE[0]}")"
	source "${cwd}/helpers/common.sh"
fi

# Define paths relative to script location
info_plist="${cwd}/../DuckDuckGo/Info.plist"
build_number_xcconfig="${cwd}/../Configuration/BuildNumber.xcconfig"

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
key_file=""

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
            # Ensure branch_prefix ends with a slash
            if [[ "${branch_prefix}" != */ ]]; then
                branch_prefix="${branch_prefix}/"
            fi
            ;;
        --output-dir=*)
            output_dir="${arg#*=}"
            ;;
        --appcast=*)
            appcast_url="${arg#*=}"
            ;;
        --key-file=*)
            key_file="${arg#*=}"
            ;;
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

# Set default key file if not provided
if [[ -z "${key_file}" ]]; then
    key_file="${output_dir}/key-file"
fi

create_branches() {
    local branch_prefix="$1"
    local appcast_url="$2"

    # Store current branch to return to later
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    echo "Creating test branches with prefix: ${branch_prefix}"

    # Branch for outdated URL changes
    branch_outdated="${branch_prefix}outdated"
    echo "Creating branch: ${branch_outdated}"
    echo "  - Updating SUFeedURL to: ${appcast_url}"
    git checkout -b "${branch_outdated}"
    plutil -replace SUFeedURL -string "${appcast_url}" "${info_plist}"
    git add "${info_plist}"
    git commit -m "Update SUFeedURL for testing"

    # Branch for regular release
    branch_release="${branch_prefix}release"
    echo "Creating branch: ${branch_release}"
    echo "  - Setting version to: ${VERSION_RELEASE}"
    git checkout -b "${branch_release}"
    sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${VERSION_RELEASE}/" "${build_number_xcconfig}"
    git add "${build_number_xcconfig}"
    git commit -m "Update version to ${VERSION_RELEASE}"

    # Branch for phased rollout
    branch_phased="${branch_prefix}phased"
    echo "Creating branch: ${branch_phased}"
    echo "  - Setting version to: ${VERSION_PHASED}"
    git checkout -b "${branch_phased}"
    sed -i '' "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${VERSION_PHASED}/" "${build_number_xcconfig}"
    git add "${build_number_xcconfig}"
    git commit -m "Update version to ${VERSION_PHASED}"

    # Return to original branch
    echo "Returning to original branch: ${current_branch}"
    git checkout "${current_branch}"
}

restack_branches() {
    local branch_prefix="$1"

    branch_outdated="${branch_prefix}outdated"
    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    current_branch=$(git rev-parse --abbrev-ref HEAD)

    echo "Restacking test branches on top of: ${current_branch}"
    echo "Branch order:"
    echo "  - ${branch_outdated}"
    echo "  - ${branch_release}"
    echo "  - ${branch_phased}"

    echo "Rebasing ${branch_outdated} onto ${current_branch}..."
    git rebase --onto "${current_branch}" "${current_branch}" "${branch_outdated}"

    echo "Rebasing ${branch_release} onto ${branch_outdated}..."
    git rebase --onto "${branch_outdated}" "${branch_outdated}" "${branch_release}"

    echo "Rebasing ${branch_phased} onto ${branch_release}..."
    git rebase --onto "${branch_release}" "${branch_release}" "${branch_phased}"

    echo "Returning to original branch: ${current_branch}"
    git checkout "${current_branch}"
}

clean_branches() {
    local branch_prefix="$1"

    branch_outdated="${branch_prefix}outdated"
    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    echo "Cleaning up test branches:"
    echo "  - ${branch_outdated}"
    echo "  - ${branch_release}"
    echo "  - ${branch_phased}"

    # Get the current branch to return to later
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    # Delete each branch if it exists
    for branch in "${branch_outdated}" "${branch_release}" "${branch_phased}"; do
        if git show-ref --verify --quiet "refs/heads/${branch}"; then
            echo "Deleting branch: ${branch}"
            git branch -D "${branch}"
        else
            echo "Branch not found: ${branch}"
        fi
    done

    echo "Returning to original branch: ${current_branch}"
    git checkout "${current_branch}"
}

push_branches() {
    local branch_prefix="$1"

    branch_outdated="${branch_prefix}outdated"
    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    echo "Pushing test branches to remote:"
    echo "  - ${branch_outdated}"
    echo "  - ${branch_release}"
    echo "  - ${branch_phased}"

    # Force push all branches
    for branch in "${branch_outdated}" "${branch_release}" "${branch_phased}"; do
        echo "Pushing branch: ${branch}"
        git push -f origin "${branch}:${branch}"
    done

    echo "Triggering builds for test branches:"
    for branch in "${branch_outdated}" "${branch_release}" "${branch_phased}"; do
        echo "  - ${branch}"
        gh workflow run .github/workflows/macos_build_notarized.yml \
            --ref "${branch}" \
            -f release-type=review \
            -f create-dmg=true
    done

    echo "✅ Builds triggered successfully!"

    read -rp "Do you want to generate the appcast after builds complete? [Y/n]: " should_generate_appcast
    if [[ "${should_generate_appcast}" != "n" ]]; then
        generate_appcast_xml "${branch_prefix}"
    fi
}

wait_for_builds() {
    local branch_prefix="$1"

    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    echo "Waiting for test builds to complete (this should take about 15 minutes):"
    echo "  - ${branch_release}"
    echo "  - ${branch_phased}"

    # Get run IDs first
    run_ids=()
    branches=("${branch_release}" "${branch_phased}")
    for branch in "${branches[@]}"; do
        echo "Getting run ID for ${branch}..."
        run_id=$(gh run list --workflow=macos_build_notarized.yml --branch="${branch}" --limit=1 --json databaseId --jq '.[0].databaseId')
        run_ids+=("${run_id}")
    done

    # Check if all builds have completed
    while true; do
        all_completed=true
        failed_builds=()

        for i in "${!run_ids[@]}"; do
            status=$(gh run view "${run_ids[$i]}" --json status --jq '.status')

            if [[ "$status" == "completed" ]]; then
                conclusion=$(gh run view "${run_ids[$i]}" --json conclusion --jq '.conclusion')
                if [[ "$conclusion" != "success" ]]; then
                    failed_builds+=("${branches[$i]}")
                fi
            else
                all_completed=false
                break
            fi
        done

        if $all_completed; then
            break
        fi

        echo "Builds still in progress... (checking again in 30 seconds)"
        sleep 30
    done

    if [ ${#failed_builds[@]} -eq 0 ]; then
        echo "✅ All test builds completed successfully!"
        return 0
    else
        echo "❌ Some test builds failed:"
        for branch in "${failed_builds[@]}"; do
            echo "  - ${branch}"
        done
        echo "To rerun failed builds, use:"
        for branch in "${failed_builds[@]}"; do
            echo "gh workflow run .github/workflows/macos_build_notarized.yml --ref ${branch} -f release-type=review -f create-dmg=true"
        done
        echo "After the builds complete successfully, run:"
        echo "./prepare_sparkle_test_builds.sh generate_appcast --branch-prefix=${branch_prefix} --output-dir=${output_dir}"
        return 1
    fi
}

download_builds() {
    local branch_prefix="$1"
    local updates_dir="$2"

    branch_release="${branch_prefix}release"
    branch_phased="${branch_prefix}phased"

    echo "Downloading builds to ${updates_dir}"

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
        output_file="${updates_dir}/$(basename "${s3_url}")"

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

    echo "✅ All builds downloaded successfully to ${updates_dir}"
    return 0
}

generate_appcast_xml() {
    local branch_prefix="$1"

    # Check for key file
    if [[ ! -f "${key_file}" ]]; then
        echo "❌ Key file not found at ${key_file}"
        echo "Please place the key file in the output directory or specify its location with --key-file"
        exit 1
    fi

    # Create updates directory
    updates_dir="${output_dir}/updates"
    if [[ ! -d "${updates_dir}" ]]; then
        echo "Creating updates directory: ${updates_dir}"
        mkdir -p "${updates_dir}"
    fi

    # First wait for all builds to complete
    echo "Waiting for builds to complete before downloading..."
    if ! wait_for_builds "${branch_prefix}"; then
        exit 1
    fi

    # Download all builds
    echo "Downloading builds to ${updates_dir}"
    if ! download_builds "${branch_prefix}" "${updates_dir}"; then
        exit 1
    fi

    # Generate appcast
    echo "Generating appcast.xml..."
    if ! generate_appcast -o "${output_dir}/appcast.xml" \
        --ed-key-file "${key_file}" \
        --versions "${VERSION_RELEASE},${VERSION_PHASED}" \
        "${updates_dir}"; then
        echo "❌ Failed to generate appcast"
        exit 1
    fi

    # Get S3 URLs and replace enclosure URLs in appcast.xml
    echo "Updating enclosure URLs in appcast.xml..."
    for branch in "${branch_release}" "${branch_phased}"; do
        echo "  - Getting URL for ${branch}..."
        run_id=$(gh run list --workflow=macos_build_notarized.yml --branch="${branch}" --limit=1 --json databaseId --jq '.[0].databaseId')
        s3_url=$(gh run view "${run_id}" --log | grep -o "s3://[^ ]*\.dmg" | tail -n 1)
        https_url="https://staticcdn.duckduckgo.com/${s3_url#s3://ddg-staticcdn/}"

        # Get the version number from the branch
        version=$(echo "${branch}" | grep -o "[0-9]*$")

        # Replace the enclosure URL in appcast.xml
        sed -i '' "s|url=\"[^\"]*${version}\.dmg\"|url=\"${https_url}\"|g" "${output_dir}/appcast.xml"
    done

    # Remove sparkle:deltas section using perl for better multiline handling
    echo "Removing delta updates from appcast.xml..."
    perl -i -pe 'BEGIN{undef $/;} s/<sparkle:deltas>.*?<\/sparkle:deltas>//gs' "${output_dir}/appcast.xml"

    # Add description to each item
    echo "Adding descriptions to appcast.xml..."
    description='<description><![CDATA[<h3 style="font-size:14px">What'\''s new</h3>
<ul>
<li>Bug fixes and improvements.</li>
</ul>]]></description>'
    perl -i -pe 's|</item>|'"${description}"'\n</item>|g' "${output_dir}/appcast.xml"

    # Get S3 URL for outdated branch
    echo "Getting URL for outdated build..."
    branch_outdated="${branch_prefix}outdated"
    run_id=$(gh run list --workflow=macos_build_notarized.yml --branch="${branch_outdated}" --limit=1 --json databaseId --jq '.[0].databaseId')
    s3_url=$(gh run view "${run_id}" --log | grep -o "s3://[^ ]*\.dmg" | tail -n 1)
    outdated_url="https://staticcdn.duckduckgo.com/${s3_url#s3://ddg-staticcdn/}"

    echo "✅ Appcast generated successfully at ${output_dir}/appcast.xml"
    echo "To test the update:"
    echo "1. Upload ${output_dir}/appcast.xml to your test server"
    echo "2. Download the outdated build: ${outdated_url}"
    echo "3. Install and run the outdated build to test the update process"
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
    generate_appcast_xml "${branch_prefix}"
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
