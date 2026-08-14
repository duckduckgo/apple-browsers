# Promo Queue: simplified iOS implementation plan

## Objective

Implement [`tech_design_final.md`](tech_design_final.md) end to end from `bartosz/promo-q-simp-2`, replacing the broad coordination foundation from merged PR #6087 with a source-level gate that prevents launch-modal promos and NTP RMF cards from being admitted together.

The implementation is complete only when:

1. the coordinated behavior is implemented and verified;
2. internal diagnostics are available;
3. the stack has landed safely; and
4. `.promoPresentationCoordination` has been remotely rolled out to 100% of iOS users.

The three PRs deliver items 1–3. Item 4 is the externally owned privacy-configuration phase described at the end; an agent without that repository access and approval must hand it off rather than report the overall project complete.

## Starting point

- Starting branch: `bartosz/promo-q-simp-2`.
- At planning time this branch and local `main` both point to `f5b0e0abd4`.
- PR #6087 is already merged as `7fdd4719a1345c8805d3bbb9639c618f7dbb562d`.
- The working tree contains the untracked `promo-queue-docs/` directory. Preserve it and any other user changes.
- Only PR #6087 is an implementation baseline. Do not merge or wholesale cherry-pick the old `bartosz/promo-q-2` or `bartosz/promo-q-3` implementations. Small, already-reviewed pieces such as cooldown constants or storage semantics may be ported deliberately after comparing them with the final design.

Before editing, re-read the repository's `AGENTS.md` and only the relevant rules it permits. In particular, preserve existing pixels rather than defining new ones, use injected `ThrowingKeyValueStoring` for the RMF cooldown timestamp, and obtain the user's required permission before running tests or performing git write operations.

## Proposed stacked pull requests

Use three stacked PRs. This keeps the cleanup reviewable, gives the end-to-end behavior its own review, and leaves the internal debug change isolated as requested.

| Stack | Branch | Base while stacked | Purpose |
| --- | --- | --- | --- |
| PR 1 | `bartosz/promo-q-simp-2` | `main` | Phase zero cleanup plus the minimal app-scoped gate, cooldown policy, and modal foundation |
| PR 2 | `bartosz/promo-q-simp-3` | `bartosz/promo-q-simp-2` | Shared `HomePageConfiguration` RMF integration and end-to-end behavior |
| PR 3 | `bartosz/promo-q-simp-4` | `bartosz/promo-q-simp-3` | Existing debug-screen extension, manual-test support, and rollout readiness |

Create `bartosz/promo-q-simp-3` only from the reviewed head of `bartosz/promo-q-simp-2`. Create `bartosz/promo-q-simp-4` only from the reviewed head of `bartosz/promo-q-simp-3`. Open each stacked PR against the preceding branch so each diff contains only its phase. After a lower PR merges, rebase or update the next branch and retarget its PR to the new merged base.

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
- Existing RMF action/dismissal event definitions and metric checks remain unchanged; no new Promo Queue pixel is added. In coordinated mode, regular shown intentionally fires once per admitted ownership after actual appearance instead of preserving today's eager/repeated calls. Unique-shown is evaluated once per ownership and retains its existing first-ever-message guard.
- Legacy behavior remains available when `.promoPresentationCoordination` is disabled.
- No NTP renderer or covering overlay reports active/renderable/visible/covered state.
- No background or view-disappear signal releases RMF ownership.
- No timers, wait queues, renderer registries, retain counts, handoff state, or exact RMF removal state are introduced.

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

The RMF lease additionally exposes a main-actor `markShown()` operation that returns `true` only for the first valid confirmation of its current acquisition. It must return `false` after release, for a stale record, and on subsequent calls.

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

Only the first valid RMF `markShown()` records RMF history. Acquisition, denial, and release do not.

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

### 1.7 Focused PR 1 tests

Add or retain compact tests for:

#### Arbiter

- modal acquisition from idle;
- RMF acquisition from idle;
- each kind blocks the other;
- a second modal attempt is denied;
- a different RMF ID is denied while one owns the slot;
- duplicate release is harmless;
- stale release cannot clear a replacement;
- dropped tokens are recoverable; and
- first valid `markShown()` wins once.

#### Cooldown

- all three cross-kind/incoming-RMF boundaries;
- exact equality;
- no-history behavior;
- future timestamps;
- write failure remains authoritative in process; and
- read fallback behavior.

