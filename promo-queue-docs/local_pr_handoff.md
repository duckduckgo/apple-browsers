# Promo Queue local PR handoff

## Documentation ownership

This handoff and all other Promo Queue project documentation live only on `bartosz/promo-q-simp-master`. Keep `project_log.md`, `project_lessons/`, `promo-queue-docs/`, review reports, and project-only handoff notes out of the open production branches `bartosz/promo-q-simp-2`, `bartosz/promo-q-simp-3`, and `bartosz/promo-q-simp-4`. Documentation changes may be committed locally on the master branch; do not push them or copy/cherry-pick them into a production branch without explicit user instructions.

## PR 1

Suggested title: **iOS Promo Queue: Simplify coordination foundation**

### Draft description

This change replaces the broad Promo Queue foundation with a startup-latched, app-scoped coordination slot while preserving legacy behavior when `promoPresentationCoordination` is disabled. It prevents launch-promo provider evaluation from racing an admitted NTP remote message and establishes the primitives required for shared-source RMF integration in the next stack unit.

The implementation removes live feature transitions, per-surface occupancy/retry APIs, renderer coordinator plumbing, transition-only tests, and obsolete project references. It reduces the arbiter to one identity-safe modal or RMF owner, uses one opaque modal ownership identity through arbitration and manager phases, and makes transferred modal-lease handling a one-way `Void` call owned entirely by the manager. It preserves exact-root modal lease retention, adds the three directional confirmed-appearance cooldown rules, and introduces a failure-tolerant `ThrowingKeyValueStoring` RMF history plus a service-owned lease that records only the first valid appearance. `PromoCoordinationFactory` constructs one mode, arbiter, modal store/manager, RMF history, cooldown policy, and service.

Accepted limitations and non-goals: feature changes require relaunch; modal dismissal is reconciled lazily; retry remains checkpoint-driven; arbitrary UIKit sheets are out of scope; there are no timers, waiters, renderer registries, release broadcasts, or new telemetry. The production feature flag remains off. End-to-end RMF publication gating follows in `bartosz/promo-q-simp-3`.

Verification completed on iPhone 17 Pro (iOS 26.4) through XcodeBuildMCP:

- Phase 0 validation: 62 focused tests passed with 0 failures.
- Phase 1 verification: 51 focused tests passed with 0 failures, covering arbiter identity safety, cooldown boundaries/fallback storage, service-owned appearance confirmation, modal/RMF admission order, and modal retention.
- Phase 1 alignment: 27 focused unit tests and 11 integration tests passed with 0 failures, including the first-read-failure/no-cache history case and the one-identity/one-way-transfer cleanup.
- `iOS Browser Alpha` Debug simulator build succeeded.
- `git diff --check` passed and static searches found none of the removed live-transition, per-surface/retry, or NTP renderer-coordinator symbols.

Stack dependency: this is PR 1, based on `main`; PR 2 integrates the gate at the shared `HomePageConfiguration` source. The production-only layer currently measures 906 insertions and 2,036 deletions across 31 files (2,942 changed lines, dominated by removal). Access-level changes: none were made solely for testing, and no production access was widened beyond the contracts required by the source gate, callback identity, and diagnostics plan.

## PR 2

Suggested title: **iOS Promo Queue: Gate NTP RMF at the shared message source**

### Draft description

This change integrates Promo Queue at the one app-scoped `HomePageConfiguration` shared by every NTP renderer. When coordination is enabled, RMF selection is deferred until an explicit NTP activation checkpoint, admitted before publication, and retained by source/message lifecycle rather than physical view visibility. Legacy behavior remains selected at launch when the feature flag is disabled.

The shared source is main-actor isolated and owns one aggregate containing the selected message, actual trigger filter, service-owned lease, and opaque presentation identity. It pins after-idle fallback to the filter actually selected, rejects unsupported content before acquisition, publishes only after the aggregate is retained, and emits a synchronous object-scoped change signal consumed by all NTP models and direct suggestion hosts. The standard NTP, legacy/iPad tray, OmniBar editing sheet, and unified-input path each prepare once at their existing activation seam. That explicit preparation is the only fresh-acquisition checkpoint. Store changes and foreground events only revalidate existing ownership. Background disables fresh admission while retaining a valid publication, lease, identity, context, and appearance history.

