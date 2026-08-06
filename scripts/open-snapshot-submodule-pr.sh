#!/bin/bash

set -euo pipefail

# Opens (or updates) the companion PR in the apple-browsers-snapshots submodule
# whenever the current branch changes reference images, then stages the updated
# submodule pointer so the monorepo PR points at a pushed commit.
#
# Run from the monorepo root, on the feature branch you are about to open a PR
# from. Requires an authenticated `gh`.
#
# Usage: ./scripts/open-snapshot-submodule-pr.sh

SUBMODULE_PATH="SnapshotReferences"
SUBMODULE_REPO="duckduckgo/apple-browsers-snapshots"
BASE_BRANCH="main"

DIRTY="$(git -C "$SUBMODULE_PATH" status --porcelain)"
ON_REMOTE="$(git -C "$SUBMODULE_PATH" branch -r --contains HEAD 2>/dev/null || true)"

if [ -z "$DIRTY" ] && [ -n "$ON_REMOTE" ]; then
	echo "ℹ️  $SUBMODULE_PATH is clean and already pushed — nothing to sync."
	exit 0
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" = "HEAD" ] || [ "$BRANCH" = "$BASE_BRANCH" ]; then
	echo "❌ Refusing to sync from '$BRANCH'. Check out a feature branch first."
	exit 1
fi

echo "🔄 Syncing snapshot references on branch '$BRANCH'..."

git -C "$SUBMODULE_PATH" checkout -B "$BRANCH"
if [ -n "$DIRTY" ]; then
	git -C "$SUBMODULE_PATH" add -A
	git -C "$SUBMODULE_PATH" commit -m "Update snapshot references for $BRANCH"
fi
git -C "$SUBMODULE_PATH" push -u origin "$BRANCH"

PR_URL="$(gh pr list -R "$SUBMODULE_REPO" --head "$BRANCH" --state open --json url --jq '.[0].url // empty')"
if [ -z "$PR_URL" ]; then
	PR_URL="$(gh pr create -R "$SUBMODULE_REPO" \
		--base "$BASE_BRANCH" \
		--head "$BRANCH" \
		--title "Snapshot references for $BRANCH" \
		--body "Companion reference-image changes for the \`$BRANCH\` branch in duckduckgo/apple-browsers.")"
	echo "✅ Opened submodule PR: $PR_URL"
else
	echo "♻️  Reusing existing submodule PR: $PR_URL"
fi

git add "$SUBMODULE_PATH"

echo ""
echo "🔗 Submodule PR: $PR_URL"
echo "📌 Staged updated '$SUBMODULE_PATH' pointer. Add the link above to your monorepo PR description."
