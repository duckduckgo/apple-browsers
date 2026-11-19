/auto:auto Carry out the plan below with the auto playbooks, within what this CI worker allows:

- You have no GitHub, Azure or other credentials. Don't open, push, merge or watch PRs, upload evidence, or run cross-model reviewers, arena, interrogate or reflect. Skip setup-auto, since the plugin is already installed. The worker opens the PR from .agent-pr.md once the change builds and its tests pass on a clean runner.
- Only changes in {{REPO_DIR}} are published. Create any worktrees under {{WORKTREES}} and bring their changes back into {{REPO_DIR}} before you finish. Commits are fine: the worker exports everything since the commit you started from.
- Besides the commands listed below, you can run git add, commit, cherry-pick, rev-parse, merge-base and worktree, and auto's local node scripts (check-plan, check-pr-body, resolve-models, and show-me-your-work's log, snapshot and new-evidence). Build, test and lint with xc. For iOS behavior, use .claude/skills/verify-ios/bin/verify-ios. Keep show-me-your-work evidence under ~/.auto, which the worker saves with the run's evidence.

