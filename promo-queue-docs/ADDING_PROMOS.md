# Adding Promo Queue Integrations on iOS

## Scope: iteration 1 is deliberately narrow

The iOS promo queue currently prevents one specific collision:

- launch-modal promos coordinated by `PromoCoordinationService`; and
- Remote Messaging Framework (RMF) cards rendered on an active New Tab Page (NTP).

It is a main-actor mutual-exclusion seam with one fixed directional cooldown policy, not a general promo scheduler. It does not coordinate badges, settings rows, notification bars, onboarding, Duck.ai sync promos, tab-switcher promos, or arbitrary UIKit presentations. It also does not share or replace the macOS promo queue.

`PromoType` currently has one supported case, `.remoteMessage`, in
[`PromoQueueLeaseArbiter.swift`](../iOS/DuckDuckGo/ModalPromptCoordination/Arbitration/PromoQueueLeaseArbiter.swift).
Do not add another case merely to make a new feature compile. A promo outside the launch-modal/NTP-RMF seam needs an explicit design decision covering its priority, visibility, lifecycle, accounting, and rollback behavior.

## The integration boundary

All coordination is `@MainActor`. The app-scoped `PromoQueueLeaseArbiter` is the only mutual-exclusion authority:

- a modal lease can exist only when there are no visible-promo leases;
- visible-promo leases can coexist across surfaces once the global RMF target cooldown allows a later appearance;
- one `(surfaceID, promoType)` slot can hold at most one promo;
- every lease is bound to a per-acquisition identity;
- dropped tokens are weakly tracked and pruned before snapshots or new acquisitions; and
- release is explicit, idempotent, and unable to clear newer state.

The arbiter owns no eligibility, priority, cooldown, RMF selection, persistence, view lifecycle, or retry policy. Consumers must not receive it directly. A separate service-owned cooldown policy/store owns the limited matrix and remains outside the arbiter and RMF framework.

## Iteration-one cooldown contract

| Previous confirmed appearance | Next requested appearance | Required elapsed time |
| --- | --- | --- |
| Modal | NTP RMF | fixed 10 minutes |
| NTP RMF | NTP RMF | fixed 10 minutes, global across IDs and NTP instances |
| NTP RMF | Modal | fixed 24 hours |
| Modal | Modal | existing remotely tunable `PromptCooldownManager` interval, currently/default 24 hours |

The service-owned component reuses the existing persisted modal timestamp and persists one last-confirmed-RMF timestamp. Both are source-event times, not expiry dates. A modal event is confirmed only at UIKit completion or adoption of the attached prepared root. An RMF event is confirmed only by the first `onAppear` of the matching admitted render session. Selection, mapping, lease acquisition alone, denial, pending work, withdrawal before appearance, and failed presentation never write history.

The exact boundary is eligible (`now >= timestamp + interval`), and a backward wall-clock change conservatively extends the wait. The 10-minute intervals and RMF-to-modal 24-hour interval are fixed production constants. Only modal-to-modal keeps existing remote tuning.

Before publishing inner RMF UI, admission retains one identity-bound global provisional reservation. This prevents two NTP instances or message IDs from both passing before either appears. The first matching appearance promotes the reservation to persisted RMF history; withdrawal first releases it without writing. Duplicate `onAppear`, physical remount, and same-ID refresh in one render session do not restart cooldown. A later admitted session, even for the same message, is a new appearance. After 10 minutes another RMF may appear while an earlier card remains visible, but every active RMF lease still blocks modal admission.

NTP code uses the narrow `NewTabPagePromoCoordinating` interface implemented by
[`PromoCoordinationService.swift`](../iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift):

```swift
var promoQueueFeatureState: PromoQueueFeatureState { get }
var promoQueueFeatureStatePublisher: AnyPublisher<PromoQueueFeatureState, Never> { get }

func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult
func releaseVisiblePromoAdmission(_ admission: PromoQueueVisiblePromoAdmission)
func cancelVisiblePromoCooldownRetry(for surfaceID: UUID)
func registerVisiblePromoRetry(
    for surfaceID: UUID,
    target: NewTabPagePromoRetrying
) -> NewTabPagePromoRetryRegistration
```

Always ask this service to admit visible content. `admitVisiblePromo` first reconciles the exact modal root through `ModalPromptCoordinationManager`, then performs the atomic arbiter acquisition. Calling `PromoQueueLeaseArbitrating.acquireVisiblePromoLease` from a feature would bypass that checkpoint and is incorrect.

The typed result is also significant:

- `.blockedByModal` is a real cross-surface conflict;
- a typed cooldown denial carries `nextEligibleDate` and is not a lease conflict;
- `.blockedByProvisionalReservation` means another RMF admission is waiting for its first appearance or withdrawal;
- `.occupiedSurfaceSlot` indicates that the surface still owns another identity;
- `.featureDisabled` and `.unavailableDuringTransition` are feature-state outcomes; and
- other denials must not be reported as modal/RMF collisions.

On the enabled/coordinated modal path, `PromoCoordinationService` follows the inverse rule: it runs its existing launch-source and UIKit/OmniBar gates, acquires a modal lease, and only then lets `ModalPromptCoordinationManager` evaluate providers. If acquisition is `.blockedByVisiblePromos`, the manager's provider-evaluation/presentation entry point and the providers must not be called; the earlier exact-root reconciliation checkpoint still applies. Feature off deliberately uses the legacy lease-free overload.

## Construction and injection

There must be exactly one arbiter and one service-owned directional cooldown policy/store per app coordination graph.

[`Launching.swift`](../iOS/DuckDuckGo/AppLifecycle/AppStates/Launching.swift) constructs `PromoQueueLeaseArbiter` beside the coordination service. The same instance is passed through `PromoCoordinationFactory.Dependency` in
[`PromoCoordinationFactory.swift`](../iOS/DuckDuckGo/ModalPromptCoordination/Factory/PromoCoordinationFactory.swift)
to the service and manager.

The production `PromoCoordinationService` initializer constructs `PromoQueueCooldownPolicy` from the same persisted `PromptCooldownStore` used by the modal manager plus `PromoQueueRemoteMessageCooldownKeyValueFilesStore`. The designated initializer accepts policy/scheduler doubles for tests. NTP code receives only `PromoQueueVisiblePromoAdmission`, which owns the lease and provisional reservation; never pass the policy or stores into the manager, provider, controller, model, or view.

`MainCoordinator` retains the service and passes it as the narrow `NewTabPagePromoCoordinating` dependency to `MainViewController`. That dependency must continue through all three NTP construction paths:

1. the standalone NTP built by `MainViewController.attachHomeScreen`;
2. the focused NTP built by `SuggestionTrayViewController` from `SuggestionTrayViewController.NewTabPageDependencies`; and
3. the cached favorites NTP built by `UnifiedInputContentContainerViewController`/`UnifiedSuggestionsHost`.

Relevant files are
[`MainCoordinator.swift`](../iOS/DuckDuckGo/UICoordination/MainCoordinator.swift),
[`MainViewController.swift`](../iOS/DuckDuckGo/MainViewController.swift),
[`SuggestionTrayViewController.swift`](../iOS/DuckDuckGo/SuggestionTrayViewController.swift), and
[`UnifiedSuggestionsHost.swift`](../iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsHost.swift).

Do not construct a second arbiter, introduce a `.shared` coordinator, store leases in user defaults, duplicate the existing modal timestamp, or inject the arbiter/cooldown store into a view or provider.

## NTP RMF admission and release

[`NewTabPageMessagesModel.swift`](../iOS/DuckDuckGo/NewTabPageMessagesModel.swift)
owns the candidate and admitted render session. `NewTabPageViewController` owns the stable `surfaceID`. The model may attempt admission only when all of these are true:

- the model is loaded and not torn down;
- the queue is enabled and not transitioning;
- the host says the NTP is logically active;
- the render location is ready;
- the controller is attached to a window;
- the matching outer RMF gate is in the SwiftUI render location; and
- no older render session for the surface is still retiring.
- the service has atomically granted the global provisional RMF cooldown reservation.

The outer `NewTabPageRemoteMessageGate` remains in
[`NewTabPageView.swift`](../iOS/DuckDuckGo/NewTabPageView.swift)
while an eligible candidate is blocked. It may render at zero height, but it is not the RMF card and must not account an appearance. Only after the service returns a lease may the model build and publish the inner `HomeMessageViewModel`.

Retain these lifecycle rules when changing or adding an NTP host:

- Treat logical activity as authoritative. A cached controller can be attached while covered by autocomplete, Duck.ai content, an overlay, or opacity.
- Use controller/window attachment only as a final safety condition.
- Keep the lease until the admitted inner view is no longer renderable.
- Give every physical SwiftUI gate mount its own UUID and balance appearance/disappearance by that identity.
- Prefer the inner view's `onDisappear` for release. Owner-driven withdrawal publishes removal first, then releases on the next main turn; reachable controller teardown is an idempotent safety path.
- Match both render-session and lease identity. A late callback from message A must not release message B.
- A same-ID refresh updates content while preserving the lease, render session, and recorded appearance.
- A matching first appearance confirms the provisional cooldown reservation once. Withdrawal before appearance releases it without a write.
- A changed-ID refresh withdraws the old inner UI, releases its exact lease after removal, and only then attempts the replacement.
- `load()` must stay idempotent. `tearDown()` must remove the RMF observer, deregister `NewTabPagePromoRetryRegistration`, and release admitted or retiring leases.
- Retry targets are weak, synchronous, and surface-specific. Dead registrations are pruned both on registration and after retries, even if the feature is disabled. The model retains the candidate; the service retains no blocked RMF content. For cooldown-only RMF denial, the service schedules/cancels one retry at the earliest 10-minute boundary. Modal cooldown denial stays foreground/checkpoint-driven and has no 24-hour timer.

