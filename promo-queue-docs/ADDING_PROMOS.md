# Adding Promo Queue integrations on iOS

## Start here

Iteration one coordinates only:

- launch-modal promos evaluated by `PromoCoordinationService`; and
- RMF cards rendered by a known New Tab Page host.

It is a main-actor mutual-exclusion and fixed-cooldown seam, not a general promo scheduler. Do not route badges, settings rows, notification bars, onboarding, arbitrary UIKit presentations, or other promo surfaces through it without a new product/design decision.

Read `TECH_DESIGN_FINAL.md` for the current contract and `PROMO_QUEUE_LOGICAL_RMF_OWNER_IMPLEMENTATION_PLAN.md` for the central RMF rationale.

## Core model

There is one app-scoped `PromoQueueLeaseArbiter` with one active owner:

```text
none | modal(attemptID) | remoteMessage(messageID, logicalSessionID)
```

Any owner blocks every other coordinated request. `PromoCoordinationService` is the only RMF lease holder and authorizes exactly one physical renderer at a time. The arbiter owns no provider priority, RMF targeting, cooldown, persistence, presentation, or retry timing.

Never:

- construct a second arbiter or service graph for another host;
- add a `.shared` queue singleton;
- put renderer identity in the logical owner;
- let an NTP model acquire or release its own RMF lease;
- reintroduce gate IDs, mount sets, or per-model outgoing-session state;
- store leases in user defaults;
- inject the arbiter or cooldown store into SwiftUI views or providers;
- add a provisional reservation or cooldown timer; or
- release because a cooldown elapsed.

## Feature mode

`PromoCoordinationFactory` samples `.promoPresentationCoordination` once and creates immutable `.legacy` or `.coordinated` behavior for the graph.

- Do not subscribe to live flag changes.
- Set local overrides before graph construction.
- Force-quit/relaunch after changing the flag.
- Legacy mode must preserve lease-free modal evaluation and direct/eager RMF behavior.
- Legacy NTP models must not register a coordinated renderer or read/write queue history.

## Adding or changing a launch-modal provider

The service acquires modal ownership and checks the fixed RMF→modal boundary before the manager evaluates any provider. Provider evaluation may have side effects, so do not query providers while RMF owns the queue or the fixed cooldown is active.

The manager remains responsible for:

- provider ordering and first-eligible selection;
- per-provider onboarding and eligibility;
- the existing remotely tunable modal→modal cooldown;
- prepared work and the inherited `0.1`-second presentation delay;
- UIKit presentation and exact-root lifetime; and
- provider shown/accounting callbacks.

Implement `ModalPromptProvider.isModalPromptStillValidForPresentation(_:)` when retained work can become stale. Keep it read-only. Conform to `InvalidModalPromptReplacing` only when repeating preparation is known to be safe.

Do not release ownership when a nested child is presented or dismissed. End the attempt only after an approved checkpoint proves the exact selected modal root is detached.

## Adding or changing an NTP RMF renderer

### Registration and candidate reporting

In coordinated mode, an NTP model registers through:

```text
registerRemoteMessageRenderer(id:target:)
```

Retain the returned `NewTabPagePromoRendererRegistration` for the renderer lifetime and explicitly deregister during teardown. Report:

- `.none` when no RMF candidate exists;
- `.available(messageID:)` when the exact candidate can be built; or
- `.unrenderable(messageID:)` when a scheduled RMF cannot be represented.

Report `isEligible` from the centralized host exposure/window/lifecycle predicate. Reporting a candidate is not authorization to publish it.

The renderer implements `NewTabPagePromoRendering`:

- `showRemoteMessage(_:)` atomically publishes only the authorized presentation and returns whether it succeeded;
- `hideRemoteMessage(_:removalID:)` begins exact removal;
- `isRemoteMessageRendererAttachedToWindow` supports terminal verification; and
- `hasPublishedRemoteMessagePresentation` lets the service fail closed after an inconsistent rejection.

### Identity and ownership

Keep these identities separate:

- stable renderer ID;
- service-minted registration generation;
- logical session ID plus message ID;
- physical presentation ID; and
- removal ID.

Echo the exact identities through appearance and removal callbacks. Never infer that a callback belongs to the current session from message ID alone.

The service chooses one eligible renderer in stable registration order. A same-message handoff retains the logical session and lease, removes the outgoing presentation, waits for its exact terminal and one settlement turn, then authorizes the successor. A changed/missing/unrenderable candidate ends the session after the same barrier.

### Removal

Do not use `onDisappear` as the release authority and do not guess with a fixed delay.

- On iOS 17+, clear with scale/opacity using `withAnimation(..., completionCriteria: .removed)` and report `.animationCompleted` from the native completion.
- On iOS 15/16, synchronously clear inside a transaction with animations disabled, use `.identity`, verify the source is gone, then report `.sourceRemovedWithoutAnimation`.
- If the exact renderer is physically detached, report `.hostDetached` only after verifying detachment.

