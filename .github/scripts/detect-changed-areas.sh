#!/bin/bash
#
# detect-changed-areas.sh
#
# Single source of truth for CI change-area detection. Reads a
# newline-separated list of changed file paths on stdin and prints one
# "<area>=<true|false>" line per area (ios, macos, shared) to stdout.
#
# Consumed by:
#   - .github/workflows/should_run_pr_checks.yml (shadow detection in the PR gate)
#   - .github/workflows/replay_change_detection.yml (replay validation on past PRs)
#
# Local usage:
#   git diff --name-only origin/main...HEAD | .github/scripts/detect-changed-areas.sh

set -euo pipefail

files=$(cat)

# A group entry ending in "/" matches everything under that directory;
# any other entry is matched as an exact file path.
changed() {
  local f p
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # shellcheck disable=SC2086 # intentional word splitting of the group list
    for p in $1; do
      case "$p" in
        */) case "$f" in "$p"*) return 0 ;; esac ;;
        *)  [ "$f" = "$p" ] && return 0 ;;
      esac
    done
  done <<< "$files"
  return 1
}

# Dependency closures. ci_infra = composite actions + the gate workflow +
# this script + the Xcode version; a change to any of them forces every
# area to run. shared adds the SharedPackages closure, which covers every
# in-repo package (including BrowserServicesKit and DataBrokerProtectionCore).
# Standalone automation workflows (e.g. macos_check_sparkle_update.yml) are
# intentionally absent, so editing them matches no area.
ci_infra=".github/actions/ .github/workflows/should_run_pr_checks.yml .github/scripts/detect-changed-areas.sh .xcode-version"
shared="$ci_infra SharedPackages/"

ios="$shared scripts/translation-pr-checks/ iOS/ .github/workflows/ios_pr_checks.yml"
macos="$shared scripts/translation-pr-checks/ macOS/ .github/workflows/macos_pr_checks.yml .github/workflows/macos_private_api_report.yml"

for area in ios macos shared; do
  if changed "${!area}"; then echo "${area}=true"; else echo "${area}=false"; fi
done
