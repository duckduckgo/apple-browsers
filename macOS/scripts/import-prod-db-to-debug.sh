#!/usr/bin/env bash
#
# ddg-import-prod-db-to-debug.sh
#
# Copy the DuckDuckGo macOS *production* Core Data store (Database.sqlite — holds
# History + Favicons, including the encrypted favicon image BLOBs) into the *debug*
# build's sandbox container, replacing whatever is there.
#
# What it does:
#   1. Takes a CONSISTENT online snapshot of the live production DB (sqlite .backup,
#      so it's safe to run while the production app is open; committed WAL included).
#   2. Verifies the snapshot (integrity_check + favicon row count).
#   3. Backs up the existing debug DB to a timestamped folder.
#   4. Installs the snapshot and removes stale -wal/-shm sidecars.
#
# Encryption note: prod and debug builds share the same data-encryption key — it's a
# login-keychain item (service "DuckDuckGo Privacy Browser Encryption Key v2",
# account "com.duckduckgo.macos.browser") that is NOT isolated by keychain access
# group — so the debug build can decrypt the imported favicons. On first launch the
# debug app may show a one-time keychain "Allow" prompt; click Allow (Always Allow).
#
# Usage:
#   ddg-import-prod-db-to-debug.sh [--prod-bundle ID] [--debug-bundle ID] [--db NAME] [-y]
#
# Defaults:
#   --prod-bundle   com.duckduckgo.macos.browser
#   --debug-bundle  com.duckduckgo.macos.browser.debug
#   --db            Database.sqlite
#   -y, --yes       skip the confirmation prompt
#
set -euo pipefail

PROD_BUNDLE="com.duckduckgo.macos.browser"
DEBUG_BUNDLE="com.duckduckgo.macos.browser.debug"
DB_NAME="Database.sqlite"
ASSUME_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prod-bundle)  PROD_BUNDLE="$2";  shift 2 ;;
    --debug-bundle) DEBUG_BUNDLE="$2"; shift 2 ;;
    --db)           DB_NAME="$2";      shift 2 ;;
    -y|--yes)       ASSUME_YES=1;      shift ;;
    -h|--help)      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

appsup() { echo "$HOME/Library/Containers/$1/Data/Library/Application Support"; }
PROD_DIR="$(appsup "$PROD_BUNDLE")"
DEBUG_DIR="$(appsup "$DEBUG_BUNDLE")"
PROD_DB="$PROD_DIR/$DB_NAME"
DEBUG_DB="$DEBUG_DIR/$DB_NAME"

# Row counts for every Core Data ENTITY table (named Z<Entity>), excluding Core
# Data's bookkeeping/join tables (Z_PRIMARYKEY, Z_METADATA, Z_MODELCACHE, Z_Nx...).
# The underscore in 'Z_%' is escaped so it matches a literal '_' rather than any
# single character (which would also exclude real entity tables like ZHISTORY).
# Output: one "TABLE<TAB>COUNT" line per table, sorted by name.
z_entity_counts() {
  local db="$1" t c
  sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' AND name NOT LIKE 'Z\\_%' ESCAPE '\\' ORDER BY name;" |
  while IFS= read -r t; do
    c="$(sqlite3 "$db" "SELECT count(*) FROM \"$t\";")"
    printf '%s\t%s\n' "$t" "$c"
  done
}

echo "Source (prod):  $PROD_DB"
echo "Target (debug): $DEBUG_DB"

command -v sqlite3 >/dev/null 2>&1 || { echo "ERROR: sqlite3 not found" >&2; exit 1; }
[ -f "$PROD_DB" ]  || { echo "ERROR: production DB not found: $PROD_DB" >&2; exit 1; }
[ -d "$DEBUG_DIR" ] || { echo "ERROR: debug container not found: $DEBUG_DIR" >&2
                         echo "       Run the debug build once so the sandbox container is created." >&2; exit 1; }

# Replacing a DB under a running app corrupts its open Core Data stack. Refuse if the
# debug app is running (its binary always lives under .../Build/Products/Debug/DuckDuckGo.app).
if pgrep -lf "Build/Products/Debug/DuckDuckGo.app/Contents/MacOS/DuckDuckGo" >/dev/null 2>&1; then
  echo "ERROR: the debug DuckDuckGo app appears to be running — quit it first." >&2
  exit 1
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  printf "Replace the debug DB with a snapshot of prod? (a timestamped backup is kept) [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 0 ;; esac
fi

TS="$(date +%Y%m%d-%H%M%S)"
SNAP="$(mktemp -t ddg-db-snapshot.XXXXXX)"
trap 'rm -f "$SNAP"' EXIT

echo "==> Snapshotting live production DB (online backup; safe while prod is open)..."
# mode=ro (NOT immutable) so the backup includes committed WAL data.
sqlite3 "file:${PROD_DB}?mode=ro" ".backup '$SNAP'"

echo "==> Verifying snapshot..."
ic="$(sqlite3 "$SNAP" 'PRAGMA integrity_check;' | head -1)"
[ "$ic" = "ok" ] || { echo "ERROR: snapshot integrity_check failed: $ic" >&2; exit 1; }
SNAP_COUNTS="$(z_entity_counts "$SNAP")"
echo "    integrity: ok | size: $(du -h "$SNAP" | cut -f1) | entity tables: $(printf '%s\n' "$SNAP_COUNTS" | grep -c .)"
printf '%s\n' "$SNAP_COUNTS" | column -t | sed 's/^/      /'

echo "==> Backing up existing debug DB..."
BAK="$DEBUG_DIR/_db-backup-$TS"
made_bak=0
for f in "$DB_NAME" "$DB_NAME-shm" "$DB_NAME-wal"; do
  if [ -e "$DEBUG_DIR/$f" ]; then
    [ "$made_bak" -eq 0 ] && mkdir -p "$BAK" && made_bak=1
    mv "$DEBUG_DIR/$f" "$BAK/"
  fi
done
[ "$made_bak" -eq 1 ] && echo "    backup: $BAK" || echo "    (nothing to back up)"

echo "==> Installing snapshot (single consistent file; no -wal/-shm)..."
cp "$SNAP" "$DEBUG_DB"
chmod 644 "$DEBUG_DB"

echo "==> Verifying installed debug DB..."
ic2="$(sqlite3 "$DEBUG_DB" 'PRAGMA integrity_check;' | head -1)"
[ "$ic2" = "ok" ] || { echo "ERROR: installed DB integrity_check failed: $ic2" >&2; exit 1; }
DEBUG_COUNTS="$(z_entity_counts "$DEBUG_DB")"
if [ "$DEBUG_COUNTS" = "$SNAP_COUNTS" ]; then
  echo "    integrity: ok | all $(printf '%s\n' "$SNAP_COUNTS" | grep -c .) entity tables match the snapshot row-for-row:"
  printf '%s\n' "$DEBUG_COUNTS" | column -t | sed 's/^/      /'
else
  echo "ERROR: installed DB entity-table counts differ from the snapshot:" >&2
  diff <(printf '%s\n' "$SNAP_COUNTS") <(printf '%s\n' "$DEBUG_COUNTS") >&2 || true
  exit 1
fi

echo
echo "Done — imported prod DB into the debug container."
echo "  • Launch the debug build; click Allow on the one-time keychain prompt if it appears."
[ "$made_bak" -eq 1 ] && echo "  • Roll back: quit debug app, then restore files from $BAK"
