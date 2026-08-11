# Adding Promo Queue integrations on iOS

## Start here

Iteration one coordinates only:

- launch-modal promos evaluated by `PromoCoordinationService`; and
- RMF cards rendered in a known New Tab Page host.

It is a main-actor mutual-exclusion and fixed-cooldown seam, not a general promo scheduler. Do not route badges, settings rows, notification bars, onboarding, arbitrary UIKit presentations, or other promo surfaces through it without a new product/design decision.

Read `TECH_DESIGN_FINAL.md` for the contract and `Q3_IMPLEMENTATION_PLAN.md` for the final implementation record.

## Core model

There is one app-scoped `PromoQueueLeaseArbiter` with one active owner:

```text
none | modal(attempt identity) | remoteMessage(surface + message identity)
```

Any owner blocks every other coordinated request. The arbiter is transient and history-free. It owns no provider priority, RMF targeting, cooldown, persistence, presentation, or retry timing.

The service owns admission and the fixed cross-promo cooldown policy. UI owners retain identity-bound tokens for the complete real lifetime of their promo.

Never:

- construct a second arbiter for another host;
- add a `.shared` queue singleton;
- query the arbiter and mutate it later as two separate operations;
- store leases in user defaults;
- inject the arbiter or cooldown store into SwiftUI views/providers;
- add a per-surface owner dictionary or provisional cooldown reservation; or
- add a cooldown deadline timer.

## Feature mode

`PromoCoordinationFactory` samples `.promoPresentationCoordination` once and creates immutable `.legacy` or `.coordinated` behavior for the service graph.

- Do not subscribe to live flag changes.
- Local overrides must be set before graph construction.
- Force-quit/relaunch after changing the flag.
- Legacy mode must keep the established lease-free modal flow and direct/eager RMF behavior.

If immediate in-process rollback becomes a requirement again, treat it as a new architecture decision rather than restoring the removed transition machinery piecemeal.

## Adding or changing a launch-modal provider

The service acquires modal ownership before the manager evaluates any provider. Provider evaluation may have side effects, so code must not query a provider while an RMF owns the queue or while the fixed RMF→modal cooldown is active.

The manager remains responsible for:

- provider ordering and first-eligible selection;
- per-provider onboarding/eligibility;
- the existing remotely tunable modal→modal cooldown;
- prepared work and the inherited `0.1`-second presentation delay;
- UIKit presentation and exact-root lifetime; and
- provider shown/accounting callbacks.

Implement `ModalPromptProvider.isModalPromptStillValidForPresentation(_:)` when prepared or retained work can become stale. Make the check read-only. Conform to `InvalidModalPromptReplacing` only when repeating preparation is known to be safe; the default is no replacement.

Do not release ownership when a nested child is presented or dismissed. The selected modal root ends the attempt only after an approved checkpoint proves that exact root is detached.

Provider tests should cover:

- no evaluation before owner/cooldown admission;
- immediate and retained revalidation;
- replacement only for explicitly safe providers;
- no-provider/cooldown release without accounting; and
- exact-root attachment, nested presentation, and dismissal.

## NTP RMF integration

### Admission boundary

An RMF card can be built and published only when the model is loaded, active, renderable, attached to a window, has a mounted matching gate, and receives `.acquired(admission)` from the service.

The public NTP facade intentionally exposes only:

```text
acquired(admission) | deferred
```

Lease conflicts, readiness, and cooldown reasons stay inside service/policy diagnostics. A deferred candidate remains in the model and is not rendered, marked shown, dismissed, or consumed.

### Identity and physical lifetime

Keep separate stable identities for:

- the NTP surface;
- the candidate gate;
- the admitted render session; and
- each physical SwiftUI mount.

Same-ID refresh is one continuous admitted session. A changed ID withdraws the old inner card and cannot acquire the replacement until the old admission releases.

Logical withdrawal is not physical disappearance. `onDisappear` begins removal but does not complete it. Move the admission into outgoing-session state, use the coordinated transition's inert animatable terminal callback to mark matching physical completion, then wait one following main turn before releasing. Every callback must match the render session and mount it changes.

The coordinated card retains the legacy scale/opacity transition. Never call the terminal-completion seam early, switch it to `.identity` merely to simplify lifecycle callbacks, or guess animation completion with a fixed delay.

### Appearance and accounting

On the first matching card appearance:

