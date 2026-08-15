# Promo Queue: simplified iOS technical design

## Status and source of truth

This document is the proposed final design for the iOS Promo Queue iteration. It supersedes the implementation direction in:

- [`tech_design_oridingal.md`](tech_design_oridingal.md);
- [`tech_design_adjusted.md`](tech_design_adjusted.md); and
- [`new_direction_proposal.md`](new_direction_proposal.md), where this document makes the remaining choices explicit.

Only [PR #6087](https://github.com/duckduckgo/apple-browsers/pull/6087) is part of the merged iOS baseline. The larger implementation described by the adjusted design is useful historical context, but it is not the target architecture.

The implementation starts from `bartosz/promo-q-simp-2`. At the 2026-08-14 review checkpoint, its HEAD is `7858a17094d8`; it is 2 commits ahead of and 7 commits behind local `main` (`375bd10e56c5`). Repository synchronization is an implementation preflight decision, not part of this design. The scope is iOS only. Android is a reference implementation, not a delivery target.

## Review validation update — 2026-08-14

The following corrections are incorporated into this revision:

- coordinated initialization cannot claim RMF before an NTP-capable path requests content;
- `HomePageConfiguration` owns remote-message refreshes and emits a distinct source-change signal;
- the admitted message and its trigger lane stay pinned for one ownership;
- appearance confirmation and cooldown persistence have an explicit service-owned wiring path;
- unsupported RMF content is rejected before admission;
- each public RMF lease exposes one opaque acquisition identity used for callback validation and SwiftUI identity;
- dismissal and unique-shown guarantees match the existing best-effort store APIs; and
- backgrounding unpublishes RMF, signals consumers, releases ownership, and disarms RMF admission until another explicit NTP preparation.

## Product decisions confirmed — 2026-08-15

- **Modal scope:** “modal sheets” means launch-promo providers routed through `PromoCoordinationService`, not every arbitrary UIKit sheet. This matches the original and adjusted designs.
- **NTP integration seam:** an NTP container has one Promo Queue-specific integration point: call `prepareForNTP(openedAfterIdle:)` once per content activation, before its initial eligibility read. Lease ownership, cooldowns, refresh, release, background handling, and accounting remain central. No surface reports visibility or lifecycle state.
- **Mixed triggers:** the first admitted message and trigger lane stay authoritative for that ownership. A later renderer request cannot replace a still-valid owner; dismissal, expiry, replacement, onboarding suppression, backgrounding, or another real invalidation ends the pin.
- **Persistence semantics:** existing dismissal and unique-shown behaviors remain best effort. This iteration does not widen shared store APIs, add a unique-shown reservation, or add telemetry for stronger guarantees.

## Decision summary

Use one app-scoped, main-actor promo slot. A launch-modal attempt or an NTP RMF message may own it, but not both.

The three iOS NTP renderers will not register themselves with the coordinator or report whether they are active, renderable, visible, or covered. Instead, the shared `HomePageConfiguration` will acquire and retain the RMF lease before it publishes a remote message into `homeMessages`. All current NTP renderers already read from that same configuration, so they need no per-renderer lease or visibility integration. Conditional containers perform one shared-source preparation before asking whether content exists.

RMF ownership follows the active message, not the physical view:

- the same message ID reuses the current lease;
- a dismissed, expired, or replaced message releases it;
- leaving the NTP does not release it;
- backgrounding first unpublishes the RMF and then releases it; and
- process termination clears all in-memory ownership.

This is intentionally less precise than the discarded design and follows the useful part of Android's implementation: claim before publishing NTP view state and accept that an active card can over-hold the slot. iOS centralizes that decision one level earlier in its shared message source. It also retains two inexpensive safety improvements: ownership is keyed by message ID, and the RMF cooldown is confirmed on actual appearance rather than when the message disappears.

The result is a coordination seam, not a scheduler or general-purpose queue.

## Goal

Prevent launch-promo modal sheets managed by `PromoCoordinationService` and NTP RMF cards from being admitted together on iOS, while keeping the implementation small, maintainable, and easy to inherit when the NTP UI changes. The coordinated launch-promo set currently consists of the new address-bar picker, default-browser prompt, win-back offer, subscription promo, existing-user subscription promo, What's New, and cookie-popup-protection opt-in providers.

## In scope

- Atomic mutual exclusion between coordinated launch-modal attempts and NTP RMF messages.
- Admission before modal-provider evaluation and before RMF publication.
- The existing modal provider order, eligibility, presentation, cooldown, and accounting behavior.
- Existing `RecentModalPromptStatusProviding` behavior used to suppress other session promos while a modal attempt is pending or active.
- Source-owned RMF ownership in the shared `HomePageConfiguration`, terminated by message lifecycle or the one app-scoped background checkpoint.
- The directional Promo Queue cooldowns from the adjusted design.
- Existing RMF event definitions, metric-eligibility checks, dismissal, and action handling. In coordinated mode, regular shown fires once per ownership after actual appearance; unique-shown is evaluated at that point and preserves the existing best-effort first-ever-message semantics. Legacy-mode frequency remains unchanged.
- A startup-latched feature mode behind `.promoPresentationCoordination`.
- Focused behavior-level tests and internal diagnostics.
- A remote-config rollout to all iOS users after validation.

## Out of scope

- Coordinating arbitrary UIKit sheets or overlays that are not launch-modal providers.
- Guaranteeing that only one physical copy of an RMF card is mounted across the three NTP renderers.
- Tracking NTP host visibility, coverage, window attachment, or renderer priority.
- Renderer selection, renderer handoff, drain state, or exact SwiftUI removal completion.
- A general promo priority queue, fairness, preemption, caps, restoration, or retry timers.
- Changes to RMF targeting, scheduling, dismissal, or campaign configuration.
- Changes to macOS `PromoService` or Android code.
- New Promo Queue telemetry.
- Atomic cross-process `remoteMessageShownUnique` reservation.

## Background

PR #6087 established a correct but broad foundation: `PromoQueueLeaseArbiter`, modal attempt phases, exact-root reconciliation, live feature transitions, per-surface RMF identities, and retry registration. The discarded follow-up design then added explicit exposure reporting from the standard NTP, suggestion tray, unified input, and overlays; renderer selection; logical sessions; handoff/drain state; and exact removal terminals.

That design solved more than the product problem. It attempted to prove which physical NTP renderer was visible at every moment. It consequently required every current and future host or covering overlay to report the correct state. A missing integration would fail silently.

The product requirement does not need that proof. It needs an atomic decision before either conflicting kind of promo is admitted.

## Android reference

The Android implementation was inspected in `/Users/bkunat/Desktop/ddg-workspace/ddg-android`; the feature landed in commit `03f99a0e42` (PR #9289).

Its relevant current production-NTP flow is:

- `RealPromptsCoordinator` owns one app-scoped in-memory slot;
- `NewTabPageViewModel` claims `NTP_CARD` before publishing the active RMF message into NTP view state;
- a refused claim publishes no card;
- the claim remains while the active-message flow is non-`null`;
- no view-disappear or background signal releases the claim; and
- actual RMF impression reporting remains a later view callback.

Android's claim is type-keyed rather than message-keyed: same-type `NTP_CARD` callers join the owner, and a same-type completion can release it. The experimental configurable NTP's separate `RemoteMessageViewModel` is not part of this coordinated path. The final iOS design copies the pre-publication ownership idea, not every Android detail.

| Concern | Android | Final iOS choice |
| --- | --- | --- |
| Live owner | Prompt type only | Modal attempt identity or RMF message identity |
| Busy acquisition | Waits up to one second | Synchronous, fail-fast main-actor admission |
| RMF release | Active message becomes `null` | Message is dismissed, expires, or is replaced |
| Background/view disappearance | Neither releases | Background releases RMF; ordinary view disappearance does not |
| Modal ownership | Released when an evaluator reports `ModalShown`; some evaluators have only enqueued activity launch at that point, so cooldown provides the remaining spacing | Retained until the exact modal root is reconciled as detached |
| RMF cooldown confirmation | Raw active-message flow becomes `null`, regardless of physical appearance | First actual admitted appearance |
| Renderer visibility | Not tracked | Not tracked |

Message identity and exact modal-root ownership are retained because they are already inexpensive on iOS and make stale callbacks safer. Android's one-second wait, type-only identity, early modal release, and background retention are not copied. The iOS background choice follows the proposal and deliberately favors freeing the ownership slot so modal admission can be reconsidered, while preserving any confirmed cooldown history.

## Design principles

1. **Coordinate at shared sources, not views.** New NTP renderers using `HomePageConfiguration` inherit coordination automatically.
2. **Ask before side effects.** Providers are not queried and RMF UI is not published until the slot is acquired.
3. **Serialize on the main actor.** Acquisition, selection, publication, confirmation, and release do not yield across the check-and-mutate boundary.
4. **Prefer suppression to overlap.** Uncertain or blocked work remains unshown and can be reconsidered later.
5. **Keep policy with its existing owner.** RMF still selects messages; the modal manager still selects providers; the gate only coordinates admission and cross-promo cooldowns.
6. **Use stable token identity.** Duplicate or stale callbacks cannot release, dismiss, or confirm a newer ownership, including one that reuses the same message ID.
7. **Accept checkpoint-driven progress.** Time passing alone does not schedule work.
8. **Keep renderer integration bounded.** A renderer of the shared NTP RMF source gets one imperative integration point: preparation at content activation. If it needs lease, release, visibility, coverage, or lifecycle calls, move that responsibility back to the shared source.

## Architecture

```text
RemoteMessagingStore
        |
        v
HomePageConfiguration -- acquire RMF before publication --> PromoCoordinationService
        |                                                     |
        v                                                     v
all NTP renderers                                    PromoQueueLeaseArbiter
                                                              ^
                                                              |
launch foreground --> PromoCoordinationService --> modal admission
                                         |
                                         v
                          ModalPromptCoordinationManager
```

### `PromoCoordinationFactory`

The factory reads `.promoPresentationCoordination` once while building the app-scoped dependency graph and resolves an immutable `PromoCoordinationMode`:

```swift
enum PromoCoordinationMode {
    case legacy
    case coordinated
}
```

The service does not subscribe to feature updates. A remote or local override takes effect after the graph is rebuilt, which in production means force-quit and relaunch. This removes live-transition barriers, lease invalidation, re-adoption, and the tests required only for those transitions.

When the mode is `.legacy`, modal and RMF behavior use their existing uncoordinated paths and no new RMF cooldown history is read or written.

### `PromoQueueLeaseArbiter`

The arbiter is one small, app-scoped, main-actor mutual-exclusion primitive:

```text
none
modal(attemptID, acquisitionID)
remoteMessage(messageID, acquisitionID, hasAppeared)
```

It owns no provider order, RMF targeting, onboarding policy, presentation, persistence, or view lifecycle.

The implementation may keep distinct typed modal and RMF lease tokens. A single generic token is not a goal; type safety is preferable to saving a few declarations. Both raw tokens must provide:

- identity-checked, idempotent release;
- stale-token protection through an acquisition identity; and
- weak-token recovery so an abandoned owner cannot wedge the process forever.

The requesting component retains its token strongly for the complete ownership lifetime. The arbiter retains only a weak reference.

The raw RMF token exposes `confirmAppearance() -> Bool`. It returns `true` only for the first valid confirmation of the current acquisition and owns no persistence or event reporting. This keeps the arbiter a pure mutual-exclusion primitive.

The read-only snapshot needed by tests and the debug screen contains only the current owner, its public debug identity, and whether the current RMF ownership has confirmed an appearance.

### `PromoCoordinationService`

`PromoCoordinationService` is the thin gate around the arbiter, directional cooldown policy, and modal manager. It has two typed admission routes.

For modals, `presentModalPromptIfNeeded`:

1. Preserves the existing launch-source and unrelated-presented-controller checks.
2. Lazily reconciles a previously presented coordinated modal.
3. Acquires the modal slot.
4. Evaluates the RMF-to-modal cooldown.
5. Only then asks `ModalPromptCoordinationManager` to evaluate providers.
6. Releases directly, without recording history, if the cross-promo cooldown denies admission.
7. Otherwise transfers lease ownership to the manager. The manager releases it if provider evaluation selects no modal, or retains that same lease if a modal is selected.

Acquisition and cooldown denial occur before provider evaluation because `provideModalPrompt()` may have side effects.

For RMF, a narrow `PromoGating` protocol exposes coordinated mode and synchronous acquisition by message ID. `HomePageConfiguration` is the sole current client. Before RMF acquisition the service lazily reconciles an exact modal root, then checks the slot and modal/RMF-to-RMF cooldowns. If the cooldown denies a request after temporary slot acquisition, the service releases that acquisition synchronously before returning no lease.

The service returns a small public RMF lease wrapper that strongly retains the raw arbiter token and exposes its opaque, hashable acquisition identity. Its no-argument `markShown() -> Bool` calls the raw token's `confirmAppearance()` and, only when that returns `true`, records the RMF cooldown timestamp through the injected history component. It remains nonthrowing and returns `true` for that first valid appearance even if durable persistence fails; the history component keeps its in-process value authoritative and logs/absorbs the storage error. Release forwards to the raw token. `HomePageConfiguration` retains only this wrapper and remains responsible for firing existing RMF shown events after a successful `markShown()`. This assigns persistence explicitly without putting it in the arbiter.

There is deliberately no collection of renderer registrations and no owner-release broadcast. Denied work retries at existing checkpoints.

### `ModalPromptCoordinationManager`

The manager continues to own:

- modal provider order and eligibility;
- onboarding rules specific to each provider;
- the existing remotely configured modal-to-modal cooldown;
- the inherited presentation delay;
- UIKit presentation;
- provider and session accounting; and
- the exact root of the coordinated modal.

Once the service passes the cross-promo cooldown and calls the manager, the manager owns the modal lease. It releases the lease if modal-to-modal cooldown or provider evaluation selects nothing. Otherwise it carries the same lease through evaluation, committed scheduling, and presentation. The lease is released when an existing checkpoint proves the exact selected root is no longer attached. A nested child does not end the modal attempt. The service does not release a lease after transferring it to the manager.

`didPresentModalPromptThisSession` must continue to suppress dependent session promos while a modal is evaluating, committed, or attached, and after an actual presentation. An evaluation that selects nothing returns to idle and stops temporary suppression when there is no earlier presentation history; it must not erase earlier actual-presentation history. No new pre-presentation cancellation mechanism is introduced.

The design does not add a dismissal callback to every modal provider. If dismissal is not observed immediately, the detached modal may over-hold the slot until the next foreground or RMF admission attempt. This is safer and much smaller than wiring every dismissal path.

### `HomePageConfiguration`

`HomePageConfiguration` is created once in `MainCoordinator` and is already passed to the standard NTP, suggestion tray, and unified-input NTP renderers. It becomes the sole logical owner of the RMF lease.

In coordinated mode, initialization builds only non-RMF home messages. It must not fetch or acquire RMF while `MainCoordinator` is being constructed; doing so would let a scheduled card claim the slot before cold-start launch-modal evaluation, even when the restored tab is a website. RMF admission begins only when an NTP-capable path calls a source-level operation such as `prepareForNTP(openedAfterIdle:)`.

The standard NTP calls this operation at its existing home-screen attachment refresh. Suggestion tray and unified input conditionally decide whether to construct NTP content by inspecting the shared array, so each must call the same source operation immediately before its existing eligibility read. These are content-loading calls at container seams, not renderer visibility or lease callbacks. A future renderer that directly consumes the already-prepared shared model needs no Promo Queue call; only a conditional container that asks whether NTP content exists before constructing a consumer must prepare the shared source first.

In coordinated mode, `HomePageConfiguration` is the sole observer of the global `remoteMessagesDidChange` notification. After it has refreshed `homeMessages`, it emits a separate object-scoped configuration signal. `NewTabPageMessagesModel` and direct host-level consumers observe that signal and rebuild or reevaluate eligibility from the shared array; they do not run candidate selection. Model delivery is synchronous on the main actor so teardown's unpublish/signal/release ordering is real; host layout reactions may still schedule their UI work. Legacy mode retains the existing notification path. The global store notification must not be reused as the configuration signal.

Use one teardown sequence everywhere an ownership ends: remove the current RMF from the shared `homeMessages`, synchronously signal all models to rebuild from that source, then release and clear the retained lease. If the source did not change or there is no lease, the corresponding step is a no-op.

Its coordinated `remoteMessageToShow` flow is:

1. Build the existing non-RMF messages and apply onboarding rules.
2. If onboarding suppresses RMF, run the teardown sequence and return the non-RMF messages.
3. If an owner exists, reevaluate its pinned trigger lane. If the same message remains scheduled and passes the pure renderability predicate, keep its lease/acquisition identity, publish refreshed content, signal if needed, and return. A later renderer request with a different trigger does not replace it.
4. If the current owner is no longer valid, run the ordered teardown before any fresh selection, even when another lane could return the same message ID.
5. Fetch a fresh candidate using the explicit request's lane (`afterIdle` or no trigger), or the last explicitly prepared lane when the refresh came from the store.
6. If there is no candidate or `HomeMessageViewModelBuilder.canBuild(for:)` (or its equivalent pure predicate) returns false, publish only the non-RMF messages. The predicate must use the same content-to-display conversion as the full builder; do not invoke the side-effecting builder as a probe or duplicate another support switch.
7. Attempt to acquire a lease for the new ID.
8. On success, retain the lease and trigger lane before publishing the candidate into `homeMessages`, then signal models to rebuild.
9. On failure, publish no RMF and leave the underlying scheduled message untouched.

The configuration releases its lease when a refresh observes dismissal, expiry, replacement, no eligible/renderable message, or onboarding suppression. It does not release when a renderer disappears, the user leaves the NTP, or one of several physical cards disappears.

Track the last explicitly prepared trigger lane separately from the current owner's pinned lane. Explicit `prepareForNTP` updates it; coordinated store refreshes use it when fresh selection is needed; background clears it. This gives store-driven retry a defined lane even when a previous attempt was denied and no owner exists.

On app background, the configuration uses the same ordered teardown, clears both trigger values, and disarms RMF admission. Store notifications while disarmed may refresh non-RMF data but cannot reacquire RMF. Foregrounding only marks the source active again; it does not publish a card. The next explicit `prepareForNTP` request can select and acquire one. This is one app-scoped lifecycle integration through `MainCoordinator`, not a callback from every renderer.

Whenever coordinated `homeMessages` changes, `HomePageConfiguration` emits one configuration-level change signal so every `NewTabPageMessagesModel` converges on the same shared value. Observers rebuild from that value; they do not trigger another candidate refresh. This is a content update, not renderer registration: it carries no renderer identity, ordering, visibility, acknowledgement, or retry intent. When ending RMF ownership, the shared source removes the old message and emits that signal before releasing the lease.

The same shared configuration supplies all renderers, so same-ID reuse requires neither a surface ID nor a retain count.

For each coordinated RMF view-model mapping, the configuration supplies an opaque presentation context containing the message ID and the public lease's acquisition identity. Appearance and dismissal callbacks capture and return that context. The configuration validates it before confirming appearance, mutating RMF lifecycle state, or releasing ownership. A same-ID content refresh keeps the context and SwiftUI identity stable because it is the same ownership; releasing and later reacquiring the same message ID creates a new lease identity, so callbacks from the old physical view become no-ops and SwiftUI constructs a new card. A valid asynchronous dismissal normally keeps its ownership authoritative until the store operation returns, preventing a refresh from replacing it mid-dismissal. Background teardown is the exception: it ends ownership immediately. Its later callback cannot directly release or confirm a new lease, although the already-started store operation and resulting store notification are still reconciled normally.

### `NewTabPageMessagesModel` and `HomeMessageView`

Renderers remain unaware of leases. They map the already-gated `homeMessages` array and forward the card's existing callbacks with the opaque presentation context; they never inspect it or report renderer lifecycle. Coordinated RMF view models expose the same opaque acquisition identity solely for SwiftUI diffing. `NewTabPageView` keys the card by message plus acquisition identity (or an equivalent composite value); legacy and non-RMF messages keep their current identity behavior.

Today, mapping and the later view `onDidAppear` can both call RMF shown accounting, so `.remoteMessageShown` may fire repeatedly while unique-shown is separately store-guarded. In coordinated mode, eager map-time accounting is removed intentionally. On actual appearance, `HomePageConfiguration` first validates the captured message/acquisition context against the current wrapper, then calls its no-argument `markShown()`. Only the first valid call for that ownership returns `true`, records the RMF queue timestamp, fires the regular shown event, and evaluates the existing unique-shown guard. Calls from another physical mount of the same shared message are ignored for that ownership lifetime. The store's check and asynchronous update are not atomic, so rapid release and same-ID reacquisition can still evaluate unique-shown twice. This design preserves the existing best-effort first-ever semantics instead of adding a process-local reservation.

In legacy mode, current behavior is preserved behind an explicit mode branch. The implementation must not silently change the feature-off accounting path as part of rollout.

`HomePageConfiguration` rejects mismatched or stale callback contexts before calling `markShown()` or coordinated dismissal. The wrapper/raw token returns `false` after release or stale raw ownership. A never-mounted card may hold a lease but does not write cooldown or shown history.

## Behavioral rules

### RMF first

If `HomePageConfiguration` owns an RMF lease, modal acquisition fails before provider evaluation. No modal provider, cooldown, shown state, or impression state changes. The modal is reconsidered on a later eligible foreground.

### Modal evaluation first

The service acquires the modal lease before provider evaluation. A concurrent RMF refresh cannot publish a card. After ownership transfers into provider evaluation, the manager releases the lease synchronously if no provider is eligible and records no presentation.

### Modal committed or visible

The modal manager retains the lease through its scheduling delay and while the exact root remains attached. RMF admission fails and the card is never mounted, marked shown, dismissed, or consumed.

### Modal dismissed

The next foreground or RMF admission checkpoint reconciles the exact root. Once detached, the modal lease is released. The RMF must also pass its 10-minute incoming cooldown before it can publish.

### RMF dismissed, expired, or removed

The next configuration refresh removes the card from the shared source, signals all models to rebuild, and then releases its lease. An explicit dismissal performs the same ordering after the store dismissal attempt completes when its context is still current; the current store API does not report persistence success. Every validly started dismissal preserves one store-refresh notification. If its context became stale during the await, it does not directly mutate a newer lease, but the configuration-owned observer still reconciles the resulting authoritative store state. Modal evaluation is not triggered immediately; it remains a foreground operation.

### RMF replaced

The old ID is unpublished from every model snapshot and released before the new ID is considered. The new ID is a new acquisition and must pass the RMF incoming cooldown. A same-ID content refresh keeps the current ownership and appearance state while still notifying models when the shared content changed.

### Background and foreground

Backgrounding removes the coordinated RMF from `homeMessages`, emits the configuration signal, then releases the lease and clears its trigger/presentation context. It records no new shown or cooldown history and does not clear history already confirmed on appearance. RMF admission remains disarmed while the app is inactive, so a store notification cannot immediately reacquire the same card.

Foregrounding re-enables future explicit NTP preparation but does not itself select or publish RMF. The stale background owner therefore cannot block ownership acquisition, but any previously confirmed RMF-to-modal cooldown still applies; after foreground, whichever eligible explicit admission checkpoint runs first wins the slot. If an NTP-capable path later calls `prepareForNTP`, the still-scheduled message can be reconsidered and receives a new acquisition identity if admitted. Ordinary NTP disappearance still does not release ownership.

All live ownership is in memory and is cleared on process termination. Persisted cooldown timestamps remain.

## Cooldown policy

Cooldowns are evaluated after acquiring the slot but before side-effecting work. A denial releases the new acquisition without changing history.

| Previous confirmed appearance | Incoming promo | Required elapsed time |
| --- | --- | --- |
| Launch modal | NTP RMF | 10 minutes |
| NTP RMF | NTP RMF | 10 minutes |
| NTP RMF | Launch modal | 24 hours |
| Launch modal | Launch modal | Existing remotely configured modal cooldown, currently/default 24 hours |

`PromoQueueCooldownPolicy` uses:

- the existing confirmed modal-presentation store;
- one injected `ThrowingKeyValueStoring`-backed timestamp for the last confirmed RMF appearance; and
- an injected clock for deterministic tests.

Timestamps represent confirmed source events, not expiry dates. Exact equality is eligible. A future timestamp conservatively remains in cooldown. A failed RMF timestamp write remains authoritative for the current process; a fresh process sees only durable history. A storage-read failure uses the last successful in-process value when one exists and otherwise behaves as no known RMF history.

The first valid public-lease `markShown()` call records the RMF timestamp through the service-owned wrapper. RMF acquisition, denial, mapping, dismissal, background teardown, or lease release does not.

There is no cooldown timer. Reaching a boundary does not itself cause a retry.

## Reconsideration checkpoints

Blocked work is reconsidered only when an existing event causes evaluation:

- an explicit NTP source preparation or refresh;
- a coordinated `remoteMessagesDidChange` refresh while RMF admission is armed;
- candidate dismissal, expiry, replacement, or configuration update;
- an `afterIdle` refresh;
- foreground modal evaluation; or
- an RMF attempt that first reconciles a detached modal.

The system does not maintain waiting queues, retry registrations, renderer callbacks, or boundary timers. This can delay an otherwise eligible promo beyond its minimum cooldown.

## Feature flag and rollout behavior

Keep:

- `FeatureFlag.promoPresentationCoordination`;
- `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination`; and
- the broader shared `PrivacyFeature.promoQueue`, which is also used outside this iOS implementation.

The iOS subfeature remains disabled by default in code and locally overridable. Production rollout is controlled remotely. Because mode is startup-latched, enabling or disabling takes effect on the next process graph.

The rollout change is externally owned in `duckduckgo/privacy-configuration`, under parent `promoQueue` and subfeature `iOSPromoPresentationCoordination`, with a minimum version that contains the complete implementation stack. The feature is not complete against its success criterion until coordinated mode has been rolled out to 100% of supported iOS users.

## Debugging

Extend the existing Modal Prompt Coordination internal debug screen rather than adding a new screen. Its simplified Promo Queue section should expose:

- startup-latched mode and the relaunch requirement;
- current owner kind and identity;
- current modal phase;
- active RMF message ID and whether appearance was confirmed;
- last confirmed modal and RMF timestamps;
- derived next RMF and next modal eligibility boundaries; and
- the most recent admission denial reason, if it can be captured without adding production state solely for diagnostics.

Provide an explicit refresh action. Keep the existing modal cooldown reset and add an explicit internal-only RMF cooldown reset for manual testing. The reset must go through the authoritative RMF history component and clear both its durable timestamp and any in-process value used for failure fallback. It must not release an active owner or dismiss a message. Do not add force-acquire controls that can manufacture impossible production ownership.

Diagnostics add no telemetry and must use side-effect-free reads except for explicit reset actions.

## Adding future promo entry points

### A new NTP implementation

Use the existing shared `HomePageConfiguration`/`NewTabPageMessagesModel` path. The complete imperative Promo Queue integration contract is one `prepareForNTP(openedAfterIdle:)` call per content activation, immediately before that container's initial eligibility read. A conditional container also observes the ordinary configuration content-change publisher so it can reevaluate eligibility.

The container must not call the gate, acquire or release a lease, call `markShown`, report visibility/coverage/lifecycle, or participate in handoff. Existing card appearance, dismissal, and action callbacks continue through `NewTabPageMessagesModel`; they are not container coordination responsibilities. If a future implementation appears to need more Promo Queue calls, extend the shared source rather than the renderer.

### A new launch-modal provider

Register it in the existing provider list. It automatically runs behind modal admission and retains existing provider policy.

### A new independent RMF surface

It is not automatically part of the current same-ID ownership contract. Add one source-level admission adapter before publishing UI and make that source own the entire lease lifecycle. Views consuming that source must not acquire, release, or report visibility individually. Joining ownership across independent sources is deliberately deferred until a real use case establishes its identity and lifecycle semantics.

### A new modal system outside `PromoCoordinationService`

It is not coordinated automatically. It must deliberately route its launch-promo admission through the gate, or remain out of scope. Arbitrary UIKit presentation is not intercepted.

## Accepted limitations

These tradeoffs are intentional and must not be reintroduced as bugs during implementation:

- An active RMF may hold the slot while the user is off the NTP. A message-lifecycle or background checkpoint releases that live ownership, but a previously confirmed RMF-to-modal cooldown can still defer the modal.
- Fire mode can suppress the card while source ownership remains. No explicit constrained-landscape suppression exists today; landscape is a QA case, not a designed lease rule.
- Two physical copies of the same RMF can be mounted briefly during renderer handoff. The system guarantees cross-kind admission, not one physical RMF renderer.
- Candidate selection across shared refreshes is checkpoint-driven and not a fair queue.
- A dismissed modal may over-hold until lazy exact-root reconciliation.
- A blocked promo may remain hidden after its cooldown expires until another natural checkpoint.
- RMF release follows removal from the shared source, not proof that every exit-animation pixel is gone. No immediate modal retry is triggered from RMF release, which keeps the normal removal path safe without an exact-removal state machine.
- In coordinated mode, `.remoteMessageShown` runs once per admitted ownership after actual appearance. Unique-shown preserves the existing best-effort first-ever behavior; it is not made atomically exact across rapid reacquisitions. Legacy mapping/on-appear duplicates are intentionally not reproduced.
- Arbitrary UIKit overlays and sheets are not intercepted and may cover an RMF; they remain outside the confirmed launch-promo scope.
- Feature flag changes require a relaunch.
- No new telemetry measures denial, fairness, or overlap.

## Alternatives rejected

### Explicit renderer exposure and handoff

Rejected because it spreads non-compiler-enforced calls through NTP hosts and overlays, creates a large state machine, and solves the unrequired problem of selecting exactly one physical renderer.

### Per-renderer leases with retain counting

Rejected because `HomePageConfiguration` is already the single shared source. Counting appearances and disappearances would recreate view-lifecycle coordination for precision that the success criterion does not require.

### Releasing RMF ownership on ordinary view disappearance

Rejected because per-view release would require tracking which of several physical renderers still represents the shared message. Background release is retained as one app-scoped exception: the shared source can synchronously unpublish once, signal all consumers, and release without renderer identities.

### Copying Android literally

Rejected because type-only ownership, a one-second waiter, cooldown confirmation at message disappearance, and early modal release are not necessary on iOS. The source-level model is the useful transferable idea.

### Moving coordination into `RemoteMessagingStore`

Rejected because the conflict is iOS presentation policy, while the store owns cross-platform RMF scheduling and persistence. `HomePageConfiguration` is already the shared iOS presentation boundary and has a smaller blast radius.

## Verification strategy

Use focused unit and integration coverage for externally observable behavior:

- atomic modal/RMF exclusion and identity-safe release;
- provider chains not queried when RMF owns the slot;
- RMF not published or accounted when a modal owns the slot;
- same-ID reuse and different-ID replacement;
- release and same-ID reacquisition rejecting callbacks from the earlier acquisition;
- exactly one confirmed appearance per RMF ownership;
- regular shown once per ownership while unique-shown retains best-effort first-ever-message behavior;
- cold launch/restored website does not acquire RMF before an explicit NTP preparation;
- unsupported content cannot acquire a lease;
- one configuration-owned store refresh updates all model and direct-array consumers;
- mixed-trigger refreshes keep the admitted message and trigger pinned;
- background teardown unpublishes before release and disarms reacquisition until explicit preparation;
- public lease/acquisition identity is stable within ownership and changes on same-ID reacquisition;
- the four cooldown directions and exact boundaries;
- no history update for denial or never-appeared content;
- modal lease retention through scheduling, nested presentation, and exact-root detachment;
- pending/active modal suppression and actual-presentation session history;
- message dismissal, expiry, replacement, `afterIdle`, and onboarding behavior;
- startup-latched legacy/coordinated behavior; and
- weak-token recovery.

Do not recreate broad suites for renderer order, host exposure propagation, handoff/drain identities, exact SwiftUI removal terminals, or one-physical-card enforcement.

Manual validation must still exercise the standard NTP, suggestion tray, and unified-input NTP because all three consume the shared configuration, plus Fire mode, landscape as behavior discovery, background release/reacquisition, and delayed-retry cases.
