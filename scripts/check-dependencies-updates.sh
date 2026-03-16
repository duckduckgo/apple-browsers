#!/usr/bin/env bash

# Swift Package Update Checker
# Scans Xcode projects for Swift packages and checks for available updates
# Only shows first-level (direct) dependencies, not transitive ones
# Compatible with Bash 3.2+ (macOS default)

set -o pipefail

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Symbols
MAJOR="🔴"
MINOR="🟡"
PATCH="🟢"
UPTODATE="✅"

# Verbose logging helpers
verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${DIM}[verbose]${NC} $*" >&2
    fi
}

verbose_warn() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BOLD}${YELLOW}[warning]${NC} $*" >&2
    fi
}

verbose_error() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${BOLD}${RED}[error]${NC}   $*" >&2
    fi
}

show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Check for Swift Package updates in Xcode projects."
    echo "By default only shows direct (first-level) dependencies, not transitive ones."
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -a, --all               Show all dependencies (including transitive)"
    echo "  -q, --quiet             Only show packages with updates"
    echo "  -j, --json              Output as JSON"
    echo "  -l, --list              Print only the list of direct dependencies (one per line)"
    echo "  -v, --verbose           Print detailed progress for every step and file analysed"
    echo "  --no-color              Disable colored output"
}

QUIET=false
JSON_OUTPUT=false
NO_COLOR=false
SHOW_ALL=false
LIST_OUTPUT=false
VERBOSE=false
SEARCH_PATH=""
WORKSPACE_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;
        -a|--all) SHOW_ALL=true; shift ;;
        -q|--quiet) QUIET=true; shift ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        -l|--list) LIST_OUTPUT=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --no-color) NO_COLOR=true; shift ;;
        -*) echo -e "${RED}Unknown option: $1${NC}" >&2; show_help; exit 1 ;;
        *) echo -e "${RED}Unknown argument: $1${NC}" >&2; show_help; exit 1 ;;
    esac
done

if [[ "$NO_COLOR" == true ]]; then
    RED=''; YELLOW=''; GREEN=''; BLUE=''; CYAN=''; DIM=''; BOLD=''; NC=''
    MAJOR="[MAJOR]"; MINOR="[MINOR]"; PATCH="[PATCH]"; UPTODATE="[OK]"
fi

# Temp files
DIRECT_DEPS_FILE="/tmp/spm_direct_deps_$$"
UPDATE_TYPES_FILE="/tmp/spm_update_types_$$"
RESOLVED_PKGS_FILE="/tmp/spm_resolved_pkgs_$$"
FILTERED_PKGS_FILE="/tmp/spm_filtered_pkgs_$$"
trap 'rm -f "$DIRECT_DEPS_FILE" "$UPDATE_TYPES_FILE" "$RESOLVED_PKGS_FILE" "$FILTERED_PKGS_FILE" 2>/dev/null' EXIT

# Extract repo identifier (owner/repo) from URL
get_repo_id() {
    local url="$1"
    # The character class [^/.] already excludes '.git' from the capture
    echo "$url" | sed -nE 's|.*github\.com[:/]([^/]+/[^/.]+).*|\1|p' | tr '[:upper:]' '[:lower:]'
}

# Parse semver
parse_semver() {
    local version="${1#v}"
    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    fi
}

# Compare versions
compare_versions() {
    local current="$1"
    local latest="$2"

    local cur_parts lat_parts
    cur_parts=$(parse_semver "$current")
    lat_parts=$(parse_semver "$latest")

    if [[ -z "$cur_parts" ]] || [[ -z "$lat_parts" ]]; then
        echo "unknown"
        return
    fi

    local cur_major cur_minor cur_patch lat_major lat_minor lat_patch
    read -r cur_major cur_minor cur_patch <<< "$cur_parts"
    read -r lat_major lat_minor lat_patch <<< "$lat_parts"

    if [[ $lat_major -gt $cur_major ]]; then
        echo "major"
    elif [[ $lat_major -eq $cur_major ]] && [[ $lat_minor -gt $cur_minor ]]; then
        echo "minor"
    elif [[ $lat_major -eq $cur_major ]] && [[ $lat_minor -eq $cur_minor ]] && [[ $lat_patch -gt $cur_patch ]]; then
        echo "patch"
    else
        echo "up-to-date"
    fi
}

