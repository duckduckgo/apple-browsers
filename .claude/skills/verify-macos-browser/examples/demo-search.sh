#!/bin/bash
# Demo: open three tabs with Cmd+T, then search DuckDuckGo from the address bar.
#
# Usage: demo-search.sh [checkout] [--vm vm-1|vm-2|auto] [--topic <name>] [--pause]
# Live service: duckduckgo.com. Evidence: ~/.ddg-verify-macos/<topic>/
set -uo pipefail
TOPIC=demo-search
source "$(dirname "$0")/demo-lib.sh"
demo_args "$@"
QUERY="is my job screwed?"

demo_start --automation

say "Open three tabs" "Cmd+T three times: real key events in the VM."
before=$(tabs); echo "   tabs: $before"
for _ in 1 2 3; do run ax "$TOPIC" key 17 cmd >/dev/null; sleep 1; done
after=$(tabs); echo "   tabs: $before -> $after"
[[ $after == $((before + 3)) ]]; check "three more tabs ($before -> $after)" $?
run shot "$TOPIC" 01-tabs

say "Search like a user" "Click the address bar, type the query, press Return."
run ax "$TOPIC" clickel AddressBarViewController.addressBarTextField
run ax "$TOPIC" type "$QUERY"
run ax "$TOPIC" key 36
sleep 5

say "Check it, twice" "First read: the page URL. Second, independent read: the results page's title."
url=$("$V" web "$TOPIC" url); echo "   url: $url"
[[ $url == *duckduckgo.com/*q=is+my+job+screwed* ]]; check "DuckDuckGo results for the query" $?
title=$("$V" web "$TOPIC" eval 'return document.title'); echo "   title: $title"
[[ $title == *"$QUERY at DuckDuckGo"* ]]; check "results page titled \"$QUERY at DuckDuckGo\"" $?
[[ $(tabs) == "$after" ]]; check "the search stayed in the current tab" $?
run shot "$TOPIC" 02-results

demo_end
