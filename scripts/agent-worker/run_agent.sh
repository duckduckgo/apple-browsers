#!/usr/bin/env bash
# Runs the coding agent: builds its allow and deny lists, runs Claude through the auto plugin with the prompt, then
# writes transcript.md and summary.md to evidence. Claude's own output goes to evidence, never the log, since this
# repo's logs are public
#
# Usage: run_agent.sh   (from the checkout)
# Env: RUNNER_TEMP, GITHUB_WORKSPACE, GITHUB_ENV, AUTO_DIR, GH_TOKEN_DIR, IDENTITY_DIR, AGENT_GIT_NAME, AGENT_GIT_EMAIL,
# MAX_TURNS, MAX_BUDGET_USD, and DEST for xc
# Writes BASE_SHA, RUN_STARTED and rc to GITHUB_ENV, and the lists to evidence for the tool report

set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ev=$RUNNER_TEMP/evidence A=$AUTO_DIR W=$RUNNER_TEMP/worktrees
mkdir -p "$ev" "$RUNNER_TEMP/bin"
ln -sf "$here/xc.sh" "$RUNNER_TEMP/bin/xc"

# File tools in the checkout, xc and read-only git, so it can check its change and fix it as it goes
allow="Read,Glob,Grep,Edit(./**),Write(./**),Bash(xc:*)"
for c in log show blame diff status grep ls-files; do allow+=",Bash(git $c:*)"; done
deny="WebFetch,WebSearch,Read(/$IDENTITY_DIR/**),Read(~/.azure/**),Read(//proc/**),Read(/$GH_TOKEN_DIR/**)"

# For auto: subagents, worktrees, git branches, commits and pushes, gh for its own PRs and their CI, auto's PR,
# babysit and evidence scripts, and verify-ios
allow+=",Agent,TodoWrite,Edit(/$W/**),Write(/$W/**),Write(~/.auto/**)"
allow+=",Bash(git worktree add $W/:*),Bash(git worktree list:*),Bash(git worktree remove:*)"
for c in add commit cherry-pick rev-parse merge-base switch checkout branch rebase merge reset restore \
  stash rm mv fetch pull push rev-list for-each-ref show-ref ls-remote; do
  allow+=",Bash(git $c:*)"
done
for c in "pr view" "pr list" "pr diff" "pr checks" "pr create" "pr edit" "pr ready" "run view" "run list" \
  "run rerun" api; do
  allow+=",Bash(gh $c:*)"
done
for s in auto/scripts/resolve-models auto/scripts/check-pr-body auto/scripts/publish-pr auto/scripts/watch-pr \
  show-me-your-work/scripts/log show-me-your-work/scripts/snapshot show-me-your-work/scripts/new-evidence \
  show-me-your-work/scripts/evidence-url show-me-your-work/scripts/resolve-decision-log; do
  allow+=",Bash(node $A/skills/$s.ts:*)"
done
allow+=",Bash(.claude/skills/verify-ios/bin/verify-ios:*)"

# The checkout's .claude and .git hold scripts the agent runs, so it can't change them. No merging, approving,
# closing, workflows, secrets or other admin, and no auto script that needs Azure, Codex or dub, or changes setup
deny+=",Edit(./.claude/**),Write(./.claude/**),Edit(./.git/**),Write(./.git/**)"
deny+=",Bash(claude:*),Bash(codex:*),Bash(git config:*),Bash(git remote:*)"
for c in "pr merge" "pr close" "pr review" "pr comment" auth secret variable workflow release repo gist issue \
  ssh-key gpg-key extension codespace cache ruleset org; do
  deny+=",Bash(gh $c:*)"
done
for s in auto/scripts/merge-strategy auto/scripts/pstack-runner show-me-your-work/scripts/upload-evidence \
  reflect/scripts/issue setup-auto/scripts/setup-config setup-auto/scripts/setup-deps setup-auto/scripts/setup-evidence \
  setup-auto/scripts/setup-labels setup-auto/scripts/setup-run setup-auto/scripts/verify-models \
  statechart/scripts/statechart statechart/scripts/supervisor statechart/scripts/worker; do
  deny+=",Bash(node $A/skills/$s.ts:*)"
done

echo "BASE_SHA=$(git rev-parse HEAD)" >> "$GITHUB_ENV"
echo "RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$GITHUB_ENV"
# For the tool report, which explains denials against these lists
printf '%s' "$allow" > "$ev/allowed-tools.txt"
printf '%s' "$deny" > "$ev/denied-tools.txt"

name=${AGENT_GIT_NAME:-Apple Agent} email=${AGENT_GIT_EMAIL:-agent@localhost}
rc=0
env -u ACTIONS_ID_TOKEN_REQUEST_URL -u ACTIONS_ID_TOKEN_REQUEST_TOKEN -u SSH_AUTH_SOCK \
  PATH="$GH_TOKEN_DIR/bin:$RUNNER_TEMP/bin:$PATH" PACKAGES="$RUNNER_TEMP/packages" VERIFY_IOS_PACKAGES="$RUNNER_TEMP/packages" \
  XC_DERIVED="$RUNNER_TEMP/derived" XC_LOGS="$RUNNER_TEMP/xc-logs" \
  BASH_DEFAULT_TIMEOUT_MS=2700000 BASH_MAX_TIMEOUT_MS=2700000 \
  GIT_AUTHOR_NAME="$name" GIT_AUTHOR_EMAIL="$email" GIT_COMMITTER_NAME="$name" GIT_COMMITTER_EMAIL="$email" \
  GIT_TERMINAL_PROMPT=0 \
  claude -p "$(cat "$RUNNER_TEMP/prompt.md")" --plugin-dir "$A" \
    --permission-mode dontAsk \
    --allowedTools "$allow" \
    --disallowedTools "$deny" \
    --model opus --max-turns "${MAX_TURNS:-250}" --max-budget-usd "${MAX_BUDGET_USD:-50}" --output-format json \
    > "$ev/result.json" 2> "$ev/claude.err" || rc=$?

# The full session as Markdown, so reviewers can see how the agent worked and tune auto or the prompt
python3 -I "$here/transcript_md.py" "$ev/result.json" "$HOME/.claude/projects" "$ev" || true
python3 -I "$here/summary_md.py" "$ev/result.json" "$ev" "$rc" || true
echo "rc=$rc" >> "$GITHUB_ENV"
