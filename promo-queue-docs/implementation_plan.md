# Promo Queue: simplified iOS implementation plan

## Objective

Implement [`tech_design_final.md`](tech_design_final.md) end to end from `bartosz/promo-q-simp-2`, replacing the broad coordination foundation from merged PR #6087 with a source-level gate that prevents launch-modal promos and NTP RMF cards from being admitted together.

The local implementation handoff is complete when:

1. the coordinated behavior is implemented and verified;
2. internal diagnostics are available;
3. the three local branch diffs are clean, focused, and ready for human review; and
4. rollout requirements and evidence are recorded for the external owner.

The project success criterion is broader: humans must later review and merge the stack, ship it, and remotely roll `.promoPresentationCoordination` out to 100% of supported iOS users. This plan records that follow-through but does not authorize the implementation agent to push, open PRs, merge, or edit the external configuration repository.

## Review validation update — 2026-08-14

This revision applies the validated review findings: cold-start RMF deferral, one configuration-owned store observer and source signal, trigger pinning, explicit appearance-to-history wiring, pre-admission renderability, per-acquisition SwiftUI identity, accurate dismissal/unique-shown guarantees, background release, current repository state, and Xcode project membership. The automated matrix is intentionally focused on architectural seams rather than exhaustive lifecycle permutations.

## Product decisions confirmed — 2026-08-15

- **Modal scope:** “modal sheets” means launch-promo providers routed through `PromoCoordinationService`, not every UIKit sheet. The stack deliberately does not intercept arbitrary presentations; any future expansion requires a separately reviewed architecture change.
- **NTP integration seam:** `prepareForNTP(openedAfterIdle:)` is the only new Promo Queue-specific method called by an NTP container, once per content activation before its initial eligibility read. A conditional container may also observe the shared content publisher as normal data-source wiring. It must not acquire/release leases or report visibility, coverage, handoff, or lifecycle state.
- **Mixed triggers:** keep the first admitted message and trigger lane pinned while that ownership remains valid. Later renderer loads do not replace it.
- **Persistence semantics:** retain best-effort dismissal and unique-shown behavior. Do not widen the store API, add an in-process/cross-process unique reservation, or add telemetry.

## Starting point

- Starting branch: `bartosz/promo-q-simp-2`.
- At the 2026-08-14 review checkpoint, HEAD is `7858a17094d8` and local `main` is `375bd10e56c5`; the branch is 2 commits ahead and 7 commits behind local `main`. Before this documentation revision the working tree was clean; the expected current edits are `tech_design_final.md` and `implementation_plan.md`.
- PR #6087 is already merged as `7fdd4719a1345c8805d3bbb9639c618f7dbb562d`.
- The five files under `promo-queue-docs/` are tracked. Preserve them and any other user changes.
- Only PR #6087 is an implementation baseline. Do not merge or wholesale cherry-pick the old `bartosz/promo-q-2` or `bartosz/promo-q-3` implementations. Small, already-reviewed pieces such as cooldown constants or storage semantics may be ported deliberately after comparing them with the final design.

Before editing, re-read the repository's `AGENTS.md` and only the relevant rules it permits. Run a read-only status/divergence preflight. Because the starting branch is behind `main`, present the exact divergence and obtain permission before rebasing, merging, creating branches, running tests, or performing any other git write. Preserve the branch's two unique commits whichever synchronization strategy the user chooses.

All implementation changes must remain local on the appropriate stack branch. Do **not** push branches, open pull requests, retarget pull requests, or make changes in external repositories. Commits and local branch creation also require the permission mandated by repository instructions. Preserve existing pixels rather than defining new ones and use injected `ThrowingKeyValueStoring` for the RMF cooldown timestamp.

## Proposed PR-sized local stack

Use three stacked, locally reviewable units. They are sized as eventual pull requests, but this plan authorizes no push or PR action. This keeps the cleanup reviewable, gives the end-to-end behavior its own review, and leaves the internal debug change isolated as requested.

| Review unit | Local branch | Local parent | Purpose |
| --- | --- | --- | --- |
| PR 1 | `bartosz/promo-q-simp-2` | `main` | Phase zero cleanup plus the minimal app-scoped gate, cooldown policy, and modal foundation |
| PR 2 | `bartosz/promo-q-simp-3` | `bartosz/promo-q-simp-2` | Shared `HomePageConfiguration` RMF integration and end-to-end behavior |
| PR 3 | `bartosz/promo-q-simp-4` | `bartosz/promo-q-simp-3` | Existing debug-screen extension, manual-test support, and rollout readiness |

After permission for git writes, create local `bartosz/promo-q-simp-3` only from the reviewed head of `bartosz/promo-q-simp-2`. Create local `bartosz/promo-q-simp-4` only from the reviewed head of `bartosz/promo-q-simp-3`. Keep each branch diff limited to its unit and hand off the local stack for human review. Do not push or open PRs.

If PR 2 proves smaller than expected, do not fold it into PR 1 merely to reduce the PR count: the distinction between coordination primitives and the behavior-changing RMF integration is useful. Split PR 2 further only if implementation uncovers an independent prerequisite that can be correct and testable on its own; do not split by arbitrary file count.

## Invariants to preserve throughout the stack

