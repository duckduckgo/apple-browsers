# Adding Promo Queue Integrations on iOS

## Scope: iteration 1 is deliberately narrow

The iOS promo queue currently prevents one specific collision:

- launch-modal promos coordinated by `PromoCoordinationService`; and
- Remote Messaging Framework (RMF) cards rendered on an active New Tab Page (NTP).

It is a main-actor mutual-exclusion seam, not a general promo scheduler. It does not coordinate badges, settings rows, notification bars, onboarding, Duck.ai sync promos, tab-switcher promos, or arbitrary UIKit presentations. It also does not share or replace the macOS promo queue.

`PromoType` currently has one supported case, `.remoteMessage`, in
[`PromoQueueLeaseArbiter.swift`](../iOS/DuckDuckGo/ModalPromptCoordination/Arbitration/PromoQueueLeaseArbiter.swift).
Do not add another case merely to make a new feature compile. A promo outside the launch-modal/NTP-RMF seam needs an explicit design decision covering its priority, visibility, lifecycle, accounting, and rollback behavior.

## The integration boundary

All coordination is `@MainActor`. The app-scoped `PromoQueueLeaseArbiter` is the only mutual-exclusion authority:

- a modal lease can exist only when there are no visible-promo leases;
- visible-promo leases can coexist across surfaces;
- one `(surfaceID, promoType)` slot can hold at most one promo;
- every lease is bound to a per-acquisition identity;
- dropped tokens are weakly tracked and pruned before snapshots or new acquisitions; and
- release is explicit, idempotent, and unable to clear newer state.

The arbiter owns no eligibility, priority, cooldown, RMF selection, persistence, view lifecycle, or retry policy. Consumers must not receive it directly.

NTP code uses the narrow `NewTabPagePromoCoordinating` interface implemented by
[`PromoCoordinationService.swift`](../iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift):

```swift
var promoQueueFeatureState: PromoQueueFeatureState { get }
var promoQueueFeatureStatePublisher: AnyPublisher<PromoQueueFeatureState, Never> { get }

func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult
func releaseVisiblePromoLease(_ lease: PromoQueueVisiblePromoLease)
func registerVisiblePromoRetry(
    for surfaceID: UUID,
    target: NewTabPagePromoRetrying
) -> NewTabPagePromoRetryRegistration
```

Always ask this service to admit visible content. `admitVisiblePromo` first reconciles the exact modal root through `ModalPromptCoordinationManager`, then performs the atomic arbiter acquisition. Calling `PromoQueueLeaseArbitrating.acquireVisiblePromoLease` from a feature would bypass that checkpoint and is incorrect.

The typed result is also significant:

- `.blockedByModal` is a real cross-surface conflict;
- `.occupiedSurfaceSlot` indicates that the surface still owns another identity;
- `.featureDisabled` and `.unavailableDuringTransition` are feature-state outcomes; and
- other denials must not be reported as modal/RMF collisions.

On the enabled/coordinated modal path, `PromoCoordinationService` follows the inverse rule: it runs its existing launch-source and UIKit/OmniBar gates, acquires a modal lease, and only then lets `ModalPromptCoordinationManager` evaluate providers. If acquisition is `.blockedByVisiblePromos`, the manager's provider-evaluation/presentation entry point and the providers must not be called; the earlier exact-root reconciliation checkpoint still applies. Feature off deliberately uses the legacy lease-free overload.

## Construction and injection

There must be exactly one arbiter per app coordination graph.

[`Launching.swift`](../iOS/DuckDuckGo/AppLifecycle/AppStates/Launching.swift) constructs `PromoQueueLeaseArbiter` beside the coordination service. The same instance is passed through `PromoCoordinationFactory.Dependency` in
[`PromoCoordinationFactory.swift`](../iOS/DuckDuckGo/ModalPromptCoordination/Factory/PromoCoordinationFactory.swift)
to the service and manager.

`MainCoordinator` retains the service and passes it as the narrow `NewTabPagePromoCoordinating` dependency to `MainViewController`. That dependency must continue through all three NTP construction paths:

1. the standalone NTP built by `MainViewController.attachHomeScreen`;
2. the focused NTP built by `SuggestionTrayViewController` from `SuggestionTrayViewController.NewTabPageDependencies`; and
3. the cached favorites NTP built by `UnifiedInputContentContainerViewController`/`UnifiedSuggestionsHost`.

