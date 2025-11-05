/bin/sh -c 'set -e -o pipefail && xcodebuild \
  ONLY_ACTIVE_ARCH=YES \
  DEBUG_INFORMATION_FORMAT=dwarf \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -scheme "macOS Browser" \
  -configuration Debug \
  -workspace <REPLACE_WITH_WORKSPACE_PATH> \
  -destination "platform=macOS,arch=<REPLACE_WITH_ARCHITECTURE>" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -disableAutomaticPackageResolution \
  -parallelizeTargets \
  build | xcbeautify'