#### Service/manager

- RMF ownership prevents provider evaluation;
- RMF-to-modal cooldown prevents provider evaluation;
- when no provider is eligible, the manager releases its transferred modal lease and records no presentation history;
- RMF cooldown denial releases its temporary acquisition and leaves the arbiter unowned;
- committed presentation retains the lease;
- nested child presentation does not release it;
- exact-root detachment does release it;
- legacy mode uses the unchanged manager route;
- pending and active attempts continue to suppress dependent session promos; and
- a no-selection evaluation clears temporary suppression without erasing earlier presentation history.

Prefer one test per observable rule. Delete transition/surface fixtures rather than adapting them into another abstraction layer.

## PR 1 completion criteria

- No live feature-state or per-surface retry types remain.
- No NTP host accepts a promo coordinator solely for this feature.
- The app graph contains one startup-latched gate.
- The arbiter has one owner, not a dictionary of surface slots.
- Directional cooldown policy is independently tested.
- Modal-first correctness remains behind the disabled-by-default flag.
- Focused affected tests and an iOS build pass after obtaining permission to run them.
- The PR description clearly states that end-to-end RMF gating follows in the stacked PR and the production flag remains off.

---

# PR 2 — `bartosz/promo-q-simp-3`

## Branch point and goal

Create `bartosz/promo-q-simp-3` from the reviewed head of `bartosz/promo-q-simp-2`. Set its PR base to `bartosz/promo-q-simp-2` until PR 1 merges.

Goal: integrate RMF once at the shared `HomePageConfiguration` boundary and deliver the actual no-overlap behavior for all existing NTP renderers.

Suggested PR title: **iOS Promo Queue: Gate NTP RMF at the shared message source**

## Phase 2 — shared RMF integration

### 2.1 Inject the gate into the shared configuration

`HomePageConfiguration` is constructed once in `MainCoordinator` and passed to all three NTP render paths. Add the narrow `PromoGating` dependency there, not to each renderer.

Update the production initializer and test initializers with an inert/legacy default only if a default does not hide required production injection. Prefer explicit production injection and a small mock in tests.

Keep the existing `isStillOnboarding` closure. It is the correct RMF eligibility signal and is not interchangeable with a generic `hasSeenOnboarding` property.

Make all lease mutation main-actor isolated. If annotating the whole configuration `@MainActor` creates unnecessary call-site churn, isolate the message refresh/admission methods and prove all access stays serialized. Do not use locks around UI-owned state as a substitute for main-actor isolation.

### 2.2 Implement the centralized RMF ownership algorithm

Add one strongly retained current RMF lease and an opaque presentation context derived from its message ID and acquisition identity. Each RMF view-model callback captures that context. A same-ID refresh within one ownership keeps the same context valid; release followed by reacquisition of the same ID produces a new context. The configuration validates the context before appearance confirmation, coordinated dismissal, or lease mutation, so a callback from an outgoing physical view cannot act on a later ownership.

Implement one `endCurrentRMFOwnership`-style helper and use it for every terminal path. Its invariant is: remove the current RMF from shared `homeMessages`, synchronously signal all models to rebuild from that source, then release and clear the retained lease. A missing message or lease makes the corresponding operation a no-op.

During `buildHomeMessages` / `remoteMessageToShow`:

1. Build non-RMF home messages as today.
2. If onboarding suppresses RMF, run the teardown helper and return the non-RMF messages.
3. Fetch the current RMF candidate using the existing `afterIdle` fallback rules.
4. If no candidate exists, run the teardown helper and return the non-RMF messages.
5. If candidate ID equals the retained lease's message ID, reuse the lease, publish the refreshed shared content, and emit the content-change signal if that content changed.
6. If the ID differs, run the teardown helper for the old ID.
7. Ask the gate for the new message ID.
8. On success, retain the returned lease before publishing the candidate into shared `homeMessages`, then emit the content-change signal.
9. If admission fails, append nothing and do not mutate `RemoteMessagingStore`.

Keep the fetch, release/acquire, and `homeMessages` publication ordering synchronous on the main actor so a modal cannot interleave between the decision and publication.

Add one configuration-level change signal for the shared `homeMessages` value. Every `NewTabPageMessagesModel` observes that signal and rebuilds from the shared value without registering a renderer identity or re-running candidate selection. Emit it after publishing an admitted RMF, after a same-ID content update, and during teardown before lease release. This lets all model snapshots converge without reintroducing visibility or handoff coordination.

