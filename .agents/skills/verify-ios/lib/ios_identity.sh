#!/bin/bash
# Doctor check: is the DuckDuckGo process running on <udid> the binary in this worktree's build product?
# Compares the full sha256 of the running executable (found by its path inside this simulator's bundle container) with
# the build's. Fails closed: a hash that cannot be computed is never a match.
# usage: ios_identity.sh <udid> <expected .app path>
UDID=$1; APP=$2
PROC=$(ps -axo pid=,command= | grep "/CoreSimulator/Devices/$UDID/data/Containers/Bundle/Application/.*/DuckDuckGo.app/DuckDuckGo" | grep -v grep | head -1)
# The command line may carry launch arguments (e.g. -ff.<flag> true): keep only the path up to the executable.
PID=$(echo "$PROC" | awk '{print $1}'); RUNBIN=$(echo "$PROC" | sed -E 's#^ *[0-9]+ (.*/DuckDuckGo\.app/DuckDuckGo)( .*)?$#\1#')
[ -z "$PID" ] && { echo '{"ok":false,"reason":"app not running on this udid"}'; exit 1; }
EXP=$(shasum -a 256 "$APP/DuckDuckGo" 2>/dev/null | awk '{print $1}'); RUN=$(shasum -a 256 "$RUNBIN" 2>/dev/null | awk '{print $1}')
EXPV=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Info.plist" 2>/dev/null)
RUNV=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$(dirname "$RUNBIN")/Info.plist" 2>/dev/null)
OK=false; REASON=""
if [ ${#EXP} -ne 64 ]; then REASON="cannot hash the build product $APP/DuckDuckGo"
elif [ ${#RUN} -ne 64 ]; then REASON="cannot hash the running binary"
elif [ "$EXP" != "$RUN" ]; then REASON="running binary is not this worktree's build"
else OK=true; fi
printf '{"ok":%s,"reason":"%s","pid":%s,"runningBinary":"%s","runningSha":"%s","expectedApp":"%s","expectedSha":"%s","runningBundleVersion":"%s","expectedBundleVersion":"%s"}\n' \
  $OK "$REASON" "$PID" "$RUNBIN" "$RUN" "$APP" "$EXP" "$RUNV" "$EXPV"
$OK
