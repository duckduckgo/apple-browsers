# Promo Queue Iteration 1 — Implementation Plan

## Purpose

This document turns `TECH_DESIGN_FINAL.md` into an implementation-ready plan for iOS iteration 1. It is based on the current repository checkout, not only the earlier code snapshot used while drafting the tech design.

The plan deliberately implements a narrow cross-surface lease boundary between:

- launch-modal promos coordinated by `PromoCoordinationService`; and
- Remote Messaging Framework (RMF) cards actually rendered in an active New Tab Page (NTP).

It does not create a general promo queue, change provider ordering/product policy, or extract the macOS implementation. The final PR 2 implementation does extend the provider adapter contract so prepared or retained prompts can be revalidated safely after a delay.

## Validation Verdict

The transactional-lease design is a good implementation direction for iteration 1. It matches the current main-actor modal flow, closes both known check-then-render races, and preserves provider ordering, eligibility policy, cooldown ownership, and RMF targeting/persistence.

The following current-code facts refine the tech design and are requirements for the implementation:

| Tech-design assumption or shorthand | Current-code finding | Implementation consequence |
| --- | --- | --- |
| The service owns the onboarding gate. | The service owns launch-source and unrelated UIKit/OmniBar gates. Onboarding is passed into each provider eligibility check by `ModalPromptCoordinationManager`. | Preserve the current split. Do not move onboarding into the service or duplicate it in the arbiter. |
| The service has six ordered providers. | It assembles seven providers in `PromoCoordinationService.swift`. | Preserve the current seven-provider order exactly; do not copy an older list into new code or tests. |
| Provider evaluation can be treated like a read. | At least the Cookie Popup Protection provider can enroll an experiment while preparing a prompt. | On the feature-enabled path, acquire the modal lease before querying any provider. An RMF-blocked modal path must not call the manager/providers at all; feature off preserves the lease-free legacy overload. |
| Each NTP activation recreates the NTP. | The standalone NTP is recreated, but the legacy suggestion tray and Unified Toggle Input (UTI) retain cached NTP controllers. A cached NTP can remain on-window while hidden by autocomplete or opacity. | Track logical visibility explicitly in all three hosts. `view.window` and `viewDidAppear` alone are not sufficient. |
| Existing shown accounting fires twice. | A normal standalone attach can refresh/map more than once and later receive SwiftUI `onAppear`, producing up to three calls. | Describe the defect as one or more eager/duplicate calls. Feature-on accounting must be tied to one admitted render appearance. |
| `dismissAfterDaysShown` bounds deferral by itself. | Expiry is reevaluated when RMF state is fetched; there is no timer that removes an already-published card. | Refresh active NTP candidates before foreground retry and modal admission. |
| The flag plumbing is ready. | PR 1 added `FeatureFlag.promoPresentationCoordination` and the iOS-specific `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination`; the checked-in privacy configuration still does not enable it. The flag now lives in the `FeatureFlags-iOS` local package. | Keep the explicit disabled default. Rollout requires a separate privacy-configuration change for the iOS-specific subfeature. |
| Providers need no lifecycle contract. | Delayed or retained work can become ineligible before UIKit presentation, and some provider selection has side effects. | Extend the provider adapter with prepared/retained revalidation and optional safe replacement. All providers use the contract; Default Browser distinguishes cached validation from a fresh retained-prompt check, and What's New can safely replace a changed scheduled message. |
| Live changes invalidate “coordination-only reservations.” | Arbiter leases/scheduled attempts are coordination state. The main-actor first-shown winner cache introduced below is session accounting state; clearing or bypassing it before the async store write completes can fire unique shown twice. | Invalidate arbiter/scheduler state on a flag change, but preserve and consult the accounting winner cache during transition republish. This is the interpretation used by this plan. |
| Current delayed presentation can be cancelled. | `ModalPromptScheduling` wraps an uncancellable `DispatchQueue.main.asyncAfter`. | Make scheduled work cancellable or generation-aware and revalidate immediately before presentation. |
| UIKit completion reveals every failed presentation. | `present(_:animated:completion:)` has no failure callback and its completion may not run for a refused presentation. | After calling `present`, verify attachment on the next main-actor turn before treating the attempt as presentation-active. |

These corrections do not change the approved iteration-one scope.

## Non-Negotiable Invariants

1. All arbitration, modal phase transitions, NTP activity transitions, and retry callbacks run on `@MainActor`.
2. Acquisition is atomic: no `await`, dispatched closure, provider callback, or view publication may occur between the conflict check and lease retention.
3. The arbiter is the only mutual-exclusion authority. It owns no provider policy, RMF selection, cooldown, persistent history, or UIKit lifecycle.
4. A modal lease and one or more visible-promo leases cannot coexist. Multiple visible-promo leases may coexist for different surfaces, but at most one lease may exist for a given `(surfaceID, promoType)`.
5. Every lease and attempt has an opaque identity. Release is identity-checked and idempotent; a stale callback cannot clear newer state.
6. Modal providers are not queried when a visible RMF holds the slot.
7. A blocked RMF remains selected/scheduled but is not rendered, shown, dismissed, or consumed.
8. The exact same modal lease moves through evaluation, committed, and presentation-active phases.
9. The selected modal root, rather than a generic topmost controller, determines whether a presentation-active attempt has finished. A child flow presented by that root does not finish the attempt.
10. Feature-disabled behavior calls the legacy modal overload and preserves direct NTP mapping with its eager accounting callbacks. No persistent queue state is introduced.

## Proposed Runtime Shape

### 1. Transactional lease arbiter

Add:

`iOS/DuckDuckGo/ModalPromptCoordination/Arbitration/PromoQueueLeaseArbiter.swift`

The production type should be a small `@MainActor` class with a narrow protocol for tests and consumers.

Suggested value types:

```swift
struct VisiblePromoIdentity: Hashable {
    let surfaceID: UUID
    let promoType: PromoType
    let promoID: String
}

enum PromoType: Hashable {
    case remoteMessage
}
```

`PromoType` is generic enough for the iteration-two seam described by the tech design, but iteration 1 must integrate only `.remoteMessage`.

The arbiter state is conceptually:

```text
idle
modal(attempt identity, weak lease token)
visible([(surfaceID, promoType): (promoID, acquisition identity, weak lease token)])
```

Required operations:

Return typed acquisition outcomes rather than only optional tokens. `PromoQueueModalLeaseAcquisitionResult` distinguishes success, blocked by modal, and blocked by one or more visible promos. `PromoQueueVisiblePromoLeaseAcquisitionResult` distinguishes success, blocked by modal, and an occupied surface slot. The service-level wrapper adds unavailable-during-transition/feature-disabled outcomes.

- acquire a modal lease only when there is no modal lease and the visible map is empty;
- acquire a visible lease only when there is no modal lease;
- reject a second visible acquisition for an already-occupied `(surfaceID, promoType)`, even when the promo ID differs;
- release a matching modal or visible lease;
- invalidate all tracked leases on a live flag transition so outstanding identity-bound tokens become no-ops;
- expose a read-only snapshot for tests and the debug screen.

