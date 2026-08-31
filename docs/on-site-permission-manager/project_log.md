# Project Log

## Current handoff

- Goal: Implement the six-PR on-site permission manager stack from `implementation-plan.md` without pushing.
- Status: Phases 1–4 are complete. There is no active blocker.
- Completed: `bartosz/on-site-permissions-4` contains commit `1003ae5ef4` directly on Phase 3 commit `f0603bafa5`. It adds the camera and microphone management sheet, Settings surfaces, both browser-menu paths, removal with Undo, immediate cross-tab revocation, and management pixels.
- Next: Create `bartosz/on-site-permissions-5` from `bartosz/on-site-permissions-4` and implement the geolocation shim, provider, dialogs, recovery, and browser integration.
- Stack state: Phase 4 is based on `bartosz/on-site-permissions-3` at `f0603bafa5`. The stack remains local; nothing has been pushed.
- Blocker: None.

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

### 2026-08-31 — Preflight combined recovery atomically

- Decision: For a combined camera and microphone allow, classify both OS states before requesting either permission. Any pre-existing blocked state suppresses every OS prompt and produces one reminder naming only the blocked type or types. Otherwise, request every undetermined type, even after an earlier fresh denial, and coalesce fresh failures into one toast.
- Why: The DRI's supplied answer resolves the known multi-permission design gap and protects an unused one-shot OS prompt when the combined WebKit request must fail anyway.
- Consequences: One combined request always produces at most one recovery surface. Site-level Allow remains committed, and OS-result pixels stay individual because iOS prompts each type separately.

### 2026-08-31 — Keep recovery in the request FIFO until dismissal

- Decision: Resolve WebKit with deny before showing recovery, but retain the active coordinator entry until the toast or reminder is dismissed.
- Why: WebKit must be answered promptly, while the per-tab FIFO must prevent a second request from stacking another permission surface.
- Consequences: App-owned recovery surfaces report dismissal through a completion callback. Navigation, process replacement, and tab closure invalidate stale callbacks safely.

### 2026-08-31 — Keep Fire-mode management session-local

- Decision: Apply management choices and removals only to the Fire tab's session state. Do not write or delete durable records from a Fire tab. Persistent denial or removal initiated outside Fire clears conflicting Fire-session overrides.
- Why: Fire browsing must not create durable permission history, but persistent changes from Settings or a normal tab must still revoke access consistently.
- Consequences: Fire-originated revocation stays local. Normal-mode denial and removal propagate to every matching live tab.

### 2026-08-31 — Separate sheet membership from menu eligibility

- Decision: Build sheet rows from stored, active, and requested-this-visit state, but show the browser-menu entry only for a stored record or active session state. Do not track a globally denied no-record request as requested-this-visit.
- Why: The sheet must explain requests from the current visit without making a temporary menu entry appear merely because the global default silently blocked a request.
- Consequences: Explicit Ask records remain visible, successful session grants remain manageable, and global Never creates neither a row nor a menu entry by itself.

### 2026-08-31 — Revoke matching tabs after durable changes

- Decision: Write a denial or removal first, then revoke the affected capture in every matching normal tab. Removal revokes both camera and microphone even when only one type appears in the current snapshot.
- Why: Another matching tab can still be using a permission that is absent from the initiating tab's visible state.
- Consequences: Grants and resets still wait for reload or the next request. Explicit denial and removal stop matching active capture immediately.

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

### Phase 3 complete

- Correctness review: No findings in combined atomic preflight, recovery FIFO ordering, stale-context handling, or generation-guarded capture observation. The reviewer confirmed that WebKit denial precedes recovery and that initial inactive observations do not expire Allow Once.
- Contract review: No production mismatch in flag-off behavior, Duck.ai precedence, supplied UI and copy, accessibility, pixels, or project registration. The review identified missing app-level action coverage; focused tests now exercise dialog impression and selection, Case B denial-before-reminder ordering, the Settings action, the unchanged legacy Voice Search alert, the redesigned alert, and every Voice Search action.
- Ponytail review: Kept `presentTracked` because the existing public overload must retain its protocol-compatible `Void` signature and recovery must dismiss only its exact toast. Kept the injected Settings opener because the new integration test uses it. Applied the recommendation to add app-level tests and simplified the coordinator helper that exceeded the lint complexity limit.
- Follow-up verification: The final focused run passed 104 tests with no failures or skips. The production build passed. No feature-specific compiler or lint warnings remain.

### Phase 4

- Correctness review: Fixed normal-mode denial and removal so revocation propagates across matching live tabs, while Fire-originated changes remain local and external persistent changes clear conflicting Fire overrides. Removal now revokes both managed permission types after the store mutation.
- Contract review: Fixed globally denied no-record requests so they do not enter requested-this-visit state or create management rows. The final review found no remaining findings.
- Test follow-up: The first focused run passed 143 of 144 tests and exposed that `BrowsingMenuModel.Entry` ignored its explicit Open Bookmarks tag. The tag propagation was fixed, the targeted regression test passed, and the fresh focused run passed all 148 tests: 106 `SitePermissionsTests` and 42 selected `UnitTests`.
- Release audit: No blockers. Scope, feature gating, frozen matrices, Fire isolation, telemetry, project wiring, headers, and submodule state all matched the Phase 4 contract.

## Recent progress

### 2026-08-31