- All coordinated admission and lease mutation is main-actor, synchronous, and non-yielding.
- Modal admission happens before provider evaluation.
- RMF admission happens before a remote message enters `homeMessages`.
- One owner exists at most: modal or RMF.
- A blocked RMF remains scheduled and records no shown, dismissed, action, or cooldown state.
- A never-appeared admitted RMF records no shown or cooldown state.
- A stale or duplicate ownership context cannot release, dismiss, or confirm a replacement owner, including when the replacement has the same message ID.
- Existing launch-source, presented-controller, provider order, onboarding, modal-to-modal cooldown, and provider accounting behavior remains with its current owner.
- Existing pending/active modal suppression and actual-presentation session history remain observable through `RecentModalPromptStatusProviding`.
- Existing RMF action/dismissal event definitions and metric checks remain unchanged; no new Promo Queue pixel is added. In coordinated mode, regular shown intentionally fires once per admitted ownership after actual appearance instead of preserving today's eager/repeated calls. Unique-shown retains the existing best-effort first-ever guard; exact-once behavior across rapid reacquisitions is not added.
- Legacy behavior remains available when `.promoPresentationCoordination` is disabled.
- No NTP renderer or covering overlay reports active/renderable/visible/covered state.
- For the shared NTP RMF source, one `prepareForNTP` call per content activation, before the initial eligibility read, is the complete imperative Promo Queue integration. No container calls the gate, `markShown`, or lease release.
- The first admitted message and trigger lane remain pinned until the ownership becomes invalid or the app backgrounds.
- App backgrounding unpublishes the coordinated RMF and releases ownership through one app-scoped lifecycle path. Ordinary view disappearance does not release it.
- No timers, wait queues, renderer registries, retain counts, handoff state, or exact RMF removal state are introduced.
- Every added or removed Swift source, test, and mock has matching references and correct target membership in `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj`. Add shared mocks only to targets that consume them; prefer repurposing an existing file when its responsibility remains accurate.

---

# PR 1 — `bartosz/promo-q-simp-2`

## Goal

Replace the broad, partially merged foundation with the smallest reusable gate and cooldown primitives. Leave the branch compiling and behaviorally safe with the feature disabled. Do not integrate RMF publication yet; that belongs to the next PR.

Suggested PR title: **iOS Promo Queue: Simplify coordination foundation**

## Phase 0 — remove or collapse merged machinery

Phase zero is part of this PR, not a cleanup-only PR. Delete obsolete concepts before adding their replacements so old APIs do not shape the new design.

### 0.1 Remove live feature-transition state

Delete `iOS/DuckDuckGo/ModalPromptCoordination/PromoQueueFeatureState.swift` and remove the corresponding project-file entries.

In `iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift`, remove:

- the Combine feature-update subscription;
- `promoQueueFeatureStateCancellable`;
- pending target-state and transition-barrier state;
- `transitionPromoQueueFeature` and transition-only admission routes;
- lease invalidation on live flag changes; and
- tests and logging that exist only for live enable/disable transitions.

Replace the mutable state with an immutable `PromoCoordinationMode` selected by the factory at graph construction. A local debug override must state that relaunch is required.

In `ModalPromptCoordinationManager`, remove:

- `promoQueueWillTransition` / `promoQueueDidTransition`;
- legacy-root re-adoption used only when enabling live;
- transition-only attempt cleanup; and
- transition-only tests.

Keep only modal state needed during one process mode.

### 0.2 Remove per-surface RMF coordination APIs

Replace the contents and purpose of `iOS/DuckDuckGo/ModalPromptCoordination/NewTabPagePromoCoordination.swift` with a narrow source-level gate contract, or rename the file if a clearer name keeps project organization understandable.

Delete these concepts:

- `VisiblePromoIdentity.surfaceID`;
- `NewTabPagePromoRetrying`;
- `NewTabPagePromoRetryRegistration`;
- per-surface admission results;
- surface-slot occupancy;
- weak retry-registration arrays;
- registration ordering and retry passes; and
- mocks dedicated to those APIs.

Do not add replacement renderer registration, a list of listeners, or a generic overlay protocol.

### 0.3 Remove unused coordinator plumbing from NTP renderers

PR #6087 threaded `NewTabPagePromoCoordinating` through multiple controllers even though the merged `NewTabPageMessagesModel` does not yet use it. Remove that route rather than repurposing each host.

Inspect and update all affected construction paths, including:

- `iOS/DuckDuckGo/MainViewController.swift`;
- `iOS/DuckDuckGo/UICoordination/MainCoordinator.swift`;
- `iOS/DuckDuckGo/NewTabPageViewController.swift`;
- `iOS/DuckDuckGo/SuggestionTrayViewController.swift`;
- `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputContentContainerViewController.swift`;
- `iOS/DuckDuckGo/NewTabPageMessagesModel.swift`;
- `iOS/DuckDuckGo/NewTabPageView.swift` previews; and
- corresponding mocks and initializer tests under `iOS/SharedTestUtils` and `iOS/DuckDuckGoTests`.

Do not remove the already-shared `HomePageMessagesConfiguration` dependency. It is the integration seam used in PR 2.

### 0.4 Prune tests that encode the discarded architecture

Delete or rewrite tests whose only contract is:

- several RMF surface slots owning leases concurrently;
- surface IDs or occupying identities;
- retry registration and registration replacement;
- feature-transition barriers and re-entrant transition behavior;
- live enabling/disabling and root re-adoption; or
- broad real-UIKit transition behavior used only by live mode.

