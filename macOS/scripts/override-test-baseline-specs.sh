#!/bin/bash
#
# override-test-baseline-specs.sh
#
# Updates xcbaseline Info.plist files with the current runner's hardware specs.
# This ensures performance baselines match the CI runner environment.
#
# Usage: ./scripts/override-test-baseline-specs.sh [search_directory]
#
# Arguments:
#   search_directory  Directory to search for xcbaselines (default: current directory)
#

set -euo pipefail

SEARCH_DIR="${1:-.}"

# Get actual hardware specs from the runner
CPU_KIND=$(sysctl -n machdep.cpu.brand_string)
CPU_CORES=$(sysctl -n hw.logicalcpu)
PHYSICAL_CORES=$(sysctl -n hw.physicalcpu)
MODEL=$(sysctl -n hw.model)

echo "Detected hardware specs:"
echo "  CPU: $CPU_KIND"
echo "  Logical cores: $CPU_CORES"
echo "  Physical cores: $PHYSICAL_CORES"
echo "  Model: $MODEL"
echo ""

# Find all Info.plist files within xcbaselines directories
find "$SEARCH_DIR" -path "*/xcbaselines/*/Info.plist" | while read -r PLIST_PATH; do
  # Get all UUIDs in the plist
  UUIDS=$(/usr/libexec/PlistBuddy -c "Print :runDestinationsByUUID" "$PLIST_PATH" 2>/dev/null | grep -E "^    [A-F0-9-]+ " | awk '{print $1}')

  # Update each UUID entry
  for UUID in $UUIDS; do
    if ! /usr/libexec/PlistBuddy -c "Set :runDestinationsByUUID:${UUID}:localComputer:cpuKind '$CPU_KIND'" "$PLIST_PATH"; then
      echo "Warning: failed to update cpuKind for UUID $UUID in $PLIST_PATH" >&2
    fi
    if ! /usr/libexec/PlistBuddy -c "Set :runDestinationsByUUID:${UUID}:localComputer:logicalCPUCoresPerPackage $CPU_CORES" "$PLIST_PATH"; then
      echo "Warning: failed to update logicalCPUCoresPerPackage for UUID $UUID in $PLIST_PATH" >&2
    fi
    if ! /usr/libexec/PlistBuddy -c "Set :runDestinationsByUUID:${UUID}:localComputer:physicalCPUCoresPerPackage $PHYSICAL_CORES" "$PLIST_PATH"; then
      echo "Warning: failed to update physicalCPUCoresPerPackage for UUID $UUID in $PLIST_PATH" >&2
    fi
    if ! /usr/libexec/PlistBuddy -c "Set :runDestinationsByUUID:${UUID}:localComputer:modelCode '$MODEL'" "$PLIST_PATH"; then
      echo "Warning: failed to update modelCode for UUID $UUID in $PLIST_PATH" >&2
    fi

    echo "✅ Updated xcbaseline: CPU=$CPU_KIND, Cores=$CPU_CORES, Model=$MODEL, UUID=$UUID"
  done
done
