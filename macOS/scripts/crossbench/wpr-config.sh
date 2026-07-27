#!/usr/bin/env bash
#
# Shared immutable inputs for provisioning and validating Web Page Replay.
# Bump WEBPAGEREPLAY_REV together with CROSSBENCH_REV in provision-macos.sh,
# using the webpagereplay_revision from that crossbench revision's DEPS file.

WEBPAGEREPLAY_GIT="${WEBPAGEREPLAY_GIT:-https://chromium.googlesource.com/webpagereplay}"
WEBPAGEREPLAY_REV="${WEBPAGEREPLAY_REV:-b2b856131e36c99e9de9c419fe8ca02f857082ba}"
WPR_BASE_URL="${WPR_BASE_URL:-https://staticcdn.duckduckgo.com/d5c04536-5379-4709-8d19-d13fdd456ff6/performance-tests}"

# Browser-neutral copy of the Windows Crossbench US-broadband profile.
WPR_US_BROADBAND_RTT_MS="${WPR_US_BROADBAND_RTT_MS:-28}"
WPR_US_BROADBAND_IN_KBPS="${WPR_US_BROADBAND_IN_KBPS:-50000}"
WPR_US_BROADBAND_OUT_KBPS="${WPR_US_BROADBAND_OUT_KBPS:-10000}"
WPR_US_BROADBAND_WINDOW="${WPR_US_BROADBAND_WINDOW:-10}"

normalize_wpr_site() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}