The `setPromoSurfaceActive`, `setPromoSurfaceRenderable`, and `setPromoSurfaceVisible` entry points in
[`NewTabPageViewController.swift`](../iOS/DuckDuckGo/NewTabPageViewController.swift)
form the host-facing bridge. The controller composes owner activity, render-location readiness, explicit visibility, and coverage; the model applies the separate attachment-provider check before admission. Standalone, legacy-tray, and Unified Toggle Input hosts must drive those inputs from the owner state that actually exposes or covers favorites, including animation windows. Do not infer visibility solely from `viewDidAppear`, `view.window`, or alpha.

A blocked candidate stays selected but is not rendered, marked shown, dismissed, or consumed.

## Feature flag and lifecycle behavior

`FeatureFlag.promoPresentationCoordination` maps to `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination` with an explicit `.disabled` default in
[`FeatureFlag.swift`](../iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift).
`PromoCoordinationService` seeds the effective state before consumers run and owns the single deduplicated `FeatureFlagger.updatesPublisher` subscription.

A live flag change is one serialized main-actor transaction:

- disabling cancels or invalidates coordination work, resets leases, clears provisional reservations/timers without writing, and republishes NTP RMF through the exact legacy path while retaining confirmed timestamps;
- enabling first withdraws legacy RMF UI, resets stale leases, restores remaining cooldown from confirmed timestamps, and re-adopts an attached exact modal root; after the barrier lowers, stable gate remounts and host-specific enablement publishers retry admission; and
- public admission is unavailable while the transition barrier is active.

The service does not synchronously retry every registered NTP from inside enablement. Foreground checkpoints still refresh/retry active registrations synchronously before modal evaluation; UTI refreshes its retained candidate through `promoQueueEnablementPublisher` once the stable enabled state is published.

Do not “clean up” feature-off behavior in this integration. The service calls the legacy modal overload, while NTP RMF intentionally preserves direct eager mapping and SwiftUI appearance accounting. Feature off bypasses all new cross-surface checks, RMF writes, provisional reservations, and timers; the existing modal-only cooldown remains unchanged. Re-enable resumes confirmed history.

Foreground modal evaluation is initiated from `Foreground.onAppReadyForInteractions` in
[`Foreground.swift`](../iOS/DuckDuckGo/AppLifecycle/AppStates/Foreground.swift).
The service reconciles the exact modal root and synchronously refreshes/retries active NTPs before acquiring a new modal lease or evaluating providers.

Backgrounding does not make a visible NTP inactive and does not release a presentation-active modal. Hosts still deactivate surfaces when their own UI covers or removes them. Committed-but-not-presented modal work is migrated to pending and its scheduled attempt is invalidated by the manager.

## Policy remains with narrow owners

Do not move modal policy into the arbiter or an NTP model.

The ordered provider array is assembled by `PromoCoordinationService` and evaluated by
[`ModalPromptCoordinationManager.swift`](../iOS/DuckDuckGo/ModalPromptCoordination/ModalPromptCoordinationManager.swift).
The current order is:

1. win-back offer;
2. delayed/reinstaller subscription promo;
3. existing-user subscription promo;
4. address-bar picker;
5. default-browser provider, including its re-activation/default-browser policy;
6. What's New; and
7. Cookie Popup Protection opt-in.

The manager remains responsible for provider eligibility evaluation, onboarding status passed to providers, first-eligible priority, the existing modal-to-modal `PromptCooldownManager` behavior, modal scheduling/presentation, provider shown callbacks, and exact-root attempt phases. The service-owned policy handles only the four fixed directional rows above and reuses the manager's confirmed modal timestamp. The provider adapter contract revalidates prepared and retained prompts before presentation and permits replacement only where repeating preparation is safe. Default Browser uses cached validation for prepared work and a fresh check with stored-status fallback for retained work; What's New re-fetches and replaces its prepared controller when the scheduled RMF message ID changes. The default replacement implementation is `nil`, so side-effectful providers are not prepared twice. The service retains launch-source and unrelated UIKit/OmniBar gates. RMF continues to own message selection, targeting, dismissal, and persistence; it does not gain a cooldown engine.

