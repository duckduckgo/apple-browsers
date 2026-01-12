#!/bin/sh

# SwiftLint build phase script
# Shared between iOS and macOS projects
# Runs SwiftLint from repo root using .swiftlint.yml
set -u

MODIFIED_ONLY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --modified-only)
      MODIFIED_ONLY=true
      shift
      ;;
    *)
      echo "warning: SwiftLint: Unknown argument: $1"
      shift
      ;;
  esac
done

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
REPO_ROOT="$(cd "${SRCROOT}/.." && pwd)"
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

if [ -z "$SWIFTLINT_VERSION" ]; then
  echo "warning: SwiftLint not available — skipping."
  exit 0
fi

echo "SwiftLint: Linting using version $SWIFTLINT_VERSION"

if [ "$MODIFIED_ONLY" = true ]; then
  MODIFIED_FILES=$(git diff --name-only --diff-filter=d HEAD 2>/dev/null | grep '\.swift$' || true)
  STAGED_FILES=$(git diff --name-only --diff-filter=d --cached 2>/dev/null | grep '\.swift$' || true)
  UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null | grep '\.swift$' || true)

  ALL_FILES=$(printf '%s\n%s\n%s' "$MODIFIED_FILES" "$STAGED_FILES" "$UNTRACKED_FILES" | sort -u | grep -v '^$' || true)

  if [ -z "$ALL_FILES" ]; then
    echo "SwiftLint: No modified Swift files to lint."
    exit 0
  fi

  FILE_COUNT=$(echo "$ALL_FILES" | wc -l | tr -d ' ')
  echo "SwiftLint: Linting $FILE_COUNT modified file(s)..."

  # Convert to absolute paths and run from /tmp to avoid SwiftLint scanning the entire repo.
  # SwiftLint scans the working directory to build its file index even when given specific files, which causes ~50s overhead.
  ABSOLUTE_FILES=$(echo "$ALL_FILES" | sed "s|^|${REPO_ROOT}/|")
  cd /tmp || exit 0
  echo "$ABSOLUTE_FILES" | xargs "$MINT" run --mintfile "${REPO_ROOT}/Mintfile" swiftlint lint --quiet --working-directory "${REPO_ROOT}" || true
else
  "$MINT" run swiftlint lint --quiet || true
fi
