#!/bin/bash
# TEMP: diagnose system alerts that keep test apps from activating on CI runners.
# Usage: ci-ui-diag.sh <label>   (writes screenshots to ./ui-diag)

label="${1:-snapshot}"
out="ui-diag"
mkdir -p "$out"

echo "=== UI diag: $label ($(date -u '+%Y-%m-%d %H:%M:%S'))"
ps -axo pid,lstart,comm | grep -E "UserNotificationCenter|SecurityAgent|CoreServicesUIAgent|loginwindow" | grep -v grep
echo "--- frontmost"
osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>&1
echo "--- UserNotificationCenter texts"
osascript -e 'tell application "System Events" to tell process "UserNotificationCenter" to get value of static texts of every window' 2>&1
echo "--- UserNotificationCenter buttons"
osascript -e 'tell application "System Events" to tell process "UserNotificationCenter" to get name of buttons of every window' 2>&1
echo "--- UserNotificationCenter log"
log show --last 3h --style compact --predicate 'process == "UserNotificationCenter"' 2>&1 | tail -60
screencapture -x "$out/$label.png" 2>&1 && echo "screenshot: $out/$label.png"
exit 0