Adding a surface must not duplicate or override any of those decisions.

## Shown accounting

For the enabled path, shown accounting belongs to an admitted render appearance:

- the outer blocked gate records nothing;
- the first inner appearance in a render session records one normal shown event;
- that same first appearance confirms the RMF cooldown timestamp once;
- a same-ID refresh in that session records nothing more; and
- leaving and later re-entering creates a new appearance.

[`HomePageConfiguration.swift`](../iOS/DuckDuckGo/HomePageConfiguration.swift)
remains the shared owner of normal shown, unique shown, and the asynchronous store update. Its main-actor `didAppear` entry point uses a session-scoped `firstShownReservations` set so two NTPs can each record a normal appearance but only one can win unique shown before the store write completes. That reservation is accounting state, not a lease, and must survive flag toggles.

The `HomePageMessageShownPixelReporting` injection is for deterministic normal/unique tests. The `PixelFiring.Type` dependency in `NewTabPageMessagesModel` continues to cover RMF action pixels; do not conflate the two seams.

## Telemetry scope

Iteration one adds no Promo Queue admission, collision, or cooldown telemetry. The two previously proposed collision pixels and their reporter, definitions, and tests were removed in `1f12bf8a66`; telemetry belongs to a separate future project.

Existing RMF shown/dismiss/action accounting and existing modal-provider prompt/impression accounting remain unchanged. Do not add queue pixels while extending or maintaining this seam. A future measurement proposal needs its own product contract, privacy/measurement review, implementation, and rollout plan.

The queue ships off by default. Enabling `promoQueue.features.iOSPromoPresentationCoordination` is a separate privacy-configuration rollout, not an app-code shortcut and not an RMF targeting rule.

## Test expectations

Use real arbiter state where practical and deterministic mocks for scheduling, presentation, feature state, RMF configuration, and host activity.

At minimum, preserve coverage for:

- mutual exclusion, multiple NTP surfaces, occupied slots, stale/duplicate release, reset safety, and dropped-token pruning in `PromoQueueLeaseArbiterTests`;
- “visible RMF blocks modal before provider evaluation” and exact typed denial attribution in `PromoCoordinationServiceTests`/`PromoCoordinationServicePromoQueueTests`;
- evaluating, committed, pending, presentation-active, background, refused-presentation, and exact-root reconciliation behavior in manager unit/integration tests;
- blocked candidates, readiness, same-ID continuity, changed-ID replacement, retry, teardown, transition rollback, and no accounting before admission in `NewTabPageMessagesModelTests`;
- standalone, legacy tray, and UTI visibility/coverage/animation behavior in the focused controller, UTI, model, and integration suites;
- two admitted NTP appearances producing two normal shown events and one unique winner before persistence completes in `HomePageConfigurationTests`/`NewTabPageMessagesModelTests`;
- all four cooldown directions at just-before/exact/just-after boundaries, persistence/relaunch/backward-clock behavior, global provisional serialization, timer cancellation/replacement, and feature-off bypass.

Feature-off tests must assert the exact legacy path. Feature-on tests must assert that no `await`, dispatched callback, provider evaluation, or inner-view publication occurs between conflict checking and lease retention.

## Practical checklist

### Adding another host for the existing NTP RMF surface

- Reuse the app-scoped `NewTabPagePromoCoordinating` dependency.
- Let `NewTabPageViewController` create one stable surface ID.
- Drive logical activity from the owner state that exposes the NTP.
- Signal render-location readiness explicitly.
- Keep window attachment as a safety check.
- Call `tearDownPromoSurface()` from a reachable path only when controller ownership actually ends; do not add `deinit` or `UnifiedSuggestionsHost.tearDown()` assumptions.
- Test covered, hidden, removed, and re-exposed states.
- Test a blocked candidate and exact identity release.
- Test that simultaneous instances share the provisional reservation and 10-minute RMF target boundary, while a later appearance after the boundary may coexist with the first lease.

### Proposing a different promo surface

- Stop and document why it belongs in the same mutual-exclusion group.
- Decide who owns its eligibility, priority, cooldown, persistence, and shown accounting.
- Do not inherit the iteration-one matrix automatically; extending cooldown policy to another surface requires an explicit product/design decision.
- Define its authoritative visibility and dismissal checkpoints.
- Define feature-off and live-transition rollback behavior.
- Decide whether simultaneous instances may coexist and what forms a stable surface identity.
- Obtain privacy/measurement approval for any telemetry.
- Only after that decision, extend a narrow service protocol and keep checkpoint reconciliation inside the service.
- Never inject the arbiter directly or silently generalize `NewTabPagePromoCoordinating`.

If those questions are unanswered, the feature is outside iteration 1 and must not be added to this seam.
