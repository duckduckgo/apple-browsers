#!/bin/bash

set -euo pipefail

# Create PR for Smartling translations with deletions/replacements
# Usage: ./smartling_create_deletions_pr.sh <new_branch> <base_branch> <job_id> <platform> <project_id>

NEW_BRANCH="$1"
BASE_BRANCH="$2"
JOB_ID="$3"
PLATFORM="$4"
PROJECT_ID="$5"

if [ -z "$NEW_BRANCH" ] || [ -z "$BASE_BRANCH" ] || [ -z "$JOB_ID" ] || [ -z "$PLATFORM" ] || [ -z "$PROJECT_ID" ]; then
	echo "❌ Error: All parameters are required"
	echo "Usage: $0 <new_branch> <base_branch> <job_id> <platform> <project_id>"
	exit 1
fi

echo "🔄 Creating PR for translations with deletions/replacements..."

# Create the PR title
PR_TITLE="⚠️ Smartling translations with deletions (Job: $JOB_ID, Platform: $PLATFORM)"

# Create the PR body with detailed information
PR_BODY="## 🚨 Translation Changes Requiring Review

This PR contains Smartling translations that include **deletions or significant changes** that could result in data loss. The changes were automatically moved to this separate PR for manual review.

### Details
- **Job ID**: \`$JOB_ID\`
- **Platform**: \`$PLATFORM\`
- **Project ID**: \`$PROJECT_ID\`
- **Base Branch**: \`$BASE_BRANCH\`

### What happened?
The translation import process detected one or more of the following issues:
- Deleted translation keys that existed in the previous version
- Significantly shortened translation values for existing keys
- Empty translation values where content previously existed

More details can be found [here](https://app.asana.com/0/0/1210223145394340)

### Next Steps
1. **Review** the changesin this PR
2. **Verify** that any deletions are intentional
3. **Merge** this PR into \`$BASE_BRANCH\` if the changes are acceptable, or close the PR otherwise.

---
*Created automatically by Smartling translation workflow*"

# Create the PR using GitHub CLI
if ! gh pr create \
	--title "$PR_TITLE" \
	--body "$PR_BODY" \
	--base "$BASE_BRANCH" \
	--head "$NEW_BRANCH" \
	--label "translation" \
	--label "needs review" 2>&1; then
	echo "❌ Failed to create PR"
	exit 1
fi

# Get the PR number for output
PR_NUMBER=$(gh pr list --head "$NEW_BRANCH" --json number --jq '.[0].number')
PR_URL=$(gh pr list --head "$NEW_BRANCH" --json url --jq '.[0].url')

echo "✅ Successfully created PR #$PR_NUMBER"
echo "🔗 PR URL: $PR_URL"

# Store PR information for later use
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "deletions_pr_number=$PR_NUMBER" >> "$GITHUB_OUTPUT"
	echo "deletions_pr_url=$PR_URL" >> "$GITHUB_OUTPUT"
fi

# Also create a file with PR info for message generation
cat > deletions_pr_info.txt << EOF
PR_NUMBER=$PR_NUMBER
PR_URL=$PR_URL
NEW_BRANCH=$NEW_BRANCH
EOF

exit 0