Do not create a lease for placeholder or non-RMF `HomeMessage` values.

### 2.3 Define same-ID and replacement semantics explicitly

- A same-ID configuration refresh is one continuous ownership. It bypasses a new cooldown check and retains its `markShown()` state.
- A different ID ends the old ownership before attempting the new ID.
- If the old message appeared, the new message must pass RMF-to-RMF cooldown.
- If the old message never appeared, releasing it writes no history; the new message can acquire if the slot is otherwise free.
- If the new message is denied, the store remains authoritative and a later natural refresh can retry it.

Add direct tests for `afterIdle` versus no-trigger selection so shared ownership does not accidentally break current fallback behavior.

### 2.4 Move coordinated shown accounting to actual appearance

In `NewTabPageMessagesModel`, retain the existing `HomeMessageViewModelBuilder` `onDidAppear` callback and remove coordinated eager map-time appearance accounting. When mapping an RMF, capture the opaque context supplied by the configuration in its appearance and dismissal closures. The model forwards but does not interpret that value.

In `HomePageConfiguration.didAppear`:

1. In legacy mode, preserve the current path deliberately.
2. In coordinated mode, require a current lease matching both the RMF ID and captured acquisition identity.
3. Call `markShown()` with that validated context.
4. Only when it returns `true`, fire the regular `remoteMessageShown` event once, then run the existing first-ever-message guard for `remoteMessageShownUnique` and its store update.
5. Ignore stale, mismatched, repeated, or post-release callbacks.

Do not add a new pixel or parameter. Preserve existing metric-enabled checks and randomized subscription parameters. Document the intentional coordinated-mode frequency change: mapping no longer fires an impression, the first actual appearance fires regular shown once for that ownership, and unique-shown still emits only for the message's first-ever shown transition. The flag-off path retains today's behavior.

Because the configuration is shared, appearance callbacks from a second physical mount of the same message reach the same lease and do not start queue history again.

### 2.5 Release from message lifecycle only

Release when a refresh observes:

- successful dismissal;
- expiry/removal from scheduled messages;
- replacement by a different message ID;
- onboarding suppression; or
- no eligible candidate.

Before starting coordinated dismissal, validate the callback's message ID and acquisition identity. Keep that ownership authoritative while the asynchronous store dismissal is in flight; a refresh may not release and reacquire the same RMF underneath it. After the store operation finishes, validate the context again, then unpublish the shared RMF, emit its content-change signal, and release ownership in that order. A callback that was already stale when invoked must not mutate the store or current lease. Continue posting/observing `remoteMessagesDidChange` so later candidate state is refreshed; do not use that notification as a substitute for removing the currently owned message before release.

Do not release from:

- `viewDidDisappear`;
- SwiftUI `onDisappear`;
- tab switching;
- suggestion-tray/unified-input handoff;
- window detachment;
- app backgrounding; or
- Fire-mode/landscape layout changes.

Do not add a retain count. `HomePageConfiguration`, not a physical renderer, owns the lease.

### 2.6 Keep retry checkpoint-driven

Do not register every NTP model for retries. A blocked RMF is reconsidered on:

- initial model load;
- `HomePageConfiguration.refresh`;
- `remoteMessagesDidChange`;
- an `afterIdle` refresh;
- creation of another renderer using the shared configuration; or
- a later RMF admission attempt that reconciles a detached modal.

Modal work remains a foreground operation and is not immediately retried when RMF ownership ends.

Do not add a service-to-configuration release callback in this stack. If checkpoint-driven retry proves insufficient in production, treat that as evidence for a separately reviewed design amendment; it is not permission to add a release publisher, renderer registration, or retry ordering during implementation.

### 2.7 Update protocols and test doubles

Adjust `HomePageMessagesConfiguration` only as much as needed to supply and round-trip the opaque presentation context and express the coordinated/legacy accounting branch. If a mode property is added, provide an explicit legacy default for previews and unrelated mocks. Do not expose the lease itself to `NewTabPageMessagesModel`.

Remove obsolete `MockNewTabPagePromoCoordinator`. Add a small `MockPromoGate` capable of:

- selecting mode;
- granting or denying RMF acquisition;
- returning controllable identity-safe leases; and
- exposing acquisition/confirmation/release calls for assertions.

Avoid mocks that reproduce the production state machine.

