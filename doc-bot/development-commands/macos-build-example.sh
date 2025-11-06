/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "macOS Browser" \
  -configuration Debug \
  -workspace /Users/daniel/Developer/browser/apple-browsers/DuckDuckGo.xcworkspace \
  -destination "platform=macOS,arch=arm64" \
  -allowProvisioningUpdates \
  -disableAutomaticPackageResolution \
  -parallelizeTargets \
  build | xcbeautify'

