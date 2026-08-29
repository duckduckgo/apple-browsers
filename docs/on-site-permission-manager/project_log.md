# Project Log

## Current handoff

- Goal: Implement the six-PR on-site permission manager stack from `implementation-plan.md` without pushing.
- Status: Phases 1 and 2 are complete. Phase 3 is ready to start.
- Completed: `bartosz/on-site-permissions-2` contains commit `fd03017631` on top of Phase 1. It adds the system-permission client, site-permission coordinator, deterministic package tests, and frozen legacy media-capture matrices without making the feature reachable in production.
- Next: Create `bartosz/on-site-permissions-3` from `bartosz/on-site-permissions-2`, then implement Phase 3 steps 1–4 in order.
- Blockers: Phase 3 step 5 requires the missing Voice Search design from Figma node `1087:27674`. Steps 1–4 are locally specified and can proceed first.

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

### 2026-08-29 — Preserve site-first permission prompting

- Decision: A stored or session Allow choice cannot silently trigger an undetermined iOS permission prompt. The coordinator returns the preexisting-denial recovery state and waits for a fresh site prompt before requesting iOS access.
- Why: The feature contract requires the site dialog to precede every native permission prompt.
- Consequences: Persistent Allow remains stored after an iOS denial, but a later automatic request shows recovery UI instead of presenting the native prompt in isolation.

### 2026-08-29 — Keep location status reads simple

- Decision: Keep the infrequent `CLLocationManager.locationServicesEnabled()` reads synchronous on the main actor during initialization and app activation.
- Why: Moving those reads off actor would add coordination machinery without changing the user-visible contract. The client already coalesces native requests and resumes all pending continuations safely.
- Consequences: Revisit only if profiling shows a measurable activation delay.

## Review outcomes

### Phase 1

- Correctness review: No findings.
- Xcode and resource-wiring audit: No findings. The package, test bundle, worker source, and icon are registered once with the expected target membership.
- Ponytail review: Applied the recommendation to remove a bespoke counting storage mock and an optimization-only test. The sparse-map tests now assert the persisted state directly. No suggestions were skipped.

### Phase 2

- Correctness review: Fixed a continuation leak when location authorization changed after app activation, coalesced concurrent location callers into one native request, and stopped audio/video callbacks from performing unrelated location refreshes.
- Contract review: Fixed queued requests so their stored and ephemeral choices are re-evaluated when they reach the front of the per-tab FIFO. Expanded the frozen legacy matrix to cover both `example.com` and Duck.ai for microphone, camera, and combined requests across all four native authorization states.
- Follow-up review: Added explicit coverage for Allow Once across same-document requests and for the fact that ephemeral choices do not survive coordinator recreation. The full post-fix correctness review found no remaining issues.
- Ponytail review: No findings after the correctness fixes. The concrete coordinator and system client remain package-owned and avoid speculative protocols or subcoordinators.

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
- Added a five-state system-permission client for camera, microphone, and location. It shares one location manager for status and position callbacks, refreshes on app activation, opens Settings, coalesces pending location requests, and drains every continuation.
- Added the site-permission coordinator with site-choice precedence, per-tab FIFO serialization, five-part browsing-context validation, stale-callback rejection, navigation and tab-lifecycle resets, combined-request handling, and preexisting/after-request recovery states.
- Kept persistent Allow durable when iOS denies access. Deny Once is an internal coordinator action for Phase 3 dismissal and cancellation paths; it is not a visible dialog button.
- Added frozen legacy matrices that exercise the unchanged `TabViewController` and `AIChatWebViewController` delegate paths for 24 exact call-site combinations plus DuckDuckGo, subdomain, and mixed combined-permission cases. Neither production delegate changed in Phase 2.
- Built `DuckDuckGo.xcworkspace` with the `iOS Browser` scheme through XcodeBuildMCP on an iPhone 17 simulator. The normal configured-target build succeeded with pre-existing warnings only.
- Initialized the pinned `privacy-reference-tests` submodule after the first full run exposed missing fixture files. The submodule remains at `c2b49fe7ce4a75404c6a79e4dd1053710a9869ee` and is not part of the implementation diff.
- Ran `SitePermissionsTests` and all `UnitTests` through the `iOS Browser` simulator scheme after review fixes: 6,629 passed, zero failed, and 37 baseline skips. The test-only iOS 16 deployment-target override remains necessary for the unrelated current-main `UIMenuElement.subtitle` compilation issue.
