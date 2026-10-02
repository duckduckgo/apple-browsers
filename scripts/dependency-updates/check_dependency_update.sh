#!/usr/bin/env bash

# Dependency Update Checker
# Checks for new releases of an exact-pinned Swift package and updates the pin.
# Outputs version info and release notes for use in CI PR creation.
#
# Environment variables:
#   DEP_REPO    - GitHub repository of the dependency, e.g. "sparkle-project/Sparkle"
#   PIN_KIND    - Where the pin lives: "package-swift" (`exact:` in a Package.swift)
#                 or "pbxproj" (`kind = exactVersion;` in an Xcode project)
#   PIN_FILES   - Space-separated list of files holding the pin
#   DRY_RUN=1   - Skip file modifications, only print what would change
#   GH_TOKEN    - GitHub token for API access (optional, uses gh auth if available)

set -euo pipefail

: "${DEP_REPO:?DEP_REPO is required}"
: "${PIN_KIND:?PIN_KIND is required}"
: "${PIN_FILES:?PIN_FILES is required}"

# The Xcode package reference name and the SPM identity both derive from the repo name.
PACKAGE_NAME="${DEP_REPO##*/}"
PACKAGE_NAME="${PACKAGE_NAME%.git}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "::error::$1" >&2; exit 1; }

# Query GitHub for the latest release tag (strips leading "v" if present)
get_latest_version() {
    local tag
    tag=$(gh api "repos/${DEP_REPO}/releases/latest" --jq '.tag_name') || die "Failed to query GitHub API"
    echo "${tag#v}"
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

# ---------------------------------------------------------------------------
# Pin reading and writing
# ---------------------------------------------------------------------------

# Prints the pinned version found in $1, or nothing if there is no exact pin.
read_pin() {
    local file="$1"

    case "$PIN_KIND" in
        package-swift)
            { grep -F "github.com/${DEP_REPO}" "$file" || true; } \
                | sed -nE 's/.*\.package\(url:.*exact:[[:space:]]*"([^"]+)".*/\1/p' \
                | head -n 1
            ;;
        pbxproj)
            # Scope to this package's XCRemoteSwiftPackageReference block; its first
            # `version =` line is the one inside `requirement`.
            awk -v header="XCRemoteSwiftPackageReference \"${PACKAGE_NAME}\" */ = {" '
                index($0, header) { in_block = 1; next }
                in_block && /kind = / { kind = $0; sub(/.*kind = /, "", kind); sub(/;.*/, "", kind) }
                in_block && /version = / {
                    version = $0; sub(/.*version = /, "", version); sub(/;.*/, "", version); gsub(/"/, "", version)
                    if (kind == "exactVersion") print version
                    exit
                }
                in_block && /^\t\t};/ { exit }
            ' "$file"
            ;;
        *)
            die "Unknown PIN_KIND '${PIN_KIND}'"
            ;;
    esac
}

# Replaces version $2 with $3 in $1, touching only this package's pin.
write_pin() {
    local file="$1" current="$2" latest="$3" tmp
    tmp=$(mktemp)

    case "$PIN_KIND" in
        package-swift)
            awk -v repo="github.com/${DEP_REPO}" -v old="exact: \"${current}\"" -v new="exact: \"${latest}\"" '
                index($0, repo) && (i = index($0, old)) {
                    $0 = substr($0, 1, i - 1) new substr($0, i + length(old))
                }
                { print }
            ' "$file" > "$tmp"
            ;;
        pbxproj)
            awk -v header="XCRemoteSwiftPackageReference \"${PACKAGE_NAME}\" */ = {" -v new="${latest}" '
                index($0, header) { in_block = 1 }
                in_block && /version = / { sub(/version = [^;]*;/, "version = " new ";"); in_block = 0 }
                in_block && /^\t\t};/ { in_block = 0 }
                { print }
            ' "$file" > "$tmp"
            ;;
    esac

    # Write through the existing file to keep its permissions.
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Releases
# ---------------------------------------------------------------------------

# Collect release notes for all versions between current (exclusive) and latest (inclusive).
# Outputs markdown.
collect_release_notes() {
    local current="$1"
    local latest="$2"

    # Fetch non-prerelease tags in order (newest first, the API default)
    local tags
    tags=$(gh api "repos/${DEP_REPO}/releases" --paginate --jq \
        '[.[] | select(.prerelease == false) | .tag_name] | .[]') || return 0

    local notes=""
    local found_latest=false

    while IFS= read -r tag; do
        local ver="${tag#v}"

        if [[ "$found_latest" == false ]]; then
            [[ "$ver" == "$latest" ]] && found_latest=true || continue
        fi

        # Stop when we reach the current version (exclusive)
        [[ "$ver" == "$current" ]] && break

        # Fetch individual release details
        local release_json name body
        release_json=$(gh api "repos/${DEP_REPO}/releases/tags/${tag}") || true
        name=$(echo "$release_json" | jq -r '.name // empty')
        body=$(echo "$release_json" | jq -r '.body // empty')

        notes+="## ${name:-$tag}"$'\n\n'
        if [[ -n "$body" ]]; then
            notes+="$body"$'\n\n'
        fi
    done <<< "$tags"

    echo "$notes"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local output="${GITHUB_OUTPUT:-/dev/null}"
    local file current="" file_version

    for file in $PIN_FILES; do
        [[ -f "$file" ]] || die "Pin file not found at ${file}. Run from repo root."

        file_version=$(read_pin "$file")
        [[ -n "$file_version" ]] || die "Could not find an exact ${PACKAGE_NAME} pin in ${file}"

        if [[ -z "$current" ]]; then
            current="$file_version"
        elif [[ "$file_version" != "$current" ]]; then
            die "${PACKAGE_NAME} pins disagree: ${current} vs ${file_version} in ${file}"
        fi
    done

    echo "Current ${PACKAGE_NAME} version: ${current}"

    local latest bump_type
    latest=$(get_latest_version)
    [[ -n "$latest" ]] || die "Could not determine latest ${PACKAGE_NAME} release"

    echo "Latest ${PACKAGE_NAME} version:  ${latest}"

    bump_type=$(compare_versions "$current" "$latest")

    if [[ "$bump_type" == "up-to-date" ]]; then
        echo "${PACKAGE_NAME} is already up-to-date."
        echo "update_available=false" >> "$output"
        exit 0
    fi

    if [[ "$bump_type" == "unknown" ]]; then
        die "Could not parse semver from current='${current}' or latest='${latest}'"
    fi

    echo "Update type: ${bump_type}"

    # Collect release notes
    local release_notes
    release_notes=$(collect_release_notes "$current" "$latest")

    # Export outputs for the workflow
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
        echo "=== DRY RUN === Would update ${PIN_FILES}: ${current} -> ${latest}"
        echo ""
        echo "Release notes:"
        echo "$release_notes"
        exit 0
    fi

    for file in $PIN_FILES; do
        write_pin "$file" "$current" "$latest"
        [[ "$(read_pin "$file")" == "$latest" ]] || die "Failed to update ${PACKAGE_NAME} pin in ${file}"
        echo "Updated ${file}: ${current} -> ${latest}"
    done
}

main "$@"
