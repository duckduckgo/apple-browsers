#!/usr/bin/env bash
# Uploads auto's evidence roots (~/.auto/evidence/<uuid>/: the decision log, plan snapshots and proofs) to <uuid>/ in
# the artifacts container, where auto's own viewer links (artifacts.go/view/auto/<uuid>/...) point. The decision log
# goes up under auto's content-hashed name, as auto's own upload would. Symlinks are dropped, since the agent made
# these files and a link could point anywhere on the runner
#
# Usage: auto_evidence.sh <evidence root> <staging dir>
# Prints the viewer URL of the most recently written decision log, if any. Everything else goes to stderr as
# status words only, since this repo's logs are public
# Env: ARTIFACTS_ACCOUNT and ARTIFACTS_CONTAINER, for blobs.sh

set -uo pipefail
root=$1 stage=$2
here=$(cd "$(dirname "$0")" && pwd)
# auto names an uploaded decision log after its SHA-256 (decisionLogName in show-me-your-work's evidence.ts)
sha256() { { shasum -a 256 "$1" 2> /dev/null || sha256sum "$1"; } | cut -d' ' -f1; }
uuid_re='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

[[ -d $root ]] || { echo "no auto evidence" >&2; exit 0; }
mkdir -p "$stage"
latest="" latest_mtime=0 uploaded=0
for dir in "$root"/*/; do
  uuid=$(basename "$dir")
  [[ $uuid =~ $uuid_re && ! -L ${dir%/} ]] || continue
  cp -RP "$dir" "$stage/$uuid" || continue
  find "$stage/$uuid" -type l -delete
  log="$dir/decisions.tsv"
  if [[ -f $log && ! -L $log ]]; then
    name="decisions-$(sha256 "$log").tsv"
    url="https://artifacts.go.duckduckgo.com/view/$ARTIFACTS_CONTAINER/$uuid/$name"
    if [[ $name =~ ^decisions-[0-9a-f]{64}\.tsv$ ]]; then
      mv "$stage/$uuid/decisions.tsv" "$stage/$uuid/$name"
      mtime=$(stat -c %Y "$log" 2> /dev/null || stat -f %m "$log")
      if (( mtime >= latest_mtime )); then latest=$url latest_mtime=$mtime; fi
    fi
  fi
  "$here/blobs.sh" put "$stage/$uuid" "$uuid" > /dev/null && uploaded=$((uploaded + 1)) || echo "auto evidence upload failed" >&2
done
echo "auto evidence roots uploaded: $uploaded" >&2
[[ -n $latest ]] && echo "$latest"
exit 0
