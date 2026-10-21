#!/usr/bin/env bash
#
# Launch a signed Review/debug app through LaunchServices and print the PID of
# the new app instance. The automation token is accepted only through the
# environment and is never printed.
#
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 APP EXECUTABLE LOG -- [APP_ARGUMENTS...]" >&2
  exit 2
fi

app="$1"
executable="$2"
log_file="$3"
shift 3
[ "$1" = -- ] || {
  echo "ERROR: missing app-argument separator." >&2
  exit 2
}
shift

[ -n "${AUTOMATION_TOKEN:-}" ] || {
  echo "ERROR: AUTOMATION_TOKEN is required." >&2
  exit 2
}
case "$app" in
  /Applications/*.app) ;;
  *)
    echo "ERROR: DuckDuckGo must be installed directly under /Applications." >&2
    exit 2
    ;;
esac
case "$executable" in
  "$app"/Contents/MacOS/*) ;;
  *)
    echo "ERROR: executable is outside the selected app bundle." >&2
    exit 2
    ;;
esac
[ -x "$executable" ] || {
  echo "ERROR: DuckDuckGo executable is unavailable." >&2
  exit 2
}

matching_pids() {
  local pid command
  while read -r pid command; do
    case "$command" in
      "$executable"|"$executable "*)
        printf '%s\n' "$pid"
        ;;
    esac
  done < <(ps -axo pid=,command=)
}

if [ -n "$(matching_pids)" ]; then
  echo "ERROR: selected DuckDuckGo app is already running." >&2
  exit 1
fi

# The app treats a non-empty CI variable as "running under UI tests" and then
# skips the window it normally opens at startup, which leaves the automation
# server with no tab to drive. Hosted runners export CI for every step, so drop
# it from the app's environment only; the caller's own CI is untouched.
/usr/bin/env -u CI /usr/bin/open -n \
  --stdout "$log_file" \
  --stderr "$log_file" \
  --env "AUTOMATION_TOKEN=$AUTOMATION_TOKEN" \
  "$app" --args "$@"

for _ in {1..40}; do
  pids=()
  while IFS= read -r pid; do
    [ -z "$pid" ] || pids+=("$pid")
  done < <(matching_pids)
  if [ "${#pids[@]}" -eq 1 ]; then
    printf '%s\n' "${pids[0]}"
    exit 0
  fi
  if [ "${#pids[@]}" -gt 1 ]; then
    echo "ERROR: multiple matching DuckDuckGo processes started." >&2
    exit 1
  fi
  sleep 0.25
done

echo "ERROR: LaunchServices did not expose the DuckDuckGo process." >&2
exit 1