Keep focused existing coverage for provider order, provider accounting, exact-root attachment, nested modal roots, modal lease retention, idempotent release, and stale-token safety where those behaviors remain.

Do not preserve a large test merely because it was merged. Preserve a test only when it protects a final-design invariant.

## Phase 1 — implement the minimal coordination foundation

### 1.1 Add startup-latched mode

Add `PromoCoordinationMode` near the coordination primitives:

```swift
enum PromoCoordinationMode: Equatable {
    case legacy
    case coordinated
}
```

In `PromoCoordinationFactory`, read `.promoPresentationCoordination` once and inject the resolved mode into the service and any dependency that needs a feature-off branch.

Retain these existing flag definitions:

- `FeatureFlag.promoPresentationCoordination`;
- `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination`; and
- `PrivacyFeature.promoQueue` / `PromoQueueSubfeature.featureEnabled` where used by other platforms or shared code.

Do not subscribe to `FeatureFlagger.updatesPublisher` for this feature.

### 1.2 Rewrite `PromoQueueLeaseArbiter`

Keep the file and the idea, but collapse its state to one owner:

```text
none
modal(attempt identity + acquisition identity)
remoteMessage(message ID + acquisition identity + appearance-confirmed bit)
```

Implement typed modal and RMF leases unless one generic token is demonstrably clearer. Both must:

- release idempotently;
- validate the acquisition identity before changing arbiter state;
- become inert after release;
- reject stale release after a replacement acquisition; and
- allow the arbiter to recover a record whose weak token deallocated.

The raw RMF arbiter token exposes a main-actor `confirmAppearance()` operation that returns `true` only for the first valid confirmation of its current acquisition. It must return `false` after release, for a stale record, and on subsequent calls. It does not persist history or fire events.

Expose a small read-only snapshot for tests/debugging. Do not include renderer, registration, handoff, drain, presentation, or removal identities.

Remove `invalidateAllLeases`; startup-latched mode does not need it.

### 1.3 Add the directional cooldown policy and RMF history store

Create a minimal file under `iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/`, based on the reviewed behavior from the discarded branch rather than copying its debug machinery wholesale.

Implement:

- incoming RMF after modal: 10 minutes;
- incoming RMF after RMF: 10 minutes;
- incoming modal after RMF: 24 hours; and
- modal after modal: leave to the existing remotely configured `PromptCooldownManager`.

Use the existing confirmed-modal timestamp source and add one injected `ThrowingKeyValueStoring`-backed last-confirmed-RMF timestamp. Keep the storage key stable if porting the old implementation:

`com.duckduckgo.promo-queue.last-confirmed-remote-message-timestamp`

Use an injected clock. Define exact-boundary behavior (`now == nextEligibility` is eligible) and future-timestamp behavior. Keep production storage reads/writes failure-tolerant and test their in-process fallback semantics.

The history component exposes the narrow record/read/reset behavior needed by the service and later diagnostics. The arbiter does not call it. Acquisition, denial, raw confirmation, and release alone do not record RMF history.

Do not add a timer or persist the current owner.

### 1.4 Simplify `PromoCoordinationService`

Keep `PromoCoordinationService` as the single app-scoped facade.

Its modal path must:

1. retain existing launch-source and unrelated-presented-controller gates;
2. use the legacy manager path when mode is `.legacy`;
3. lazily reconcile a previously attached exact root in coordinated mode;
4. acquire a modal lease before provider evaluation;
5. evaluate RMF-to-modal cooldown before provider evaluation;
6. release directly and immediately when cross-promo cooldown denies admission; and
7. otherwise transfer lease ownership to the manager, which releases it if modal-to-modal cooldown/provider evaluation selects nothing or retains it when a modal is committed.

Its source-level RMF protocol must provide only what PR 2 needs:

- immutable mode;
- synchronous acquisition by message ID; and
- read-only diagnostic state if that is best exposed from the service.

Before RMF acquisition, reconcile a detached exact modal root. Then acquire the slot and evaluate the incoming RMF cooldown. If cooldown evaluation denies the request after acquisition, release that temporary acquisition synchronously before returning no lease. A denial must leave the arbiter idle unless another valid owner already existed.

On admission, return a small service-owned RMF lease wrapper that strongly retains the raw arbiter token and exposes one opaque, hashable acquisition identity. Its no-argument `markShown() -> Bool` calls `confirmAppearance()` and records RMF history exactly when that first confirmation succeeds. It stays nonthrowing and returns `true` for the first valid appearance even when durable persistence fails; the history component keeps the in-process value authoritative and logs/absorbs the storage error. Its release forwards to the raw token. This wrapper is the only connection between appearance confirmation and cooldown persistence; `HomePageConfiguration` later retains only the wrapper.

Do not add waiters, retry arrays, a release publisher, or surface-specific APIs. A caller will retry through natural configuration checkpoints.

### 1.5 Reduce `ModalPromptCoordinationManager` to retained modal correctness

Keep the existing provider-selection and legacy behavior. In coordinated mode, retain only the state needed to carry one lease through:

```text
idle -> evaluating -> committed -> presentationActive -> idle
```

Requirements:

- no provider query before the service has admitted the modal;
- when modal-to-modal cooldown or provider evaluation selects nothing, the manager releases its transferred lease synchronously and records no presentation history;
- the selected attempt retains the same identity through the presentation delay;
- a stale scheduled callback cannot mutate a replacement attempt;
- the exact selected root remains authoritative even if it presents a child; and
- reconciliation releases only after that exact root is detached or deallocated.

Preserve `didPresentModalPromptThisSession` semantics: pending or active attempts suppress dependent session promos; a completed presentation remains session history; and an evaluation that selects nothing returns to idle without erasing earlier presentation history. Do not add a pre-presentation cancellation mechanism solely for Promo Queue.

Keep `ModalPromptRootAttachmentChecker.swift` if it remains the smallest way to express exact-root reconciliation.

Remove the manager's direct arbiter dependency if it only existed for live feature re-adoption. The service acquires and transfers the token; from that call onward the manager must either release or retain the lease it was given. The service must not release it a second time based on the returned disposition.

Do not add dismissal callbacks to every modal provider in this iteration. Lazy reconciliation is the accepted simpler behavior.

### 1.6 Simplify composition

Update:

- `PromoCoordinationFactory.Dependency`;
- `iOS/DuckDuckGo/AppLifecycle/AppStates/Launching.swift`; and
- service/manager mocks.

Construct exactly one mode, arbiter, directional cooldown policy, RMF history component, manager, and service for the app graph. Retain the existing modal `PromptCooldownKeyValueFilesStore`/`PromptCooldownManager` graph separately; the directional policy reads its confirmed modal history and the new RMF history. Avoid duplicate policy/history instances in debug code or NTP previews.

Update `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` as part of the same change: remove build-phase/group references for deleted Swift files and add new source/test/mock files only to the targets that compile them.

### 1.7 Focused PR 1 tests

Keep this suite compact and table-driven where practical:

- Arbiter: cover cross-kind mutual exclusion, identity-safe/idempotent release, weak-token recovery, and first valid `confirmAppearance()` in one small parameterized group.
- Cooldown: table-test the three new directional rules at just-before/equality/after boundaries, plus one focused storage-failure fallback test.
- Service/manager: prove providers are not queried when the slot or RMF-to-modal cooldown blocks them; prove no-selection releases; and preserve one exact-root/nested-child retention test and the legacy route.
- Service wrapper: with a real arbiter and spying history component, two `markShown()` calls record once, while stale or post-release confirmation records nothing; a durable-write failure still returns `true` once and leaves the in-process timestamp authoritative.

Delete transition/surface fixtures rather than adapting them into another abstraction layer. Add only a regression case when it protects behavior changed by this unit.

## PR 1 completion criteria

- No live feature-state or per-surface retry types remain.
- No NTP host accepts a promo coordinator solely for this feature.
- The app graph contains one startup-latched gate.
- The arbiter has one owner, not a dictionary of surface slots.
- Directional cooldown policy is independently tested.
- Modal-first correctness remains behind the disabled-by-default flag.
- Focused affected tests and an iOS build pass after obtaining permission to run them.
- Local handoff notes state that end-to-end RMF gating follows on `bartosz/promo-q-simp-3` and the production flag remains off.

---

# PR 2 — `bartosz/promo-q-simp-3`

## Branch point and goal

After permission for git writes, create local `bartosz/promo-q-simp-3` from the reviewed head of `bartosz/promo-q-simp-2`. Keep its diff relative to `bartosz/promo-q-simp-2`; do not push or open a PR.

Goal: integrate RMF once at the shared `HomePageConfiguration` boundary and deliver the actual no-overlap behavior for all existing NTP renderers.

Suggested PR title: **iOS Promo Queue: Gate NTP RMF at the shared message source**

## Phase 2 — shared RMF integration

### 2.1 Inject the gate into the shared configuration

`HomePageConfiguration` is constructed once in `MainCoordinator` and passed to all three NTP render paths. Add the narrow `PromoGating` dependency there, not to each renderer.

Update the production initializer and test initializers with an inert/legacy default only if a default does not hide required production injection. Prefer explicit production injection and a small mock in tests.

Keep the existing `isStillOnboarding` closure. It is the correct RMF eligibility signal and is not interchangeable with a generic `hasSeenOnboarding` property.

Make all lease mutation main-actor isolated. If annotating the whole configuration `@MainActor` creates unnecessary call-site churn, isolate the message refresh/admission methods and prove all access stays serialized. Do not use locks around UI-owned state as a substitute for main-actor isolation.

In coordinated mode, change initialization to build only non-RMF messages. Do not fetch or acquire RMF during `MainCoordinator` construction. Add one source-level operation, named to expose its side effect (for example, `prepareForNTP(openedAfterIdle:)`), that arms RMF admission and performs selection.

Call it only at existing content-loading seams:

- replace the standard NTP's existing `HomePageConfiguration.refresh` call in `MainViewController.attachHomeScreen`;
- call it immediately before suggestion tray's existing `canShow(.favorites)` / `hasRemoteMessages` eligibility read; and
- call it once at unified input's activation/content-loading seam, before `activationResolveTrigger.send(())`; keep the `hasMessages` closure a pure read.

These two conditional-host calls are required to bootstrap RMF-only content before those hosts construct a messages model. They are not visibility, lease, or disappearance callbacks. Do not add them to leaf views.