### 2.8 Focused PR 2 tests

#### `HomePageConfigurationTests`

- free slot publishes the RMF only after acquisition;
- modal owner suppresses publication;
- cooldown denial suppresses publication;
- denial does not dismiss, mark shown, or consume the scheduled message;
- same ID reuses one lease;
- different ID releases old ownership and attempts a new acquisition;
- `nil`, dismissal, expiry, and onboarding suppression release;
- backgrounding alone does not release;
- a never-appeared message releases without writing history;
- first real appearance confirms once and fires regular shown once per ownership;
- unique-shown retains first-ever-message behavior across later ownerships;
- stale/mismatched appearance is ignored;
- release and reacquisition of the same ID gives new callbacks a new context, while old appearance/dismissal callbacks are ignored;
- ownership remains authoritative across an in-flight asynchronous dismissal;
- `afterIdle` selection and fallback remain unchanged; and
- feature-off path remains legacy.

#### `NewTabPageMessagesModelTests`

- coordinated mapping does not eagerly report appearance;
- `onDidAppear` and dismissal closures forward the context captured at mapping time rather than looking up the current acquisition when invoked;
- existing close/action/primary/secondary action behavior and pixels are unchanged;
- remote-message notifications refresh gated state; and
- configuration-level change signals make multiple models converge on the same gated source without per-renderer registration or recursive candidate refresh.

#### Cross-component tests

- RMF first: foreground modal evaluation never queries providers.
- Modal evaluating/committed/visible first: RMF never enters `homeMessages`.
- No modal provider: the manager releases its transferred lease with no history.
- Detached modal root is lazily reconciled before a later RMF attempt.
- Same shared configuration used by two or more models does not need separate ownership and confirms one queue appearance.
- Removing a shared RMF publishes the source change before releasing ownership.

Do not add real-UIKit tests for all three hosts. One integration test can prove the shared instance is passed through the composition root; manual QA covers physical entry points.

## Phase 2 manual validation

Use the existing feature-flag override and RMF internal tooling. Because mode is startup-latched, force-quit after changing the flag.

Validate:

1. Flag off: current modal and RMF behavior is unchanged.
2. RMF first: open a card, foreground the app, and confirm no launch-modal provider is evaluated/presented.
3. Modal first: commit a modal, open/refresh NTP beneath it, and confirm no RMF flashes.
4. No eligible modal: confirm the temporary modal acquisition does not strand the slot.
5. Dismissed modal: confirm lazy reconciliation at the next checkpoint and observe the incoming RMF cooldown.
6. RMF dismissal, expiry, and replacement: confirm source-level release/reacquisition.
7. Standard NTP, suggestion tray favorites, and unified-input/address-bar favorites: confirm all consume the same gated result with no host callbacks.
8. `afterIdle` message selection.
9. Onboarding suppression.
10. Fire tab and constrained landscape: confirm the accepted invisible over-hold and no crash.
11. Leave the NTP and background/foreground: confirm the accepted RMF over-hold blocks modal admission while the message remains active.
12. Relaunch: confirm live owner resets while persisted cooldown remains.

## PR 2 completion criteria

- The feature goal works end to end when the flag is enabled.
- `HomePageConfiguration` is the only current RMF lease owner.
- No NTP host, overlay, or physical renderer reports visibility.
- A blocked card never enters `homeMessages` and never records accounting.
- Same-ID ownership and first appearance are deterministic at the shared source.
- Accepted background/offscreen over-hold is covered or documented.
- Focused affected tests and an iOS build pass after obtaining permission.
- No new telemetry exists.

---

# PR 3 — `bartosz/promo-q-simp-4`

## Branch point and goal

Create `bartosz/promo-q-simp-4` from the reviewed head of `bartosz/promo-q-simp-3`. Set its PR base to `bartosz/promo-q-simp-3` until PR 2 merges.

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

- formatting each owner kind;
- startup mode and relaunch text;
- RMF appearance state;
- cooldown boundary formatting;
- Refresh reading new state;
- unavailable dependency behavior; and
- RMF cooldown reset changing eligibility immediately while leaving ownership untouched.

Avoid snapshot tests unless layout complexity genuinely warrants them.

## PR 3 completion criteria