The iOS 15/16 coordinated dismissal intentionally has no animation. Do not restore one without a separately proven exact terminal. A missing or unverifiable terminal must fail closed rather than time-release the lease.

### Appearance and accounting

For each authorized physical presentation:

1. ask the registration to confirm the exact session/presentation appearance, including current window attachment;
2. continue only if the service accepts it; and
3. perform ordinary RMF shown accounting once for that physical presentation.

The service confirms persisted queue history only on the first accepted appearance of the logical session. A same-session renderer handoff can perform another ordinary physical appearance accounting event, but it does not restart the Promo Queue cooldown timestamp.

Authorization, denial, build failure, withdrawal before appearance, stale callback, and removal write no queue history.

Atomic `remoteMessageShownUnique` persistence remains an independent optional correctness change. Do not silently mix it into a renderer integration.

## Host exposure contract

Known hosts are:

- standard NTP;
- suggestion tray/favorites NTP; and
- unified-input/favorites NTP.

Use the centralized exposure predicate and outgoing-before-incoming host handoff. `view.window` alone is not enough: a cached controller can remain attached while autocomplete, Duck.ai, or another overlay covers it.

Async host callbacks must carry generation identity so stale completion cannot reactivate an old renderer.

A future host or overlay that can cover or retain an NTP must explicitly:

1. register one stable renderer;
2. report its candidate and logical eligibility;
3. perform outgoing-before-incoming exposure updates;
4. invalidate stale async completion;
5. preserve window/readiness checks; and
6. add direct host and handoff tests.

This obligation is not compiler-enforced. The redesign removes distributed mount bookkeeping; it does not eliminate the need to know which physical host can actually render.

## Cooldown contract

| Confirmed source | Requested target | Required elapsed time |
| --- | --- | --- |
| Modal | RMF | 10 minutes |
| RMF | RMF | 10 minutes |
| RMF | Modal | 24 hours |
| Modal | Modal | Existing remotely tunable interval, currently/default 24 hours |

The service-owned policy reuses the modal manager's persisted confirmed-modal timestamp and owns one persisted confirmed-RMF timestamp. It stores event times, not expiry dates.

Admission order is significant:

- RMF: readiness/eligible renderer → modal reconciliation → acquire global owner → evaluate cooldown → authorize presentation;
- modal: service gates → acquire global owner → evaluate RMF→modal → enter manager.

Acquiring first serializes requests. Exact boundary equality is eligible. Future timestamps conservatively extend the wait. Denial releases raw ownership and consumes no provider/RMF accounting or timestamp state.

Cooldown passage is not an event. Reconcile at real candidate, renderer eligibility, host exposure, foreground-readiness, successful-release, and removal-settlement checkpoints. Do not add a deadline timer.

A cooldown is only a minimum delay for a new session. A still-owned promo remains the blocker after the interval has elapsed.

## Reconciliation and failure policy

The service owns a coalescing, non-reentrant `idle` / `owned` / `draining` reconciliation loop. Renderer callbacks request reconciliation; they do not perform independent cross-renderer handoff.

- Stable registration order resolves idle contention.
- Same-message transfer retains ownership until outgoing settlement.
- No eligible renderer ends the balanced logical session after exact removal.
- Stale or duplicate callbacks are no-ops.
- Unexpected renderer loss, published-content inconsistency, or a missing terminal fails closed.
- Process death clears transient ownership; persisted confirmed history preserves cooldown behavior after relaunch.

## Construction and diagnostics

Construct one service graph. The service construction path creates one modal cooldown store, passes it to the manager and directional policy, and creates one persisted RMF timestamp store.

The debug projection is read-only and reports process mode, global owner, modal state, logical RMF state and identities, renderer counts, removal state, confirmed history, and derived boundaries. It must not schedule retries or mutate history. Do not add Promo Queue telemetry as part of an integration.

## Test checklist for any extension

- Acquisition and reconciliation are main-actor and atomic.
- At most one renderer is authorized.
- Publication happens only after ownership and cooldown admission.
- Same-message transfer waits for exact terminal and settlement.
- Changed candidate ends the old session before a new one can start.
- Stale renderer/session/presentation/removal identities cannot alter current state.
- Missing removal evidence fails closed.
- The iOS 17+ animated and iOS 15/16 synchronous paths both preserve ownership safety.
- Appearance confirms queue history once per logical session and ordinary accounting once per accepted presentation.
- Host coverage and foreground changes cannot authorize hidden content.
- Feature-off behavior remains legacy and performs no coordinated history access.
- Time passage alone is a no-op; a real checkpoint reconciles.
- No provider is queried before modal owner/cooldown admission.
- No new queue pixel, scheduler, provisional token, per-model admission, or second arbiter is introduced.

If a proposed surface needs different coexistence, priority, frequency, persistence, preemption, or rollback semantics, stop and write a new design decision. Those requirements are outside iteration one.
