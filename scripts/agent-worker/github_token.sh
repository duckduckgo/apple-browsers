#!/usr/bin/env bash
# Keeps a fresh ddg-apple-agent-publish installation token on disk for the agent's gh and git push, since app tokens
# last an hour and a run with babysitting lasts longer. A background loop mints a new one every 45 minutes. The
# private key stays in that loop's memory: it's read from the environment, unset before the loop starts, and passed
# to openssl through a pipe, so it's never in a file or in any process's environment
#
# Usage: github_token.sh <dir>
# Env: APP_CLIENT_ID, APP_PRIVATE_KEY, GITHUB_REPOSITORY
# Writes <dir>/token and <dir>/refresher.pid, a gh wrapper at <dir>/bin/gh, and the git credential helper and bot
# identity to GITHUB_ENV. Prints status words only, since this repo's logs are public

set -euo pipefail
dir=$1
mkdir -p "$dir/bin" && chmod 0700 "$dir"
key=$APP_PRIVATE_KEY client=$APP_CLIENT_ID repo=$GITHUB_REPOSITORY
unset APP_PRIVATE_KEY
[[ -n $key && -n $client ]] ||
  { echo "::error::set AGENT_APP_CLIENT_ID and AGENT_APP_PRIVATE_KEY (ddg-apple-agent-publish) in the agent-worker environment"; exit 1; }
api=https://api.github.com

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
jwt() {
  local now header payload sig
  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$client" | b64url)
  sig=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign <(printf '%s\n' "$key") | b64url)
  printf '%s.%s.%s' "$header" "$payload" "$sig"
}
call() { curl -fsS --retry 3 --retry-all-errors -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $1" "${@:2}"; }

# Only this repo, and only what the agent's PR work needs: push agent/* branches (the ruleset limits where), open and
# update PRs, read CI, rerun jobs. No workflows, administration or merge beyond what contents write implies
body='{"repositories":["'"${repo#*/}"'"],"permissions":{"contents":"write","pull_requests":"write","checks":"read","statuses":"read","actions":"write"}}'
mint() {
  local j id
  j=$(jwt)
  id=$(call "$j" "$api/repos/$repo/installation" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])')
  call "$j" -X POST -d "$body" "$api/app/installations/$id/access_tokens" |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["token"])' > "$dir/token.tmp"
  chmod 0600 "$dir/token.tmp" && mv "$dir/token.tmp" "$dir/token"
}
mint
echo "::add-mask::$(cat "$dir/token")"
(while sleep 2700; do mint || true; done) > /dev/null 2>&1 &
echo $! > "$dir/refresher.pid"
unset key

# gh reads GH_TOKEN once at start, so a wrapper hands each call the current token
real=$(command -v gh)
printf '#!/bin/bash\nGH_TOKEN=$(cat %q) exec %q "$@"\n' "$dir/token" "$real" > "$dir/bin/gh"
chmod 0755 "$dir/bin/gh"

# Pushes and commits show as the app's bot account
login="ddg-apple-agent-publish[bot]"
uid=$(GH_TOKEN=$(cat "$dir/token") "$real" api "users/${login/\[bot\]/%5Bbot%5D}" --jq .id)
helper="!f() { test \"\$1\" = get && echo username=x-access-token && echo password=\$(cat $dir/token); }; f"
{
  echo "GH_TOKEN_DIR=$dir"
  echo "GIT_CONFIG_COUNT=1"
  echo "GIT_CONFIG_KEY_0=credential.https://github.com.helper"
  echo "GIT_CONFIG_VALUE_0=$helper"
  echo "AGENT_GIT_NAME=$login"
  echo "AGENT_GIT_EMAIL=$uid+$login@users.noreply.github.com"
} >> "$GITHUB_ENV"
echo "github token ready"
