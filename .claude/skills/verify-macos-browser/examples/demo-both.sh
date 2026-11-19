#!/bin/bash
# Run the two demos at once, one per VM: Duck.ai on vm-1, the search on vm-2.
# Builds take turns (they share DerivedData); the drives run in parallel. Each line is prefixed with its VM.
#
# Usage: demo-both.sh [checkout]
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
checkout=${1:-.}

"$here/demo-duckai.sh" "$checkout" --vm vm-1 2>&1 | sed -u 's/^/[vm-1 duck.ai] /' &
sleep 2
"$here/demo-search.sh" "$checkout" --vm vm-2 2>&1 | sed -u 's/^/[vm-2 search]  /' &
wait
