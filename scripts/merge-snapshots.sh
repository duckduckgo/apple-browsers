#!/bin/bash

set -euo pipefail

# Merges the companion PR in the apple-browsers-snapshots submodule into its
# main with a merge commit, then verifies the monorepo PR's submodule pointer is
# reachable from that main, so the monorepo can never reference a commit that
# only lived on the deleted companion branch. The monorepo PR branch is left
# untouched so its CI results and approvals stay valid.
#
# Triggered by the "Merge snapshots" label via
# .github/workflows/merge_snapshots.yml. Requires a `gh` authenticated with
# write access to duckduckgo/apple-browsers-snapshots, run from a checkout of
# the monorepo PR branch.
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

PR_NUMBER="$(gh pr list -R "$SUBMODULE_REPO" --base "$BASE_BRANCH" --head "$BRANCH" --state all --limit 100 --json number --jq 'sort_by(.number) | last | .number // empty')"
if [ -z "$PR_NUMBER" ]; then
	echo "❌ No companion PR targeting '$BASE_BRANCH' was found for branch '$BRANCH'."
	exit 1
fi

MERGED_AT="$(gh pr view "$PR_NUMBER" -R "$SUBMODULE_REPO" --json mergedAt --jq '.mergedAt // empty')"
if [ -z "$MERGED_AT" ]; then
	PR_STATE="$(gh pr view "$PR_NUMBER" -R "$SUBMODULE_REPO" --json state --jq '.state')"
	if [ "$PR_STATE" != "OPEN" ]; then
		echo "❌ Companion PR #$PR_NUMBER is '$PR_STATE', not merged."
		exit 1
	fi

	echo "🔀 Merging $SUBMODULE_REPO PR #$PR_NUMBER..."
	gh pr merge "$PR_NUMBER" -R "$SUBMODULE_REPO" --merge
else
	echo "ℹ️  Companion PR #$PR_NUMBER is already merged."
fi

CURRENT_POINTER="$(git rev-parse "HEAD:$SUBMODULE_PATH")"

STATUS=""
for attempt in 1 2 3 4 5; do
	STATUS="$(gh api "repos/$SUBMODULE_REPO/compare/$BASE_BRANCH...$CURRENT_POINTER" --jq '.status' 2>/dev/null || true)"
	if [ "$STATUS" = "identical" ] || [ "$STATUS" = "behind" ]; then
		break
	fi
	if [ "$attempt" -lt 5 ]; then
		echo "⏳ $SUBMODULE_PATH pointer not on $SUBMODULE_REPO@$BASE_BRANCH yet (status: '${STATUS:-unknown}', attempt $attempt/5); retrying in 3s..."
		sleep 3
	fi
done
if [ "$STATUS" != "identical" ] && [ "$STATUS" != "behind" ]; then
	echo "❌ $SUBMODULE_PATH points at $CURRENT_POINTER, which is not reachable from $SUBMODULE_REPO@$BASE_BRANCH (status: '${STATUS:-unknown}')."
	echo "   Run ./scripts/open-snapshot-submodule-pr.sh on '$BRANCH' and push, so the pointer matches the companion PR."
	exit 1
fi

echo "✅ Companion PR #$PR_NUMBER is merged and $SUBMODULE_PATH ($CURRENT_POINTER) is on $SUBMODULE_REPO@$BASE_BRANCH. No new commit needed."