# Get latest release tag from GitHub
get_latest_github_release() {
    local repo_url="$1"
    local repo_path

    repo_path=$(echo "$repo_url" | sed -nE 's|.*github\.com[:/]([^/]+/[^/.]+).*|\1|p')
    repo_path="${repo_path%.git}"

    if [[ -z "$repo_path" ]]; then
        verbose_error "Could not extract repo path from URL: $repo_url"
        echo ""
        return
    fi

    local api_url="https://api.github.com/repos/${repo_path}/releases/latest"
    verbose "Fetching latest release from GitHub API: $api_url"
    local response tag
    response=$(curl --max-time 60 -sf -H "Accept: application/vnd.github.v3+json" "$api_url" 2>/dev/null) || true

    if [[ -n "$response" ]]; then
        tag=$(echo "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        if [[ -n "$tag" ]]; then
            verbose "GitHub API returned tag: $tag for $repo_path"
            echo "$tag"
            return
        fi
    fi

    # Fallback: git ls-remote
    verbose_warn "GitHub API returned no release for $repo_path, falling back to git ls-remote"
    local tags
    tags=$(git ls-remote --tags --refs "https://github.com/${repo_path}.git" 2>/dev/null | \
           awk '{print $2}' | sed 's|refs/tags/||' | \
           grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | \
           awk '{
               tag = $0
               version = tag
               gsub(/^v/, "", version)
               print version "\t" tag
           }' | \
           sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -f2) || true

    if [[ -z "$tags" ]]; then
        verbose_warn "No tags found for $repo_path via git ls-remote either"
    else
        verbose "git ls-remote returned tag: $tags for $repo_path"
    fi

    echo "$tags"
}

# Extract package name from URL
get_package_name() {
    local name="${1##*/}"
    echo "${name%.git}"
}

# Get project name from path
get_project_name() {
    local path="$1"
    if [[ "$path" == *".xcodeproj"* ]]; then
        local proj="${path%.xcodeproj*}.xcodeproj"
        proj="${proj##*/}"
        echo "${proj%.xcodeproj}"
    else
        local dir="${path%/*}"
        echo "${dir##*/}"
    fi
}

# Find direct dependencies from Package.swift files (URL-based only)
# Outputs: repo_id|project_name
extract_from_package_swift() {
    local search_path="$1"
    local output_file="$2"

    verbose "Searching for Package.swift files in: $search_path"
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        verbose "Analysing Package.swift: $file"
        local project_name
        project_name=$(get_project_name "$file")

        # Extract URL-based packages (handles multi-line declarations)
        # Look for .package followed by url: with a GitHub URL
        grep -oE 'url:[[:space:]]*"https://github\.com/[^"]+"' "$file" 2>/dev/null | \
            sed -nE 's/.*url:[[:space:]]*"([^"]+)".*/\1/p' | while read -r url; do
                local repo_id
                repo_id=$(get_repo_id "$url")
                if [[ -n "$repo_id" ]]; then
                    verbose "  Found dependency: $repo_id (project: $project_name)"
                    echo "${repo_id}|${project_name}"
                fi
            done || true
    done < <(find "$search_path" \( -name ".build" -o -name "DerivedData" -o -name "Packages" \) -prune -o -name "Package.swift" -print 2>/dev/null)
}

# Find direct dependencies from Xcode project files
# Outputs: repo_id|project_name
extract_from_xcode_project() {
    local search_path="$1"
    local output_file="$2"

    verbose "Searching for Xcode project files in: $search_path"
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        verbose "Analysing Xcode project: $file"
        local project_name
        project_name=$(get_project_name "$file")

        # Extract repositoryURL from XCRemoteSwiftPackageReference sections
        grep "repositoryURL" "$file" 2>/dev/null | \
            sed -nE 's/.*repositoryURL[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' | while read -r url; do
                local repo_id
                repo_id=$(get_repo_id "$url")
                if [[ -n "$repo_id" ]]; then
                    verbose "  Found dependency: $repo_id (project: $project_name)"
                    echo "${repo_id}|${project_name}"
                fi
            done || true
    done < <(find "$search_path" \( -name ".build" -o -name "DerivedData" \) -prune -o -name "project.pbxproj" -print 2>/dev/null)
}

# Build direct dependencies map (repo_id -> project names)
build_direct_deps_map() {
    local path="$1"
    local roots=()

    rm -rf "$DIRECT_DEPS_FILE"

    verbose "Building direct dependencies map from: $path"

    while IFS= read -r root; do
        [[ -n "$root" ]] && roots+=("$root")
    done < <(get_search_roots "$path")

    if [[ ${#roots[@]} -eq 0 ]]; then
        verbose_warn "No search roots found"
        return
    fi

    verbose "Search roots: ${roots[*]}"

    for root in "${roots[@]}"; do
        verbose "Scanning root: $root"
        # Extract from Package.swift files
        extract_from_package_swift "$root" >> "$DIRECT_DEPS_FILE"

        # Extract from Xcode projects
        extract_from_xcode_project "$root" >> "$DIRECT_DEPS_FILE"
    done

    # Sort and dedupe
    if [[ -s "$DIRECT_DEPS_FILE" ]]; then
        local count
        count=$(wc -l < "$DIRECT_DEPS_FILE" | tr -d ' ')
        sort -u "$DIRECT_DEPS_FILE" -o "$DIRECT_DEPS_FILE"
        local unique_count
        unique_count=$(wc -l < "$DIRECT_DEPS_FILE" | tr -d ' ')
        verbose "Direct dependencies found: $unique_count unique (from $count total entries)"
    else
        verbose_warn "No direct dependencies found in project files"
    fi
}

# Get projects using a package
get_projects_for_package() {
    local repo_id="$1"
    grep "^${repo_id}|" "$DIRECT_DEPS_FILE" 2>/dev/null | cut -d'|' -f2 | sort -u | tr '\n' ',' | sed 's/,$//'
}

# Check if a URL is a direct dependency
is_direct_dependency() {
    local url="$1"
    local repo_id
    repo_id=$(get_repo_id "$url")
    grep -q "^${repo_id}|" "$DIRECT_DEPS_FILE" 2>/dev/null
}

# Get search roots limited to expected directories
get_search_roots() {
    local path="$1"
    local search_roots=(
        "${path%/}/SharedPackages"
        "${path%/}/iOS"
        "${path%/}/macOS"
        "${path%/}/DuckDuckGo.xcworkspace"
    )

    local root found=false
    for root in "${search_roots[@]}"; do
        if [[ -e "$root" ]]; then
            found=true
            verbose "Search root exists: $root"
            echo "$root"
        else
            verbose "Search root not found (skipped): $root"
        fi
    done

    if [[ "$found" != true ]]; then
        echo -e "${YELLOW}Warning: None of the expected search roots exist under ${path}.${NC}" >&2
        echo -e "${YELLOW}Checked: ${search_roots[*]}${NC}" >&2
        return 1
    fi
}

# Find all Package.resolved files
find_resolved_files() {
    local path="$1"
    local roots=()

    while IFS= read -r root; do
        [[ -n "$root" ]] && roots+=("$root")
    done < <(get_search_roots "$path")

    if [[ ${#roots[@]} -eq 0 ]]; then
        return
    fi

    verbose "Searching for Package.resolved files in: ${roots[*]}"
    local results
    results=$(find "${roots[@]}" \( -name ".build" -o -name "DerivedData" \) -prune -o \
        \( -name "Package.resolved" -o -path "*/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" \) -print 2>/dev/null)
    if [[ -n "$results" ]]; then
        while IFS= read -r f; do
            verbose "Found resolved file: $f"
        done <<< "$results"
    else
        verbose_warn "No Package.resolved files found"
    fi
    echo "$results"
}

# Resolve packages for workspace
resolve_workspace_packages() {
    local workspace="$1"

    verbose "Resolving workspace packages for: $workspace"
    if ! command -v xcodebuild >/dev/null 2>&1; then
        echo -e "${YELLOW}Warning: xcodebuild not found; skipping package resolution.${NC}" >&2
        return
    fi

    if [[ ! -d "$workspace" ]]; then
        echo -e "${YELLOW}Warning: ${workspace} not found; skipping package resolution.${NC}" >&2
        return
    fi

    if [[ "$JSON_OUTPUT" != true ]] && [[ "$QUIET" != true ]]; then
        echo -e "${DIM}Resolving Swift packages for ${workspace}...${NC}" >&2
    fi
    if ! xcodebuild -resolvePackageDependencies -workspace "$workspace" >/dev/null 2>&1; then
        local scheme
        scheme=$(xcodebuild -list -workspace "$workspace" 2>/dev/null | \
            awk '/Schemes:/ {found=1; next} found && NF {gsub(/^[ \t]+/, ""); print; exit}')
        if [[ -n "$scheme" ]]; then
            if [[ "$JSON_OUTPUT" != true ]] && [[ "$QUIET" != true ]]; then
                echo -e "${DIM}Retrying package resolution with scheme ${scheme}...${NC}" >&2
            fi
            if ! xcodebuild -resolvePackageDependencies -workspace "$workspace" -scheme "$scheme" >/dev/null 2>&1; then
                echo -e "${YELLOW}Warning: Package resolution failed for ${workspace} (scheme ${scheme}). Continuing.${NC}" >&2
            fi
        else
            echo -e "${YELLOW}Warning: Package resolution failed for ${workspace}. Continuing.${NC}" >&2
        fi
    fi
}

# Detect DuckDuckGo.xcworkspace in . or ..
detect_workspace() {
    local cwd
    cwd="$(dirname "${BASH_SOURCE[0]}")"
    verbose "Detecting workspace from script directory: $cwd"

    if [[ -d "${cwd}/DuckDuckGo.xcworkspace" ]]; then
        WORKSPACE_PATH="${cwd}/DuckDuckGo.xcworkspace"
        SEARCH_PATH="${cwd}"
        verbose "Found workspace at: $WORKSPACE_PATH"
        return
    fi

    if [[ -d "${cwd%/}/../DuckDuckGo.xcworkspace" ]]; then
        WORKSPACE_PATH="${cwd%/}/../DuckDuckGo.xcworkspace"
        SEARCH_PATH="${cwd%/}/.."
        verbose "Found workspace at: $WORKSPACE_PATH"
        return
    fi

    echo -e "${RED}DuckDuckGo.xcworkspace not found in ${cwd} or ${cwd%/}/..${NC}" >&2
    echo -e "${YELLOW}Run this script from the repo root or the scripts directory.${NC}" >&2
}

# Parse Package.resolved and output packages (url|version per line)
parse_resolved_files() {
    local files="$1"
    local output_file="$2"

    rm -rf "$output_file"

    verbose "Parsing Package.resolved files"
    echo "$files" | while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        local version="2"
        if tail -3 "$file" 2>/dev/null | grep -q '"version"[[:space:]]*:[[:space:]]*1'; then
            version="1"
        fi
        verbose "Parsing $file (format version: $version)"

        if [[ "$version" == "1" ]]; then
            awk '
                /"repositoryURL"/ { gsub(/.*"repositoryURL"[[:space:]]*:[[:space:]]*"|".*/, ""); url=$0 }
                /"version"/ { gsub(/.*"version"[[:space:]]*:[[:space:]]*"|".*/, ""); ver=$0; if(url) print url "|" ver; url="" }
            ' "$file"
        else
            awk '
                /"location"/ { gsub(/.*"location"[[:space:]]*:[[:space:]]*"|".*/, ""); url=$0 }
                /"version"/ { gsub(/.*"version"[[:space:]]*:[[:space:]]*"|".*/, ""); ver=$0; if(url && ver ~ /^[0-9]/) print url "|" ver; url="" }
            ' "$file"
        fi
    done | sort -t'|' -k1,1 -u > "$output_file"
}

# Main logic
main() {
    local resolved_files

    detect_workspace
    if [[ -z "$WORKSPACE_PATH" ]] || [[ -z "$SEARCH_PATH" ]]; then
        exit 1
    fi

    # Force workspace package resolution before reading Package.resolved files
    resolve_workspace_packages "$WORKSPACE_PATH"
    resolved_files=$(find_resolved_files "$SEARCH_PATH")

    if [[ -z "$resolved_files" ]]; then
        echo -e "${RED}No Package.resolved files found in ${SEARCH_PATH}${NC}" >&2
        exit 1
    fi

    # Build direct dependencies map
    if [[ "$SHOW_ALL" != true ]]; then
        build_direct_deps_map "$SEARCH_PATH"
        if [[ ! -s "$DIRECT_DEPS_FILE" ]]; then
            echo -e "${YELLOW}Warning: Could not find any URL-based dependencies in Package.swift or .xcodeproj files.${NC}" >&2
            echo -e "${YELLOW}Showing all dependencies. Use -a flag to suppress this warning.${NC}" >&2
            echo ""
            SHOW_ALL=true
        fi
    fi

    # Get all packages from resolved files
    parse_resolved_files "$resolved_files" "$RESOLVED_PKGS_FILE"

    # Filter to direct dependencies only
    rm -rf "$FILTERED_PKGS_FILE"
    if [[ "$SHOW_ALL" == true ]]; then
        verbose "Showing all dependencies (no filtering)"
        cp "$RESOLVED_PKGS_FILE" "$FILTERED_PKGS_FILE"
    else
        verbose "Filtering resolved packages to direct dependencies only"
        while IFS='|' read -r url version; do
            [[ -z "$url" ]] && continue
            if is_direct_dependency "$url"; then
                verbose "  Direct dependency: $(get_package_name "$url") ($version)"
                echo "${url}|${version}" >> "$FILTERED_PKGS_FILE"
            else
                verbose "  Transitive (skipped): $(get_package_name "$url") ($version)"
            fi
        done < "$RESOLVED_PKGS_FILE"
    fi

    local pkg_count
    pkg_count=$(grep -c '|' "$FILTERED_PKGS_FILE" 2>/dev/null || echo "0")

    if [[ "$pkg_count" -eq 0 ]]; then
        echo -e "${RED}No direct dependencies found${NC}" >&2
        exit 1
    fi

    # If list output is requested, just print package names and exit
    if [[ "$LIST_OUTPUT" == true ]]; then
        while IFS='|' read -r url version; do
            [[ -z "$url" ]] && continue
            get_package_name "$url"
        done < "$FILTERED_PKGS_FILE" | sort -u
        exit 0
    fi

    if [[ "$JSON_OUTPUT" != true ]]; then
        echo -e "${BOLD}${BLUE}Swift Package Update Checker${NC}"
        if [[ "$SHOW_ALL" == true ]]; then
            echo -e "${CYAN}Found ${pkg_count} packages (all dependencies)${NC}"
        else
            echo -e "${CYAN}Found ${pkg_count} direct dependencies${NC}"
        fi
        echo ""
    fi

    local json_first=true
    rm -rf "$UPDATE_TYPES_FILE"

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "{"
        echo "  \"packages\": ["
    fi

    verbose "Checking ${pkg_count} packages for updates..."
    while IFS='|' read -r url current; do
        [[ -z "$url" ]] && continue

        local name repo_id projects
        name=$(get_package_name "$url")
        repo_id=$(get_repo_id "$url")
        projects=$(get_projects_for_package "$repo_id")
        [[ -z "$projects" ]] && projects="unknown"

        verbose "Checking package: $name (current: $current, repo: $repo_id, used by: $projects)"

        if [[ "$JSON_OUTPUT" != true ]] && [[ "$QUIET" != true ]]; then
            printf "Checking %-40s\r" "$name..."
        fi

        local latest
        latest=$(get_latest_github_release "$url")

        local update_type="unknown"
        local latest_display="${latest:-N/A}"

        if [[ -n "$latest" ]]; then
            update_type=$(compare_versions "$current" "$latest")
        else
            verbose_warn "Could not fetch latest version for $name ($url)"
        fi

        verbose "  Result: $name $current → $latest_display ($update_type)"

        if [[ "$JSON_OUTPUT" == true ]]; then
            local comma=""
            if [[ "$json_first" != true ]]; then
                comma=","
            fi
            local projects_json
            projects_json=${projects//,/\",\"}
            echo "    ${comma}{\"name\":\"$name\",\"url\":\"$url\",\"current\":\"$current\",\"latest\":\"$latest_display\",\"update_type\":\"$update_type\",\"projects\":[\"$projects_json\"]}"
            json_first=false
        else
            if [[ "$QUIET" == true ]] && [[ "$update_type" == "up-to-date" || "$update_type" == "unknown" ]]; then
                :
            else
                local symbol status_color
                case "$update_type" in
                    major) symbol="$MAJOR"; status_color="$RED" ;;
                    minor) symbol="$MINOR"; status_color="$YELLOW" ;;
                    patch) symbol="$PATCH"; status_color="$GREEN" ;;
                    up-to-date) symbol="$UPTODATE"; status_color="$GREEN" ;;
                    *) symbol="❓"; status_color="$CYAN" ;;
                esac

                printf "%-35s %s  ${status_color}%-12s${NC} %s → %s\n" \
                    "$name" "$symbol" "[$update_type]" "$current" "$latest_display"
                printf "  ${DIM}└─ %s${NC}\n" "$projects"
            fi
        fi

        echo "$update_type" >> "$UPDATE_TYPES_FILE"
    done < "$FILTERED_PKGS_FILE"

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "  ],"
    fi

    # Summary
    verbose "All packages checked, computing summary"
    local m=0 n=0 p=0 u=0 k=0
    if [[ -f "$UPDATE_TYPES_FILE" ]]; then
        while read -r t; do
            case "$t" in
                major) m=$((m+1)) ;;
                minor) n=$((n+1)) ;;
                patch) p=$((p+1)) ;;
                up-to-date) u=$((u+1)) ;;
                *) k=$((k+1)) ;;
            esac
        done < "$UPDATE_TYPES_FILE"
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        echo "  \"summary\": {\"major\": $m, \"minor\": $n, \"patch\": $p, \"up_to_date\": $u, \"unknown\": $k}"
        echo "}"
    else
        echo ""
        echo -e "${BOLD}Summary:${NC}"
        echo -e "  $MAJOR Major updates:  $m"
        echo -e "  $MINOR Minor updates:  $n"
        echo -e "  $PATCH Patch updates:  $p"
        echo -e "  $UPTODATE Up to date:    $u"
        [[ $k -gt 0 ]] && echo -e "  ❓ Unknown:       $k"

        if [[ $m -gt 0 ]] || [[ $n -gt 0 ]] || [[ $p -gt 0 ]]; then
            echo ""
            echo -e "${YELLOW}Run 'swift package update' or update via Xcode to get the latest versions.${NC}"
        fi
    fi
}

main