Treat this as the complete NTP-container integration contract. Containers do not call `tryAcquire`, `markShown`, or `release`; they do not report active/renderable/visible/covered state; and they do not forward background or disappearance to Promo Queue. The shared configuration, service, existing messages model, and one composition-root lifecycle hook own everything else. If implementation requires another container callback, stop and move that responsibility into the shared source.

Route app lifecycle once through the composition root: `Background.onTransition` → `MainCoordinator.onBackground` → `HomePageConfiguration.handleAppBackgrounded`, and `Foreground.onTransition` → `MainCoordinator.onForeground` → `HomePageConfiguration.handleAppForegrounded`. Foreground handling only marks the source active; it neither arms selection nor publishes RMF. Do not create an RMF/model `viewDidDisappear` signal; none exists today and the final design does not need one.

### 2.2 Implement the centralized RMF ownership algorithm

In coordinated mode, make `HomePageConfiguration` the sole observer of global `remoteMessagesDidChange`. After updating `homeMessages`, emit a distinct, object-scoped configuration publisher. `NewTabPageMessagesModel` observes that publisher and only rebuilds from the shared value; it must not select another candidate. Keep the current global-notification behavior behind the legacy branch.

Update direct consumers to react only after the shared source changes:

- merge the configuration publisher into unified input's existing search-state reevaluation; and
- replace or branch `OmniBarEditingStateViewController`'s direct store-notification observation so its existing initial-suggestions and Dax-visibility updates run from the configuration signal in coordinated mode.

Do not republish `remoteMessagesDidChange` as the configuration signal; that would make update order and recursion ambiguous. Config-signal sinks reevaluate already-published state and must not call `prepareForNTP` from inside `hasMessages` or another publisher mapping closure.

Add one strongly retained service-owned RMF lease wrapper, the trigger lane that selected it, the last explicitly prepared trigger lane, and an opaque presentation context derived from the message ID and acquisition identity. Explicit preparation updates `lastPreparedTriggerLane`; clear it on background. Implement one `endCurrentRMFOwnership` helper whose ordering is always: remove the coordinated RMF from `homeMessages`, emit the configuration signal, then release and clear the lease, owner-pinned trigger, and context. Ordinary ownership teardown does not clear `lastPreparedTriggerLane`, allowing a later armed store refresh to use the most recent explicit request.

During an armed preparation or coordinated store refresh:

1. Build non-RMF home messages as today.
2. If onboarding suppresses RMF, run the teardown helper and return the non-RMF messages.
3. If the current owner remains scheduled and renderable in its pinned trigger lane, reuse it, publish any refreshed same-owner content, and stop fresh selection. Ignore a later renderer's competing trigger for this ownership.
4. Otherwise tear down the invalid owner, then fetch using the current explicit request or, for a store-driven refresh, `lastPreparedTriggerLane`, with the existing fallback rules.
5. If no renderable candidate exists, publish only non-RMF content.
6. Ask the gate for the new message ID.
7. On success, retain the lease, selected trigger lane, and new ownership context before publishing the candidate and emitting the configuration signal.
8. If admission fails, append nothing and do not mutate `RemoteMessagingStore`.

Keep the fetch, release/acquire, and `homeMessages` publication ordering synchronous on the main actor so a modal cannot interleave between the decision and publication.

### 2.3 Define same-ID and replacement semantics explicitly

- A same-ID refresh in the pinned trigger lane is one continuous ownership. It bypasses a new cooldown check and retains its appearance state and acquisition identity.
- A preparation from another renderer with a different trigger cannot replace a valid owner. The first admitted trigger lane remains authoritative until that ownership ends.
- A different ID ends the old ownership before attempting the new ID.
- If the old message appeared, the new message must pass RMF-to-RMF cooldown.
- If the old message never appeared, releasing it writes no history; the new message can acquire if the slot is otherwise free.
- If the new message is denied, the store remains authoritative and a later natural refresh can retry it.

Do not define same-ID joining for a future independent RMF source in this iteration. Such a source needs a separately reviewed source-level lifecycle contract.

### 2.4 Reject unrenderable content and reuse acquisition identity in SwiftUI

Add a pure `HomeMessageViewModelBuilder.canBuild(for:)` (or equivalently named) check that uses the builder's existing content-to-display conversion. Call it before RMF acquisition. Missing content and unsupported `.cardsList` content must acquire no lease, publish no card, and mutate no store state. Do not maintain a second independent support switch.

Use the public wrapper's acquisition identity for both callback validation and SwiftUI diffing; do not mint a second presentation UUID. Carry it opaquely through `HomeMessageViewModel`, keep it stable across same-owner refreshes, and key coordinated RMF content by message plus acquisition identity. A release/reacquisition naturally produces a new identity even for the same message ID. Preserve current identity behavior for legacy and non-RMF messages.

### 2.5 Move coordinated shown accounting to actual appearance

In `NewTabPageMessagesModel`, retain the existing `HomeMessageViewModelBuilder` `onDidAppear` callback and remove coordinated eager map-time appearance accounting. When mapping an RMF, capture the opaque context supplied by the configuration in its appearance and dismissal closures. The model forwards but does not interpret that value.

In `HomePageConfiguration.didAppear`:

1. In legacy mode, preserve the current path deliberately.
2. In coordinated mode, require a current lease matching both the RMF ID and captured acquisition identity.
3. After configuration validation succeeds, call the service-owned lease wrapper's no-argument `markShown()`. That wrapper independently rejects stale raw state, confirms with the arbiter, and records RMF cooldown history only on the first valid confirmation.
4. Only when it returns `true`, fire the regular `remoteMessageShown` event once, then run the existing best-effort first-ever guard for `remoteMessageShownUnique` and its store update.
5. Ignore stale, mismatched, repeated, or post-release callbacks.

