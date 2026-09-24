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

is_release_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Succeeds when version $1 is greater than version $2 (both plain X.Y.Z)
version_gt() {
    local a_major a_minor a_patch b_major b_minor b_patch
    IFS=. read -r a_major a_minor a_patch <<< "$1"
    IFS=. read -r b_major b_minor b_patch <<< "$2"

    (( a_major != b_major )) && { (( a_major > b_major )); return; }
    (( a_minor != b_minor )) && { (( a_minor > b_minor )); return; }
    (( a_patch > b_patch ))
}

# Outputs: major, minor, or patch. Assumes latest > current.
bump_type() {
    local cur_major cur_minor lat_major lat_minor
    IFS=. read -r cur_major cur_minor _ <<< "$1"
    IFS=. read -r lat_major lat_minor _ <<< "$2"

    if (( lat_major > cur_major )); then
        echo "major"
    elif (( lat_minor > cur_minor )); then
        echo "minor"
    else
        echo "patch"
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
            grep -F "github.com/${DEP_REPO}" "$file" \
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

# Prints "<version> <tag>" for every published, non-prerelease X.Y.Z release, oldest first.
list_releases() {
    local tags tag ver
    tags=$(gh api "repos/${DEP_REPO}/releases" --paginate --jq \
        '.[] | select(.prerelease == false and .draft == false) | .tag_name') || die "Failed to query GitHub API"

    while IFS= read -r tag; do
        ver="${tag#v}"
        if is_release_version "$ver"; then
            echo "${ver} ${tag}"
        fi
    done <<< "$tags" | sort -V
}

# Collect release notes for all releases between current (exclusive) and latest (inclusive),
# newest first. Outputs markdown.
collect_release_notes() {
    local current="$1" latest="$2" releases="$3"
    local notes="" ver tag release_json name body

    while read -r ver tag; do
        version_gt "$ver" "$current" || continue
        version_gt "$ver" "$latest" && continue

        release_json=$(gh api "repos/${DEP_REPO}/releases/tags/${tag}") || true
        name=$(echo "$release_json" | jq -r '.name // empty')
        body=$(echo "$release_json" | jq -r '.body // empty')

        notes+="## ${name:-$tag}"$'\n\n'
        if [[ -n "$body" ]]; then
            notes+="$body"$'\n\n'
        fi
    done < <(echo "$releases" | sort -r -V)

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

    is_release_version "$current" || die "Current ${PACKAGE_NAME} pin '${current}' is not a plain X.Y.Z release"

    local releases latest
    releases=$(list_releases)
    latest=$(echo "$releases" | tail -n 1 | cut -d ' ' -f 1)
    [[ -n "$latest" ]] || die "Could not determine latest ${PACKAGE_NAME} release"

    echo "Latest ${PACKAGE_NAME} version:  ${latest}"

    if ! version_gt "$latest" "$current"; then
        echo "${PACKAGE_NAME} is already up-to-date."
        echo "update_available=false" >> "$output"
        exit 0
    fi

    local bump
    bump=$(bump_type "$current" "$latest")
    echo "Update type: ${bump}"

    local release_notes
    release_notes=$(collect_release_notes "$current" "$latest" "$releases")

    # Export outputs for the workflow
    echo "update_available=true" >> "$output"
    echo "current_version=${current}" >> "$output"
    echo "latest_version=${latest}" >> "$output"
    echo "bump_type=${bump}" >> "$output"

    # Multi-line release notes output, with a delimiter that can't appear in the notes
    local delimiter
    delimiter="RELEASE_NOTES_$(openssl rand -hex 16)"
    {
        echo "release_notes<<${delimiter}"
        echo "$release_notes"
        echo "${delimiter}"
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