Coordinated shown accounting now occurs on the first validated physical appearance. The acquisition identity is reused for callback validation and SwiftUI diffing, so stale appearances and dismissals cannot affect a replacement owner. Async dismissal remains unfrozen: authoritative store changes may progress while awaiting, direct teardown occurs only for the still-current context, and exactly one existing reconciliation notification follows. That notification cannot acquire a replacement. There are no renderer visibility callbacks, host registration, container teardown callbacks, release broadcasts, timers, retry registries, or new telemetry.

Accepted limitations and non-goals: the feature remains startup-latched and off by default; fresh acquisition is checkpoint-only; foreground and store notifications do not replay a denied request; ownerless arrival, modal/cooldown denial, dismissal, and different-ID replacement wait for another natural preparation; same-ID refresh and invalidation remain immediate; an attached NTP can remain blank beyond a cooldown boundary until another natural checkpoint; rapid cross-acquisition unique-shown accounting retains the pre-existing best-effort behavior. The expected regular `remoteMessageShown` volume is lower because coordinated mode reports only the first real appearance per acquisition instead of eager model mapping. Diagnostic visibility and reset controls follow in PR 3.

The 2026-08-17 background-retention correction was verified on iPhone 16 Pro (iOS 18.6) through XcodeBuildMCP:

- 111 focused unit tests passed with 0 failures across the arbiter, directional cooldown, promo service, modal manager/root/UIKit, shared source/model/builder, and feature-flag suites.
- Phase 2 coverage includes startup/background admission, notification-only owner revalidation, actual-filter pinning, modal/cooldown denial, renderability, retained-before-publication ordering, same-ID identity, delayed ownerless arrival/replacement, ordered expiry/removal/onboarding teardown, background retention, and suspended dismissal reconciliation.
- `iOS Browser Alpha` Debug simulator build succeeded with no build warnings or errors.
- `git diff --check` passed; static searches found no discarded renderer/retry/live-transition vocabulary or live feature-flag subscription, and confirmed exactly four activation-time preparation calls.
- The feature-state manual matrix remains for human QA because it requires configured Remote Messaging content and launch-modal eligibility states not available in the local automated harness.

Stack dependency: this is PR 2, based on unchanged PR 1 (`bartosz/promo-q-simp-2` at `6234fda331f2d6eac29b7524eba1dab9f68f8f51`). The corrected local PR 2 head is `eb9ad4cf254c2615593354278b987d683be038ef`; the live PR remains at `479ebe6956e6723ddfbdac41c0f04bc4c2ea62b8` until a human pushes. PR 3 adds internal diagnostics and reset controls. The local production-only layer measures 1,636 insertions and 147 deletions across 19 files (1,783 changed lines). Project documentation is not part of this branch. No production access was widened solely for tests.

### Checkpoint-only acquisition amendment — 2026-08-18

Starting from PR #6368 head `6a8a59fe99`, local commit `f5a4db2117` on `bartosz/promo-q-simp-3` removes the host enum, host-taking preparation overload, deactivation contract, host registry/recency state, and retained preparation policy. The only fresh-acquisition path is an enabled explicit `prepareForNTP(openedAfterIdle:)`. XcodeBuildMCP passed 89 focused unit tests, 13 SharedState host tests, and the `iOS Browser Alpha` Debug build on iPhone 17 Pro (iOS 26.4). The equivalent inherited result at PR #6369 head `88542be420` passed 91 focused unit/diagnostic tests, the same 13 host tests, and the Alpha build. Both verified diffs pass `git diff --check`; nothing was pushed, and PR #6369 was not restacked.

## PR 3

Suggested title: **iOS Promo Queue: Add simplified coordination diagnostics**

