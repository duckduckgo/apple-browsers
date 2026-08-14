# Promo Queue: simplified iOS technical design

## Status and source of truth

This document is the proposed final design for the iOS Promo Queue iteration. It supersedes the implementation direction in:

- [`tech_design_oridingal.md`](tech_design_oridingal.md);
- [`tech_design_adjusted.md`](tech_design_adjusted.md); and
- [`new_direction_proposal.md`](new_direction_proposal.md), where this document makes the remaining choices explicit.

Only [PR #6087](https://github.com/duckduckgo/apple-browsers/pull/6087) is part of the merged iOS baseline. The larger implementation described by the adjusted design is useful historical context, but it is not the target architecture.

The implementation starts from `bartosz/promo-q-simp-2`, which matched `main` at `f5b0e0abd4` when this design was written. The scope is iOS only. Android is a reference implementation, not a delivery target.

## Decision summary

Use one app-scoped, main-actor promo slot. A launch-modal attempt or an NTP RMF message may own it, but not both.

The three iOS NTP renderers will not register themselves with the coordinator or report whether they are active, renderable, visible, or covered. Instead, the shared `HomePageConfiguration` will acquire and retain the RMF lease before it publishes a remote message into `homeMessages`. All current NTP renderers already read from that same configuration, so they become coordinated without host-specific integration.

RMF ownership follows the active message, not the physical view:

- the same message ID reuses the current lease;
- a dismissed, expired, or replaced message releases it;
- leaving the NTP or backgrounding the app does not release it; and
- process termination clears all in-memory ownership.

This is intentionally less precise than the discarded design and follows the useful part of Android's implementation: claim before publishing NTP view state and accept that an active card can over-hold the slot. iOS centralizes that decision one level earlier in its shared message source. It also retains two inexpensive safety improvements: ownership is keyed by message ID, and the RMF cooldown is confirmed on actual appearance rather than when the message disappears.

The result is a coordination seam, not a scheduler or general-purpose queue.

## Goal

Prevent launch-modal promos managed by `PromoCoordinationService` and NTP RMF cards from appearing together on iOS, while keeping the implementation small, maintainable, and easy to inherit when the NTP UI changes.

## In scope

- Atomic mutual exclusion between coordinated launch-modal attempts and NTP RMF messages.
- Admission before modal-provider evaluation and before RMF publication.
- The existing modal provider order, eligibility, presentation, cooldown, and accounting behavior.
- Existing `RecentModalPromptStatusProviding` behavior used to suppress other session promos while a modal attempt is pending or active.
- Message-lifecycle RMF ownership in the shared `HomePageConfiguration`.
- The directional Promo Queue cooldowns from the adjusted design.
- Existing RMF event definitions, metric-eligibility checks, dismissal, and action handling. In coordinated mode, regular shown fires once per ownership after actual appearance; unique-shown is evaluated at that point but retains its existing first-ever-message semantics. Legacy-mode frequency remains unchanged.
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
| Background/view disappearance | Does not release | Does not release |
| Modal ownership | Released when an evaluator reports `ModalShown`; some evaluators have only enqueued activity launch at that point, so cooldown provides the remaining spacing | Retained until the exact modal root is reconciled as detached |
| RMF cooldown confirmation | Raw active-message flow becomes `null`, regardless of physical appearance | First actual admitted appearance |
| Renderer visibility | Not tracked | Not tracked |

Message identity and exact modal-root ownership are retained because they are already inexpensive on iOS and make stale callbacks safer. Android's one-second wait, type-only identity, and early modal release are not needed.

## Design principles

1. **Coordinate at shared sources, not views.** New NTP renderers using `HomePageConfiguration` inherit coordination automatically.
2. **Ask before side effects.** Providers are not queried and RMF UI is not published until the slot is acquired.
3. **Serialize on the main actor.** Acquisition, selection, publication, confirmation, and release do not yield across the check-and-mutate boundary.
4. **Prefer suppression to overlap.** Uncertain or blocked work remains unshown and can be reconsidered later.
5. **Keep policy with its existing owner.** RMF still selects messages; the modal manager still selects providers; the gate only coordinates admission and cross-promo cooldowns.
6. **Use stable token identity.** Duplicate or stale callbacks cannot release, dismiss, or confirm a newer ownership, including one that reuses the same message ID.
7. **Accept checkpoint-driven progress.** Time passing alone does not schedule work.

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

The implementation may keep distinct typed modal and RMF lease tokens. A single generic token is not a goal; type safety is preferable to saving a few declarations. Both tokens must provide:

- identity-checked, idempotent release;
- stale-token protection through an acquisition identity; and
- weak-token recovery so an abandoned owner cannot wedge the process forever.

The requesting component retains its token strongly for the complete ownership lifetime. The arbiter retains only a weak reference.

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

Use one teardown sequence everywhere an ownership ends: remove the current RMF from the shared `homeMessages`, synchronously signal all models to rebuild from that source, then release and clear the retained lease. If the source did not change or there is no lease, the corresponding step is a no-op.

Its coordinated `remoteMessageToShow` flow is:

1. Build the existing non-RMF messages and apply onboarding rules.
2. If onboarding suppresses RMF, run the teardown sequence and return the non-RMF messages.
3. Fetch the candidate for the requested trigger (`afterIdle` or no trigger).
4. If there is no candidate, run the teardown sequence and return the non-RMF messages.
5. If the candidate has the same ID as the retained lease, retain its appearance state, publish the refreshed shared content, and signal models if that content changed. Do not make another cooldown decision.
6. If the ID changed, run the teardown sequence for the old ID.
7. Attempt to acquire a lease for the new ID.
8. On success, retain the lease before publishing the candidate into `homeMessages`, then signal models to rebuild.
9. On failure, publish no RMF and leave the underlying scheduled message untouched.

The configuration releases its lease when a refresh observes dismissal, expiry, replacement, or no eligible message. It does not release when a renderer disappears, the user leaves the NTP, the app backgrounds, or one of several physical cards disappears.

Whenever coordinated `homeMessages` changes, `HomePageConfiguration` emits one configuration-level change signal so every `NewTabPageMessagesModel` converges on the same shared value. Observers rebuild from that value; they do not trigger another candidate refresh. This is a content update, not renderer registration: it carries no renderer identity, ordering, visibility, acknowledgement, or retry intent. When ending RMF ownership, the shared source removes the old message and emits that signal before releasing the lease.

The same shared configuration supplies all renderers, so same-ID reuse requires neither a surface ID nor a retain count.

For each coordinated RMF view-model mapping, the configuration supplies an opaque presentation context containing the message ID and current acquisition identity. Appearance and dismissal callbacks capture and return that context. The configuration validates it before confirming appearance, mutating RMF lifecycle state, or releasing ownership. A same-ID content refresh keeps the context valid because it is the same ownership; releasing and later reacquiring the same message ID creates a new acquisition identity, so callbacks from the old physical view become no-ops. A valid asynchronous dismissal keeps its ownership authoritative until the store operation returns, preventing a refresh from replacing it mid-dismissal.

### `NewTabPageMessagesModel` and `HomeMessageView`

Renderers remain unaware of leases. They map the already-gated `homeMessages` array and forward the card's existing callbacks with the opaque presentation context; they never inspect it or report renderer lifecycle.

Today, mapping and the later view `onDidAppear` can both call RMF shown accounting, so `.remoteMessageShown` may fire repeatedly while unique-shown is separately store-guarded. In coordinated mode, eager map-time accounting is removed intentionally. On actual appearance, `HomePageConfiguration` validates the captured presentation context and asks its matching RMF lease to `markShown()`. Only the first valid call for that ownership returns `true`, records the RMF queue timestamp, fires the regular shown event, and evaluates the existing first-ever guard for unique-shown. Calls from another physical mount of the same shared message are ignored for that ownership lifetime. This changes coordinated regular-impression frequency to once per ownership; it does not change unique-shown into a per-ownership event or claim that the legacy frequency is preserved.

In legacy mode, current behavior is preserved behind an explicit mode branch. The implementation must not silently change the feature-off accounting path as part of rollout.

`markShown()` and coordinated dismissal must reject a released lease, mismatched message ID, and stale acquisition context. A never-mounted card may hold a lease but does not write cooldown or shown history.

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

The next configuration refresh removes the card from the shared source, signals all models to rebuild, and then releases its lease. A successful explicit dismissal performs the same ordering after its store update completes. Modal evaluation is not triggered immediately; it remains a foreground operation.

### RMF replaced

The old ID is unpublished from every model snapshot and released before the new ID is considered. The new ID is a new acquisition and must pass the RMF incoming cooldown. A same-ID content refresh keeps the current ownership and appearance state while still notifying models when the shared content changed.

### Background and foreground

Backgrounding does not release the RMF lease. This matches Android's actual behavior and avoids releasing while SwiftUI may still retain a published card. A still-active message can therefore block a launch modal on a later foreground even while the user was away from the NTP. This over-hold is accepted.

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

The first valid `markShown()` call records the RMF timestamp. RMF acquisition, denial, mapping, dismissal, or lease release does not.

There is no cooldown timer. Reaching a boundary does not itself cause a retry.

## Reconsideration checkpoints

Blocked work is reconsidered only when an existing event causes evaluation:

- NTP/configuration creation or refresh;
- `remoteMessagesDidChange`;
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

Use the existing shared `HomePageConfiguration`/`NewTabPageMessagesModel` path. No coordination call, surface ID, visibility callback, or overlay integration is required.

### A new launch-modal provider

Register it in the existing provider list. It automatically runs behind modal admission and retains existing provider policy.

### A new independent RMF surface

Acquire at that surface's shared message-source boundary before publishing UI, and release from the message lifecycle. Do not add calls from every view or overlay. If several renderers share the source, the source—not each renderer—owns the lease.

### A new modal system outside `PromoCoordinationService`

It is not coordinated automatically. It must deliberately route its launch-promo admission through the gate, or remain out of scope. Arbitrary UIKit presentation is not intercepted.

## Accepted limitations

These tradeoffs are intentional and must not be reintroduced as bugs during implementation:

- An active RMF may hold the slot while the user is off the NTP or the app is backgrounded, delaying a modal until the message ends.
- Fire-mode and constrained landscape layouts may hold an RMF lease even when layout does not draw the card.
- Two physical copies of the same RMF can be mounted briefly during renderer handoff. The system guarantees cross-kind admission, not one physical RMF renderer.
- Candidate selection across shared refreshes is checkpoint-driven and not a fair queue.
- A dismissed modal may over-hold until lazy exact-root reconciliation.
- A blocked promo may remain hidden after its cooldown expires until another natural checkpoint.
- RMF release follows removal from the shared source, not proof that every exit-animation pixel is gone. No immediate modal retry is triggered from RMF release, which keeps the normal removal path safe without an exact-removal state machine.
- In coordinated mode, `.remoteMessageShown` runs once per admitted ownership after actual appearance; unique-shown is checked once there and still emits only for the message's first-ever shown transition. Legacy mapping/on-appear duplicates are intentionally not reproduced.
- New arbitrary overlays are not detected, because they no longer need to be detected for source-level modal/RMF exclusion.
- Feature flag changes require a relaunch.
- No new telemetry measures denial, fairness, or overlap.

## Alternatives rejected

### Explicit renderer exposure and handoff

Rejected because it spreads non-compiler-enforced calls through NTP hosts and overlays, creates a large state machine, and solves the unrequired problem of selecting exactly one physical renderer.

### Per-renderer leases with retain counting

Rejected because `HomePageConfiguration` is already the single shared source. Counting appearances and disappearances would recreate view-lifecycle coordination for precision that the success criterion does not require.

### Releasing RMF ownership on background or view disappearance

Rejected because a safe background release also requires synchronously unpublishing every retained renderer and defining foreground re-acquisition ordering. Android does not release there. Keeping the lease is simpler and fails toward delayed presentation rather than overlap.

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
- regular shown once per ownership while unique-shown retains first-ever-message behavior;
- the four cooldown directions and exact boundaries;
- no history update for denial or never-appeared content;
- modal lease retention through scheduling, nested presentation, and exact-root detachment;
- pending/active modal suppression and actual-presentation session history;
- message dismissal, expiry, replacement, `afterIdle`, and onboarding behavior;
- startup-latched legacy/coordinated behavior; and
- weak-token recovery.

Do not recreate broad suites for renderer order, host exposure propagation, handoff/drain identities, exact SwiftUI removal terminals, or one-physical-card enforcement.

Manual validation must still exercise the standard NTP, suggestion tray, and unified-input NTP because all three consume the shared configuration, plus the accepted Fire-mode, landscape, background, and delayed-retry cases.
