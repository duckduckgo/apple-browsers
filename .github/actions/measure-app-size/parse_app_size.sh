#!/bin/bash

# Script to parse App Thinning Size Report and extract app sizes
# Usage: ./parse_app_size.sh "App Thinning Size Report.txt"

# =============================================================================
# CONSTANTS AND REGEX PATTERNS
# =============================================================================
VARIANT_PATTERN="^Variant:.*DuckDuckGo(-Alpha)?\.ipa$"
APP_SIZE_PATTERN="^App size:"
COMPRESSED_SIZE_REGEX="^App size: \([0-9.]* [A-Z]*\) compressed.*"
UNCOMPRESSED_SIZE_REGEX="^.*compressed, \([0-9.]* [A-Z]*\) uncompressed.*"

# =============================================================================
# FUNCTION: Validate script inputs
# Returns: 0 if valid, exits with 1 if invalid
# Sets global variable: REPORT_FILE
# =============================================================================
validate_inputs() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <path_to_app_thinning_size_report.txt>"
        exit 1
    fi

    REPORT_FILE="$1"

    if [ ! -f "$REPORT_FILE" ]; then
        echo "Error: File '$REPORT_FILE' not found"
        exit 1
    fi

    return 0
}

# =============================================================================
# FUNCTION: Find the App size line for the universal variant
# Parses from bottom up to find the first (universal) variant encountered
# Returns: Outputs the App size line to stdout, returns 0 if found, 1 if not found
# =============================================================================
find_universal_app_size_line() {
    # Read file into array (from bottom up)
    local lines=()
    while IFS= read -r line; do
        lines=("$line" "${lines[@]}")
    done < "$REPORT_FILE"
    
    local target_app_size_line=""
    
    # Parse from bottom (which is now top of array)
    for line in "${lines[@]}"; do
        # If we find an App size line first, store it
        if [[ "$line" =~ $APP_SIZE_PATTERN ]]; then
            target_app_size_line="$line"
        fi
        
        # If we then find the universal variant, this App size line belongs to it
        if [[ "$line" =~ $VARIANT_PATTERN ]]; then
            echo "Found universal variant: $line" >&2
            if [ -n "$target_app_size_line" ]; then
                echo "$target_app_size_line"  # Output the line to stdout
                return 0
            fi
        fi
    done
    
    echo "Error: Universal variant App size line not found" >&2
    return 1
}

# =============================================================================
# FUNCTION: Parse app size values from a given App size line
# Input: App size line as parameter
# Returns: 0 if successfully parsed, 1 if parsing failed
# Outputs: Sets DOWNLOAD_SIZE and INSTALLATION_SIZE variables
# =============================================================================
parse_app_size_from_line() {
    local app_size_line="$1"
    
    echo "Parsing app size line: $app_size_line"
    
    # Extract compressed size (download size) with unit
    DOWNLOAD_SIZE=$(echo "$app_size_line" | sed -n "s/$COMPRESSED_SIZE_REGEX/\1/p")
    
    # Extract uncompressed size (installation size) with unit
    INSTALLATION_SIZE=$(echo "$app_size_line" | sed -n "s/$UNCOMPRESSED_SIZE_REGEX/\1/p")
    
    if [ -n "$DOWNLOAD_SIZE" ] && [ -n "$INSTALLATION_SIZE" ]; then
        # Remove spaces from sizes to avoid URL encoding issues (space becomes +)
        DOWNLOAD_SIZE=$(echo "$DOWNLOAD_SIZE" | sed 's/ //')
        INSTALLATION_SIZE=$(echo "$INSTALLATION_SIZE" | sed 's/ //')
        
        echo ""
        echo "Results:"
        echo "--------"
        echo "Download size (compressed): $DOWNLOAD_SIZE"
        echo "Installation size (uncompressed): $INSTALLATION_SIZE"
        
        return 0
    else
        echo "Error: Could not extract size values from line: $app_size_line"
        return 1
    fi
}

# =============================================================================
# FUNCTION: Save values to GitHub Actions output
# =============================================================================
save_to_github_output() {
    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "download_size=$DOWNLOAD_SIZE" >> "$GITHUB_OUTPUT"
        echo "installation_size=$INSTALLATION_SIZE" >> "$GITHUB_OUTPUT"
        echo "Values saved to GitHub Actions output"
    else
        echo "Note: GITHUB_OUTPUT not set (not running in GitHub Actions)"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Step 1: Validate inputs
validate_inputs "$@"

# Step 2: Find the universal variant App size line (parsing from bottom)
echo "Parsing App Thinning Size Report: $REPORT_FILE"
echo "============================================="
echo "Searching for universal variant App size line..."
APP_SIZE_LINE=$(find_universal_app_size_line)
if [ $? -ne 0 ]; then
    exit 1
fi

# Step 3: Parse the app size values from that line
if ! parse_app_size_from_line "$APP_SIZE_LINE"; then
    exit 1
fi

# Step 4: Save to GitHub Actions output
save_to_github_output

echo ""
echo "Parsing completed successfully!"