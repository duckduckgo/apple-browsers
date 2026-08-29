# Project Log

## Current handoff

- Goal: Implement the six-PR on-site permission manager stack from `implementation-plan.md` without pushing.
- Status: Phase 1 is complete. Phase 2 is ready to start.
- Completed: `bartosz/on-site-permissions-1` contains commits `9319d540ff` and `794c151acd`. Together they add the disabled-by-default feature flag, required icon resources, the package model and persistence store, Xcode registration, focused tests, and flag-independent Fire clearing.
- Next: Create `bartosz/on-site-permissions-2` from `bartosz/on-site-permissions-1`, then implement the coordinator and system client from Phase 2.
- Blockers: None.

## Decisions

### 2026-08-29 — Isolate implementation from documentation edits

- Decision: Keep implementation work in a linked worktree and leave the primary worktree on `bartosz/on-site-permissions`.
- Why: The primary worktree already contains three uncommitted documentation edits that must not enter an implementation branch.
- Consequences: Run implementation commands from `/private/tmp/apple-browsers4-on-site-permissions`; write project memory and PR descriptions only in the primary documentation worktree.

### 2026-08-29 — Keep Fire construction on the main actor

- Decision: Mark the Fire executor initializer as `@MainActor` so it constructs the main-actor permission store without an unsafe isolation escape.
- Why: All production and test construction sites are already main-actor isolated. A `nonisolated` store initializer compiled but produced a Swift 6 isolation warning.
- Consequences: The normal app build has no feature-specific actor-isolation warnings.

### 2026-08-29 — Reuse the existing delete-text color

- Decision: Later UI phases must use `DesignSystemColor.buttonsDeleteGhostText` for the status-red state.
- Why: It resolves to the required light and dark values, and iOS has no `statusRed` token.
- Consequences: Do not add a new semantic color unless the design system changes before the UI phase.

## Review outcomes

### Phase 1

- Correctness review: No findings.
- Xcode and resource-wiring audit: No findings. The package, test bundle, worker source, and icon are registered once with the expected target membership.
- Ponytail review: Applied the recommendation to remove a bespoke counting storage mock and an optimization-only test. The sparse-map tests now assert the persisted state directly. No suggestions were skipped.

## Recent progress

### 2026-08-29

- Fetched `origin/main` at `49fdbe59e5` and initialized the local stack as `main ← bartosz/on-site-permissions-1`.
- Verified the missing icon is absent from the working tree, all local refs and history, and unreachable local commits. Existing 16px permission, 24px options, and Settings gear artwork are not valid substitutes.
- Validated the supplied 24×24 SVG as well-formed XML and integrated the exact bytes (SHA-256 `5aeb1bf2a5827c922012052341539d57089151778fa76176248ff08104bb2fcf`) as `Website-Permissions-Color-24`.
- Added and resolved the `SitePermissions` package with its local `Persistence` dependency. Xcode discovers the package through the wrapper-only local-package pattern.
- Added host-only URL normalization, plist-native split-key persistence, explicit-reset `ask` records, binary global defaults, and conflict-safe Undo snapshots.
- Added an ungated Fire worker that preserves global defaults and fireproofed site records, including subdomains and the implicit DuckDuckGo exemptions.
- Ran the wide-event schema check successfully.
- Built `DuckDuckGo.xcworkspace` with the `iOS Browser` scheme through XcodeBuildMCP on an iOS simulator. The normal configured-target build succeeded with pre-existing warnings only.
- After the review fix, ran `SitePermissionsTests` and `UnitTests/FireExecutorTests` through the `iOS Browser` simulator scheme: 77 passed, zero failed, and zero skipped. The test output named `SitePermissionsTests` and reported a nonzero count.
- The current SDK cannot compile an unrelated iOS 15 `UIAction.subtitle` test on `main`. The focused test command used a test-only `IPHONEOS_DEPLOYMENT_TARGET=16.0` override; the production app build used the project setting without an override.