The returned token may be a main-actor object with an explicit `release()` method or a value passed back to the arbiter. In either case:

- release must be safe to call more than once;
- the arbiter weakly tracks lease tokens and prunes records whose owner dropped the token without releasing it;
- a token invalidated by reset must be a no-op;
- a token for message A must not release message B after a refresh.

Do not admit message B for a surface until message A is no longer renderable and its matching lease has been released. If implementation introduces an atomic replacement API, it may replace only within the same `(surfaceID, promoType)` after the old inner UI has been withdrawn; it must never create two simultaneous leases for that slot.

Do not add priority, waiting order, history, persistence, restoration, or general policy.

### 2. Promo coordination service as the cross-surface checkpoint seam

Keep `PromoCoordinationService` as the entry point already owned by `MainCoordinator`. Give NTP code a narrow protocol backed by that service rather than access to all modal APIs.

The narrow interface needs to support:

- the effective feature state;
- visible-promo lease admission;
- identity-matched lease release;
- registration of a weak, synchronous retry callback per NTP surface.

Visible-promo admission must perform:

1. ask `ModalPromptCoordinationManager` to reconcile the exact selected root;
2. ask the arbiter for the visible lease;
3. return the retained token on success.

The service owns only weak retry registrations, not blocked RMF candidates. Each `NewTabPageMessagesModel` retains its own candidate and registration token. Reachable model/controller teardown deregisters explicitly, while weak targets and weak lease ownership prevent abandoned UI from wedging the queue. Dead retry registrations are pruned both when registering and after retry snapshots, including when the feature is disabled.

Retry registry behavior must be deterministic and reentrancy-safe:

- retain registration order and iterate a snapshot, because callbacks may unregister or replace themselves;
- ignore callbacks whose model is gone or surface is no longer logically active;
- guard against a callback recursively starting another registry-wide retry;
- identity-check deregistration so an old registration token cannot remove a replacement.

Before every foreground modal evaluation, the service must synchronously:

1. reconcile the exact modal root;
2. invoke all registered active-NTP refresh/retry callbacks;
3. run the existing launch-source and unrelated-modal/OmniBar gates;
4. acquire a modal lease;
5. call the manager with that lease.

The retry callbacks execute synchronously on the main actor. They refresh RMF selection first, so expiry/config changes are observed, then retry admission. This ordering guarantees that a still-eligible waiting RMF can take the newly freed slot before a new launch modal.

When an approved checkpoint releases a stale presentation-active modal lease, retry all other logically active registered NTPs as well as completing the triggering NTP's admission. A practical ordering is:

1. reconcile and remember whether the modal lease was released;
2. complete admission for the NTP that triggered the checkpoint;
3. retry a snapshot of the remaining active registrations, excluding the triggering surface.

When committed work fails preflight, is refused by UIKit, or otherwise releases before any modal becomes visible, trigger the same guarded registry-wide retry. Releasing an RMF lease never triggers modal evaluation; launch modals remain deferred until the next eligible foreground.

Do not implement the retry as an asynchronously delivered notification or `Task`, because that would reintroduce the ordering race.

### 3. Modal attempt state

Refactor `ModalPromptCoordinationManager` around explicit state:

```text
idle
evaluating(attempt, modal lease)
committed(attempt, modal lease, prepared configuration/provider)
presentationActive(attempt, modal lease, exact selected root)
```

Keep at most one separate pending prepared configuration:

```text
pending(configuration, provider)
```

Pending work does not hold an arbitration lease, but it continues to suppress the AI Chat sync promo until it is retried or terminally discarded.

The manager flow with an acquired lease is:

1. If pending work exists, retry it before cooldown or provider evaluation.
2. Otherwise check the existing cooldown.
3. Query providers in their existing order, synchronously and without yielding.
4. Release immediately if cooldown blocks or no provider is eligible.
5. If a provider returns a configuration, transition the same attempt and lease to committed.
6. Schedule presentation using a cancellable token or an identity/generation check.
7. Immediately before `present`, validate:
   - attempt and lease identities are still current;
   - the flag remains enabled;
   - the app is active;
   - the intended presenter is attached;
   - the existing unrelated-modal and OmniBar conditions still allow the chosen presentation route.
8. If preflight fails for a recoverable reason, retain the prepared item as pending, cancel the schedule, and release the lease. Terminal/superseded reasons discard it as defined below.
9. When invoking UIKit presentation, retain the exact selected root and transition to presentation-active.
10. On the next main-actor turn, verify that the selected root is actually attached. If UIKit silently refused presentation and completion did not run, return the prepared item to pending and release the lease without provider/cooldown accounting.
11. Confirmed actual presentation, either UIKit completion or adoption of an already-attached prepared root:
    - calls the provider's existing shown callback;
    - records cooldown;
    - records actual-presentation session history.

`ModalPromptConfiguration` remains identity-stable and still carries no dismissal callback. The provider adapter contract adds prepared/retained revalidation and optional replacement so a delayed configuration is never presented solely because it was once eligible. Product eligibility, priority, cooldown, and provider shown accounting remain with their existing owners.

Pending retention applies only to recoverable conditions:

- the app backgrounded or is temporarily inactive;
- an unrelated modal or changed OmniBar state appeared during the delay;
- the intended presenter is temporarily detached/not ready;
- UIKit refused the call and the selected root remains unattached.

Terminal/superseded conditions clear pending work, cancel the attempt, release any lease, and restore transient sync-promo suppression:

- the feature was disabled;
- a different logical attempt or feature transition superseded both the attempt and its pending item;
- a newer prepared item explicitly superseded the old one;
- the selected root is invalid or is attached to an incompatible presentation hierarchy.

If the exact selected root is already attached through the intended route, adopt/reconcile it as presentation-active instead of retrying `present`. Repeated recoverable failures may remain pending for a later eligible foreground, but there is never more than one pending item and no pending path records provider/cooldown state.

Background cancellation is a special recoverable migration: first move the current prepared item into separate pending state, then invalidate only the scheduled attempt/generation and release its lease. A later stale scheduler callback must no-op without clearing that separately retained pending item.

### 4. Exact-root checkpoint reconciliation

The manager retains the exact `ModalPromptConfiguration.viewController` used for the selected attempt.

Retain the most recently selected/presented exact root even when the feature is disabled. The legacy path does not acquire a lease, but this observation is required so a disabled-to-enabled live transition can re-adopt an attached modal before allowing RMF admission.

At a checkpoint, the manager releases a presentation-active attempt only when that exact root is no longer attached/presented. Use one shared helper for both reconciliation and post-presentation verification so UIKit attachment semantics do not diverge.

Do not release merely because:

- the current topmost controller is different;
- the exact root is presenting a nested child;
- the app backgrounds;
- a generic dismissal notification fires.

Checkpoint callers:

- every NTP visible-promo admission attempt;
- the foreground preparation immediately before modal evaluation;
- live feature re-enablement when an exact root may already be visible.

