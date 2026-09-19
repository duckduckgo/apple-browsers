#!/bin/sh

set -eu

usage() {
    echo "Usage: $0 [on|off|toggle]" >&2
}

if [ "$#" -gt 1 ]; then
    usage
    exit 1
fi

action="${1:-toggle}"
case "$action" in
    on|off|toggle) ;;
    *)
        usage
        exit 1
        ;;
esac

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: Run this script from an apple-browsers Git checkout." >&2
    exit 1
}

override_file="$repo_root/macOS/LocalOverrides.xcconfig"
override_line='DEPLOYMENT_LOCATION[config=Debug] = YES'
current_value=""

if [ -f "$override_file" ]; then
    current_value="$(awk '
        /^[[:space:]]*DEPLOYMENT_LOCATION\[config=Debug\][[:space:]]*=/ {
            value = $0
            sub(/^[[:space:]]*DEPLOYMENT_LOCATION\[config=Debug\][[:space:]]*=[[:space:]]*/, "", value)
        }
        END { print value }
    ' "$override_file")"
fi

if [ "$action" = "toggle" ]; then
    if [ "$current_value" = "YES" ]; then
        action="off"
    else
        action="on"
    fi
fi

temporary_file="$(mktemp "${TMPDIR:-/tmp}/duckduckgo-local-overrides.XXXXXX")"
trap 'rm -f "$temporary_file"' EXIT HUP INT TERM

if [ -f "$override_file" ]; then
    awk -v action="$action" -v override="$override_line" '
        BEGIN { found = 0 }
        /^[[:space:]]*DEPLOYMENT_LOCATION\[config=Debug\][[:space:]]*=/ {
            if (action == "on" && !found) {
                print override
                found = 1
            }
            next
        }
        { print }
        END {
            if (action == "on" && !found) {
                print override
            }
        }
    ' "$override_file" > "$temporary_file"
elif [ "$action" = "on" ]; then
    printf '%s\n' "$override_line" > "$temporary_file"
fi

if [ "$action" = "off" ] && ! grep -q '[^[:space:]]' "$temporary_file"; then
    rm -f "$override_file"
    echo "Disabled macOS debug deployment."
    exit 0
fi

if [ -f "$override_file" ] && cmp -s "$temporary_file" "$override_file"; then
    echo "macOS debug deployment is already $action."
    exit 0
fi

cp "$temporary_file" "$override_file"
echo "Turned macOS debug deployment $action: $override_file"
