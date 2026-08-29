# Project Log

## Current handoff

- Goal: Implement the six-PR on-site permission manager stack from `implementation-plan.md` without pushing.
- Status: Phases 1 and 2 are complete. Phase 3 steps 0–2 are committed. Work is paused before step 3 at the first design blocker.
- Completed: `bartosz/on-site-permissions-3` contains commit `0bb7913527` on top of Phase 2. It adds the localized site-permission dialog and browser media-capture routing while preserving the legacy and Duck.ai behavior.
- Next: Obtain the combined camera-and-microphone recovery UX, then implement Phase 3 step 3.
- Blocker: The plan specifies recovery UI only for one failed permission type. It does not define Case A or Case B for combined camera-and-microphone failures, including mixed preexisting and after-request failures. Implementation needs the number and order of surfaces, exact title, body, and toast copy, and whether recovery pixels use `camera_and_microphone` or individual type tokens.
- Later blocker: Phase 3 step 5 requires the missing Voice Search design from Figma node `1087:27674`. This step has not been reached.

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

### 2026-08-29 — Validate media requests against public WebKit lifecycle signals

- Decision: Retain each request's exact `WKFrameInfo` object and frame identity, plus navigation and web-process generations. Reject requests during provisional navigation and reject callbacks from an older navigation object.
- Why: Public `WKFrameInfo` exposes identity but no frame-liveness API. Navigation identity prevents a stale failure callback from reopening requests during a newer provisional navigation.
- Consequences: Same-document iframe removal cannot be observed through public WebKit APIs. The implementation uses the strongest available validation and documents this limitation in code.

### 2026-08-29 — Keep pending requests with their tab

- Decision: Keep a tab's FIFO permission queue when the tab is dismissed during a tab switch. Drain it on navigation, web-process replacement, or tab close.
- Why: The plan assigns request ownership to the tab and defers inactive-tab hardening to Phase 6.
- Consequences: Do not cancel pending requests merely because another tab becomes active. Revisit the inactive-tab behavior in Phase 6.

### 2026-08-29 — Reject media requests from link previews

- Decision: Do not construct or forward site-permission dependencies to link-preview tabs. Deny any media-capture request from a link preview.
- Why: A link preview is not a committed browsing context and must not present permission UI.
- Consequences: Only normal tabs can enter the site-permission coordinator path.

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

### Phase 3 steps 0–2

- Contract review: No findings. The dialog variants, localization, committed-URL routing, Duck.ai precedence, per-tab FIFO behavior, and accessibility behavior match the implementation plan.
- Correctness review: Fixed provisional-navigation tracking so a stale failure cannot validate a request during a newer navigation. Also denied link-preview requests without constructing site-permission dependencies. The final review found no remaining issues.
- Ponytail review: No findings. The custom domain truncation is required because native text truncation would truncate the whole localized title, and the navigation state is the minimum needed to preserve the last committed URL safely.

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
- Created `bartosz/on-site-permissions-3` from `bartosz/on-site-permissions-2` and committed Phase 3 steps 0–2 as `0bb7913527`.
- Added camera, microphone, and combined site-prompt dialogs with the specified copy, design-system controls, localized resources, Dynamic Type support, domain-only middle truncation, modal VoiceOver behavior, and stable accessibility identifiers.
- Added lazy per-tab media-capture coordination. Duck.ai handling remains first, flag-off behavior remains unchanged, and flag-on requests use only the last committed top-level URL.
- Added request identity and lifecycle checks for the exact web view and frame, provisional-navigation identity, web-process generation, navigation generation, and tab closure. Navigation, process replacement, and closure drain pending handlers exactly once.
- Denied requests from link previews, replaced web views, uncommitted pages, and pages in provisional navigation without constructing the coordinator.
- Ran the focused Phase 3 package and browser-routing suites through the `iOS Browser` simulator scheme: 72 passed, zero failed, and zero skipped. Re-ran the frozen `TabViewController` legacy matrix after the final fixes: one passed, zero failed, and zero skipped.
- Built the production app through XcodeBuildMCP with the `iOS Browser` scheme and the normal project deployment setting. The build passed. Focused tests used the existing test-only iOS 16 deployment-target override for unrelated current-main tests that require iOS 16 APIs.
- Stopped before Phase 3 step 3 because combined camera-and-microphone recovery behavior is not specified. The required design decision is recorded in the current handoff.
