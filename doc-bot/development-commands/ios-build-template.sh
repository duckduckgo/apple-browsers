/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "iOS Browser" \
  -configuration Debug \
  -workspace <REPLACE_WITH_WORKSPACE_PATH> \
  -destination "platform=iOS Simulator,id=<REPLACE_WITH_SIMULATOR_ID>" \
  -allowProvisioningUpdates \
  -parallelizeTargets \
  build | xcbeautify'

