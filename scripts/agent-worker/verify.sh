#!/usr/bin/env bash
# Builds the agent's change and runs its evidence plan: tests, then on iOS a launch screenshot and the
# Maestro flow as a GIF. Never fails: every result, good or bad, goes into verify.md
#
# Usage: verify.sh <repo dir> <plan dir> <out dir>
# Env: DEST (iOS Simulator destination), UDID (that simulator), PACKAGES (cloned source packages dir)
# Output to the log is status words only, since this repo's logs are public

set -uo pipefail
repo=$1 plan=$2 out=$3
mkdir -p "$out"
md="$out/verify.md"
cd "$repo" || exit 0

platform=ios
if git diff --cached --name-only | grep -q '^macOS/' && ! git diff --cached --name-only | grep -q '^iOS/'; then
  platform=macos
fi
if [[ $platform == ios ]]; then
  build=(-scheme 'iOS Browser' -destination "$DEST")
else
  build=(-scheme 'macOS Browser' -configuration CI -destination 'platform=macOS' ENABLE_TESTABILITY=true)
fi
common=(-derivedDataPath DerivedData -clonedSourcePackagesDirPath "$PACKAGES" -disableAutomaticPackageResolution
  -skipPackagePluginValidation -skipMacroValidation)

{
  echo "# Verify"
  echo
  echo "The worker built the agent's change on a clean runner and ran the agent's evidence plan. None of"
  echo "these results stop the run; they're here for the approver."
  echo
  echo "Platform: $platform"
} > "$md"

# Lines worth showing from an xcodebuild log, without the long command echoes
errors() { grep -E ": error:|^error:|BUILD FAILED|Testing failed|failed \(" "$1" | grep -v "^ *export " | cut -c1-300 | sort -u | head -30; }

start=$SECONDS
SPM_FORCE_DEBUG=1 xcodebuild build-for-testing "${build[@]}" "${common[@]}" OTHER_CODE_SIGN_FLAGS=--timestamp=none \
  > "$out/build.log" 2>&1 && built=yes || built=no
echo "build: $built"
{
  echo
  echo "## Build"
  echo
  if [[ $built == yes ]]; then
    echo "Succeeded in $(( (SECONDS - start) / 60 )) min."
  else
    echo "Failed after $(( (SECONDS - start) / 60 )) min. Errors (full log in build.log.gz):"
    echo; echo '```'; errors "$out/build.log"; echo '```'
  fi
} >> "$md"
gzip -f "$out/build.log"
[[ $built == yes ]] || exit 0

echo -e "\n## Tests\n" >> "$md"
if [[ -s "$plan/tests.txt" ]]; then
  only=()
  while read -r t; do [[ -n $t ]] && only+=("-only-testing:$t"); done < "$plan/tests.txt"
  xcodebuild test-without-building "${build[@]}" "${common[@]}" "${only[@]}" \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
    > "$out/test.log" 2>&1 && tested=passed || tested=failed
  echo "tests: $tested"
  {
    echo "Ran ${only[*]#-only-testing:}: **$tested**."
    echo; echo '```'
    grep -E "^Test Case .*(passed|failed)|Executed [0-9]+ test|^Test .* (passed|failed)|TEST (EXECUTE )?(SUCCEEDED|FAILED)|: error:" "$out/test.log" | cut -c1-300 | head -40
    echo '```'
  } >> "$md"
  gzip -f "$out/test.log"
else
  echo "The agent named no tests." >> "$md"
fi

[[ $platform == ios ]] || exit 0

echo -e "\n## Screens\n" >> "$md"
app=$(find DerivedData/Build/Products -maxdepth 2 -name 'DuckDuckGo.app' | head -1)
if [[ -z $app || -z ${UDID:-} ]]; then
  echo "No app or simulator to run it on." >> "$md"
  exit 0
fi
xcrun simctl boot "$UDID" > /dev/null 2>&1
xcrun simctl bootstatus "$UDID" > /dev/null 2>&1
if xcrun simctl install "$UDID" "$app" > /dev/null 2>&1 && xcrun simctl launch "$UDID" com.duckduckgo.mobile.ios > /dev/null 2>&1; then
  sleep 15
  xcrun simctl io "$UDID" screenshot "$out/launch.png" > /dev/null 2>&1 && echo "![App after launch](launch.png)" >> "$md"
  xcrun simctl terminate "$UDID" com.duckduckgo.mobile.ios > /dev/null 2>&1
else
  echo "Couldn't install or launch the app on the simulator." >> "$md"
  exit 0
fi

if [[ ! -s "$plan/flow.yaml" ]]; then
  echo -e "\nThe agent wrote no Maestro flow, so there's no recording." >> "$md"
  exit 0
fi
if ! command -v maestro > /dev/null; then
  echo -e "\nMaestro isn't installed, so the flow didn't run." >> "$md"
  exit 0
fi
mkdir -p "$out/maestro" && cp "$plan/flow.yaml" "$out/maestro/flow.yaml"
(cd "$out/maestro" && MAESTRO_CLI_NO_ANALYTICS=1 maestro --device "$UDID" test flow.yaml > ../maestro.log 2>&1) &&
  flowed=passed || flowed=failed
echo "maestro: $flowed"
{
  echo
  echo "Maestro flow: **$flowed**."
  if [[ $flowed == failed ]]; then
    echo; echo '```'
    grep -vE "^\s+at " "$out/maestro.log" | grep -iE "error|exception|fail|not found|timed out" | cut -c1-300 | head -15
    echo '```'
  fi
} >> "$md"
for v in "$out"/maestro/*.mp4; do
  [[ -f $v ]] || continue
  gif="$out/$(basename "${v%.mp4}").gif"
  if ffmpeg -loglevel error -y -i "$v" -vf "fps=8,scale=320:-1:flags=lanczos" -t 30 "$gif" 2> /dev/null; then
    echo -e "\n![Recording $(basename "$gif")]($(basename "$gif"))" >> "$md"
  fi
  rm -f "$v"
done
for p in "$out"/maestro/*.png; do
  [[ -f $p ]] || continue
  mv "$p" "$out/"
  echo -e "\n![$(basename "$p")]($(basename "$p"))" >> "$md"
done
exit 0