- Created `bartosz/on-site-permissions-4` directly from Phase 3 commit `f0603bafa5`. The branch remains local and nothing has been pushed.
- Added the three-state on-site camera and microphone management sheet with content-fitting detents, the iOS 15 fallback, iPad popover behavior, Dynamic Type, VoiceOver state values, and the approved in-use icon treatment.
- Added Settings › Site Permissions with two-option global defaults, a locale-sorted persistent-site list, per-site three-option pickers, favicons, the System Settings link, and per-site and all-sites removal with conflict-safe Undo.
- Added the temporary Site Permissions entry to both browser-menu paths. Visibility covers persistent records, explicit Ask, and active session state while remaining absent with the flag off or no eligible state.
- Replaced the sheet menu's literal preferred-detent count with the flattened position of the tagged Open Bookmarks entry. The tests cover both menu layouts, the permission row present and absent, optional entries, and the YouTube Ad Block section.
- Added store-first immediate revocation for denial and removal. Normal-mode changes propagate across matching tabs; Fire-mode changes remain session-local; removal revokes both camera and microphone.
- Added the approved management pixels through PixelKit. `permission_center_changed` keeps `from` as a parameter, and no management event contains site metadata.
- The first focused run passed 143 of 144 tests and exposed an ignored explicit detent tag. After the fix, the targeted test passed, and the final focused run passed 148 tests with no failures: 106 `SitePermissionsTests` and 42 selected `UnitTests`.
- Ran the full `SitePermissionsTests` and `UnitTests` gate: 6,726 passed, zero failed, and 37 baseline skips.
- Built the production `iOS Browser` scheme on an iPhone 17 Pro simulator running iOS 26.4 with the normal project deployment target. The build passed.
- Validated `site_permissions.json5` for product target 7.234.0 and checked it with Prettier. Both checks passed.
- Ran Swift parser checks, property-list syntax checks, and `git diff --check`; all passed.
- Squashed Phase 4 into `1003ae5ef4` directly on `f0603bafa5`. Nothing was pushed.

- Received and inspected the six supplied Figma screenshots. Updated the implementation plan with the exact card widths, corners, material, dim, spacing, shadows, button treatment, Voice Search variant, combined copy, and recovery event rules.
- Applied the supplied combined-recovery decision: one surface per combined request, atomic OS preflight, no prompt spending in mixed blocked states, both fresh prompts attempted, and type-accurate coverage in recovery copy and pixels.
- Added camera and microphone capture observation. Active, paused, and inactive states are tracked independently; only the matching Allow Once grant expires when capture ends.
- Added Case A no-action toasts and Case B reminder dialogs. Recovery remains in the coordinator FIFO through dismissal, and page, process, and tab lifecycle changes dismiss only the feature-owned surface.
- Restyled the denied-microphone Voice Search prompt behind `sitePermissions`. The flag-off `UIAlertController` remains unchanged; the new variant supports Change Permissions, Hide Voice Search, and Cancel.
- Added all six approved Phase 3 pixel families through PixelKit. Combined site events use `camera_and_microphone`; OS prompt results remain individual; no event contains a domain, host, URL, or origin.
- Validated `site_permissions.json5` against product target 7.234.0 and checked it with Prettier. The repository-wide validator also reached and validated the new file, then failed on unrelated existing wide-event generated schemas; no generated schema changes remain in the worktree.
- Ran the full `SitePermissionsTests` and `UnitTests` gate: 6,668 passed, zero failed, and 37 baseline skips. After review changes and new app-level tests, ran the focused package, routing, and pixel suites: 104 passed, zero failed, and zero skipped.
- Built the production app with the `iOS Browser` scheme and normal project deployment target through XcodeBuildMCP. The build passed with pre-existing repository warnings only.
- Squashed Phase 3 into commit `f0603bafa5` directly on `fd03017631`. The implementation worktree is clean, and nothing was pushed.

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
- Created `bartosz/on-site-permissions-3` from `bartosz/on-site-permissions-2` and committed Phase 3 steps 0–2 as `0bb7913527`. The partial commit was later squashed into the final Phase 3 commit recorded above.
- Added camera, microphone, and combined site-prompt dialogs with the specified copy, design-system controls, localized resources, Dynamic Type support, domain-only middle truncation, modal VoiceOver behavior, and stable accessibility identifiers.
- Added lazy per-tab media-capture coordination. Duck.ai handling remains first, flag-off behavior remains unchanged, and flag-on requests use only the last committed top-level URL.
- Added request identity and lifecycle checks for the exact web view and frame, provisional-navigation identity, web-process generation, navigation generation, and tab closure. Navigation, process replacement, and closure drain pending handlers exactly once.
- Denied requests from link previews, replaced web views, uncommitted pages, and pages in provisional navigation without constructing the coordinator.
- Ran the focused Phase 3 package and browser-routing suites through the `iOS Browser` simulator scheme: 72 passed, zero failed, and zero skipped. Re-ran the frozen `TabViewController` legacy matrix after the final fixes: one passed, zero failed, and zero skipped.
- Built the production app through XcodeBuildMCP with the `iOS Browser` scheme and the normal project deployment setting. The build passed. Focused tests used the existing test-only iOS 16 deployment-target override for unrelated current-main tests that require iOS 16 APIs.
- Stopped before Phase 3 step 3 because combined camera-and-microphone recovery behavior was not specified. That blocker was recorded in the handoff at the time and resolved by the supplied answer on 2026-08-31.
