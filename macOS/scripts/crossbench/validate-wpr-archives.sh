#!/usr/bin/env bash
#
# Download WPR archives and validate their stored top-level navigations without
# starting a replay server. Site errors exclude that site; package errors stop
# all browser jobs.
#
# Usage:
#   ./validate-wpr-archives.sh [--sites a.com,b.com]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=macOS/scripts/crossbench/wpr-config.sh
. "$SCRIPT_DIR/wpr-config.sh"

SITES_OVERRIDE=""
WPR_DIR="${WPR_DIR:-$PWD/wpr-archives}"
WPR_VALIDATOR_BIN="${WPR_VALIDATOR_BIN:-$HOME/Developer/mac-perf-runner/bin/validate-wpr}"
MANIFEST_FILE="${MANIFEST_FILE:-$PWD/wpr-validation/manifest.tsv}"
REPORT_FILE="${REPORT_FILE:-$PWD/wpr-validation/report.txt}"
# When separate from WPR_DIR, receives only archives with an `ok` verdict.
WPR_REPLAY_DIR="${WPR_REPLAY_DIR:-$PWD/validated-wpr-archives}"
SITES_FILE="$SCRIPT_DIR/wpr-sites.txt"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sites) SITES_OVERRIDE="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ ! -x "$WPR_VALIDATOR_BIN" ]; then
  echo "ERROR: WPR validator not found at $WPR_VALIDATOR_BIN." >&2
  exit 2
fi

if [ -n "$SITES_OVERRIDE" ]; then
  IFS=',' read -r -a sites <<< "$SITES_OVERRIDE"
else
  sites=()
  while IFS= read -r site; do
    [ -z "$site" ] && continue
    [[ "$site" == \#* ]] && continue
    sites+=("$site")
  done < "$SITES_FILE"
fi
if [ "${#sites[@]}" -eq 0 ]; then
  echo "ERROR: no sites selected." >&2
  exit 2
fi
normalized_sites=()
for site in "${sites[@]}"; do
  site="$(normalize_wpr_site "$site")"
  if ! [[ "$site" =~ ^[a-z0-9.-]+$ ]]; then
    echo "ERROR: invalid site hostname: $site" >&2
    exit 2
  fi
  if [ "${#normalized_sites[@]}" -gt 0 ]; then
    for previous in "${normalized_sites[@]}"; do
      if [ "$site" = "$previous" ]; then
        echo "ERROR: duplicate site hostname: $site" >&2
        exit 2
      fi
    done
  fi
  normalized_sites+=("$site")
done
sites=("${normalized_sites[@]}")

mkdir -p "$WPR_DIR" "$(dirname "$MANIFEST_FILE")" "$(dirname "$REPORT_FILE")"
if [ "$WPR_REPLAY_DIR" = "$WPR_DIR" ]; then
  echo "ERROR: WPR_REPLAY_DIR must be separate from WPR_DIR." >&2
  exit 2
fi
if [ -d "$WPR_REPLAY_DIR" ] && [ -n "$(find "$WPR_REPLAY_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo "ERROR: WPR_REPLAY_DIR must be empty: $WPR_REPLAY_DIR" >&2
  exit 2
fi
mkdir -p "$WPR_REPLAY_DIR"

normalize() { printf '%s' "$1" | tr '+/' '__'; }

fetch_archive() {
  local site="$1" normalized archive temp
  normalized="$(normalize "navToLCP+$site")"
  archive="$WPR_DIR/$normalized.wprgo"
  temp="$archive.tmp"
  rm -f "$archive" "$temp"
  if curl -fLSs --retry 2 --retry-all-errors \
      --connect-timeout 20 --max-time 300 \
      --output "$temp" "$WPR_BASE_URL/$normalized.wprgo"; then
    mv "$temp" "$archive"
  else
    rm -f "$temp"
    echo "WARNING: archive download failed: $site" >&2
  fi
}

# Fetch in small batches; the validator reports any missing archives.
pids=()
for site in "${sites[@]}"; do
  fetch_archive "$site" &
  pids+=("$!")
  if [ "${#pids[@]}" -eq 6 ]; then
    for pid in "${pids[@]}"; do
      wait "$pid" || true
    done
    pids=()
  fi
done
for pid in "${pids[@]}"; do
  wait "$pid" || true
done

args=(
  --archive-dir "$WPR_DIR"
  --manifest "$MANIFEST_FILE"
  --report "$REPORT_FILE"
  --sites "$(IFS=,; printf '%s' "${sites[*]}")"
)

"$WPR_VALIDATOR_BIN" "${args[@]}"

while IFS= read -r archive; do
  cp "$WPR_DIR/$archive" "$WPR_REPLAY_DIR/$archive"
done < <(awk -F'\t' 'NR > 1 && $5 == "ok" { print $2 }' "$MANIFEST_FILE")
cp "$MANIFEST_FILE" "$WPR_REPLAY_DIR/manifest.tsv"
