#!/bin/bash

set -euo pipefail

RENDERED_DIR="${1:-}"
BRANCH="${2:-}"
SUBMODULE_PATH="SnapshotReferences"
SUBMODULE_REPO="duckduckgo/apple-browsers-snapshots"
BASE_BRANCH="main"
BOT_NAME="github-actions[bot]"
BOT_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"

if [ -z "$RENDERED_DIR" ] || [ -z "$BRANCH" ]; then
	echo "❌ Usage: $0 <rendered-dir> <pr-branch>"
	exit 1
fi

if [ "$BRANCH" = "$BASE_BRANCH" ]; then
	echo "❌ Refusing to record from '$BRANCH'. Record from a feature branch, so the images go through a snapshots PR."
	exit 1
fi

if [ ! -d "$RENDERED_DIR" ]; then
	echo "❌ No rendered snapshots at '$RENDERED_DIR'."
	exit 1
fi
RENDERED_DIR="$(cd "$RENDERED_DIR" && pwd)"

UNEXPECTED="$(find "$RENDERED_DIR" ! -type f ! -type d)"
if [ -n "$UNEXPECTED" ]; then
	echo "❌ Rendered snapshots contain entries that aren't regular files:"
	echo "$UNEXPECTED"
	exit 1
fi

IMAGES=()
while IFS= read -r -d '' file; do
	relative="${file#"$RENDERED_DIR"/}"
	if ! [[ "$relative" =~ ^macOS/([A-Za-z0-9._+-]+/)*__Snapshots__/[A-Za-z0-9._+-]+/[A-Za-z0-9._+-]+\.png$ ]] || [[ "/$relative/" == */../* ]]; then
		echo "❌ Unexpected file in rendered snapshots: $relative"
		exit 1
	fi
	IMAGES+=("$relative")
done < <(find "$RENDERED_DIR" -type f -print0 | sort -z)

if [ "${#IMAGES[@]}" -eq 0 ]; then
	echo "❌ No rendered snapshots to record in '$RENDERED_DIR'."
	exit 1
fi

POINTER="$(git rev-parse "HEAD:$SUBMODULE_PATH")"
SUBMODULE_URL="https://github.com/$SUBMODULE_REPO.git"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

git_snapshots() {
	git -C "$WORK_DIR" -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"
}

git_snapshots init -q
git_snapshots remote add origin "$SUBMODULE_URL"

if git_snapshots fetch -q origin "refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null; then
	BRANCH_HEAD="$(git_snapshots rev-parse "origin/$BRANCH")"
	if [ "$BRANCH_HEAD" != "$POINTER" ]; then
		echo "❌ $SUBMODULE_REPO@$BRANCH is at $BRANCH_HEAD, but $SUBMODULE_PATH points at $POINTER, the references CI compared against."
		echo "   Point $SUBMODULE_PATH at the snapshots branch, push, wait for the macOS PR checks, then re-add the label."
		exit 1
	fi
	BRANCH_EXISTS=true
else
	BRANCH_EXISTS=false
fi
git_snapshots fetch -q origin "$POINTER"
git_snapshots checkout -q -b "$BRANCH" "$POINTER"

for image in "${IMAGES[@]}"; do
	blob="$(git_snapshots hash-object -w -- "$RENDERED_DIR/$image")"
	git_snapshots update-index --add --cacheinfo "100644,$blob,$image"
done

if git_snapshots diff --cached --quiet; then
	echo "ℹ️  $SUBMODULE_REPO@$BRANCH already has CI's renderings."
	if [ "$BRANCH_EXISTS" = false ]; then
		exit 0
	fi
else
	git_snapshots -c user.name="$BOT_NAME" -c user.email="$BOT_EMAIL" \
		commit -q -m "Record CI snapshot renderings for $BRANCH"
	git_snapshots push -q origin "HEAD:refs/heads/$BRANCH"
	echo "✅ Committed ${#IMAGES[@]} rendered snapshot(s) to $SUBMODULE_REPO@$BRANCH."
fi

PR_URL="$(gh pr list -R "$SUBMODULE_REPO" --head "$BRANCH" --state open --json url --jq '.[0].url // empty')"
if [ -z "$PR_URL" ]; then
	PR_URL="$(gh pr create -R "$SUBMODULE_REPO" \
		--base "$BASE_BRANCH" \
		--head "$BRANCH" \
		--title "Snapshot references for $BRANCH" \
		--body "Companion reference-image changes for the \`$BRANCH\` branch in duckduckgo/apple-browsers.")"
	echo "✅ Opened submodule PR: $PR_URL"
fi

NEW_POINTER="$(git_snapshots rev-parse HEAD)"
if [ "$NEW_POINTER" = "$POINTER" ]; then
	echo "ℹ️  $SUBMODULE_PATH already points at $NEW_POINTER. No monorepo commit needed."
else
	git update-index --cacheinfo "160000,$NEW_POINTER,$SUBMODULE_PATH"
	git -c user.name="$BOT_NAME" -c user.email="$BOT_EMAIL" \
		commit -q -m "Record CI snapshot renderings"
	git push -q origin "HEAD:refs/heads/$BRANCH"
	echo "✅ Pointed $SUBMODULE_PATH at $NEW_POINTER on '$BRANCH'."
fi

echo "🔗 Submodule PR: $PR_URL"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### 📸 Recorded ${#IMAGES[@]} CI snapshot rendering(s)"
		echo "Review them in $PR_URL before adding the \`Merge snapshots\` label."
	} >> "$GITHUB_STEP_SUMMARY"
fi
