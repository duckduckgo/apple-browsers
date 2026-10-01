#!/usr/bin/env bash
set -euxo pipefail

# run the CLI to disable Bitrise build cache for Xcode (the CLI is installed by setup_bitrise_build_cache.sh)
if [[ -x /tmp/bin/bitrise-build-cache ]]; then
  /tmp/bin/bitrise-build-cache deactivate xcode
else
  echo "Bitrise Build Cache CLI not found at /tmp/bin/bitrise-build-cache, nothing to deactivate"
fi
