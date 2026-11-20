#!/usr/bin/env bash
# The worker's reads and writes to artifacts.go, with the current az login. Storage is create-only, so
# every upload goes to a new prefix. Prints status words only, since this repo's logs are public
#
# Usage:
#   blobs.sh plan <file> <sha256>          Download PLAN_BLOB, checking its size and hash
#   blobs.sh auto <file> <sha256>          Download AUTO_BLOB (the auto plugin zip), checking its size and hash
#   blobs.sh put <dir> <prefix>            Upload dir under a prefix and print its SSO viewer URL
# Env: ARTIFACTS_ACCOUNT, ARTIFACTS_CONTAINER, PLAN_BLOB for plan, AUTO_BLOB for auto

set -euo pipefail
az_blob() { az storage blob "$@" --auth-mode login --only-show-errors --account-name "$ARTIFACTS_ACCOUNT"; }

case ${1:-} in
  plan)
    file=$2 sha=$3
    size=$(az_blob show --container-name "$ARTIFACTS_CONTAINER" --name "$PLAN_BLOB" --query properties.contentLength -o tsv)
    [[ "$size" =~ ^[0-9]+$ && "$size" -gt 0 && "$size" -le 200000 ]] ||
      { echo "::error::plan is missing, empty or too large"; exit 1; }
    az_blob download --container-name "$ARTIFACTS_CONTAINER" --name "$PLAN_BLOB" --file "$file" > /dev/null
    echo "$sha  $file" | shasum -a 256 -c --status || { echo "::error::plan hash does not match; refusing to run"; exit 1; }
    echo "plan downloaded and verified ($(wc -c < "$file") bytes)"
    ;;
  auto)
    file=$2 sha=$3
    size=$(az_blob show --container-name "$ARTIFACTS_CONTAINER" --name "$AUTO_BLOB" --query properties.contentLength -o tsv)
    [[ "$size" =~ ^[0-9]+$ && "$size" -gt 0 && "$size" -le 50000000 ]] ||
      { echo "::error::auto plugin is missing, empty or too large"; exit 1; }
    az_blob download --container-name "$ARTIFACTS_CONTAINER" --name "$AUTO_BLOB" --file "$file" > /dev/null
    echo "$sha  $file" | shasum -a 256 -c --status || { echo "::error::auto plugin hash does not match; refusing to run"; exit 1; }
    echo "auto plugin downloaded and verified ($(wc -c < "$file") bytes)"
    ;;
  put)
    dir=$2 prefix=$3
    az_blob upload-batch --destination "$ARTIFACTS_CONTAINER" --destination-path "$prefix" --source "$dir" > /dev/null
    echo "https://artifacts.go.duckduckgo.com/view/$ARTIFACTS_CONTAINER/$prefix"
    ;;
  *)
    sed -n '2,9p' "$0" >&2
    exit 2
    ;;
esac