Relevant files are
[`MainCoordinator.swift`](../iOS/DuckDuckGo/UICoordination/MainCoordinator.swift),
[`MainViewController.swift`](../iOS/DuckDuckGo/MainViewController.swift),
[`SuggestionTrayViewController.swift`](../iOS/DuckDuckGo/SuggestionTrayViewController.swift), and
[`UnifiedSuggestionsHost.swift`](../iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsHost.swift).

Do not construct a second arbiter, introduce a `.shared` coordinator, store leases in user defaults, or inject the arbiter into a view or provider.

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
- A changed-ID refresh withdraws the old inner UI, releases its exact lease after removal, and only then attempts the replacement.
- `load()` must stay idempotent. `tearDown()` must remove the RMF observer, deregister `NewTabPagePromoRetryRegistration`, and release admitted or retiring leases.
- Retry targets are weak, synchronous, and surface-specific. Dead registrations are pruned both on registration and after retries, even if the feature is disabled. The model retains the candidate; the service retains no blocked RMF content.

The `setPromoSurfaceActive`, `setPromoSurfaceRenderable`, and `setPromoSurfaceVisible` entry points in
[`NewTabPageViewController.swift`](../iOS/DuckDuckGo/NewTabPageViewController.swift)
form the host-facing bridge. The controller composes owner activity, render-location readiness, explicit visibility, and coverage; the model applies the separate attachment-provider check before admission. Standalone, legacy-tray, and Unified Toggle Input hosts must drive those inputs from the owner state that actually exposes or covers favorites, including animation windows. Do not infer visibility solely from `viewDidAppear`, `view.window`, or alpha.

A blocked candidate stays selected but is not rendered, marked shown, dismissed, or consumed.

## Feature flag and lifecycle behavior

`FeatureFlag.promoPresentationCoordination` maps to `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination` with an explicit `.disabled` default in
[`FeatureFlag.swift`](../iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift).
`PromoCoordinationService` seeds the effective state before consumers run and owns the single deduplicated `FeatureFlagger.updatesPublisher` subscription.

A live flag change is one serialized main-actor transaction:

- disabling cancels or invalidates coordination work, resets leases, and republishes NTP RMF through the exact legacy path;
- enabling first withdraws legacy RMF UI, resets stale leases, and re-adopts an attached exact modal root; after the barrier lowers, stable gate remounts and host-specific enablement publishers retry admission; and
- public admission is unavailable while the transition barrier is active.

The service does not synchronously retry every registered NTP from inside enablement. Foreground checkpoints still refresh/retry active registrations synchronously before modal evaluation; UTI refreshes its retained candidate through `promoQueueEnablementPublisher` once the stable enabled state is published.

Do not “clean up” feature-off behavior in this integration. The service calls the legacy modal overload, while NTP RMF intentionally preserves direct eager mapping and SwiftUI appearance accounting, so remote rollback restores the previous product behavior.

Foreground modal evaluation is initiated from `Foreground.onAppReadyForInteractions` in
[`Foreground.swift`](../iOS/DuckDuckGo/AppLifecycle/AppStates/Foreground.swift).
The service reconciles the exact modal root and synchronously refreshes/retries active NTPs before acquiring a new modal lease or evaluating providers.

Backgrounding does not make a visible NTP inactive and does not release a presentation-active modal. Hosts still deactivate surfaces when their own UI covers or removes them. Committed-but-not-presented modal work is migrated to pending and its scheduled attempt is invalidated by the manager.

## Policy remains with the existing owners

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

The manager remains responsible for provider eligibility evaluation, onboarding status passed to providers, first-eligible priority, `PromptCooldownManager`, modal scheduling/presentation, provider shown callbacks, and exact-root attempt phases. The provider adapter contract revalidates prepared and retained prompts before presentation and permits replacement only where repeating preparation is safe. Default Browser uses cached validation for prepared work and a fresh check with stored-status fallback for retained work; What's New re-fetches and replaces its prepared controller when the scheduled RMF message ID changes. The default replacement implementation is `nil`, so side-effectful providers are not prepared twice. The service retains launch-source and unrelated UIKit/OmniBar gates. RMF continues to own message selection, targeting, dismissal, and persistence.

Adding a surface must not duplicate or override any of those decisions.

## Shown accounting

For the enabled path, shown accounting belongs to an admitted render appearance:

- the outer blocked gate records nothing;
- the first inner appearance in a render session records one normal shown event;
- a same-ID refresh in that session records nothing more; and
- leaving and later re-entering creates a new appearance.

[`HomePageConfiguration.swift`](../iOS/DuckDuckGo/HomePageConfiguration.swift)
remains the shared owner of normal shown, unique shown, and the asynchronous store update. Its main-actor `didAppear` entry point uses a session-scoped `firstShownReservations` set so two NTPs can each record a normal appearance but only one can win unique shown before the store write completes. That reservation is accounting state, not a lease, and must survive flag toggles.

The `HomePageMessageShownPixelReporting` injection is for deterministic normal/unique tests. The `PixelFiring.Type` dependency in `NewTabPageMessagesModel` continues to cover RMF action pixels; do not conflate the two seams.

## Aggregate collision telemetry and privacy

Promo-queue collision telemetry has only two meanings:

- modal admission was blocked by one or more active NTP RMF leases; and
- a logically active, render-ready NTP RMF admission was blocked by a modal lease.

Fire these only when the queue is enabled and the typed result proves that exact conflict. Modal telemetry belongs after all existing service gates pass. RMF telemetry belongs after all host/render readiness checks pass. Duplicate slots, stale callbacks, feature-disabled behavior, and transition denials are not collision events.

Use `DailyPixel.fireDailyAndCount` so monitoring provides aggregate affected-user and occurrence counts. The approved counting unit is every qualifying denial attempt, consistently at both emitting sites and in tests. The definitions are `m_promo-queue_modal-admission-blocked-by-remote-message` and `m_promo-queue_remote-message-admission-blocked-by-modal`, owned by `bkunat`, with permanent `daily_count`, `platform`, and `form_factor` suffixes and only the automatically supplied `appVersion` parameter.

Never attach a message ID, surface UUID, provider name, URL, modal identity, lease identity, or another high-cardinality/identifying value. The existing RMF shown/action parameters are not suitable for these aggregate collision pixels. Pixel cases belong in
[`PixelEvent.swift`](../iOS/Core/PixelEvent.swift)
and definitions belong in
[`prompt-coordination.json5`](../iOS/PixelDefinitions/pixels/definitions/prompt-coordination.json5).
Any future name, parameter, counting, or ownership change requires renewed measurement-owner approval before rollout.

The queue ships off by default. Enabling `promoQueue.features.iOSPromoPresentationCoordination` is a separate privacy-configuration rollout, not an app-code shortcut and not an RMF targeting rule.

## Test expectations

Use real arbiter state where practical and deterministic mocks for scheduling, presentation, feature state, RMF configuration, and host activity.

At minimum, preserve coverage for:

- mutual exclusion, multiple NTP surfaces, occupied slots, stale/duplicate release, reset safety, and dropped-token pruning in `PromoQueueLeaseArbiterTests`;
- “visible RMF blocks modal before provider evaluation” and exact typed denial attribution in `PromoCoordinationServiceTests`/`PromoCoordinationServicePromoQueueTests`;
- evaluating, committed, pending, presentation-active, background, refused-presentation, and exact-root reconciliation behavior in manager unit/integration tests;
- blocked candidates, readiness, same-ID continuity, changed-ID replacement, retry, teardown, transition rollback, and no accounting before admission in `NewTabPageMessagesModelTests`;
- standalone, legacy tray, and UTI visibility/coverage/animation behavior in the focused controller, UTI, model, and integration suites;
- two admitted NTP appearances producing two normal shown events and one unique winner before persistence completes in `HomePageConfigurationTests`/`NewTabPageMessagesModelTests`; and
- both aggregate collision pixels, plus negative cases for every non-conflict denial.

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

### Proposing a different promo surface

- Stop and document why it belongs in the same mutual-exclusion group.
- Decide who owns its eligibility, priority, cooldown, persistence, and shown accounting.
- Define its authoritative visibility and dismissal checkpoints.
- Define feature-off and live-transition rollback behavior.
- Decide whether simultaneous instances may coexist and what forms a stable surface identity.
- Obtain privacy/measurement approval for any telemetry.
- Only after that decision, extend a narrow service protocol and keep checkpoint reconciliation inside the service.
- Never inject the arbiter directly or silently generalize `NewTabPagePromoCoordinating`.

If those questions are unanswered, the feature is outside iteration 1 and must not be added to this seam.