Do not add a new pixel, parameter, or in-process unique-shown reservation. Preserve existing metric-enabled checks and randomized subscription parameters. Mapping no longer fires an impression; the first actual appearance fires regular shown once for that ownership. Because the store's unique check and asynchronous update are not atomic, rapid same-ID reacquisition may still duplicate unique-shown. The flag-off path retains today's behavior.

Because the configuration is shared, appearance callbacks from a second physical mount of the same message reach the same lease and do not start queue history again.

### 2.6 Implement terminal and background teardown

Release when a refresh observes:

- completion of a dismissal attempt;
- expiry/removal from scheduled messages;
- replacement by a different message ID;
- onboarding suppression; or
- no eligible or renderable candidate.

Before starting coordinated dismissal, validate the callback's message ID and acquisition identity. A callback already stale before the await does nothing and must not call the store. Normally keep a validly started ownership authoritative while asynchronous `dismissRemoteMessage` runs. After the attempt completes, if the context is still current, run the ordered teardown; then preserve the existing single store-refresh notification. If background/reacquisition made the context stale, do not directly mutate the lease, but still trigger that notification once so the configuration-owned observer reconciles authoritative scheduled-message state. The store API returns `Void` and logs persistence failures, so do not claim a successful dismissal.

Background is the explicit exception to in-flight dismissal retention. On background:

1. mark RMF admission inactive/disarmed;
2. remove the coordinated RMF from `homeMessages`;
3. synchronously emit the configuration signal; and
4. release and clear its lease, both trigger values, and presentation context without recording new history.

An outstanding dismissal completion then fails context validation and cannot directly release or confirm a newer lease. The already-started store operation may still change scheduled-message state; its notification is reconciled normally and may make a reacquired same-ID owner ineligible. Do not add cancellation or reservation machinery. Store notifications while inactive may update non-RMF state but must not reacquire RMF. Foreground only re-enables a future explicit `prepareForNTP`; it must not automatically publish RMF.

Do not release from:

- `viewDidDisappear`;
- SwiftUI `onDisappear`;
- tab switching;
- suggestion-tray/unified-input handoff;
- window detachment; or
- Fire-mode or layout changes.

Do not add a retain count. `HomePageConfiguration`, not a physical renderer, owns the lease.

### 2.7 Keep retry checkpoint-driven

Do not register every NTP model for retries. A blocked RMF is reconsidered on:

- explicit `prepareForNTP` from an NTP-capable path;
- a coordinated `remoteMessagesDidChange` while admission is armed;
- an `afterIdle` refresh;
- a later RMF admission attempt that reconciles a detached modal.

Modal work remains a foreground operation and is not immediately retried when RMF ownership ends.

Do not add a service-to-configuration release callback in this stack. If checkpoint-driven retry proves insufficient in production, treat that as evidence for a separately reviewed design amendment; it is not permission to add a release publisher, renderer registration, or retry ordering during implementation.

### 2.8 Update protocols, target membership, and test doubles

Adjust `HomePageMessagesConfiguration` only as much as needed to expose the configuration-scoped change publisher, supply and round-trip the opaque presentation context, and express the coordinated/legacy accounting branch. Its coordinated publisher must deliver model updates synchronously on the main actor; do not insert a `receive(on:)` hop before `NewTabPageMessagesModel` rebuilds. Host layout reactions may remain scheduled. Add the publisher to relevant mocks with an explicit inert value. If a mode property is added, provide an explicit legacy default for previews and unrelated mocks. Do not expose the lease itself to `NewTabPageMessagesModel`.

Remove obsolete `MockNewTabPagePromoCoordinator`. Add a small `MockPromoGate` capable of:

- selecting mode;
- granting or denying RMF acquisition;
- returning controllable identity-safe leases; and
- exposing acquisition/confirmation/release calls for assertions.

Avoid mocks that reproduce the production state machine.

For every added/deleted production file, test, or shared mock, update `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` file references and the exact app/test target memberships. Do not add a shared mock to every test target by default. Prefer keeping an existing file when its final responsibility and name remain honest.

### 2.9 Focused PR 2 tests

Prefer a handful of behavior groups over an edge-case matrix:

1. Cold start/restored website: coordinated initialization builds no RMF and holds no lease; the first explicit NTP preparation performs admission.
2. Shared refresh: one store notification causes one configuration selection, two models converge synchronously from its signal, and a direct host consumer reevaluates after the source changes without recursion. After an earlier denial with no owner, retry uses `lastPreparedTriggerLane`.
3. Trigger pinning: an admitted `afterIdle` owner survives a no-trigger renderer load (and the reverse case can share the same table); replacement occurs only after the pinned owner becomes invalid.
4. Admission boundary: modal ownership/cooldown and unsupported content prevent publication or store mutation; a free slot publishes only after acquisition.
5. Appearance identity/wiring: same-ownership refresh keeps acquisition identity, same-ID reacquisition changes it, and the real service wrapper writes history and regular shown once while stale callbacks do nothing. Retain one deterministic existing unique-guard test if that path changes; do not assert exact-once across acquisitions or test the asynchronous race.
6. Ordered teardown: table-drive dismissal-attempt completion, expiry/replacement, onboarding suppression, and background; assert unpublish/signal precedes release, background writes no new history and preserves confirmed history, and stale dismissal callbacks cannot directly mutate a newer lease while later store state is still reconciled.
7. Legacy regression: retain one focused action/dismissal/pixel test proving the feature-off path is unchanged.

