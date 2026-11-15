#!/usr/bin/env bash
# Exports the agent's change as a patch, after moving its PR text and evidence plan out of the checkout
# so they never go into the patch. Fails when there's no change, or when the patch touches .github/ or
# scripts/agent-worker/. A retry that leaves the previous patch as it was still goes to verify, since a
# failure can be flaky
#
# Usage: export_patch.sh <evidence dir>   (run from the checkout)

set -euo pipefail
evidence=$1
here=$(cd "$(dirname "$0")" && pwd)
python3 -I "$here/pr_text.py" extract . "$evidence"
python3 -I "$here/evidence_plan.py" extract . "$evidence"
git add -A
git diff --cached --binary > "$evidence/changes.patch"
python3 -I "$here/evidence_plan.py" excluded "$evidence"
if [[ ! -s "$evidence/changes.patch" ]]; then
  printf '\n## Changes\n\nNone, so nothing will be published.\n' >> "$evidence/summary.md"
  echo "::error::agent made no changes"
  exit 1
fi
{ printf '\n## Changes\n\n```\n'; git diff --cached --stat; printf '```\n'; } >> "$evidence/summary.md"
if git diff --cached --name-only | grep -qE '^(\.github|scripts/agent-worker)/'; then
  echo "::error::patch touches .github/ or scripts/agent-worker/; refusing"
  exit 1
fi
git diff --cached --stat
