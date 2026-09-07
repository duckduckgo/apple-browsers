# Prompt: rebase PR 5 and PR 6 onto the PR 4 stack, push, open draft PRs

Repo: apple-browsers (`git@github.com:duckduckgo/apple-browsers.git`). Work from the main checkout at `/Users/bkunat/Desktop/ddg-workspace/apple-browsers4`, but **do not touch its checked-out branch** (`bartosz/on-site-permissions`, the docs branch — it has uncommitted doc edits). Do all branch work in a fresh temporary worktree. Never push `main`, the docs branch, or `bartosz/on-site-permissions-4`.

## Situation (verified 2026-09-07)

- PRs 1–3 are merged to `main` (#6595, #6613, #6661). PR 4 is open: https://github.com/duckduckgo/apple-browsers/pull/6705, branch `bartosz/on-site-permissions-4`, origin tip `700c925c8c`, already rebased onto `main` (24 commits ahead of `origin/main`, including review-feedback commits such as "Extract tab site-permission handling and teardown" and "Fix media permission frames and prompt UI").
- **`origin/bartosz/on-site-permissions-5` (tip `7e9520c173`) still sits on the OLD, pre-rebase PR 3/4 lineage.** Only two of its commits are PR 5's own: `f6e87826eb` "Add on-site geolocation permission flows" and `7e9520c173` "Align geolocation tests with current permission flow". Everything below `f6e87826eb` is a stale duplicate of PR 3/4 work under old SHAs and **must not be replayed**. The rebase cut point is `c86a962534` (the parent of `f6e87826eb`; it is not an ancestor of the rebased PR 4).
- `origin/bartosz/on-site-permissions-6` (tip `7cdf1ec881`) is one commit, "Complete on-site permission management", on top of `origin/…-5`. Its cut point is `7e9520c173`.
- The local branches `…-4`, `…-5`, `…-6` are stale pre-rebase copies. Their "local-only" commits are the same work under old SHAs — no unique work. Reset them to origin after eyeballing the titles.
- Two leftover temp worktrees are clean and block checkout: `/private/tmp/apple-browsers4-permissions-rebase-20260904` (holds branch `…-6`) and `/private/tmp/apple-browsers4-permissions-validation-20260904` (detached). Remove them.
- Tooling present: `gh` 2.96 with the `gh stack` extension. PR titles/bodies are prepared on the docs branch: `docs/on-site-permission-manager/pr5-description.md` and `pr6-description.md` (read with `git show bartosz/on-site-permissions:docs/on-site-permission-manager/pr5-description.md`).

## Steps

1. **Prepare.** `git fetch origin --prune`. Confirm the two temp worktrees are clean (`git -C <path> status --short` prints nothing), then `git worktree remove <path>` for both and `git worktree prune`. Create a working worktree: `git worktree add --detach /private/tmp/apple-browsers4-stack-rebase-$(date +%Y%m%d) origin/bartosz/on-site-permissions-4` and run everything below inside it.
2. **Safety tags (local only, never pushed):** `git tag backup/osp-5-$(date +%Y%m%d) origin/bartosz/on-site-permissions-5` and `git tag backup/osp-6-$(date +%Y%m%d) origin/bartosz/on-site-permissions-6`.
3. **Reset local branches to origin.** For 4, 5, and 6: print `git log --oneline origin/bartosz/on-site-permissions-N..bartosz/on-site-permissions-N` and confirm every title also exists in the origin branch's history (old SHAs of rebased commits); then `git branch -f bartosz/on-site-permissions-N origin/bartosz/on-site-permissions-N`. If any local-only commit title has no counterpart on origin, stop and ask the user.
4. **Rebase 5.** `git checkout bartosz/on-site-permissions-5 && git rebase --onto bartosz/on-site-permissions-4 c86a962534`. Expect exactly two commits replayed. Verify with `git log --oneline bartosz/on-site-permissions-4..bartosz/on-site-permissions-5` — it must list only "Add on-site geolocation permission flows" and "Align geolocation tests with current permission flow". Conflicts are plausible (PR 4's review commits touched `TabViewController`, user-script registration, and the sheet UI): resolve preserving both intents, and never drop PR 4's review changes.
5. **Rebase 6.** `git checkout bartosz/on-site-permissions-6 && git rebase --onto bartosz/on-site-permissions-5 7e9520c173`. Expect exactly one commit. Verify with `git log --oneline bartosz/on-site-permissions-5..bartosz/on-site-permissions-6`.
6. **Verify the stack.** `git log --oneline origin/main..bartosz/on-site-permissions-6` must show PR 4's 24 commits, then the two PR 5 commits, then the PR 6 commit — no duplicate titles. Build the iOS app and run the `SitePermissions` package tests plus the touched app test suites via XcodeBuildMCP (selected tests, no manual simulator testing). Fix any compile fallout from the rebase on the branch it belongs to (5 or 6), amending that branch's own commits — do not add commits that touch PR 4's files without need.
7. **Snapshot submodule check.** If `git diff origin/main..bartosz/on-site-permissions-6 --stat -- SnapshotReferences` shows the submodule pointer changed, follow CLAUDE.md: run `./scripts/open-snapshot-submodule-pr.sh` and add the printed link to the affected PR body.
8. **Push with lease** (rewritten history, so force is required — but only against the exact tips you started from):
   - `git push --force-with-lease=bartosz/on-site-permissions-5:7e9520c173 origin bartosz/on-site-permissions-5`
   - `git push --force-with-lease=bartosz/on-site-permissions-6:7cdf1ec881 origin bartosz/on-site-permissions-6`
   If a lease fails, someone pushed meanwhile — stop and ask the user. Do not push branch 4.
9. **Open the draft PRs.** First `gh pr view 6705 --json baseRefName,headRefName,isDraft` and confirm head is `bartosz/on-site-permissions-4` (its base should be `main` now that PRs 1–3 merged). Then:
   - PR 5: `gh pr create --draft --base bartosz/on-site-permissions-4 --head bartosz/on-site-permissions-5 --title "Add on-site geolocation permission flows" --body-file <file>` where the body is the "Suggested PR body" section of `pr5-description.md`, prefixed with one line: `Stacked on #6705 (PR 4 of 6) — review only the commits unique to this branch.` End the body with your environment's standard Claude Code attribution line.
   - PR 6: same with `--base bartosz/on-site-permissions-5 --head bartosz/on-site-permissions-6 --title "Complete on-site permission management"`, body from `pr6-description.md`, prefixed with `Stacked on PR 5 (#<its number>) → #6705.`
   Do not edit #6705's body or base. Do not mark anything ready for review.
10. **Report** the two new PR URLs, the final `git log --oneline origin/main..bartosz/on-site-permissions-6`, every conflict you resolved (file + one line on the resolution), and the test results. Remove the temporary worktree when done; keep the backup tags.

## Guardrails

- Never rebase with a plain `git rebase bartosz/on-site-permissions-4` — it would try to replay the 14 stale PR 3/4 duplicates; always use `--onto` with the cut points above.
- If the number of replayed commits differs from the expected 2 (branch 5) or 1 (branch 6), stop and ask before pushing.
- Nothing here touches the docs branch; do not commit or push documentation.
