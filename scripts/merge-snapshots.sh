#!/bin/bash

set -euo pipefail

# Merges the companion PR in the apple-browsers-snapshots submodule into its
# main, then repoints the monorepo PR branch at the resulting main commit so the
# monorepo can never reference a commit that only lives on a soon-deleted branch.
#
# Triggered by the "Merge snapshots" label via
# .github/workflows/merge_snapshots.yml. Requires a `gh`/git authenticated with
# write access to both duckduckgo/apple-browsers and
# duckduckgo/apple-browsers-snapshots.
#
# Usage: ./scripts/merge-snapshots.sh <pr-branch>

BRANCH="${1:-}"
SUBMODULE_PATH="SnapshotReferences"
SUBMODULE_REPO="duckduckgo/apple-browsers-snapshots"
BASE_BRANCH="main"

if [ -z "$BRANCH" ]; then
	echo "❌ Usage: $0 <pr-branch>"
	exit 1
fi

PR_NUMBER="$(gh pr list -R "$SUBMODULE_REPO" --head "$BRANCH" --state open --json number --jq '.[0].number // empty')"
if [ -n "$PR_NUMBER" ]; then
	echo "🔀 Merging $SUBMODULE_REPO PR #$PR_NUMBER..."
	gh pr merge "$PR_NUMBER" -R "$SUBMODULE_REPO" --merge
else
	echo "ℹ️  No open companion PR on '$BRANCH'; assuming it is already merged."
fi

NEW_POINTER="$(gh api "repos/$SUBMODULE_REPO/commits/$BASE_BRANCH" --jq '.sha')"
CURRENT_POINTER="$(git rev-parse "HEAD:$SUBMODULE_PATH")"

if [ "$NEW_POINTER" = "$CURRENT_POINTER" ]; then
	echo "✅ Pointer already at $SUBMODULE_REPO@$BASE_BRANCH ($NEW_POINTER) — nothing to update."
	exit 0
fi

echo "📌 Repointing $SUBMODULE_PATH: $CURRENT_POINTER → $NEW_POINTER"
git update-index --cacheinfo "160000,$NEW_POINTER,$SUBMODULE_PATH"
git -c user.name="github-actions[bot]" \
	-c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
	commit -m "Update $SUBMODULE_PATH pointer to merged $BASE_BRANCH"
git push origin "HEAD:$BRANCH"

echo "✅ Merged the companion PR and repointed $SUBMODULE_PATH to $NEW_POINTER."
