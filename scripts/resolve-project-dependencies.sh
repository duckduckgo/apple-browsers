#!/usr/bin/env bash

# Re-resolves Swift package dependencies for the components whose committed
# Package.resolved lockfiles are hashed by CI, so they pick up a dependency bump
# (e.g. a content-scope-scripts update that landed in SharedPackages/BrowserServicesKit).
#
# These lockfiles drift because Dependabot only updates BrowserServicesKit itself;
# every other consumer that resolves BSK by path lags behind until re-resolved.
#
# Run it after checking out a Dependabot bump, then review and commit any
# changed Package.resolved files yourself.

set -euo pipefail

# Run from the repo root regardless of where the script is invoked from.
cd "$(dirname "$0")/.."

# Xcode projects resolve via xcodebuild.
for project in iOS/DuckDuckGo-iOS.xcodeproj macOS/DuckDuckGo-macOS.xcodeproj; do
    echo "Resolving packages for $project..."
    xcodebuild -resolvePackageDependencies -project "$project" >/dev/null
done

# DataBrokerProtectionCore is a SwiftPM package with its own CI-hashed lockfile;
# it resolves via swift package rather than xcodebuild.
echo "Resolving packages for SharedPackages/DataBrokerProtectionCore..."
( cd SharedPackages/DataBrokerProtectionCore && swift package resolve >/dev/null )

echo "Done. Review and commit any changed Package.resolved files:"
# git pathspec, not a shell glob: '*' matches '/' (no FNM_PATHNAME), so this
# catches nested lockfiles like iOS/.../Package.resolved at any depth. The
# quotes stop the shell expanding '*' before git sees the pathspec.
git status --short '*Package.resolved'