Do not add real-UIKit tests for all three hosts, an exhaustive content-type suite, or landscape lifecycle tests. One composition assertion can prove the shared instance and central lifecycle hook; manual QA covers physical entry points.

## Phase 2 manual validation

Use the existing feature-flag override and RMF internal tooling. Because mode is startup-latched, force-quit after changing the flag.

Validate:

1. Flag off: current modal and RMF behavior is unchanged.
2. RMF first: in a cold/restored-NTP setup where RMF wins admission before the pending launch-modal checkpoint, confirm no launch-modal provider is evaluated or presented. Treat the reverse order as the modal-first case; do not background an already shown card for this ownership check because background intentionally releases it.
3. Modal first: commit a modal, open/refresh NTP beneath it, and confirm no RMF flashes.
4. No eligible modal: confirm the temporary modal acquisition does not strand the slot.
5. Dismissed modal: confirm lazy reconciliation at the next checkpoint and observe the incoming RMF cooldown.
6. RMF dismissal, expiry, and replacement: confirm source-level release/reacquisition.
7. Standard NTP, suggestion tray favorites, and unified-input/address-bar favorites: confirm all consume the same gated result with only the documented shared-source preparation calls and no per-renderer lease/visibility callbacks.
8. `afterIdle` message selection.
9. Onboarding suppression.
10. Fire tab: confirm current suppression behavior and that source ownership remains safe. Rotate through landscape as behavior discovery; confirm actual rendering and no crash without adding special lease handling.
11. Leave the NTP: confirm message ownership remains source-driven rather than tied to one renderer.
12. Background/foreground: confirm the card is unpublished before lease release, a background store update does not reacquire it, and a later explicit NTP preparation can reconsider the card. Confirm the launch modal reaches normal admission/cooldown evaluation; use a never-appeared RMF or reset/wait for the persisted RMF-to-modal cooldown before expecting provider evaluation.
13. Relaunch: confirm live owner resets while persisted confirmed cooldown history remains.

## PR 2 completion criteria

- The feature goal works end to end when the flag is enabled.
- `HomePageConfiguration` is the only current RMF lease owner.
- No NTP host, overlay, or physical renderer reports visibility.
- A blocked card never enters `homeMessages` and never records accounting.
- Same-ID ownership and first appearance are deterministic at the shared source.
- Cold launch cannot claim RMF before an NTP request, and background teardown releases it in the documented order.
- Focused affected tests and an iOS build pass after obtaining permission.
- No new telemetry exists.

---

# PR 3 — `bartosz/promo-q-simp-4`

## Branch point and goal

After permission for git writes, create local `bartosz/promo-q-simp-4` from the reviewed head of `bartosz/promo-q-simp-3`. Keep its diff relative to `bartosz/promo-q-simp-3`; do not push or open a PR.

Goal: make the simplified machinery easy to inspect and manually verify using the app's existing internal debug area, without changing production admission behavior.

Suggested PR title: **iOS Promo Queue: Add simplified coordination diagnostics**

## Phase 3 — extend the existing debug screen

### 3.1 Reuse current debug wiring

Extend:

- `iOS/DuckDuckGo/ModalPromptCoordination/DebugMenu/ModalPromptCoordinationDebugMenu.swift`;
- its registration in `iOS/DuckDuckGo/DebugScreensViewModel+Screens.swift`;
- `iOS/DuckDuckGo/DebugScreen.swift` dependencies; and
- the two debug construction paths in `MainViewController+Segues.swift` and `SettingsLegacyViewProvider.swift` as needed.

Do not create another production coordinator or cooldown store. Inject a read-only snapshot provider backed by the app-scoped service and the same stores used by production.

Update `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` for any new debug/test files and their exact internal app/test target memberships.

### 3.2 Add the simplified snapshot

Show:

- process mode (`Legacy` or `Coordinated`);
- a note that flag changes require relaunch;
- active owner (`None`, modal attempt ID, or RMF message ID/acquisition ID);
- modal phase (`Idle`, `Evaluating`, `Committed`, or `Presentation Active`);
- whether the current RMF ownership confirmed appearance;
- last confirmed modal appearance;
- last confirmed RMF appearance;
- next RMF eligibility;
- next modal eligibility; and
- optional last denial reason only if it naturally exists in the service.

Add a Refresh button. State clearly that eligibility dates do not schedule retries.

Do not display deleted concepts such as renderer count, eligible renderer, logical session, handoff, drain, removal ID, or exact removal terminal.

### 3.3 Manual-test controls

Keep the existing modal cooldown reset and add an explicit internal-only RMF cooldown reset because the production intervals are impractical for repeated manual validation. Route it through the same authoritative history component used by cooldown admission. It must:

- clear both the persisted RMF timestamp and any authoritative in-process fallback/cache;
- update the debug snapshot immediately;
- be clearly labeled as debug-only; and
- not release an active owner or dismiss a message.

