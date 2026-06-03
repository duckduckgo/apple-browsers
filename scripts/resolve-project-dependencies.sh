#!/usr/bin/env bash

# Re-resolves Swift package dependencies for the iOS and macOS app projects so
# their committed Package.resolved lockfiles pick up a dependency bump (e.g. a
# content-scope-scripts update that landed in SharedPackages/BrowserServicesKit).
#
# Run it after checking out a Dependabot bump, then review and commit any
# changed Package.resolved files yourself.

set -euo pipefail

# Run from the repo root regardless of where the script is invoked from.
cd "$(dirname "$0")/.."

for project in iOS/DuckDuckGo-iOS.xcodeproj macOS/DuckDuckGo-macOS.xcodeproj; do
    echo "Resolving packages for $project..."
    xcodebuild -resolvePackageDependencies -project "$project" >/dev/null
done

echo "Done. Review and commit any changed Package.resolved files:"
git status --short '*Package.resolved'
