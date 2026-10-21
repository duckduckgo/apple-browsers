#!/bin/sh

# Common function for running xcodebuild from the correct directory
# Usage: run_in_directory <target_dir> <command...>
run_in_directory() {
    local target_dir="$1"
    shift # Remove the first argument (target_dir) so $@ contains only the command
    
    # Save current directory to return to it later
    local current_dir=$(pwd)
    
    # Change to target directory if we're not already there
    if [ "$(pwd)" = "$target_dir" ]; then
        # Already in the correct directory, execute command directly
        "$@"
    else
        # Change to target directory for the command
        cd "$target_dir"
        "$@"
        local exit_code=$?
        # Return to the original directory
        cd "$current_dir"
        return $exit_code
    fi
}