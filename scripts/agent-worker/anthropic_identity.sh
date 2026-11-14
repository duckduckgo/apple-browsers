#!/usr/bin/env bash
# Keeps a fresh GitHub identity token on disk for Claude's workload identity federation and exports the
# ANTHROPIC_* settings to later steps. A background loop refreshes the token every minute
#
# Usage: anthropic_identity.sh <dir>
# Env: RULE, ORG, SERVICE_ACCOUNT, WORKSPACE (optional), ACTIONS_ID_TOKEN_REQUEST_URL and _TOKEN

set -euo pipefail
dir=$1
mkdir -p "$dir" && chmod 0700 "$dir"
fetch() {
  curl -fsS --retry 3 --retry-all-errors -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=https://api.anthropic.com" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["value"])' > "$dir/token.tmp" &&
    mv "$dir/token.tmp" "$dir/token"
}
fetch
(while sleep 60; do fetch || true; done) > /dev/null 2>&1 &
{
  echo "ANTHROPIC_FEDERATION_RULE_ID=$RULE"
  echo "ANTHROPIC_ORGANIZATION_ID=$ORG"
  echo "ANTHROPIC_SERVICE_ACCOUNT_ID=$SERVICE_ACCOUNT"
  if [ -n "${WORKSPACE:-}" ]; then echo "ANTHROPIC_WORKSPACE_ID=$WORKSPACE"; fi
  echo "ANTHROPIC_IDENTITY_TOKEN_FILE=$dir/token"
} >> "$GITHUB_ENV"