### Draft description

This change extends the existing internal Modal Prompt Coordination debug screen with read-only Promo Queue diagnostics and explicit cooldown-reset controls. It reuses the app-scoped `PromoCoordinationService`, arbiter, modal store, and RMF history created by production; it does not create a second coordinator or policy graph.

The screen shows startup-latched mode, the active modal ownership ID or RMF message/acquisition IDs, RMF appearance confirmation, last confirmed modal/RMF appearances, and the next RMF/modal eligibility boundaries. A valid source-owned RMF therefore remains the same diagnostic owner across same-process background/foreground. Refresh is passive, flag changes are labeled as requiring relaunch, and the UI states that eligibility dates do not schedule retries. Arbiter snapshots now report a dead weak token as ownerless without pruning; stale-record cleanup remains on the next acquisition path.

The existing modal reset and the new clearly labeled RMF reset route through the production cooldown policy. RMF reset clears persisted history plus the authoritative in-process fallback/cache and refreshes the displayed boundaries immediately. Neither reset releases an owner or dismisses a message. The related What’s New, global prompt-reset, and CPM debug actions now use the same authoritative modal reset route instead of constructing or bypassing production cooldown state.

There are no force-owner controls, modal-phase/last-denial plumbing, retry timers, release broadcasts, production admission changes, or new telemetry. Human review/integration and execution of the external rollout handoff follow. The three production pull requests are open; documentation and final-review work does not authorize further pushes, PR metadata changes, remote-configuration changes, or flag deployment.

Verification completed on iPhone 17 Pro (iOS 26.4) through XcodeBuildMCP:

- 18 focused tests passed with 0 failures across passive refresh/formatting, RMF reset persistence and ownership preservation, passive arbiter snapshots, cooldown policy, and the service gate.
- `iOS Browser Alpha` Debug simulator build succeeded with no build warnings or errors.
- `git diff --check`, target-membership review, and static searches passed; the one new test source belongs only to `UnitTests`.

The diagnostics layer was locally rebased without conflicts onto corrected PR 2. `git range-diff` classified all three PR 3 commits as equivalent and in the same order, so no PR 3-specific follow-up commit was required. On the final tip, 32 selected background/source/diagnostic/arbiter tests passed with 0 failures and 0 skipped on iPhone 16 Pro (iOS 18.6), and an independent `iOS Browser Alpha` Debug simulator build succeeded with only existing workspace warnings.

### Complete manual validation matrix

Because mode is startup-latched, force-quit after changing the local feature override.

1. Flag off: confirm current modal and RMF behavior is unchanged.
2. RMF first: with an eligible restored/cold NTP, confirm an admitted card blocks launch-modal provider evaluation, including after a same-process background/foreground transition.
3. Modal first: commit a launch modal, then open/refresh NTP beneath it and confirm no RMF flashes.
4. No eligible modal: confirm temporary modal acquisition is released and does not strand the slot.
5. Dismissed modal: confirm lazy reconciliation at the next checkpoint and observe the modal-to-RMF cooldown.
6. RMF dismissal, expiry, and replacement: confirm immediate source-level release, no notification-driven replacement acquisition, and a new identity only after the next explicit preparation.
7. Check the standard NTP, legacy/iPad tray, OmniBar editing sheet, and unified-input favorites path; each must consume one shared gated result with one activation-time preparation and no renderer visibility callbacks or recursive preparation.
8. Verify direct after-idle selection and no-trigger fallback; a later after-idle candidate must not displace a still-valid fallback owner.
9. Confirm onboarding suppression.
10. Confirm Fire-tab suppression remains safe, rotate through landscape, and verify rendering/no crash without special lease handling.
11. Leave the NTP and confirm ownership remains source-driven rather than tied to one renderer.
12. Background/foreground: confirm valid ownership, publication, identity, context, and appearance history are retained; inactive invalidation releases without replacement; ownerless foreground validation does not acquire; and the foreground-visible NTP's later explicit preparation can acquire.
13. Relaunch: confirm live ownership resets while confirmed cooldown history persists.
14. Diagnostics: verify mode/owner/appearance/timestamps/boundaries update on Refresh, flag relaunch and no-timer notes are visible, and modal/RMF resets update only their matching cooldown without releasing the displayed owner.

