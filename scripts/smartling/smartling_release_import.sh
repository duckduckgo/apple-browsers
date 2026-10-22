#!/bin/bash
set -euo pipefail

usage() {
	echo "Usage: $0 <iOS|macOS> --release-branch <release/ios/x.y.z|release/macos/x.y.z> [--dry-run] [--reimport]" >&2
	exit 1
}

PLATFORM="${1:-}"
shift || true

RELEASE_BRANCH=""
DRY_RUN="false"
REIMPORT="false"

while [ $# -gt 0 ]; do
	case "$1" in
		--release-branch) RELEASE_BRANCH="${2:-}"; shift 2 ;;
		--dry-run) DRY_RUN="true"; shift ;;
		--reimport) REIMPORT="true"; shift ;;
		*) usage ;;
	esac
done

case "$PLATFORM" in
	iOS)
		PLATFORM_SLUG="ios"
		EXPORT_FILES=(
			"./iOS/scripts/assets/loc/en.xcloc/Localized Contents/en.xliff"
			"./iOS/DuckDuckGo/UserInterfaceResources/en.lproj/Localizable.stringsdict"
		)
		;;
	macOS)
		PLATFORM_SLUG="macos"
		EXPORT_FILES=("./macOS/scripts/assets/loc/en.xliff")
		;;
	*)
		usage
		;;
esac

if [[ "$RELEASE_BRANCH" != "release/$PLATFORM_SLUG/"* ]]; then
	usage
fi

VERSION="${RELEASE_BRANCH#"release/$PLATFORM_SLUG/"}"
JOB_NAME="Release $PLATFORM $VERSION"
IMPORT_BRANCH="smartling/release-$PLATFORM_SLUG-$VERSION"
FILE_URIS=()
for export_file in "${EXPORT_FILES[@]}"; do
	FILE_URIS+=("$RELEASE_BRANCH/$(basename "$export_file")")
done

OUTCOME=""
REASON=""
JOB_ID=""
JOB_URL=""
JOB_STATUS=""
TOTAL_STRINGS=""
STRINGS_LEFT=""
INCOMPLETE_LOCALES=""
JOBS_AWAITING_AUTHORIZATION=""
INTEGRITY=""
PR_URL=""

finish() {
	trap - ERR
	OUTCOME="$1"
	REASON="${2:-$REASON}"
	REASON="$(printf '%s' "$REASON" | tr '\r\n' '  ' | cut -c 1-300)"

	echo "OUTCOME=$OUTCOME"
	[ -z "$REASON" ] || echo "REASON=$REASON"

	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		{
			echo "outcome=$OUTCOME"
			echo "version=$VERSION"
			echo "job_name=$JOB_NAME"
			echo "job_id=$JOB_ID"
			echo "job_url=$JOB_URL"
			echo "job_status=$JOB_STATUS"
			echo "total_strings=$TOTAL_STRINGS"
			echo "strings_left=$STRINGS_LEFT"
			echo "incomplete_locales=$INCOMPLETE_LOCALES"
			echo "jobs_awaiting_authorization=$JOBS_AWAITING_AUTHORIZATION"
			echo "integrity=$INTEGRITY"
			echo "pr_url=$PR_URL"
			echo "reason=$REASON"
		} >> "$GITHUB_OUTPUT"
	fi

	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		{
			echo "## $PLATFORM release translations: $VERSION"
			echo
			echo "- Outcome: \`$OUTCOME\`"
			echo "- Release branch: \`$RELEASE_BRANCH\`"
			echo "- Job: \`$JOB_NAME\` (\`${JOB_STATUS:-not found}\`)"
			[ -z "$STRINGS_LEFT" ] || echo "- String translations left: \`$STRINGS_LEFT\` of \`$TOTAL_STRINGS\`"
			[ -z "$INCOMPLETE_LOCALES" ] || echo "- Incomplete locales: \`$INCOMPLETE_LOCALES\`"
			[ -z "$JOBS_AWAITING_AUTHORIZATION" ] || echo "- Jobs awaiting authorization: $JOBS_AWAITING_AUTHORIZATION"
			[ -z "$INTEGRITY" ] || echo "- Integrity check: \`$INTEGRITY\`"
			[ -z "$PR_URL" ] || echo "- Pull request: $PR_URL"
			[ -z "$REASON" ] || echo "- Reason: $REASON"
		} >> "$GITHUB_STEP_SUMMARY"
	fi

	case "$OUTCOME" in
		error|status_error) exit 1 ;;
		*) exit 0 ;;
	esac
}

trap 'finish error "Failed at line $LINENO: $BASH_COMMAND"' ERR

echo "Release branch: $RELEASE_BRANCH"
echo "Smartling files: ${FILE_URIS[*]}"

OPEN_PR_URL=""
if [ "$REIMPORT" = "true" ]; then
	OPEN_PR_URL="$(gh pr list --head "$IMPORT_BRANCH" --state open --limit 1 --json url --jq '.[].url')"
else
	existing_pr="$(gh pr list --head "$IMPORT_BRANCH" --state all --limit 1 --json state,url --jq '.[] | "\(.state) \(.url)"')"
	if [ -n "$existing_pr" ]; then
		PR_URL="${existing_pr#* }"
		finish skipped_existing_pr "A translations pull request for $VERSION already exists (${existing_pr% *})"
	fi
fi

if [ -n "$(git status --porcelain)" ]; then
	finish error "The working tree has uncommitted changes"
fi

echo "Exporting the release branch's strings..."
"./$PLATFORM/scripts/loc_export.sh" | xcbeautify
git restore --staged --worktree -- .

