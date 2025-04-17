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
#   action: 'new' (default), 'restack', 'clean', or 'push'
#   --branch-prefix: Optional prefix for branch names (default: username/)
#

# Check if gh is installed
check_command gh

VERSION_RELEASE=1000
VERSION_PHASED=2000

default_prefix="$(whoami)/"

# Parse command line arguments
action="new"
branch_prefix="${default_prefix}"

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
        *)
            echo "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

create_branches() {
    local branch_prefix="$1"
    local feed_url="$2"

    # Store current branch to return to later
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    echo "Creating branches with prefix: ${branch_prefix}"

    # Branch for outdated URL changes
    branch_outdated="${branch_prefix}outdated"
    echo "Creating branch: ${branch_outdated}"
    git checkout -b "${branch_outdated}"

    # Update Info.plist with the custom feed URL
    plutil -replace SUFeedURL -string "${feed_url}" "${info_plist}"
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

    # Trigger the orchestrated workflow
    echo "Triggering Sparkle test builds workflow"
    gh workflow run macos_create_sparkle_test_builds.yml --ref "${branch_outdated}" -f branch_prefix="${branch_prefix}"
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
        echo "Invalid action: ${action}. Use 'new', 'restack', 'clean', or 'push'."
        exit 1
    fi
else
    if [[ "${action}" == "new" ]]; then
        # Ask for custom SUFeedURL
        while true; do
            read -rp "Enter custom SUFeedURL for testing: " feed_url
            if [[ -n "${feed_url}" ]]; then
                break
            fi
            echo "Error: SUFeedURL cannot be empty"
        done
        create_branches "${branch_prefix}" "${feed_url}"
    elif [[ "${action}" == "restack" ]]; then
        echo "Branches do not exist. Cannot restack."
        exit 1
    else
        echo "Invalid action: ${action}. Use 'new', 'restack', 'clean', or 'push'."
        exit 1
    fi
fi
