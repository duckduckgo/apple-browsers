#!/usr/bin/env bash
# Exports the agent's change as a patch for the run's evidence, after moving its evidence plan out of the checkout
# so it never goes into the patch. Fails when there's no change, or when the patch touches .github/ or
# scripts/agent-worker/
#
# Usage: export_patch.sh <evidence dir>   (run from the checkout)
# Env: BASE_SHA, the commit the agent started from, so commits the agent made are part of the patch

set -euo pipefail
evidence=$1
here=$(cd "$(dirname "$0")" && pwd)
python3 -I "$here/evidence_plan.py" extract . "$evidence"
base=${BASE_SHA:-HEAD}
git add -A
git diff --cached --binary "$base" > "$evidence/changes.patch"
python3 -I "$here/evidence_plan.py" excluded "$evidence"
if [[ ! -s "$evidence/changes.patch" ]]; then
  printf '\n## Changes\n\nNone.\n' >> "$evidence/summary.md"
  echo "::error::agent made no changes"
  exit 1
fi
{ printf '\n## Changes\n\n```\n'; git diff --cached --stat "$base"; printf '```\n'; } >> "$evidence/summary.md"
if git diff --cached --name-only "$base" | grep -qE '^(\.github|scripts/agent-worker)/'; then
  echo "::error::patch touches .github/ or scripts/agent-worker/; refusing"
  exit 1
fi
git diff --cached --stat "$base"
