#!/bin/bash

set -euo pipefail

# Opens (or updates) the companion PR in the apple-browsers-snapshots submodule
# whenever the current branch changes reference images, then stages the updated
# submodule pointer so the monorepo PR points at a pushed commit.
#
# Run from the monorepo root, on the feature branch you are about to open a PR
# from. The push reuses whatever GitHub access you already have: SSH when the
# monorepo is cloned over SSH, otherwise `gh` credentials, otherwise git's own
# credential helper. Without an authenticated `gh`, it prints a link to open the
# PR in the browser instead.
#
# Usage: ./scripts/open-snapshot-submodule-pr.sh

SUBMODULE_PATH="SnapshotReferences"
SUBMODULE_REPO="duckduckgo/apple-browsers-snapshots"
SUBMODULE_SSH_URL="git@github.com:$SUBMODULE_REPO.git"
SUBMODULE_HTTPS_URL="https://github.com/$SUBMODULE_REPO.git"
BASE_BRANCH="main"

gh_is_authenticated() {
	command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1
}

push_submodule_branch() {
	case "$(git remote get-url origin 2>/dev/null || true)" in
		git@github.com:* | ssh://*)
			git -C "$SUBMODULE_PATH" push "$SUBMODULE_SSH_URL" "HEAD:refs/heads/$BRANCH"
			return
			;;
	esac

	if gh_is_authenticated; then
		git -C "$SUBMODULE_PATH" \
			-c credential.helper= \
			-c "credential.helper=!gh auth git-credential" \
			push "$SUBMODULE_HTTPS_URL" "HEAD:refs/heads/$BRANCH"
		return
	fi

	git -C "$SUBMODULE_PATH" push "$SUBMODULE_HTTPS_URL" "HEAD:refs/heads/$BRANCH"
}

TOP_LEVEL="$(git rev-parse --show-toplevel)"
SUBMODULE_ROOT="$(git -C "$SUBMODULE_PATH" rev-parse --show-toplevel 2>/dev/null || true)"
if [ "$SUBMODULE_ROOT" != "$TOP_LEVEL/$SUBMODULE_PATH" ]; then
	echo "❌ $SUBMODULE_PATH is not initialized. Run 'git submodule update --init $SUBMODULE_PATH' first."
	exit 1
fi

DIRTY="$(git -C "$SUBMODULE_PATH" status --porcelain)"
SUBMODULE_HEAD="$(git -C "$SUBMODULE_PATH" rev-parse HEAD)"
BASE_SUBMODULE_HEAD="$(git rev-parse "$(git merge-base HEAD "origin/$BASE_BRANCH"):$SUBMODULE_PATH")"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" = "HEAD" ] || [ "$BRANCH" = "$BASE_BRANCH" ]; then
	echo "❌ Refusing to sync from '$BRANCH'. Check out a feature branch first."
	exit 1
fi

if [ -z "$DIRTY" ] && [ "$SUBMODULE_HEAD" = "$BASE_SUBMODULE_HEAD" ]; then
	echo "ℹ️  $SUBMODULE_PATH has no changes to sync."
	exit 0
fi

echo "🔄 Syncing snapshot references on branch '$BRANCH'..."

git -C "$SUBMODULE_PATH" checkout -B "$BRANCH"
if [ -n "$DIRTY" ]; then
	git -C "$SUBMODULE_PATH" add -A
	git -C "$SUBMODULE_PATH" commit -m "Update snapshot references for $BRANCH"
fi
push_submodule_branch

if gh_is_authenticated; then
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
else
	PR_URL="https://github.com/$SUBMODULE_REPO/compare/$BASE_BRANCH...$BRANCH?expand=1"
	echo "⚠️  gh is not installed or not authenticated, so the submodule PR was not opened automatically."
	echo "   Open it (or find the existing one) here, then use its link instead: $PR_URL"
fi

git add "$SUBMODULE_PATH"

echo ""
echo "🔗 Submodule PR: $PR_URL"
echo "📌 Staged updated '$SUBMODULE_PATH' pointer. Add the link above to your monorepo PR description."
