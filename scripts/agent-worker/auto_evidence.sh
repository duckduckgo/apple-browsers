#!/usr/bin/env bash
# Uploads whatever the agent left un-uploaded in auto's evidence roots (~/.auto/evidence/<uuid>/: the decision log,
# plan snapshots and proofs), with auto's own upload-evidence. The agent uploads as it publishes PRs; this catches the
# final decision log and anything from a run that stopped early. Uploads are create-only, so files the agent already
# uploaded are skipped, and auto skips symlinks
#
# Usage: auto_evidence.sh <evidence root>
# Prints the viewer URL of the most recently written decision log, if any. Everything else goes to stderr as
# status words only, since this repo's logs are public
# Env: AUTO_DIR, ARTIFACTS_CONTAINER, and the AZURE_* settings from azure_identity.sh

set -uo pipefail
root=$1
upload=$AUTO_DIR/skills/show-me-your-work/scripts/upload-evidence.ts
uuid_re='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

[[ -d $root ]] || { echo "no auto evidence" >&2; exit 0; }
latest="" latest_mtime=0 uploaded=0 failed=0
for dir in "$root"/*/; do
  uuid=$(basename "$dir")
  [[ $uuid =~ $uuid_re && ! -L ${dir%/} ]] || continue
  out=$(node "$upload" --directory "${dir%/}" 2> /dev/null) && uploaded=$((uploaded + 1)) || failed=$((failed + 1))
  # auto names the uploaded decision log after its SHA-256 and reports that name
  name=$(python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read() or "{}").get("decisionLog", ""))' <<< "$out" 2> /dev/null)
  log="$dir/decisions.tsv"
  if [[ $name =~ ^decisions-[0-9a-f]{64}\.tsv$ && -f $log ]]; then
    mtime=$(stat -c %Y "$log" 2> /dev/null || stat -f %m "$log")
    if (( mtime >= latest_mtime )); then
      latest="https://artifacts.go.duckduckgo.com/view/$ARTIFACTS_CONTAINER/$uuid/$name" latest_mtime=$mtime
    fi
  fi
done
echo "auto evidence roots uploaded: $uploaded, failed: $failed" >&2
[[ -n $latest ]] && echo "$latest"
exit 0