The accepted delay between modal dismissal and the next checkpoint remains as specified by the tech design.

### 5. Separate actual history from active/pending suppression

The current `didPresentModalPromptThisSession` value is set before the delayed presentation. Split it into:

- `didActuallyPresentModalPromptThisSession`, set only by UIKit completion and never cleared during the session;
- transient `hasActiveOrPendingModalAttempt`.

Keep the existing `RecentModalPromptStatusProviding` consumer stable by returning:

```text
didActuallyPresentModalPromptThisSession || hasActiveOrPendingModalAttempt
```

This preserves AI Chat sync-promo suppression:

- during evaluation, scheduling, presentation, and a retained pending retry;
- after any actual modal presentation.

A terminal pre-presentation cancellation with no pending item returns to false only when no earlier modal actually presented. Cancelling newer work must never erase earlier session history.

## Feature Flag and Live Transitions

Use `.promoPresentationCoordination` in `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift` and map it to:

```swift
Config(
    defaultValue: .disabled,
    source: .remoteReleasable(iOSPromoQueueSubfeature.iOSPromoPresentationCoordination)
)
```

The explicit disabled default is intentional. Local overrides should continue to work through the existing feature-flag debug infrastructure.

Observe `FeatureFlagger.updatesPublisher` once at the app-scoped coordination owner and apply changes on the main actor.

Treat a flag change as one serialized main-actor transaction. The owner must expose a short-lived `transitioning` state during which public modal evaluation is deferred and public NTP admission cannot acquire a coordination lease. Only the transition routine's internal re-adoption/retry operations may mutate arbiter state while the barrier is set. This prevents a withdrawal or retry callback from reentering admission between reset and exact-root re-adoption.

Transition callbacks must carry the target state. While transitioning to enabled, an NTP withdrawal callback must not execute the ordinary feature-disabled legacy republish path.

### Enabled to disabled

1. Enter the transition barrier.
2. Run the manager and registered-NTP `willTransition(to: .disabled)` callbacks. The manager cancels/generation-invalidates committed work, clears pending coordination work, and preserves confirmed actual-presentation history; NTP models withdraw coordinated inner UI.
3. Invalidate arbiter leases.
4. Run the manager and NTP `didTransition(to: .disabled)` callbacks. Do not dismiss an already-presented UIKit modal; NTP models republish through the exact legacy mapping/accounting path while the public barrier remains up.
5. Publish the stable disabled state and lower the barrier.
6. Drain any target state queued by a reentrant flag update.

### Disabled to enabled

1. Enter the transition barrier.
2. Run the manager and registered-NTP `willTransition(to: .enabled)` callbacks; NTP models withdraw legacy-published RMF UI before coordinated readmission.
3. Invalidate stale arbiter leases so their identity-bound tokens become no-ops.
4. Run the manager and NTP `didTransition(to: .enabled)` callbacks. The manager re-adopts a modal lease if its retained exact root is still attached; NTP models publish stable coordinated gates while public admission remains unavailable.
5. Publish the stable enabled state and lower the barrier. Gate remounts and host-specific stable-state publishers, including UTI's `promoQueueEnablementPublisher`, perform readmission after the barrier.
6. Drain any target state queued by a reentrant flag update.

This order prevents enabling the flag while a legacy-path modal is visible from admitting an RMF underneath it. Enabling does not synchronously invoke every registered NTP retry from inside the transition; stable gate remounts and enablement publishers perform readmission after the barrier is lowered. Foreground checkpoints still refresh/retry active registrations synchronously before modal evaluation.

The in-memory first-shown winner cache described below is accounting state, not an arbiter lease. Do not clear it on flag toggles, because clearing it could duplicate the unique-shown pixel in one app session. During enabled-to-disabled republish, the transition path must consult this cache before the legacy unique check until the asynchronous store write is visible; normal shown and all other legacy behavior remain unchanged. Add a test that disables the flag immediately after unique shown fires but before the store update completes.

Seed the initial effective flag value before either modal or NTP consumers can admit work, retain exactly one deduplicated `FeatureFlagger.updatesPublisher` subscription, and cancel that subscription with the app-scoped owner. Test callback reentrancy during both transitions.

## Dependency Injection

Construct one `PromoQueueLeaseArbiter` in `Launching` near the current modal service construction.

Pass the same instance through:

- `PromoCoordinationFactory.Dependency`;
- `PromoCoordinationService`;
- `ModalPromptCoordinationManager`;
- the NTP-facing narrow coordination interface passed by `MainCoordinator`.

The existing modal service already reaches `MainCoordinator`; expose its narrow NTP dependency from there and add it to `SuggestionTrayViewController.NewTabPageDependencies`.

Do not:

- create a second arbiter;
- add a new `.shared` singleton to `AppDependencyProvider`;
- store the arbiter in user defaults;
- extract the macOS `PromoService`.

The three NTP construction paths that must receive the dependency are:

1. standalone NTP in `MainViewController.attachHomeScreen`;
2. legacy focused NTP in `SuggestionTrayViewController`;
3. UTI focused NTP in `UnifiedInputContentContainerViewController`.

New production and test source files must be added to `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj`; this project is not folder-synchronized.

## App Lifecycle Integration

### Foreground

Keep UI readiness owned by `Foreground`/`UIInteractionManager`.

Place the ordered reconciliation/retry directly in the existing `onAppReadyForInteractions` path immediately before `presentModalPromptIfNeeded()`. The service can encapsulate the preparation at the beginning of that call, but it must occur before any service gate or manager/provider evaluation.

Do not rely on `MainCoordinator.onForeground()` alone: it is a separate lifecycle hook and does not make the required adjacency to modal evaluation obvious or testable.

Required foreground order:

```text
UI ready
  -> exact modal-root reconciliation
  -> synchronous refresh/retry of logically active NTPs
  -> existing launch-source and unrelated-modal gates
  -> modal lease acquisition
  -> cooldown/provider evaluation
```

### Background

Route `MainCoordinator.onBackground()` to the modal coordination service/manager.

- Committed but not yet presented: migrate the prepared item to pending, then cancel/invalidate only the scheduled attempt, release the modal lease, and make any stale callback unable to clear the pending item.
- Presentation-active: keep the exact root and modal lease.
- Active NTP: keep its lease while backgrounded; do not mark the surface inactive merely because the application resigned active.

On foreground, refresh/revalidate the retained NTP candidate before retrying modal admission.

### Termination

No restoration work is required. Arbiter state, pending work, registrations, and first-shown reservations are in-memory and disappear with the process.

## NTP Render Gate

### Model ownership

Make `NewTabPageMessagesModel` main-actor-bound and give it:

- a stable `surfaceID` created by its owning `NewTabPageViewController`;
- logical-active state supplied by the host;
- render-location readiness supplied by the controller/embedded owner;
- the current RMF candidate;
- an optional admitted render session containing identity, lease, and `appearanceRecorded`;
- one retry-registration token;
- idempotent `load()`/observer teardown.

