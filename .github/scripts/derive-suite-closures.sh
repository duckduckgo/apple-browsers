#!/bin/bash
#
# derive-suite-closures.sh  (REPLAY / ANALYSIS ONLY — not used by the CI gate)
#
# Derives, offline (no swift, no network), which SharedPackages a change must
# touch to warrant running the BSK unit-test suite vs the DBP unit-test suite.
#
# Method: read the local package graph from each SharedPackages Package.swift's
# `.package(path:)` edges, then take the forward dependency closure of the BSK
# and DBP package roots. A suite must run when its package OR anything that
# package (transitively) depends on changes, so the trigger set = that root's
# dependency closure. DBP depends on BSK, so DBP_CLOSURE ⊇ BSK_CLOSURE.
#
# Output (stdout), consumed by replay_change_detection.yml:
#   BSK_CLOSURE=<space-separated package ids>
#   DBP_CLOSURE=<space-separated package ids>
#
# Package id = directory under SharedPackages/, e.g. "BrowserServicesKit" or
# "Infrastructure/SystemFrameworksExtensions".

set -euo pipefail

SP="${1:-SharedPackages}"
edges=$(mktemp)
trap 'rm -f "$edges"' EXIT

# Canonicalise a SharedPackages-relative path to a package id: keep the first
# path component, except under Infrastructure/ keep the first two.
canon() {
  case "$1" in
    Infrastructure/*) printf '%s/%s\n' Infrastructure "$(printf '%s' "${1#Infrastructure/}" | cut -d/ -f1)" ;;
    *) printf '%s\n' "$(printf '%s' "$1" | cut -d/ -f1)" ;;
  esac
}

# Build package -> package edges from real package manifests (depth 2, or depth
# 3 directly under Infrastructure/). Skip any nested/fixture manifests.
while IFS= read -r m; do
  id=${m#"$SP"/}; id=${id%/Package.swift}
  case "$id" in
    Infrastructure/*/*) continue ;;   # deeper than Infrastructure/<sub>
    */*/*)              continue ;;   # deeper than a top-level package
    Infrastructure/*)   : ;;          # Infrastructure/<sub> — ok
    */*)                continue ;;   # 2-component non-Infrastructure — skip
    *)                  : ;;          # top-level package — ok
  esac
  d=$(dirname "$m")
  { grep -oE '\.package\(path: *"[^"]*"' "$m" 2>/dev/null || true; } \
    | sed -E 's/.*path: *"//; s/"$//' \
    | while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        # Resolve rel against the manifest dir, lexically, relative to SP —
        # no filesystem access needed and portable across macOS/Linux.
        tgt=$(python3 -c 'import os,sys; print(os.path.relpath(os.path.normpath(os.path.join(sys.argv[1],sys.argv[2])), sys.argv[3]))' "$d" "$rel" "$SP")
        case "$tgt" in ..*) continue ;; esac   # resolves outside SharedPackages
        printf '%s\t%s\n' "$id" "$(canon "$tgt")" >> "$edges"
      done
done < <(find "$SP" -name Package.swift)

# Forward-reachability closure from a root package (root included).
closure() {
  awk -v root="$1" -F'\t' '
    { dep[$1] = dep[$1] " " $2 }
    END {
      seen[root] = 1; q[n++] = root
      for (i = 0; i < n; i++) {
        c = q[i]; m = split(dep[c], a, " ")
        for (j = 1; j <= m; j++) {
          t = a[j]
          if (t != "" && !(t in seen)) { seen[t] = 1; q[n++] = t }
        }
      }
      for (k in seen) print k
    }' "$edges" | sort | paste -sd' ' -
}

# Single-quoted so the space-separated lists are safe to `eval`.
printf "BSK_CLOSURE='%s'\n" "$(closure BrowserServicesKit)"
printf "DBP_CLOSURE='%s'\n" "$(closure DataBrokerProtectionCore)"