Do not add force-modal, force-RMF, arbitrary owner mutation, or fake-visibility controls. Existing provider reset screens and Remote Messaging debug configuration remain the source of test content.

### 3.4 Debug tests

Add focused view-model/snapshot tests for:

- owner/mode/appearance formatting as one table-driven group;
- Refresh reading new state and unavailable-dependency behavior; and
- RMF cooldown reset changing eligibility immediately while leaving ownership untouched.

Avoid snapshot tests unless layout complexity genuinely warrants them.

## PR 3 completion criteria

- The existing screen exposes every state needed for the manual matrix.
- Passive debug reads do not mutate production history or ownership; only the explicitly labeled reset actions mutate their matching cooldown history, and neither changes ownership.
- Any reset is explicit and internal-only.
- No telemetry or production retry behavior is added.
- Focused debug tests and an iOS build pass after obtaining permission.
- Local handoff notes include the complete manual validation matrix and rollout caveats.

---

# Final stack verification

After all three branches are combined, perform one final review against the design rather than reviewing each PR in isolation.

## Static checks

Search the final diff and repository for discarded vocabulary and investigate every remaining result:

- `setPromoSurfaceActive`
- `setPromoSurfaceRenderable`
- `setPromoSurfaceVisible`
- `setPromoSurfaceCovered`
- `NewTabPagePromoSurfaceHandoff`
- `NewTabPagePromoRetrying`
- `NewTabPagePromoRetryRegistration`
- renderer generation, handoff, drain, and removal-terminal types
- `PromoQueueFeatureState`
- live `.promoPresentationCoordination` subscriptions

Some names may exist only on historical branches or docs; none should remain in the final production path.

Verify the final dependency graph contains one production arbiter/service and one shared `HomePageConfiguration` instance for the three NTP renderers.

Use `git diff --check` and the repository's normal lint/build checks. Run tests only after obtaining the permission required by repository instructions.

## Focused automated suites

Run the smallest targets that include:

- Promo Queue arbiter tests;
- directional cooldown tests;
- Promo Coordination service tests;
- Modal Prompt manager/root tests;
- `HomePageConfigurationTests`;
- `NewTabPageMessagesModelTests`;
- feature-flag mapping/default tests; and
- debug view-model tests.

Then run the normal iOS build/test coverage appropriate for a change spanning app composition and presentation, subject to the repository's test-permission rule. Do not compensate for removed architecture tests by recreating a similarly large suite under new names.

## Review checklist

- Does any renderer or overlay know about leases, ownership, visibility, coverage, or lifecycle coordination? It must not.
- Does an NTP container have any imperative Promo Queue integration beyond `prepareForNTP` once per content activation? It must not; move any additional coordination responsibility to the shared source.
- Can provider evaluation occur before modal admission? It must not.
- Can an RMF enter `homeMessages` before admission? It must not.
- Can a stale context release, dismiss, or confirm the current owner, including a reacquired owner with the same message ID? It must not.
- Is an RMF cooldown written before actual appearance? It must not be.
- Does ordinary NTP disappearance release RMF? It must not. Does app background unpublish and then release it? It must.
- Is time passage alone scheduling work? It must not.
- Does the feature-off path still work after a fresh graph is built? It must.
- Did the change add telemetry? It must not.
- Are accepted limitations described consistently in code comments, tests, debug UI, and local handoff notes?

# External phase 4 — rollout handoff only

The local implementation agent must not modify or push `duckduckgo/privacy-configuration`, open a configuration PR, deploy a cohort, or change a project tracker. Instead, record a handoff for the project/feature DRI containing:

- the three local branch names and, after human integration, placeholders for merged PR links and the first containing iOS version;
- parent feature `promoQueue` and subfeature `iOSPromoPresentationCoordination`, the remote source of `.promoPresentationCoordination`;
- the completed automated and manual validation evidence;
- the startup-latched relaunch caveat;
- a suggested 5% → 25% → 50% → 100% cohort sequence, subject to the rollout DRI;
- existing crash/regression, RMF/provider accounting, manual-reproduction, and support-report hold criteria; and
- named owners for privacy-config review, deployment, and iOS release confirmation.

The eventual external owner must set the first containing iOS version as the minimum supported version and must not use generated `iOS/Core/ios-config.json` as the rollout source. Rollback is the remote disable of `iOSPromoPresentationCoordination`; because mode is startup-latched, a new process graph is required. No new telemetry is added. Do not claim the product success criterion complete until the deployed flag reaches 100% of supported iOS users and that state is recorded.

# Definitions of done

## Local implementation handoff

- `bartosz/promo-q-simp-2`, local `bartosz/promo-q-simp-3`, and local `bartosz/promo-q-simp-4` contain the three clean review units; no branch was pushed and no PR was opened.
- The combined local diff matches `tech_design_final.md` and removes or reduces PR #6087 machinery to final-design behavior.
- Focused automated and manual validation has passed after obtaining required permission.
- The existing debug screen explains current owner and cooldown state.
- No new telemetry exists.
- A new NTP renderer can consume the shared source without visibility/coverage callbacks; only a conditional container that checks content before construction invokes the shared preparation seam.
- The rollout handoff is complete and clearly marked as external work.

## Project success criterion after human/external follow-through

- The three review units are reviewed, merged, and shipped.
- The coordinated flag reaches 100% of supported iOS users.
- The final rollout version and validation record are captured by the project owner.
