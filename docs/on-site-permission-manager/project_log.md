# Project Log

## Current handoff

- Goal: Implement the six-PR on-site permission manager stack from `implementation-plan.md` without pushing.
- Status: Phase 1 is paused at Step 2 because the required Settings icon artwork is unavailable.
- Completed: Created `bartosz/on-site-permissions-1` from `origin/main` in the linked worktree `/private/tmp/apple-browsers4-on-site-permissions`. Commit `9319d540ff` adds the disabled-by-default `sitePermissions` flag and the missing 24px microphone/video blocked-glyph accessors. The `iOS Browser` simulator build passed.
- Next: Add `Website-Permissions-Color-24` to DesignResourcesKitIcons, then continue with Phase 1 Step 3 (the `SitePermissions` package scaffold).
- Blockers: Obtain the design-exported `Website-Permissions-Color-24.svg`. If the design library defines separate current/rebrand and legacy variants, obtain both SVGs; otherwise one canonical SVG is sufficient.

## Decisions

### 2026-08-29 — Isolate implementation from documentation edits

- Decision: Keep implementation work in a linked worktree and leave the primary worktree on `bartosz/on-site-permissions`.
- Why: The primary worktree already contains three uncommitted documentation edits that must not enter an implementation branch.
- Consequences: Run implementation commands from `/private/tmp/apple-browsers4-on-site-permissions`; write project memory and PR descriptions only in the primary documentation worktree.

## Recent progress

### 2026-08-29

- Fetched `origin/main` at `49fdbe59e5` and initialized the local stack as `main ← bartosz/on-site-permissions-1`.
- Verified the missing icon is absent from the working tree, all local refs and history, and unreachable local commits. Existing 16px permission, 24px options, and Settings gear artwork are not valid substitutes.
- Built `DuckDuckGo.xcworkspace` with scheme `iOS Browser` through XcodeBuildMCP on an iOS simulator; build succeeded with pre-existing warnings.
