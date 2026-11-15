#!/usr/bin/env bash
# Builds the agent's change and runs its evidence plan: tests, then on iOS a launch screenshot and the
# Maestro flow as a GIF. Never fails: every result, good or bad, goes into results.md, which verify_md.py
# puts into verify.md
#
# Usage: verify.sh <repo dir> <plan dir> <out dir>
# Writes build=, tests= and maestro= lines to <out dir>/status. build= and tests= decide between approval
# and a retry, and maestro= is evidence only
# Env: DEST (iOS Simulator destination), IOS_VERSION (its iOS version), PACKAGES (cloned source packages dir),
# VERIFY_URL (where out dir is uploaded, for links)
# Output to the log is status words only, since this repo's logs are public

set -uo pipefail
repo=$1 plan=$2 out=$3
mkdir -p "$out"
md="$out/results.md" status="$out/status"
url=${VERIFY_URL:-.}
cd "$repo" || exit 0

# The iPhone 17 simulator for IOS_VERSION, for simctl and Maestro
UDID=$(xcrun simctl list devices available -j | python3 -I -c '
import json, os, sys
v = "iOS-" + os.environ.get("IOS_VERSION", "").replace(".", "-")
d = json.load(sys.stdin)["devices"]
print(next((x["udid"] for rt, xs in d.items() if rt.endswith(v) for x in xs if x["name"] == "iPhone 17"), ""))') || UDID=""

platform=ios name=iOS
if git diff --cached --name-only | grep -q '^macOS/' && ! git diff --cached --name-only | grep -q '^iOS/'; then
  platform=macos name=macOS
fi
if [[ $platform == ios ]]; then
  build=(-scheme 'iOS Browser' -destination "$DEST")
else
  build=(-scheme 'macOS Browser' -configuration CI -destination 'platform=macOS' ENABLE_TESTABILITY=true)
fi
common=(-derivedDataPath DerivedData -clonedSourcePackagesDirPath "$PACKAGES" -disableAutomaticPackageResolution
  -skipPackagePluginValidation -skipMacroValidation)

: > "$md"
: > "$status"

# A small copy of a screenshot that fits on screen, linked to the full size one
thumb() {
  local small="${1%.png}-small.png" name
  name=$(basename "$1")
  if sips --resampleWidth 300 "$1" --out "$small" > /dev/null 2>&1; then
    echo "[![$2]($url/$(basename "$small"))]($url/$name)"
  else
    echo "[$2]($url/$name)"
  fi
}
shot() { echo -e "\n$(thumb "$1" "$2")" >> "$md"; }

# Lines worth showing from an xcodebuild log, without the long command echoes
errors() { grep -E ": error:|^error:|BUILD FAILED|Testing failed|failed \(" "$1" | grep -v "^ *export " | cut -c1-300 | sort -u | head -30; }

start=$SECONDS
SPM_FORCE_DEBUG=1 xcodebuild build-for-testing "${build[@]}" "${common[@]}" OTHER_CODE_SIGN_FLAGS=--timestamp=none \
  > "$out/build.log" 2>&1 && built=yes || built=no
echo "build: $built"
echo "build=$built" >> "$status"
{
  echo "## Build and tests"
  echo
  if [[ $built == yes ]]; then
    echo "The $name app built in $(( (SECONDS - start) / 60 )) min ([build.log.gz]($url/build.log.gz))."
  else
    echo "The $name build failed after $(( (SECONDS - start) / 60 )) min ([build.log.gz]($url/build.log.gz)):"
    echo; echo '```'; errors "$out/build.log"; echo '```'
  fi
} >> "$md"
gzip -f "$out/build.log"
[[ $built == yes ]] || exit 0

if [[ -s "$plan/tests.txt" ]]; then
  only=()
  while read -r t; do [[ -n $t ]] && only+=("-only-testing:$t"); done < "$plan/tests.txt"
  xcodebuild test-without-building "${build[@]}" "${common[@]}" "${only[@]}" \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
    > "$out/test.log" 2>&1 && tested=passed || tested=failed
  echo "tests: $tested"
  echo "tests=$tested" >> "$status"
  {
    echo; echo "Tests **$tested**: ${only[*]#-only-testing:} ([test.log.gz]($url/test.log.gz))"
    echo; echo '```'
    grep -E "^Test Case .*(passed|failed)|Executed [0-9]+ test|^Test .* (passed|failed)|TEST (EXECUTE )?(SUCCEEDED|FAILED)|: error:" "$out/test.log" | cut -c1-1000 | head -40
    echo '```'
  } >> "$md"
  gzip -f "$out/test.log"
else
  echo -e "\nNo tests were named for this change." >> "$md"
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
if xcrun simctl install "$UDID" "$app" > /dev/null 2>&1 && xcrun simctl launch "$UDID" com.duckduckgo.mobile.ios \
    -isOnboardingCompleted true -isRunningUITests true > /dev/null 2>&1; then
  sleep 15
  xcrun simctl io "$UDID" screenshot "$out/launch.png" > /dev/null 2>&1 && shot "$out/launch.png" "The app after launch"
  xcrun simctl terminate "$UDID" com.duckduckgo.mobile.ios > /dev/null 2>&1
else
  echo "Couldn't install or launch the app on the simulator." >> "$md"
  exit 0
fi

if [[ ! -s "$plan/flow.yaml" ]]; then
  echo -e "\nThere's no Maestro flow for this change." >> "$md"
  exit 0
fi
if ! command -v maestro > /dev/null; then
  echo -e "\nMaestro isn't installed, so the flow didn't run." >> "$md"
  exit 0
fi
mkdir -p "$out/maestro" && cp "$plan/flow.yaml" "$out/maestro/flow.yaml"
(cd "$out/maestro" && MAESTRO_CLI_NO_ANALYTICS=1 maestro --device "$UDID" test --test-output-dir "$out/maestro/output" flow.yaml > ../maestro.log 2>&1) &&
  flowed=passed || flowed=failed
echo "maestro: $flowed"
echo "maestro=$flowed" >> "$status"
{
  echo
  echo "Maestro flow **$flowed** ([flow.yaml]($url/maestro/flow.yaml), [maestro.log]($url/maestro.log))."
  if [[ $flowed == failed ]]; then
    echo; echo '```'
    grep -vE "^\s+at " "$out/maestro.log" | grep -iE "error|exception|fail|not found|timed out" | cut -c1-300 | head -15
    echo '```'
  fi
} >> "$md"
# Maestro writes screenshots and recordings to the flow's directory or the output dir, depending on its version
find "$out/maestro" -type f \( -name '*.mp4' -o -name '*.png' \) -print0 |
  while IFS= read -r -d '' f; do [[ $(dirname "$f") == "$out/maestro" ]] || mv -n "$f" "$out/maestro/"; done
gifs=() pngs=()
for v in "$out"/maestro/*.mp4; do
  [[ -f $v ]] || continue
  gif="$out/$(basename "${v%.mp4}").gif"
  if ffmpeg -loglevel error -y -i "$v" -vf "fps=8,scale=320:-1:flags=lanczos" -t 30 "$gif" 2> /dev/null; then
    gifs+=("![Recording $(basename "$gif")]($url/$(basename "$gif"))")
  fi
  rm -f "$v"
done
[[ ${#gifs[@]} -gt 0 ]] && echo -e "\n${gifs[*]}" >> "$md"
for p in "$out"/maestro/*.png; do
  [[ -f $p ]] || continue
  mv "$p" "$out/"
  pngs+=("$(thumb "$out/$(basename "$p")" "$(basename "${p%.png}")")")
done
[[ ${#pngs[@]} -gt 0 ]] && echo -e "\n${pngs[*]}" >> "$md"
[[ ${#gifs[@]} -gt 0 || ${#pngs[@]} -gt 0 ]] || echo -e "\nThe flow saved no recording or screenshots." >> "$md"
exit 0
