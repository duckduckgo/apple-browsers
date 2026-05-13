#!/bin/sh
set -eu

# Warn when the Xcode compilation cache exceeds this size, in GB.
LIMIT_GB=20

cache_dir="${COMPILATION_CACHE_CAS_PATH:-}"
limit_gb="${DDG_COMPILATION_CACHE_LIMIT_GB:-$LIMIT_GB}"

if [ -z "$cache_dir" ] || [ ! -d "$cache_dir" ]; then
    exit 0
fi

size_kb=$(du -sk "$cache_dir" 2>/dev/null | awk '{print $1}')
limit_kb=$((limit_gb * 1024 * 1024))

if [ "${size_kb:-0}" -gt "$limit_kb" ]; then
    size_gb=$(awk -v kb="$size_kb" 'BEGIN { printf "%.1f", kb / 1024 / 1024 }')
    echo "warning: 🚨 Compilation cache too large — clear it via Xcode → Settings → Locations → Compilation Cache → (i) → Clear Cache. Current size: ${size_gb} GB (limit ${limit_gb} GB) at ${cache_dir}"
fi
