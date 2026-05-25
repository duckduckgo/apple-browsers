#!/bin/sh
set -eu

# Pre-build sanity checks shared between iOS and macOS targets.
# Emits Xcode `warning:` lines for anything the developer should know about
# their build environment before continuing.

# Skip during SwiftUI Previews — those builds are noisy and we don't want
# to spam the canvas with warnings.
if [ "${ENABLE_PREVIEWS:-NO}" = "YES" ]; then
    exit 0
fi

# --- Active LocalOverrides reminder ---
# When a developer has LocalOverrides*.xcconfig in their platform root, warn
# every build so they don't waste time debugging a setting they themselves
# overrode locally.
for override in "${SRCROOT}"/LocalOverrides*.xcconfig; do
    if [ -e "$override" ]; then
        echo "warning: 🚨 Local build override active: ${override##*/} — settings in this file are overriding the defaults."
    fi
done

# --- Compilation cache size warning ---
# Warn when the Xcode compilation cache exceeds this size, in GB.
LIMIT_GB=20

if [ "${COMPILATION_CACHE_ENABLE_CACHING:-NO}" = "YES" ]; then
    cache_dir="${COMPILATION_CACHE_CAS_PATH:-}"
    limit_gb="${DDG_COMPILATION_CACHE_LIMIT_GB:-$LIMIT_GB}"

    if [ -n "$cache_dir" ] && [ -d "$cache_dir" ]; then
        size_kb=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
        limit_kb=$((limit_gb * 1024 * 1024))

        if [ "${size_kb:-0}" -gt "$limit_kb" ]; then
            size_gb=$(awk -v kb="$size_kb" 'BEGIN { printf "%.1f", kb / 1024 / 1024 }')
            echo "warning: 🚨 Compilation cache too large — clear it via Xcode → Settings → Locations → Compilation Cache → (i) → Clear Cache. Current size: ${size_gb} GB (limit ${limit_gb} GB) at ${cache_dir}"
        fi
    fi
fi
