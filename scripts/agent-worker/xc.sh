#!/usr/bin/env bash
# The agent's build, test and lint commands, so it can check its change and fix it as it goes. The agent may
# only run this script, not xcodebuild or a shell directly. Output is trimmed to what the agent needs
#
# Usage (from the checkout):
#   xc.sh build [ios|macos]          Build for testing. The platform defaults to the one the change touches
#   xc.sh test [ios|macos] [<test>]  Run tests in xcodebuild -only-testing form, or .agent-evidence/tests.txt
#   xc.sh lint                       SwiftLint --strict on the changed Swift files
#   xc.sh mv <from> <to>             Move or rename a file in the checkout
#   xc.sh rm <path>...               Delete files in the checkout
#
# Env: DEST (iOS Simulator destination), PACKAGES (cloned source packages dir), XC_DERIVED (derived data dir,
# outside the checkout so build products never go into the patch), XC_LOGS (where full logs go)

set -uo pipefail
cmd=${1:-}
shift || true

# A path inside the checkout, or an error, so mv and rm can't touch anything else
inside() {
  local root abs
  root=$(pwd -P)
  abs=$(python3 -I -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1")
  [[ $abs == "$root"/* && $abs != "$root"/.git && $abs != "$root"/.git/* ]] || { echo "$1 is outside the checkout"; exit 2; }
  echo "$abs"
}

case $cmd in
  mv)
    [[ $# == 2 ]] || { echo "Usage: xc mv <from> <to>"; exit 2; }
    from=$(inside "$1") || { echo "$from"; exit 2; }
    to=$(inside "$2") || { echo "$to"; exit 2; }
    mkdir -p "$(dirname "$to")" && mv "$from" "$to" && echo "moved $1 to $2"
    exit $?
    ;;
  rm)
    [[ $# -gt 0 ]] || { echo "Usage: xc rm <path>..."; exit 2; }
    for f in "$@"; do
      abs=$(inside "$f") || { echo "$abs"; exit 2; }
      [[ -f $abs ]] || { echo "$f isn't a file"; exit 2; }
      rm "$abs" && echo "deleted $f"
    done
    # Drop directories the deletes left empty
    find . -path ./.git -prune -o -type d -empty -print 2>/dev/null | grep -v '^\./\.git' | xargs -r rmdir 2>/dev/null
    exit 0
    ;;
esac

platform=""
if [[ ${1:-} == ios || ${1:-} == macos ]]; then platform=$1; shift; fi
if [[ -z $platform ]]; then
  changed=$(git status --porcelain | cut -c4-)
  if grep -q '^macOS/' <<< "$changed" && ! grep -q '^iOS/' <<< "$changed"; then platform=macos; else platform=ios; fi
fi
if [[ $platform == ios ]]; then
  build=(-scheme 'iOS Browser' -destination "$DEST")
else
  # No signing assets on this runner, so macOS builds skip signing, like the repo's other non-release checks
  build=(-scheme 'macOS Browser' -configuration CI -destination 'platform=macOS' ENABLE_TESTABILITY=true
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES)
fi
common=(-derivedDataPath "$XC_DERIVED/$platform" -clonedSourcePackagesDirPath "$PACKAGES" -disableAutomaticPackageResolution
  -skipPackagePluginValidation -skipMacroValidation)
logs=${XC_LOGS:-/tmp}
mkdir -p "$logs"

errors() { grep -E ": (error|warning: unreachable)|^error:|BUILD FAILED|Testing failed|failed \(" "$1" | grep -v "^ *export " | cut -c1-400 | sort -u | head -40; }

case $cmd in
  build)
    log="$logs/build-$platform.log"
    echo "Building $platform (full log: $log)"
    if SPM_FORCE_DEBUG=1 xcodebuild build-for-testing "${build[@]}" "${common[@]}" OTHER_CODE_SIGN_FLAGS=--timestamp=none > "$log" 2>&1; then
      echo "BUILD SUCCEEDED"
    else
      echo "BUILD FAILED"; errors "$log"; exit 1
    fi
    ;;
  test)
    tests=("$@")
    if [[ ${#tests[@]} == 0 && -s .agent-evidence/tests.txt ]]; then
      while read -r t; do [[ -n $t ]] && tests+=("$t"); done < .agent-evidence/tests.txt
    fi
    [[ ${#tests[@]} -gt 0 ]] || { echo "Name tests to run, or list them in .agent-evidence/tests.txt"; exit 2; }
    only=(); for t in "${tests[@]}"; do only+=("-only-testing:$t"); done
    log="$logs/test-$platform.log"
    echo "Testing $platform: ${tests[*]} (full log: $log). Run build first after changing code"
    if xcodebuild test-without-building "${build[@]}" "${common[@]}" "${only[@]}" \
        -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 > "$log" 2>&1; then r=0; else r=1; fi
    grep -E "^Test Case .*(passed|failed)|Executed [0-9]+ test|^Test .* (passed|failed)|TEST (EXECUTE )?(SUCCEEDED|FAILED)|: error:|XCTAssert|Fatal error" "$log" | cut -c1-600 | head -60
    [[ $r == 0 ]] && echo "TESTS PASSED" || { echo "TESTS FAILED"; exit 1; }
    ;;
  lint)
    command -v swiftlint > /dev/null || { echo "SwiftLint isn't installed on this runner; the PR checks run it"; exit 0; }
    files=(); while read -r f; do [[ $f == *.swift && -f $f ]] && files+=("$f"); done < <(git status --porcelain | cut -c4-)
    [[ ${#files[@]} -gt 0 ]] || { echo "No changed Swift files"; exit 0; }
    swiftlint lint --strict --quiet "${files[@]}" 2>&1 | cut -c1-400 | head -60
    ;;
  *)
    sed -n '2,10p' "$0"; exit 2
    ;;
esac
