#!/usr/bin/env bash
# Keeps a fresh GitHub identity token on disk for the artifacts identity, so auto's upload-evidence can write the
# agent's evidence to auto's artifact storage. auto signs in with the Azure SDK's ManagedIdentityCredential, which
# exchanges the token in AZURE_FEDERATED_TOKEN_FILE when AZURE_CLIENT_ID and AZURE_TENANT_ID are set. A background
# loop refreshes the token every 4 minutes. Only that loop can request tokens: the agent's environment drops
# ACTIONS_ID_TOKEN_REQUEST_URL and _TOKEN
#
# Usage: azure_identity.sh <dir>
# Env: CLIENT_ID, TENANT_ID, ACTIONS_ID_TOKEN_REQUEST_URL and _TOKEN
# Writes <dir>/token and <dir>/refresher.pid, and AZURE_* and AZURE_TOKEN_DIR to GITHUB_ENV

set -euo pipefail
dir=$1
[[ -n ${CLIENT_ID:-} && -n ${TENANT_ID:-} ]] ||
  { echo "::error::set ARTIFACTS_CLIENT_ID and ARTIFACTS_TENANT_ID in the agent-worker environment"; exit 1; }
mkdir -p "$dir" && chmod 0700 "$dir"
fetch() {
  curl -fsS --retry 3 --retry-all-errors -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["value"])' > "$dir/token.tmp" &&
    chmod 0600 "$dir/token.tmp" && mv "$dir/token.tmp" "$dir/token"
}
fetch
(while sleep 240; do fetch || true; done) > /dev/null 2>&1 &
echo $! > "$dir/refresher.pid"
{
  echo "AZURE_CLIENT_ID=$CLIENT_ID"
  echo "AZURE_TENANT_ID=$TENANT_ID"
  echo "AZURE_FEDERATED_TOKEN_FILE=$dir/token"
  echo "AZURE_TOKEN_DIR=$dir"
} >> "$GITHUB_ENV"
echo "azure identity ready"
