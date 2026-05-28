#!/usr/bin/env bash

# Sparkle Update Checker
# Checks for new Sparkle releases and updates the pinned version in Package.swift.
# Outputs version info and release notes for use in CI PR creation.
#
# Environment variables:
#   DRY_RUN=1    - Skip file modifications, only print what would change
#   GH_TOKEN     - GitHub token for API access (optional, uses gh auth if available)

set -euo pipefail

PACKAGE_SWIFT="macOS/LocalPackages/AppUpdater/Package.swift"
SPARKLE_REPO="sparkle-project/Sparkle"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "::error::$1" >&2; exit 1; }

# Extract the pinned Sparkle version from Package.swift
get_current_version() {
    sed -nE 's/.*\.package\(url:.*Sparkle\.git",[[:space:]]*exact:[[:space:]]*"([^"]+)".*/\1/p' "$PACKAGE_SWIFT"
}

# Query GitHub once for Sparkle releases. Callers derive both latest version and notes from this payload.
fetch_releases() {
    gh api "repos/${SPARKLE_REPO}/releases" --paginate
}

# Extract the latest non-draft, non-prerelease Sparkle version from a releases payload.
get_latest_version() {
    jq -r '
        [ .[] | select(.draft == false and .prerelease == false) ][0].tag_name
        | sub("^v"; "")
    '
}

# Parse semver into components: "2.8.1" -> "2 8 1"
parse_semver() {
    local v="${1#v}"
    if [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    fi
}

# Compare two semver strings. Outputs: major, minor, patch, or up-to-date
compare_versions() {
    local cur_parts lat_parts
    cur_parts=$(parse_semver "$1")
    lat_parts=$(parse_semver "$2")

    [[ -z "$cur_parts" || -z "$lat_parts" ]] && { echo "unknown"; return; }

    read -r cur_major cur_minor cur_patch <<< "$cur_parts"
    read -r lat_major lat_minor lat_patch <<< "$lat_parts"

    if (( lat_major > cur_major )); then
        echo "major"
    elif (( lat_major == cur_major && lat_minor > cur_minor )); then
        echo "minor"
    elif (( lat_major == cur_major && lat_minor == cur_minor && lat_patch > cur_patch )); then
        echo "patch"
    else
        echo "up-to-date"
    fi
}

# Collect release notes for all versions between current (exclusive) and latest (inclusive).
# Outputs markdown.
collect_release_notes() {
    local current="$1"
    local latest="$2"

    jq -r --arg current "$current" --arg latest "$latest" '
        [ .[] | select(.draft == false and .prerelease == false) ] as $releases
        | ($releases | map(.tag_name | sub("^v"; "")) | index($latest)) as $latest_index
        | ($releases | map(.tag_name | sub("^v"; "")) | index($current)) as $current_index
        | if $latest_index == null then
            empty
          else
            $releases[$latest_index:($current_index // ($releases | length))]
            | map(
                "## \(if ((.name // "") == "") then .tag_name else .name end)\n\n\(.body // "")\n"
              )
            | join("\n")
          end
    '
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    [[ -f "$PACKAGE_SWIFT" ]] || die "Package.swift not found at ${PACKAGE_SWIFT}. Run from repo root."

    local current releases_json latest bump_type
    current=$(get_current_version)
    [[ -n "$current" ]] || die "Could not parse current Sparkle version from ${PACKAGE_SWIFT}"

    releases_json=$(fetch_releases) || die "Failed to query GitHub API"
    latest=$(echo "$releases_json" | get_latest_version)
    [[ -n "$latest" ]] || die "Could not determine latest Sparkle release"

    echo "Current Sparkle version: ${current}"
    echo "Latest Sparkle version:  ${latest}"

    bump_type=$(compare_versions "$current" "$latest")

    if [[ "$bump_type" == "up-to-date" ]]; then
        echo "Sparkle is already up-to-date."
        echo "update_available=false" >> "${GITHUB_OUTPUT:-/dev/null}"
        exit 0
    fi

    if [[ "$bump_type" == "unknown" ]]; then
        die "Could not parse semver from current='${current}' or latest='${latest}'"
    fi

    echo "Update type: ${bump_type}"

    # Collect release notes
    local release_notes
    release_notes=$(echo "$releases_json" | collect_release_notes "$current" "$latest")

    # Export outputs for the workflow
    local output="${GITHUB_OUTPUT:-/dev/null}"
    echo "update_available=true" >> "$output"
    echo "current_version=${current}" >> "$output"
    echo "latest_version=${latest}" >> "$output"
    echo "bump_type=${bump_type}" >> "$output"

    # Multi-line release notes output
    {
        echo "release_notes<<RELEASE_NOTES_EOF"
        echo "$release_notes"
        echo "RELEASE_NOTES_EOF"
    } >> "$output"

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        echo ""
        echo "=== DRY RUN === Would update Package.swift: ${current} -> ${latest}"
        echo ""
        echo "Release notes:"
        echo "$release_notes"
        exit 0
    fi

    # Update Package.swift
    local escaped_current="${current//./\\.}"
    sed -i '' "s|exact: \"${escaped_current}\"|exact: \"${latest}\"|" "$PACKAGE_SWIFT"
    echo "Updated ${PACKAGE_SWIFT}: ${current} -> ${latest}"
}

main "$@"