Move the one-time `messagesModel.load()` call out of `NewTabPageView.init`. SwiftUI view initialization is not a lifecycle guarantee and can run repeatedly. Start the model once from the controller/owner and remove its notification observer on teardown.

Local, non-RMF home messages remain on their existing path. Only `.remoteMessage` uses the iteration-one gate.

Represent an RMF candidate with a stable outer render-gate item in the NTP data/view hierarchy. The outer item may be zero-height while blocked; it is not the visible RMF card and does not record shown state. It must remain present while the candidate is eligible so scrolling/LazyVStack unmount and remount can retry. Construct `HomeMessageView` only as the admitted inner content after lease acquisition.

### Admission and publication

For feature-on RMF:

1. Refresh and map the candidate without recording shown state.
2. Keep/update its stable outer render-gate item.
3. Require host logical activity, render-location readiness, and `viewIfLoaded?.window != nil`.
4. Reconcile the exact modal root through the narrow coordination interface.
5. Acquire `VisiblePromoIdentity(surfaceID, .remoteMessage, messageID)`.
6. Only after acquisition, construct/publish the inner `HomeMessageViewModel`.
7. On the admitted inner view's first `onAppear`, record one shown appearance and set `appearanceRecorded`.
8. When the outer gate leaves the visible render location, withdraw the inner view, release the exact matching lease, and keep the eligible outer candidate so reappearance can retry.

If admission fails:

- retain the candidate in the model;
- retain the outer gate but publish/build no inner remote `HomeMessageViewModel`;
- do not call shown/dismiss/store APIs;
- wait for a surface activation, foreground retry, RMF-change notification, or feature transition.

For feature-off RMF, preserve the current eager mapping and SwiftUI appearance behavior exactly. The first iteration is guarded, so rollout rollback must restore the legacy path rather than partially coordinating it.

### Same-ID and changed-ID refresh

An active refresh with the same `(surfaceID, messageID)`:

- keeps the existing lease;
- keeps `appearanceRecorded`;
- updates content without a new appearance or shown event.

A refresh to a different message:

- withdraws/removes the old outer gate and admitted UI;
- releases only the old identity/token after the old inner UI is no longer renderable;
- uses an identity-checked physical-removal fallback if SwiftUI does not deliver disappearance;
- attempts a new lease for the new identity only after the old same-surface slot is released;
- treats the new admitted card as a new appearance.

Late disappearance from an older SwiftUI view must not release the newer session. Compare both render-session and lease identity.

### Logical activity in all NTP hosts

UIKit attachment is a safety condition, not the authoritative visibility signal.

#### Standalone NTP

In `MainViewController`:

- mark the surface logically active as part of `attachHomeScreen`, ordered so admission completes before the RMF can become visible;
- mark it inactive before/during `removeHomeScreen`;
- deactivate the underlying standalone NTP whenever legacy suggestion or UTI content fully covers it, and reactivate it after the overlay is dismissed;
- perform explicit cleanup from reachable dismissal/removal paths; do not depend on actor-isolated work from `deinit`.

Use `viewWillAppear` as the controller readiness signal so a lease can be retained before visual appearance. Use `viewDidDisappear`, not `viewWillDisappear`, for normal disappearance release; releasing during the transition would allow a modal while the card is still visible.

When focused content is `.favorites`, the focused/cached NTP may hold the visible lease while the covered standalone NTP remains inactive. When autocomplete, Duck.ai, or UTI list content covers both RMF surfaces, neither NTP may suppress the OmniBar-compatible modal route.

#### Legacy suggestion tray

The embedded NTP can remain mounted underneath other suggestion content.

Propagate logical activity from the existing `SuggestionType` transitions:

- active only when favorites/NTP content is actually exposed;
- inactive for autocomplete, Duck.ai suggestions, and tray hiding;
- explicitly clean up when the retained controller is removed.

Do not infer activity from its window or controller appearance callbacks.

Because this hierarchy does not reliably forward child-controller appearance, the suggestion owner must also signal render-location readiness after the embedded NTP is installed/exposed. Require `viewIfLoaded?.window != nil` as a final safety check, but do not use it as logical visibility.

#### Unified Toggle Input

The UTI host memoizes the NTP and can hide it with opacity while it remains on-window.

Propagate logical activity through the existing `UnifiedInputContentContainerViewController.setActive`/content state:

- host is active;
- selected content is favorites;
- no overlay state is covering the favorites surface.

All must be true before admission. Transition to inactive from the same owner state change that hides/covers favorites.

Do not make promo correctness depend on `UnifiedSuggestionsHost.tearDown()` or a view-controller `deinit`: the cached favorites controller can outlive the hosting view. The UTI owner must drive the cached NTP inactive whenever favorites are covered or the host is inactive. Reachable controller removal calls model teardown where ownership really ends; otherwise weak retry registrations and weak lease-token pruning ensure abandoned objects cannot wedge admission.

### Disappearance ordering

Each physical SwiftUI gate mount has its own UUID so balanced appearance/disappearance callbacks cannot be confused by SwiftUI remounts. Prefer the admitted inner view's `onDisappear` for exact visual-lifetime release. Owner-driven withdrawal removes the inner UI first and releases the identity-matched lease on the next main turn; reachable controller teardown is an idempotent fallback.

When an owner hides a cached surface without UIKit disappearance, replaces a candidate, or physically removes a container:

1. stop it from making new admissions;
2. withdraw the admitted remote view;
3. release from the matching disappearance callback;
4. after the old node/container is no longer renderable, run a deterministic deferred, identity-checked cleanup fallback if SwiftUI does not deliver disappearance;
5. only then retry a replacement candidate for the same surface/promo type.

This keeps the lease until the coordinated card is no longer renderable while still preventing a hidden cached controller from suppressing modals indefinitely.

## RMF Shown and Unique Accounting

Remove the eager map-time `didAppear` only on the feature-on path. Keep the admitted view's existing appearance callback, guarded by the render session's `appearanceRecorded` bit.

The shared `HomePageConfiguration` remains the owner of:

- the normal RMF shown pixel;
- the unique shown pixel;
- the asynchronous store update.

Make the admitted-accounting entry point main-actor-bound and add a session-scoped:

```swift
private var firstShownReservations: Set<String>
```

Inject a shown-pixel reporter or `PixelFiring.Type` into `HomePageConfiguration`, with the existing production implementation as the default. The `PixelFiring` dependency already present in `NewTabPageMessagesModel` covers action pixels and is not a seam for the shown/unique pixels currently fired directly by `HomePageConfiguration`.

For each admitted appearance:

1. fire the normal shown pixel once;
2. read persisted `hasShown`;
3. if not persisted, atomically insert the message ID into the reservation set;
4. only the successful insertion fires unique shown and starts the store update.

Because the production `HomePageConfiguration` is shared by all NTP models and runs on the main actor, two NTP instances cannot both win the reservation before the asynchronous store write completes.