Stack dependency: this is PR 3, based on corrected local PR 2 (`eb9ad4cf254c2615593354278b987d683be038ef`). Its locally restacked head is `bb00c551eefc2e30cc186b79b94f4ece9beb89e1`; the live PR remains at `5037f6fbee00d52eb003a33989a34a559cf7e9be` until a human pushes. The rebased layer measures 544 insertions and 143 deletions across 17 files. Project-log and handoff updates live only on `bartosz/promo-q-simp-master`. The full manual matrix remains for human execution with configured RMF content and launch-modal eligibility states.

## External Phase 4 rollout handoff

This section is a handoff for external human-owned integration and rollout work. No privacy-configuration change, deployment, project-tracker update, production-branch push, or PR mutation is part of documentation maintenance or final review.

### Integration record

- Local PR 1 branch: `bartosz/promo-q-simp-2`
- Local PR 2 branch: `bartosz/promo-q-simp-3`
- Local PR 3 branch: `bartosz/promo-q-simp-4`
- Merged PR 1 link: `[PENDING — add merged PR link]`
- Merged PR 2 link: `[PENDING — add merged PR link]`
- Merged PR 3 link: `[PENDING — add merged PR link]`
- First containing iOS version: `[PENDING — add first shipped version]`
- Minimum supported version for rollout: use the first containing iOS version above; do not enable this subfeature for older iOS app versions.

### Remote configuration source

- Parent privacy-config feature: `promoQueue`
- iOS subfeature: `iOSPromoPresentationCoordination`
- App feature flag: `.promoPresentationCoordination`
- Mapping: `.promoPresentationCoordination` uses `.remoteReleasable(iOSPromoQueueSubfeature.iOSPromoPresentationCoordination)` under the `promoQueue` parent.
- Rollout source: the human-reviewed configuration in `duckduckgo/privacy-configuration` for the parent/subfeature above.
- Warning: do not edit or use generated `iOS/Core/ios-config.json` as the rollout source.

### Validation evidence

Automated verification completed on 2026-08-15 on iPhone 17 Pro (iOS 26.4) through XcodeBuildMCP:

- `bartosz/promo-q-simp-2`: the two affected SharedState classes passed 14 tests with 0 failures on the final complete run; `iOS Browser Alpha` Debug built successfully.
- `bartosz/promo-q-simp-3`: `HomePageConfigurationTests` and `NewTabPageMessagesModelTests` passed 42 tests with 0 failures; the two SharedState classes passed 14 tests with 0 failures on the final complete run; `iOS Browser Alpha` Debug built successfully.
- `bartosz/promo-q-simp-4`: the focused final-stack Promo Queue suites passed 70 tests with 0 failures across arbiter, directional cooldown, service, modal queue manager, shared source/model, feature-flag mapping, and debug view-model behavior; the two SharedState classes passed 14 tests with 0 failures on the final complete run; `iOS Browser Alpha` Debug built successfully.
- Branch ancestry and the required branch-range `git diff --check` commands were verified after the stack was restacked.

Focused amendment verification completed on 2026-08-17 on the booted iPhone 16 Pro simulator (iOS 18.6, `C625E175-7AE1-4FC0-8049-92C9D15EDB21`) with workspace `DuckDuckGo.xcworkspace`, scheme `iOS Unit Tests` for tests, scheme `iOS Browser Alpha` for builds, and Debug configuration:

