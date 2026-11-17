#!/usr/bin/env bash

set -eo pipefail

platform=$1
destination=$2
repository=$(cd "$(dirname "$0")/.." && pwd)

case "$platform" in
  ios)
    log="ios-build-log.txt"
    report="ios-unittests.xml"
    ;;
  macos)
    log="build-log.txt"
    report="package-tests.xml"
    ;;
  *)
    echo "Unknown platform: $platform" >&2
    exit 1
    ;;
esac

packages=$(jq -ce --arg platform "$platform" '
  .[] | select($platform == "macos" or .macosTestOnly != true)
' "$repository/.github/shared-package-checks.json")

run_package() (
  package=$1
  path=$2
  scheme=$(jq -er --arg name "${path##*/}" '.scheme // $name' <<< "$package") || exit 1
  macos_test_only=$(jq -r '.macosTestOnly // false' <<< "$package") || exit 1
  build_only=$(jq -r '.buildOnly // false' <<< "$package") || exit 1
  test_targets=$(jq -r '.testTargets[]?' <<< "$package") || exit 1
  sources=$(jq -r '(.warningSources // ["Sources", "Tests"])[]' <<< "$package") || exit 1

  cd "$repository/SharedPackages/$path" || exit 1

  build_actions=(clean test)
  xcode_args=(-scheme "$scheme" -destination "$destination" -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO)
  formatter=(xcbeautify --report junit --report-path . --junit-report-filename "$report")
  if [[ "$build_only" == true ]]; then
    build_actions=(clean build)
    formatter=(xcbeautify)
  else
    if [[ "$macos_test_only" == true ]]; then
      build_actions=(test)
    fi
    if [[ "$platform" == macos ]]; then
      xcode_args+=(-skipPackagePluginValidation -skipMacroValidation -test-iterations 3 -retry-tests-on-failure)
    fi
    while IFS= read -r target; do
      [[ -n "$target" ]] && xcode_args+=("-only-testing:$target")
    done <<< "$test_targets"
  fi

  if [[ "$platform" == macos && "$build_only" != true ]]; then
    xcodebuild "${build_actions[@]}" "${xcode_args[@]}" 2>&1 | tee "$log" \
      | sed -e 's/CoreData: error:/CoreData: [notice]:/g' -e 's/Failed to create NSXPCConnection/[notice] NSXPCConnection unavailable/g' \
      | "${formatter[@]}" || exit 1
  else
    xcodebuild "${build_actions[@]}" "${xcode_args[@]}" 2>&1 | tee "$log" | "${formatter[@]}" || exit 1
  fi

  if [[ "$macos_test_only" != true ]]; then
    warning_sources=()
    while IFS= read -r source; do
      warning_sources+=("$source")
    done <<< "$sources"
    python3 "$repository/scripts/check-swift-concurrency-warnings.py" "$log" "${warning_sources[@]}"
  fi
)

# Keep running after a package fails so the job reports every failure.
failed=()
while IFS= read -r package; do
  path=$(jq -er '.path' <<< "$package")
  echo "::group::$path"
  run_package "$package" "$path" || failed+=("$path")
  echo "::endgroup::"
done <<< "$packages"

if (( ${#failed[@]} > 0 )); then
  echo "::error::Package checks failed for: ${failed[*]}"
  exit 1
fi
