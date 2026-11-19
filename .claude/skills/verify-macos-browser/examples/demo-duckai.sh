#!/bin/bash
# Demo: open a new Duck.ai chat from the tab bar and type a prompt into it (not sent).
#
# Usage: demo-duckai.sh [checkout] [--vm vm-1|vm-2|auto] [--topic <name>] [--pause]
# Live service: duck.ai (the page loads from the network). Evidence: ~/.ddg-verify-macos/<topic>/
set -uo pipefail
TOPIC=demo-duckai
source "$(dirname "$0")/demo-lib.sh"
demo_args "$@"
PROMPT="how's everybody?"

demo_start --automation

say "Open Duck.ai like a user" "Tab bar \"Ask Duck.ai\" pill, then New Chat in its menu."
run shot "$TOPIC" 01-start
run ax "$TOPIC" clickel TabBarViewController.duckAIChromeTitleButton
sleep 1
run ax "$TOPIC" clickel duckAIMenuNewChatAction
sleep 6
url=$("$V" web "$TOPIC" url); echo "   url: $url"
[[ $url == *duck.ai* ]]; check "Duck.ai opened ($url)" $?

say "Type the prompt" "Click the chat input, then real key events type the text. It isn't sent."
run ax "$TOPIC" clickel "Ask anything privately"
sleep 1
run ax "$TOPIC" type "$PROMPT"
sleep 1

say "Check it, twice" "First read: the input's value in the accessibility tree. Second, independent read: the page's textarea."
"$V" ax "$TOPIC" find "Ask anything privately" | grep -qF "value=\"$PROMPT\""; check "input shows \"$PROMPT\" (accessibility tree)" $?
page=$("$V" web "$TOPIC" eval 'return document.querySelector("textarea") ? document.querySelector("textarea").value : null')
echo "   page textarea: $page"
[[ $page == "\"$PROMPT\"" ]]; check "page textarea holds \"$PROMPT\"" $?
run shot "$TOPIC" 02-typed

demo_end