- Corrected PR 2: `HomePageConfigurationTests` passed 26/26; `NewTabPageMessagesModelTests` plus `PromoCoordinationServicePromoQueueTests` passed 28/28; an independent app build succeeded.
- Restacked PR 3: `HomePageConfigurationTests`, `PromptCoordinationDebugViewModelTests`, and `PromoQueueLeaseArbiterTests` passed 32/32; an independent app build succeeded.
- The test selectors were `UnitTests/HomePageConfigurationTests`, `UnitTests/NewTabPageMessagesModelTests`, `UnitTests/PromoCoordinationServicePromoQueueTests`, `UnitTests/PromptCoordinationDebugViewModelTests`, and `UnitTests/PromoQueueLeaseArbiterTests` as grouped above.
- No source/test failure occurred. Two initial discovery invocations selected the wrong scheme or test-bundle prefix and ran zero tests; one build invocation supplied an unsupported progress option. All were corrected before evidence was recorded, so unaffected-base reproduction was not applicable.
- Builds and tests emitted existing workspace warnings, including unavailable Mint/SwiftLint, a duplicate test build-file entry, and existing concurrency/deprecation/dependency-scan diagnostics; there were no errors.
- PR 1 stayed at `6234fda331f2d6eac29b7524eba1dab9f68f8f51`. Corrected PR 2 is `eb9ad4cf254c2615593354278b987d683be038ef`; restacked PR 3 is `bb00c551eefc2e30cc186b79b94f4ece9beb89e1`. Nothing was pushed and no GitHub PR metadata was changed.

Manual-validation evidence: **PENDING — user must complete the full manual validation matrix above and attach results before rollout.** No manual validation is claimed by this handoff.

### Rollout and hold criteria

The mode is startup-latched. A local override or remote cohort change does not change an existing process graph; force-quit/relaunch, or otherwise create a new process graph, before evaluating the new state.

Regular `remoteMessageShown` volume is expected to decrease in coordinated cohorts because shown accounting changes from eager model mapping to once per actually appeared ownership. Treat that directional change as expected unless it is inconsistent with cohort size or accompanied by other RMF/provider accounting anomalies.

Suggested cohort sequence, subject to the rollout DRI and completion of manual validation: **5% → 25% → 50% → 100%**. At each step, hold rather than advance when any of these criteria is met:

- Crash/regression: a statistically credible crash or stability regression, or a confirmed promo overlap, flash, blank/stranded NTP state, or launch-modal presentation regression attributable to the cohort.
- RMF/provider accounting: an unexplained accounting shift beyond the expected regular `remoteMessageShown` reduction, including inconsistent provider shown/seen/dismissed/cooldown/impression behavior.
- Manual reproduction: any required manual scenario is still pending at the first cohort, or reproduces flag-off behavior change, simultaneous modal/RMF admission, stale ownership, incorrect cooldown, or failed startup-latched enable/disable behavior.
- Support reports: new or sustained user reports plausibly connected to promo overlap, missing RMF content, unexpected modal suppression, or relaunch-dependent behavior.

### External owners and follow-through

- Privacy-config review owner: `[OWNER REQUIRED — assign privacy-config reviewer]`
- Cohort deployment/rollout owner: `[OWNER REQUIRED — assign rollout DRI]`
- iOS release-confirmation owner: `[OWNER REQUIRED — confirm merged PRs and first containing version]`
- Manual-validation evidence owner: `[OWNER REQUIRED — user/project DRI to attach completed matrix]`
- Post-100% cleanup owner: `[OWNER REQUIRED — create and own separate cleanup task]`
- Agreed 100% soak/rollback window: `[PENDING — define duration before rollout]`

Create the separate cleanup task only after the flag has reached 100% of supported iOS users and the agreed soak window has completed without a hold criterion. Its scope may then remove the legacy source/accounting branches, duplicate legacy observer behavior, obsolete mode plumbing, and superseded tests. Any hold criterion during rollout or soak is a rollback trigger and blocks cleanup.

Rollback procedure: remotely disable `iOSPromoPresentationCoordination` in the authoritative privacy configuration, deploy that configuration, and then create a new process graph on affected devices because the mode is startup-latched. Record the rollback cohort/version and evidence; do not rely on a live in-process transition.