1. confirm the RMF cooldown appearance through the admission;
2. mark the session appearance as recorded; and
3. run ordinary RMF shown accounting.

Confirmation is once per admitted render session. Duplicate `onAppear`, remount, same-ID refresh, stale session callbacks, and confirmation after release do nothing. Withdrawal or build failure before appearance writes no RMF history.

Normal shown accounting is once per admitted appearance. Atomic `remoteMessageShownUnique` persistence is an independent optional correctness change; do not silently mix it into a new surface integration.

## Host exposure contract

The known hosts are:

- standard NTP;
- suggestion tray/favorites NTP; and
- unified-input/favorites NTP.

Use the centralized exposure predicate and outgoing-before-incoming handoff. UIKit appearance or `view.window` alone is not enough: a cached controller can remain attached while hidden by autocomplete, Duck.ai content, an overlay, or opacity.

Async transition/completion callbacks must carry a generation or identity so stale completion cannot reactivate a covered host.

A future host or overlay that can cover or retain an NTP must explicitly:

1. define the stable surface owner;
2. report logical renderability and coverage;
3. perform outgoing-before-incoming handoff;
4. invalidate stale async completions;
5. preserve window/gate readiness; and
6. add direct host tests.

This obligation is not compiler-enforced. Missing it can let a hidden NTP starve every promo under singular ownership.

## Cooldown contract

| Confirmed source | Requested target | Required elapsed time |
| --- | --- | --- |
| Modal | RMF | 10 minutes |
| RMF | RMF | 10 minutes |
| RMF | Modal | 24 hours |
| Modal | Modal | Existing remote-tunable interval, currently/default 24 hours |

The service-owned policy reuses the modal manager's persisted confirmed-modal timestamp and owns one persisted confirmed-RMF timestamp. It stores event times, not expiry dates.

Admission order is significant:

- RMF: readiness → modal reconciliation → acquire global owner → evaluate cooldown → return admission;
- modal: service gates → acquire global owner → evaluate RMF→modal → enter manager.

Acquiring first serializes requests. Do not add a provisional reservation.

Exact boundary equality is eligible. Future timestamps conservatively extend the wait. Denial releases raw ownership and consumes no provider/RMF accounting or timestamp state.

Cooldown passage is not an event. Do not add a timer. Reconsider retained work at existing real checkpoints: configuration/refresh, gate mount, window/host exposure, foreground readiness, successful owner release, and same-surface retry after physical removal.

With singular ownership, 10 minutes is a minimum RMF→RMF delay, not permission to overlap two cards. A second RMF still waits for the first card's physical removal.

## Retry and release handoff

Each NTP model owns its retained candidate and a weak service registration. The service owns no blocked RMF content.

Registry-wide handoff is allowed only after a token successfully releases the current owner. It must:

- run only while app/UI readiness is valid;
- exclude the releasing surface;
- preserve registration order;
- iterate a snapshot;
- re-check membership and target liveness before each callback;
- skip inactive targets; and
- suppress nested drains.

Stale/double release and cooldown-denied raw rollback do not drain the registry. RMF release never starts modal evaluation.

## Construction and diagnostics

There is one coordination graph. The service convenience initializer creates one modal cooldown store, passes that exact instance to both the existing manager and directional policy, and adds one persisted production RMF timestamp store.

The debug projection is read-only and shows:

- immutable process mode;
- singular owner identity;
- modal phase and pending/suppression state;
- readiness/retry count where useful;
- confirmed modal/RMF timestamps; and
- derived next-RMF/next-modal boundaries with a note that no timer is scheduled.

Do not expose stale transition, plural-lease, provisional-reservation, or timer fields. Do not add new Promo Queue telemetry as part of an integration.

## Test checklist for any extension

- Acquisition is main-actor and atomic.
- Blocked work is retained and unaccounted.
- Stale and duplicate release cannot clear a newer owner.
- Physical lifetime covers the full visible transition.
- Background/foreground and host coverage cannot admit hidden content.
- The process-latched feature-off path remains legacy.
- Cooldown checks use confirmed history and exact boundaries.
- Time passage alone is a no-op; a real checkpoint retries.
- No provider is queried before modal owner/cooldown admission.
- No new queue pixel, scheduler, provisional token, or second arbiter is introduced.

If a proposed surface needs different coexistence, priority, frequency, persistence, preemption, or rollback semantics, stop and write a new design decision. Those requirements are outside iteration one.