- The existing screen exposes every state needed for the manual matrix.
- Passive debug reads do not mutate production history or ownership; only the explicitly labeled reset actions mutate their matching cooldown history, and neither changes ownership.
- Any reset is explicit and internal-only.
- No telemetry or production retry behavior is added.
- Focused debug tests and an iOS build pass after obtaining permission.
- The PR description includes the complete manual validation matrix and rollout caveats.

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

- Does any renderer or overlay need to know coordination exists? If yes, move the decision back to the shared source.
- Can provider evaluation occur before modal admission? It must not.
- Can an RMF enter `homeMessages` before admission? It must not.
- Can a stale context release, dismiss, or confirm the current owner, including a reacquired owner with the same message ID? It must not.
- Is an RMF cooldown written before actual appearance? It must not be.
- Does leaving the NTP or backgrounding release RMF? It must not.
- Is time passage alone scheduling work? It must not.
- Does the feature-off path still work after a fresh graph is built? It must.
- Did the change add telemetry? It must not.
- Are accepted limitations described consistently in code comments, tests, debug UI, and PR descriptions?

# External phase 4 — privacy-configuration rollout

Merging the stack completes the `apple-browsers` repository implementation, but it does not meet the project success criterion because the iOS flag is disabled by default. Rollout is a separate, externally approved change in [duckduckgo/privacy-configuration](https://github.com/duckduckgo/privacy-configuration), targeting parent feature `promoQueue` and subfeature `iOSPromoPresentationCoordination` (the remote source of `.promoPresentationCoordination`). Do not manually edit the generated `iOS/Core/ios-config.json` as the rollout mechanism.

The project/feature DRI owns this phase. The privacy-configuration repository's required reviewers approve and deploy its change, and the iOS release owner confirms the first app version containing all three PRs. Set that version as the rollout's minimum supported version so the flag cannot enable code that is absent.

If the implementation agent has access to the privacy-configuration repository and explicit authorization to make that external change, continue there. Otherwise, create or update the project rollout task with:

- links to the three merged PRs and the first containing iOS version;
- the exact parent/subfeature keys above;
- the completed automated and manual validation record;
- the startup-latched relaunch caveat;
- the proposed cohort stages and hold criteria; and
- the feature DRI, privacy-config reviewer, and iOS release owner assignments.

Do not claim the product success criterion complete while that handoff is pending.

## Rollout execution

1. Land the three code PRs in stack order and ship a build containing the full stack with the remote kill switch available.
2. Complete the Phase 2 manual matrix in internal/ad-hoc builds and verify the Phase 3 diagnostics on a fresh process.
3. Open the privacy-configuration change that enables `promoQueue.iOSPromoPresentationCoordination` only for the first containing app version and later. Use staged rollout steps of 5%, 25%, 50%, and 100% unless the rollout DRI selects a more conservative sequence.
4. Obtain privacy-config review/approval and deploy the first stage.
5. Verify the deployed configuration version, confirm fresh eligible internal devices resolve the startup mode as `Coordinated` without a local override, and repeat the modal-first/RMF-first smoke cases.
6. At each hold, use existing crash/regression monitoring, RMF and provider accounting sanity checks, manual reproduction, and support reports. Interpret regular RMF shown counts with the documented coordinated-mode deduplication in mind; unique-shown keeps its first-ever semantics. No new telemetry is added for this rollout.
7. Advance only after the DRI records that the current stage meets the agreed hold criteria. Continue until the final rollout step is 100% for supported iOS versions.
8. To roll back, disable `iOSPromoPresentationCoordination` in privacy configuration and deploy that change. Because mode is startup-latched, the disable applies when an app next builds its process graph; force-quit/relaunch is the immediate manual mitigation.
9. Record the final configuration version, app version, deployment date, and 100% verification in the project task. That record closes the stated success criterion.

If rollout finds unacceptable modal starvation from active-message over-hold, the first follow-up to consider is a single shared source-level release checkpoint. Do not restore renderer exposure reporting without new product evidence that the simpler model cannot meet the requirement.

# Final definition of done

- All three stacked PRs are merged.
- The final implementation matches `tech_design_final.md`.
- The broad PR #6087 transition/surface machinery has been removed or reduced to final-design behavior.
- Focused automated and manual validation has passed.
- The existing debug screen can explain current owner and cooldown state.
- No new telemetry was added.
- The coordinated flag has reached 100% of supported iOS users.
- Maintainers can add a new NTP renderer without adding Promo Queue integration, and can add a new independent promo source through one source-level admission seam rather than host visibility callbacks.