if ! ./scripts/smartling/loc_tool.sh refresh-files --file-uri-prefix "$RELEASE_BRANCH" --files "${EXPORT_FILES[@]}"; then
	finish status_error "Could not refresh the release files in Smartling"
fi

RESULT_FILE="${RUNNER_TEMP:-/tmp}/smartling-release-status-${PLATFORM}.json"
./scripts/smartling/loc_tool.sh release-status \
	--job-name "$JOB_NAME" \
	--file-uris "${FILE_URIS[@]}" \
	--result-file "$RESULT_FILE"

status_outcome="$(jq -r '.outcome' "$RESULT_FILE")"
JOB_ID="$(jq -r '.job_id' "$RESULT_FILE")"
JOB_URL="$(jq -r '.job_url // empty' "$RESULT_FILE")"
JOB_STATUS="$(jq -r '.job_status' "$RESULT_FILE")"
TOTAL_STRINGS="$(jq -r '.total_strings // empty' "$RESULT_FILE")"
STRINGS_LEFT="$(jq -r '.strings_left // empty' "$RESULT_FILE")"
INCOMPLETE_LOCALES="$(jq -r '.incomplete_locales | join(", ")' "$RESULT_FILE")"
JOBS_AWAITING_AUTHORIZATION="$(jq -r '(.jobs_awaiting_authorization // []) | join(", ")' "$RESULT_FILE")"
REASON="$(jq -r '.reason' "$RESULT_FILE")"

case "$status_outcome" in
	ready) ;;
	not_ready) finish not_ready "$STRINGS_LEFT of $TOTAL_STRINGS string translations are not completed yet" ;;
	*) finish status_error ;;
esac

DOWNLOAD_DIR="$(mktemp -d)/smartling_downloads"
mkdir -p "$DOWNLOAD_DIR"
./scripts/smartling/loc_tool.sh download --file-uris "${FILE_URIS[@]}" --out-dir "$DOWNLOAD_DIR"
./scripts/smartling/smartling_import.sh "$DOWNLOAD_DIR" "$PLATFORM"
rm -rf "$DOWNLOAD_DIR"

echo "Cleaning non-localization files from working tree..."
git restore --staged --worktree -- . ':(exclude)**/*.strings' ':(exclude)**/*.stringsdict' ':(exclude)**/*.xcstrings'

if ./scripts/smartling/check_translation_integrity.py --include-xcstrings; then
	INTEGRITY="passed"
else
	INTEGRITY="issues_found"
fi

if [ -z "$(git status --porcelain -- ':(glob)**/*.strings' ':(glob)**/*.stringsdict' ':(glob)**/*.xcstrings')" ]; then
	if [ -n "$OPEN_PR_URL" ]; then
		PR_URL="$OPEN_PR_URL"
		if [ "$DRY_RUN" = "true" ]; then
			finish no_changes "Dry run: the release branch already has every translation, so the open translations pull request would be closed"
		fi
		gh pr close "$OPEN_PR_URL" --comment "Closed by the Smartling release import: the release branch already has every translation from Smartling, so this pull request is out of date."
		finish pr_closed "The release branch already has every translation, so the open translations pull request was closed"
	fi
	finish no_changes "The release branch already has every translation"
fi

git diff --stat

if [ "$DRY_RUN" = "true" ]; then
	finish ready_dry_run "Dry run: the translations were imported into the working tree but not committed"
fi

git config user.name "Dax the Duck"
git config user.email "dax@duckduckgo.com"
git checkout -B "$IMPORT_BRANCH"
git add -A -- ':(glob)**/*.strings' ':(glob)**/*.stringsdict' ':(glob)**/*.xcstrings'
git commit -m "Import $PLATFORM $VERSION translations from Smartling"
git push --force origin "HEAD:refs/heads/$IMPORT_BRANCH"

if [ -n "$JOB_URL" ]; then
	job_line="- Smartling job: [$JOB_NAME]($JOB_URL)"
else
	job_line="- Smartling job: none, every string in the release was already translated by earlier jobs"
fi

if [ "$INTEGRITY" = "passed" ]; then
	integrity_line="- Integrity check: passed"
else
	integrity_line="- Integrity check: ⚠️ found deleted or much shorter translations. Review the diff before merging."
fi

workflow_line=""
if [ -n "${GITHUB_RUN_ID:-}" ]; then
	workflow_line="- Workflow: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
fi

PR_BODY_FILE="$(mktemp)"
cat > "$PR_BODY_FILE" <<EOF
Tech Design URL: https://app.asana.com/0/0/1219548238783890/f

### Description
Imports the $PLATFORM $VERSION translations from Smartling into \`$RELEASE_BRANCH\`.

- Smartling files: \`${FILE_URIS[*]}\`
$job_line
$integrity_line
$workflow_line

---
*Created automatically by the Smartling release import workflow*
EOF

if [ -n "$OPEN_PR_URL" ]; then
	gh pr edit "$OPEN_PR_URL" --body-file "$PR_BODY_FILE"
	rm -f "$PR_BODY_FILE"
	PR_URL="$OPEN_PR_URL"
	echo "✅ Updated $PR_URL"
	finish pr_updated "The open translations pull request now has this import"
fi

PR_URL="$(gh pr create \
	--base "$RELEASE_BRANCH" \
	--head "$IMPORT_BRANCH" \
	--title "[$PLATFORM] Import $VERSION translations from Smartling" \
	--body-file "$PR_BODY_FILE")"
rm -f "$PR_BODY_FILE"

echo "✅ Opened $PR_URL"
finish pr_opened
