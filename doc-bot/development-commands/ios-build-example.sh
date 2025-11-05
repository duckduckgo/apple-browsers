/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "iOS Browser" \
  -configuration Debug \
  -workspace /Users/daniel/Developer/browser/apple-browsers/DuckDuckGo.xcworkspace \
  -destination "platform=iOS Simulator,id=6E6A828D-8C2C-4409-8E56-753DB02090F7" \
  -allowProvisioningUpdates \
  -parallelizeTargets \
  build | xcbeautify'

