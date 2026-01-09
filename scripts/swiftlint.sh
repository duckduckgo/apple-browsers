#!/bin/sh

# SwiftLint build phase script
# Shared between iOS and macOS projects
# Runs SwiftLint from repo root using .swiftlint.yml
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

# Run from repo root where .swiftlint.yml and Mintfile live
REPO_ROOT="${SRCROOT}/.."
cd "${REPO_ROOT}" || exit 0

# Check for required files
if [ ! -f ".swiftlint.yml" ]; then
  echo "warning: SwiftLint: No .swiftlint.yml found in ${REPO_ROOT} — skipping."
  exit 0
fi

if [ ! -f "Mintfile" ]; then
  echo "warning: SwiftLint: Mintfile not found in ${REPO_ROOT} — skipping."
  exit 0
fi

# Get SwiftLint version
SWIFTLINT_VERSION="$("$MINT" run swiftlint --version 2>/dev/null || true)"

if [ -n "$SWIFTLINT_VERSION" ]; then
  echo "SwiftLint: Linting using version $SWIFTLINT_VERSION"
  # Run lint from repo root - lints entire project
  "$MINT" run swiftlint lint --quiet || true
else
  echo "warning: SwiftLint not available — skipping."
fi
