#!/bin/sh

# SwiftLint build phase script
# Shared between iOS and macOS projects
# Runs SwiftLint from SRCROOT, using the platform's .swiftlint.yml
set -u

echo "Running SwiftLint..."

# Skip in CI - handled by dedicated workflow
if [ -n "${CI:-}" ] || [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  echo "SwiftLint: Skipping in CI (handled by dedicated workflow)."
  exit 0
fi

# Xcode build phases don't inherit the user's shell PATH.
# Prepend Homebrew bin paths so Mint can be found.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Check if Mint is installed
MINT="$(command -v mint || true)"
if [ -z "$MINT" ]; then
  echo "warning: SwiftLint: Mint not found — skipping (opt-in)."
  exit 0
fi

# Run from SRCROOT (iOS/ or macOS/) so SwiftLint picks up the local .swiftlint.yml
cd "${SRCROOT}" || exit 0

# Check for .swiftlint.yml in current directory
if [ ! -f ".swiftlint.yml" ]; then
  echo "warning: SwiftLint: No .swiftlint.yml found in ${SRCROOT} — skipping."
  exit 0
fi

# cd to repo root where Mintfile lives, then back to run SwiftLint
REPO_ROOT="${SRCROOT}/.."
if [ ! -f "${REPO_ROOT}/Mintfile" ]; then
  echo "warning: SwiftLint: Mintfile not found in ${REPO_ROOT} — skipping."
  exit 0
fi

# Get SwiftLint version (run from repo root for Mintfile)
SWIFTLINT_VERSION="$(cd "${REPO_ROOT}" && "$MINT" run swiftlint --version 2>/dev/null || true)"

if [ -n "$SWIFTLINT_VERSION" ]; then
  echo "SwiftLint: Linting using version $SWIFTLINT_VERSION from ${SRCROOT}"
  # Run lint from SRCROOT (for local .swiftlint.yml) but use repo root's Mintfile
  cd "${REPO_ROOT}" && "$MINT" run swiftlint lint --quiet --config "${SRCROOT}/.swiftlint.yml" || true
else
  echo "warning: SwiftLint not available — skipping."
fi