Do not broaden `RemoteMessagingStoring` for iteration 1 unless implementation evidence shows the shared reservation cannot cover a real call path. A BrowserServicesKit store API redesign would add scope without improving this app-local coordination boundary.

Expected accounting:

- two independently admitted NTP appearances of the same message: two normal shown events, one unique event;
- same-ID refresh in one admitted render session: no additional shown event;
- leave and later re-enter: a new normal shown event, no new unique event;
- blocked candidate: no shown or unique event.

## Detailed Implementation Sequence

The sequence below follows the planned task timeline while making dependencies explicit. Keep each step buildable and reviewable; do not combine the entire feature into one change.

The screenshot timeline maps to these implementation slices:

| Planned slice | Steps in this document |
| --- | --- |
| Week 3 core admission | Step 1 flag; Step 2 arbiter/tests; Step 3 injection; Step 4 service lease and manager phases |
| Week 4 lifecycle and NTP gate | Step 5 foreground/background/scheduler/suppression split; Step 6 NTP gate and foreground RMF retry |
| Week 5 hardening and rollout | Step 7 atomic accounting; Step 8 behavioral tests; manual QA; Step 9 debug/pixels/docs; Step 10 privacy-config rollout and ship review |

Treat these as dependency-ordered slices rather than new calendar commitments.

## Pull Request Split and Landing Workflow

The completed `bartosz/promo-queue` branch is the temporary source snapshot for
the implementation. Normally each next slice starts from the reviewed result on
`main`. Because PR 2 was final but not yet merged when PR 3 preparation began,
the source was explicitly rebuilt on the exact final PR 2 tip before extraction;
this avoids carrying pre-review behavior into the last pull request.

Land the app implementation as three sequential pull requests:

1. `bartosz/promo-q-1` (**merged as [#6087](https://github.com/duckduckgo/apple-browsers/pull/6087)**): Steps 1–4 — the disabled-by-default iOS flag,
   transactional arbiter and tests, app-scoped injection, and coordinated modal
   lease/attempt phases.
2. `bartosz/promo-q-2` (**final and awaiting review as [#6175](https://github.com/duckduckgo/apple-browsers/pull/6175), tip `8d6d95438e`**): Steps 5–6 — lifecycle-safe scheduling, provider prepared/retained-prompt revalidation, foreground/background ordering, the coordinated NTP render gate, all three host visibility/coverage/animation paths, weak lifecycle cleanup, and exact feature-off regression coverage.
3. `bartosz/promo-q-3` (**prepared locally from final PR 2, tip `c9c1de13c0`**): the remaining Step 7 atomic shown accounting, Step 8 behavioral integration coverage, one standalone stale alpha-animation completion guard, and Step 9 debug state/collision telemetry. Temporary developer documentation stays only on the source branch.

Create each branch just in time from the reviewed predecessor and cherry-pick the
relevant dependency-ordered commits. Prefer merged `main`; when a predecessor is
final but awaiting review, an explicitly approved stacked branch may use that
exact predecessor tip. In that case, first resynchronize the temporary source
with the reviewed predecessor so extraction cannot restore superseded behavior.

Fold late test corrections into the pull request that introduces the affected
production or test code, even when the correction was committed later on the
source branch. Keep each intermediate pull request buildable and tested while
the feature remains remotely disabled.

The later privacy-configuration rollout in Step 10 is a separate pull request in
the sibling `privacy-configuration` repository after the first containing app
version and rollout inputs are known.

Everything under `promo-queue-docs/` is temporary working documentation for this
project and must not be cherry-picked, committed, or merged into `main`.
`project_log.md` is also project-working memory and must not be included in the
app pull requests. The implementation PR descriptions may link to the source
branch or copy the relevant review notes without landing these files.

### Step 1 — Add the iOS feature flag

Files:

- `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift`
- `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/iOSPromoQueueSubfeature.swift`
- feature-flag tests/mocks affected by exhaustive switches

Work:

- add `.promoPresentationCoordination`;
- add and map `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination`;
- declare `.disabled` explicitly;
- verify local override support follows existing infrastructure;
- add focused mapping/default tests where similar flags are tested.

Exit criteria:

- default behavior is legacy/off;
- the `FeatureFlags-iOS` subfeature is iOS-specific and remains under BrowserServicesKit's existing `promoQueue` privacy-feature parent;
- no privacy-config enablement in this repository change.

Estimated effort: 0.5 day.

### Step 2 — Implement and unit-test the transactional arbiter

Files:

- new `PromoQueueLeaseArbiter.swift`;
- new `PromoQueueLeaseArbiterTests.swift`;
- `project.pbxproj`.

Test first:

- modal acquired from idle;
- visible acquired from idle;
- visible blocks modal with the typed visible-conflict reason;
- modal blocks visible with the typed modal-conflict reason;
- multiple visible identities coexist;
- a surface/promo slot cannot hold message A and message B simultaneously;
- release of one NTP does not clear another;
- duplicate and stale release are harmless;
- old token cannot release a new lease after reset;
- reset clears state and invalidated tokens cannot release later acquisitions;
- dropped lease tokens are pruned and cannot wedge the arbiter.

Exit criteria:

- pure main-actor state machine has no UIKit, provider, RMF-store, or feature-flag dependencies.

Estimated effort: 1.5 days.

### Step 3 — Construct and inject one arbiter

Files:

- `Launching.swift`;
- `PromoCoordinationFactory.swift`;
- `PromoCoordinationService.swift`;
- `MainCoordinator.swift`;
- `MainViewController.swift`;
- `SuggestionTrayViewController.NewTabPageDependencies`;
- all test dependency builders/mocks.

Work:

- construct one arbiter;
- pass it to service and manager;
- expose a narrow NTP coordination dependency through the existing object graph;
- cover all three NTP controller construction paths;
- inject/reuse the factory's existing `FeatureFlagger`, seed the initial effective state, and retain one deduplicated main-actor `updatesPublisher` subscription at the app-scoped coordination owner;
- scaffold the serialized transition barrier and target-state callbacks; Steps 4–6 fill in modal and NTP transition behavior as those components are implemented;
- avoid `AppDependencyProvider.shared`.

Exit criteria:

- every modal and NTP path observes the same arbiter instance;
- the project compiles with the feature still behaviorally off;
- initial state, deduplication, subscription lifetime, and barrier reentrancy are unit-tested without depending on later modal/NTP implementation.

Estimated effort: 1 day (0.5 day for injection and approximately 0.5 day for live-flag ownership/transition tests).

### Step 4 — Add modal lease admission and attempt phases

Files:

- `PromoCoordinationService.swift`;
- `ModalPromptCoordinationManager.swift`;
- related protocols and mocks;
- existing service/manager unit and integration tests.

Work:

- acquire after existing service gates and before manager/provider evaluation;
- consume the typed acquisition outcome without firing telemetry yet; only the visible-conflict result represents RMF blocking modal admission;
- accept the lease in the manager API;
- add evaluating/committed/presentation-active attempt state;
- release synchronously on cooldown/no eligible provider;
- retain exact selected root;
- observe the exact root on the legacy flag-off presentation path for later live re-adoption;
- implement the manager half of live transitions: release/reset modal coordination state on disable and re-adopt an attached exact root on enable;
- split actual history from active/pending suppression;
- add exact-root reconciliation callable by foreground and NTP admission;
- report approved modal-lease releases back to the service so all other active NTP registrations retry through the guarded snapshot.

Preserve:

- seven-provider order;
- provider eligibility and onboarding handling;
- cooldown ownership;
- provider shown/seen/action accounting;
- OmniBar presentation route.

Exit criteria:

- RMF-first denial cannot reach providers;
- no-provider/cooldown paths leave no lease;
- nested child presentations do not finish the selected root;
- a checkpoint triggered by one of two blocked active NTPs retries both without recursion.

Estimated effort: 2.5 days (approximately 1 day for the service admission seam and 1.5 days for manager phases/checkpoint state).

### Step 5 — Make scheduling safe and wire foreground/background

Files:

- `ModalPromptScheduling.swift`;
- `ModalPromptCoordinationManager.swift`;
- `PromoCoordinationService.swift`;
- `Foreground.swift`;
- `MainCoordinator.onBackground`;
- scheduler/presenter mocks and tests.

Work:

- return a cancellation token or use generation-aware scheduling;
- add pre-presentation validation;
- add next-turn attachment verification;
- retain at most one pending prepared item without a lease;
- revalidate every prepared/retained prompt and allow optional provider-safe replacement;
- distinguish recoverable pending reasons from terminal/superseded cancellation;
- retry pending before querying providers;
- wake all logically active registered NTPs when a failed/unattached modal attempt releases its slot;
- reconcile/refresh/retry immediately before foreground modal evaluation;
- cancel committed-not-presented work on background;
- preserve presentation-active modal and active NTP leases on background;
- make flag disable migrate/discard pending work according to the terminal rules and make stale scheduler callbacks unable to mutate post-transition state.

Exit criteria:

- a stale `0.1`-second closure cannot present;
- foreground ordering is deterministic and synchronous;
- background cancellation does not consume provider/cooldown state;
- terminal pending paths restore transient sync-promo suppression while earlier actual history remains intact.

Estimated effort: 2.5 days (approximately 1 day for foreground ordering, 1 day for scheduling/revalidation, and 0.5 day for the suppression-state split and lifecycle wiring).

### Step 6 — Implement the per-NTP render gate

Files:

- `NewTabPageMessagesModel.swift`;
- `NewTabPageViewController.swift`;
- `NewTabPageView.swift`;
- `HomeMessageView.swift` or a small NTP-only gate wrapper;
- `HomeMessageViewModel`/builder only if a paired disappearance closure cannot remain NTP-local;
- all three NTP hosts;
- NTP model/controller tests and mocks.

Work:

- make the model main-actor-bound;
- make `load()` idempotent and clean up its observer;
- separate a stable outer candidate gate from admitted inner UI;
- add stable surface IDs and render-session identity;
- acquire before constructing/publishing remote card UI;
- consume the typed outcome so only a modal-conflict result represents modal blocking an otherwise renderable RMF;
- record appearance once per admitted session;
- release by exact token on disappearance;
- implement same-ID continuity and changed-ID replacement;
- propagate logical activity and explicit embedded render readiness from standalone, legacy tray, and UTI owners;
- deactivate the covered standalone NTP during focused overlays;
- drive cached UTI favorites renderability from host/content state without relying on `UnifiedSuggestionsHost.tearDown()` or `deinit`;
- retain blocked candidates for synchronous foreground retry;
- implement the NTP half of live transitions: target-state withdrawal, legacy republish with pending first-shown protection, then stable gate remount/readmission and host-specific enablement refresh after the barrier lowers;
- preserve exact feature-off behavior.

Exit criteria:

- hidden cached NTPs do not hold leases;
- an exposed embedded NTP can admit without relying on forwarded appearance callbacks;
- overlay-covered standalone NTPs do not hold leases;
- no visible RMF can be published without a lease;
- blocked candidates remain scheduled and unaccounted;
- idempotent load/reachable teardown leave one observer while alive and no observer or retry registration after teardown; dead weak registrations also prune on later registration/retry;
- global dismissal releases/removes the matching message from every NTP;
- config removal or expiry before retry clears the candidate without accounting.

Estimated effort: 2.5 days (2 days for the render gate/all host paths and 0.5 day for synchronous foreground RMF retry).

### Step 7 — Make first-shown accounting atomic

Files:

- `HomePageConfiguration.swift`;
- `HomePageMessagesConfiguration.swift`;
- associated mocks;
- `HomePageConfigurationTests.swift`;
- `NewTabPageMessagesModelTests.swift`.

Work:

- move feature-on shown accounting to admitted appearance;
- inject a deterministic shown/unique pixel reporter into `HomePageConfiguration`;
- add the shared main-actor first-shown reservation;
- test concurrent per-NTP appearances before the async store write;
- keep feature-off behavior unchanged.

Exit criteria:

- normal shown fires once per appearance;
- unique shown has exactly one winner across NTP instances;
- blocked/same-ID refresh paths do not account.

Estimated effort: 0.5 day.

### Step 8 — Add behavioral integration coverage

Files:

- extend `ModalPromptCoordinationManagerIntegrationTests.swift` and focused unit suites;
- `project.pbxproj`.

Use real arbiter/manager state with deterministic mocks for scheduler, presenter, feature flag, RMF configuration, and active NTP surfaces. Avoid full UI tests unless a behavior cannot be covered at this boundary.

Exit criteria:

- all behavioral rules in the matrix below are covered;
- full enabled-to-disabled and disabled-to-enabled flows cover schedule/pending invalidation, lease reset, legacy republish, the pre-store-write unique race, exact-root re-adoption, active-NTP retry, and callback reentrancy;
- existing provider priority/cooldown/OmniBar suites remain green.

Estimated effort: 1.5 days.

### Step 9 — Add rollout observability and docs

Files:

- `iOS/DuckDuckGo/ModalPromptCoordination/DebugMenu/ModalPromptCoordinationDebugMenu.swift`;
- `iOS/DuckDuckGo/DebugScreen.swift`;
- `iOS/DuckDuckGo/MainViewController+Segues.swift`;
- `iOS/DuckDuckGo/SettingsLegacyViewProvider.swift`;
- `iOS/DuckDuckGo/ModalPromptCoordination/Arbitration/PromoQueueLeaseArbiter.swift`;
- `iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift`;
- `iOS/DuckDuckGo/NewTabPageMessagesModel.swift` or the final NTP gate emitting call site;
- `iOS/Core/PixelEvent.swift`;
- `iOS/PixelDefinitions/pixels/definitions/prompt-coordination.json5`;
- existing arbiter, service, and NTP gate/model unit tests for outcome attribution and emission;
- new `promo-queue-docs/ADDING_PROMOS.md`.

Debug screen:

- extend the existing “Modal Prompt Coordination” screen;
- inject one read-only snapshot provider through `DebugScreen.Dependencies` and both debug-screen builders;
- show effective flag, arbiter modal occupancy, manager phase, pending state, and active visible-lease count;
- add a refresh action;
- do not add persistent history or manual lease mutation.

Pixels use the approved attempt-based contract:

- modal admission blocked by an active RMF lease;
- RMF admission blocked by a modal lease.

Return a typed arbiter acquisition result, or equivalent internal denial reason, so pixels distinguish a real cross-surface conflict from duplicate/stale/transition denial.

- Fire modal-blocked-by-RMF only after the existing service gates pass and modal acquisition loses specifically to one or more visible leases.
- Fire RMF-blocked-by-modal only when a logically active, render-ready RMF candidate loses specifically to the modal lease.
- Fire only while the feature is enabled.
- Count every qualifying denied admission attempt. Use `m_promo-queue_modal-admission-blocked-by-remote-message` and `m_promo-queue_remote-message-admission-blocked-by-modal`, owned by `bkunat`, with permanent `daily_count`, `platform`, and `form_factor` definitions and only the automatically supplied `appVersion` parameter.

Use `DailyPixel.fireDailyAndCount` for aggregate user/occurrence reporting. Do not attach message IDs, surface UUIDs, provider names, URLs, or other high-cardinality/identifying values. Add unit tests at the service and NTP gate emitting call sites, including non-conflict denials that must not fire.

`promo-queue-docs/ADDING_PROMOS.md` must explain:

- iteration 1 coordinates only launch modals and NTP RMF;
- how a future surface uses the narrow lease/checkpoint interface without bypassing the arbiter;
- construction/injection, flag, lifecycle, and test expectations;
- provider priority, eligibility, and cooldown remain in the existing modal manager;
- features outside this seam require a new design decision rather than silently extending iteration 1.

Exit criteria:

- rollout can distinguish both prevented-collision directions;
- pixel definitions validate;
- internal QA can inspect live in-memory state;
- both debug-screen construction paths receive the same read-only snapshot provider;
- the developer guide is concrete enough to prevent bypassing or expanding the narrow seam accidentally.

Estimated effort: 1.75 days, with privacy-config elapsed monitoring overlapping other work.

### Step 10 — Prepare the separate privacy-config rollout

This starts only after the first containing app version is known and is not bundled into the Step 1 app flag change.

Repository/artifacts:

- `../privacy-configuration/features/promo-queue.json`;
- `../privacy-configuration/overrides/ios-override.json`;
- that repository's validation and review workflow.

Work:

- add the iOS `promoQueue` override and `iOSPromoPresentationCoordination` rollout;
- set `minSupportedVersion` to the actual first containing iOS release;
- record rollout owner, staged percentages, observation window, and rollback criteria;
- validate the privacy configuration;
- confirm remote disable works on an internal build before increasing percentages.

Exit criteria:

- the app remains off below the containing release;
- remote enable/disable changes the effective iOS flag without restart;
- rollout steps and monitoring owners are explicit.

Estimated engineering effort: 0.5 day, excluding observation windows and ship review.

## Behavioral Test Matrix

| Rule | Required coverage |
| --- | --- |
| 1. RMF first | Active RMF lease makes modal acquisition fail; manager/providers/cooldown/impressions remain untouched. On later eligible foreground the active candidate refreshes/retries before modal evaluation. |
| 2. Modal evaluation first | Modal lease is held before cooldown/provider calls. Cooldown/no-provider releases synchronously. |
| 3. Modal first | Committed and presentation-active phases deny RMF; candidate remains retained; no shown/dismiss/store mutation occurs. |
| 4. RMF changes during modal | RMF-change notification maps a candidate but cannot publish the inner card while the modal lease is held. Animation/scheduling-window selection cannot overlap. |
| 5. Modal dismissal checkpoint | Exact root remains active through nested child flows. Once the exact root is detached, NTP admission and foreground checkpoints release it. A checkpoint from NTP A also retries other active blocked NTPs through a guarded snapshot. Foreground RMF retry wins before new modal evaluation. |
| 6. Multiple NTPs | Two surface IDs hold independent visible leases. Removing A does not release B. Same message ID on two surfaces has independent render sessions. One surface cannot hold old and new message leases simultaneously. Global dismissal clears every matching surface. |
| 7. Existing gates | Onboarding/provider eligibility, external launch/deep link, unrelated modal, OmniBar, cooldown, and provider order remain unchanged. |
| 8. Feature disabled/live toggle | Disabled uses the exact legacy path. Disable cancels stale work/releases leases. A transition barrier rejects reentrant acquisition. Re-enable re-adopts an attached exact modal root, including one presented while initially disabled, before active NTP retry. |
| 9. Background/termination | Background keeps active NTP and presentation-active modal leases; committed schedule is cancelled/pending without consuming state; stale callback cannot present. New process starts empty. |

Additional required cases:

- feature-on eager mapping records no shown event;
- admitted `onAppear` is idempotent;
- same-ID refresh is a continuous appearance;
- changed ID releases/reacquires by identity;
- old and new message IDs never hold the same surface slot together, even when disappearance is delayed/missed;
- two admitted NTP appearances produce two normal shown and one unique shown;
- already-persisted shown state produces no unique event;
- enabled-to-disabled republish before the async shown-store write completes does not fire unique twice;
- `afterIdle` candidate waits behind a modal and retains the correct trigger selection;
- UIKit preflight failures for inactive app, detached presenter, unrelated modal, and changed OmniBar state;
- silent UIKit refusal is detected by the attachment check;
- recoverable preflight failures retain one pending item; terminal/superseded failures discard it;
- a failed/unattached modal attempt retries two active blocked NTPs without registry recursion;
- terminal cancellation clears transient AI sync-promo suppression only when there is no earlier actual presentation;
- existing actual presentation history survives later cancellation;
- standard NTP, legacy suggestion tray, and UTI visibility transitions all acquire/release correctly;
- an installed embedded NTP can admit without forwarded controller appearance;
- UTI teardown leaves no cached controller lease or retry registration;
- opacity-hidden, autocomplete-covered, or focused-overlay-covered standalone NTP does not suppress modal admission;
- calling `load()` twice installs one notification observer, and teardown removes the observer/registration;
- config removal/expiry before retry clears a blocked candidate with no accounting;
- retry callbacks may deregister/reregister without skipped entries, stale removal, or recursive retry;
- feature transition callbacks cannot reacquire between withdrawal, reset, and exact-root re-adoption.

## File-Level Change Inventory

Expected production changes:

- `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/FeatureFlag.swift`
- `iOS/LocalPackages/FeatureFlags-iOS/Sources/FeatureFlags/iOSPromoQueueSubfeature.swift`
- `iOS/DuckDuckGo/AppLifecycle/AppStates/Launching.swift`
- `iOS/DuckDuckGo/AppLifecycle/AppStates/Foreground.swift`
- `iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift`
- `iOS/DuckDuckGo/ModalPromptCoordination/Factory/PromoCoordinationFactory.swift`
- `iOS/DuckDuckGo/ModalPromptCoordination/ModalPromptCoordinationManager.swift`
- `iOS/DuckDuckGo/ModalPromptCoordination/Helpers/ModalPromptScheduling.swift`
- new `iOS/DuckDuckGo/ModalPromptCoordination/Arbitration/PromoQueueLeaseArbiter.swift`
- `iOS/DuckDuckGo/UICoordination/MainCoordinator.swift`
- `iOS/DuckDuckGo/MainViewController.swift`
- `iOS/DuckDuckGo/SuggestionTrayViewController.swift`
- `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputContentContainerViewController.swift`
- `iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/SuggestionsFavoritesView.swift`
- `iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsHost.swift`
- `iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsView.swift`
- `iOS/DuckDuckGo/NewTabPageViewController.swift`
- `iOS/DuckDuckGo/NewTabPageMessagesModel.swift`
- `iOS/DuckDuckGo/NewTabPageView.swift`
- `iOS/DuckDuckGo/HomeMessageView.swift` or an NTP-local wrapper
- `iOS/DuckDuckGo/HomePageConfiguration.swift`
- `iOS/DuckDuckGo/HomePageMessagesConfiguration.swift`
- `iOS/DuckDuckGo/ModalPromptCoordination/DebugMenu/ModalPromptCoordinationDebugMenu.swift`
- `iOS/DuckDuckGo/DebugScreen.swift`
- `iOS/DuckDuckGo/MainViewController+Segues.swift`
- `iOS/DuckDuckGo/SettingsLegacyViewProvider.swift`
- `iOS/Core/PixelEvent.swift`
- `iOS/PixelDefinitions/pixels/definitions/prompt-coordination.json5`
- `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj`
- new `promo-queue-docs/ADDING_PROMOS.md`

Update only the mocks/tests affected by the final protocol surface. Prefer test-local mocks unless a mock is genuinely reused across targets.

Xcode target membership must include:

- `PromoQueueLeaseArbiter.swift` in the app production Compile Sources;
- `PromoQueueLeaseArbiterTests.swift` in `iOS Unit Tests`;
- extended `ModalPromptCoordinationManagerIntegrationTests.swift` in `iOS Integration Tests`;
- each test-local mock only in the target that consumes it.

## Manual QA Pass

Run with the flag both off and on.

1. **RMF visible, app foregrounded:** confirm no launch modal appears and the RMF remains interactive.
2. **Modal commits, NTP opens during delay:** confirm the RMF card is not rendered.
3. **Modal presents a nested child:** confirm opening/retrying NTP still does not render RMF.
4. **Modal root dismissed, NTP checkpoint occurs:** confirm eligible RMF appears and accounts once.
5. **Modal root dismissed, app foregrounded:** confirm RMF refresh/retry happens before a new modal evaluation.
6. **Legacy suggestion tray:** switch between favorites, autocomplete, and Duck.ai suggestions; hidden NTP must not block a modal.
7. **UTI:** switch focused content and overlay state; opacity-hidden favorites must not block a modal.
8. **Multiple NTP instances:** remove one while another remains visible; the remaining card must keep modal blocked.
9. **Background during the 0.1-second delay:** confirm stale modal closure never presents after returning.
10. **Background with visible RMF:** confirm its lease survives and is revalidated on foreground.
11. **Same-ID configuration refresh:** confirm no visual flicker, lease replacement, or duplicate shown event.
12. **New-ID configuration refresh:** confirm old lease is released and the new card is independently admitted.
13. **After-idle RMF:** confirm it remains pending behind a modal and appears with the intended trigger afterward.
14. **Live flag disable:** confirm pending schedule is invalidated and legacy behavior resumes.
15. **Live flag enable while a modal is visible:** confirm RMF is not admitted underneath the modal.
16. **Provider regression:** sample default-browser, subscription, What's New, cookie-popup, and address-picker prompts for unchanged presentation/accounting.
17. **AI Chat sync promo:** confirm it stays suppressed during active/pending attempts and after an actual presentation.

Inspect the extended debug screen during these scenarios and verify that lease counts/phases return to idle when expected.

## Verification and Review

Repository rules require explicit permission before running tests. Once permission is granted, use the CI-configured `iOS Browser` scheme as the authoritative gate, with focused `-only-testing` selectors while iterating. The standalone unit/integration schemes can be useful for compile checks but do not reproduce the CI launch arguments and skip list.

Also validate pixel definitions from `iOS` with:

```text
npm run validate-pixel-defs
```

No new UI-test target is required for iteration 1 if the owner-state forwarding and cross-surface rules are covered deterministically in unit/integration tests.

Review the implementation in this order:

1. arbiter correctness and identity safety;
2. modal provider/cooldown/accounting preservation;
3. foreground/background and failed-presentation behavior;
4. all three NTP logical-visibility paths;
5. RMF accounting and live flag rollback;
6. pixels/debug/rollout.

## Rollout

The app change should ship disabled by default.

Before enabling:

1. land the implementation and focused tests;
2. retain the approved attempt-based contract for the two aggregate suppression pixels;
3. land a separate privacy-configuration change for `promoQueue.features.iOSPromoPresentationCoordination`;
4. use the actual first containing iOS release as `minSupportedVersion`;
5. exercise local override/internal channels;
6. start with a small staged percentage;
7. monitor both suppression directions alongside existing RMF shown/dismissed and provider-specific prompt/impression signals; there is no existing generic cooldown-blocked occurrence signal, so add one only if separately approved;
8. increase only after the agreed observation window and ship review.

Rollback is the remote feature disable. It must invalidate scheduled coordination work and return both surfaces to the existing iOS behavior without requiring an app restart.

## Definition of Done

Iteration 1 is complete when:

- the feature flag is mapped and defaults off;
- one app-scoped arbiter is used by modal and all NTP paths;
- on the feature-enabled coordinated path, modal providers are never queried without a modal lease;
- committed/presentation-active modal work blocks RMF through exact-root checkpoint release;
- foreground refresh/retry is ordered before modal evaluation;
- stale scheduled modal work cannot present;
- all three NTP hosts supply authoritative logical visibility;
- a blocked RMF is neither rendered nor accounted/consumed;
- feature-on shown accounting is once per admitted appearance and unique shown has one winner;
- feature-off and live rollback restore legacy behavior;
- provider order, onboarding policy, cooldown, OmniBar routing, and provider accounting remain unchanged; prepared/retained prompt adapters revalidate before presentation;
- unit/integration coverage satisfies the behavioral matrix;
- the existing debug screen exposes current coordination state;
- approved aggregate monitoring pixels and definitions are present;
- privacy-config rollout and ship review are tracked as separate release actions;
- no general queue, persistent history, macOS extraction, or unrelated promo integration was added.

## External Decisions Needed Before Rollout

No implementation-level architectural decision remains open. The following release inputs must come from the appropriate owners:

- the first shipping iOS version;
- privacy-config rollout percentages and observation windows;
- ship-review approval.
