# Promo Queue iteration 1 — final technical design

## Status and source of truth

This document describes the intended iteration-one endpoint after the agreed Q2 simplification work on `bartosz/promo-q-2-fixes` and the remaining Q3 work in `Q3_IMPLEMENTATION_PLAN.md`.

When sources disagree, use this order:

1. the implementation at `origin/bartosz/promo-q-2-fixes` (`37b99b0d78` when this document was updated);
2. `PROMO_QUEUE_Q2_SIMPLIFICATION_IMPLEMENTATION_PLAN.md` in the shared project documents;
3. `PROMO_QUEUE_Q3_SIMPLIFICATION_IMPLEMENTATION_PLAN.md` in the shared project documents;
4. this document for the consolidated iteration-one target.

PR 1 is already on `main`. PR 2 and its stacked fixes establish the Q2 foundation. Directional cooldowns were deliberately deferred to the final PR. The older `bartosz/promo-q-3` implementation and commit `06a2417373` predate the Q2 simplification and are evidence only; their live-flag, per-surface-owner, provisional-reservation, timer, and debug shapes must not be ported.

## Goal

Prevent launch-modal promos and NTP Remote Messaging Framework (RMF) cards from appearing together on iOS, apply the fixed directional cooldown matrix, and preserve existing provider ordering, eligibility, modal-to-modal cooldown, presentation, and feature-specific accounting.

The implementation is a narrow cross-surface coordinator, not a general promo scheduler. RMF continues to own message content, targeting, selection, dismissal, and persistence. The modal manager continues to own provider policy and UIKit presentation.

## Scope

Iteration one includes:

- one app-scoped, main-actor, identity-bearing global promo owner;
- coordinated launch-modal admission before provider evaluation;
- coordinated RMF admission before card construction or publication;
- truthful ownership through modal root detachment and RMF physical removal;
- explicit renderability for the standard NTP, suggestion tray, and unified-input hosts;
- retained blocked RMF candidates and readiness-gated release handoff;
- a process-latched feature mode with an exact legacy path;
- fixed modal/RMF directional cooldowns based on confirmed appearances;
- read-only Promo Queue diagnostics; and
- focused unit, integration, and real-host lifecycle coverage.

Iteration one does not include:

- extracting or changing macOS `PromoService`;
- other iOS promo surfaces or a generic queue API;
- arbitrary priority, severity, restoration, caps, or remote cooldown policy;
- new Promo Queue admission, collision, fairness, or cooldown telemetry;
- the privacy-configuration rollout change; or
- atomic `remoteMessageShownUnique` reservation unless approved as a separate correctness change.

## Q2 foundation

### Process-latched mode

`PromoCoordinationFactory` reads `.promoPresentationCoordination` once when constructing the process-wide service graph and converts it to immutable `PromoCoordinationMode.legacy` or `.coordinated`.

The service does not subscribe to feature-flag updates. A remote change or local override made after graph construction affects only a fresh graph, which in production means force-quit and relaunch. Legacy mode keeps the established lease-free modal path and direct/eager RMF mapping and accounting.

### One global owner

`PromoQueueLeaseArbiter` owns one transient `ActiveOwner?`:

```text
none
modal(attempt identity)
remoteMessage(surface identity, message identity)
```

Any owner blocks every other coordinated request. Two RMFs cannot own the queue simultaneously, even on different NTP instances. Tokens are strongly retained by their consumer and weakly observed by the arbiter so abandoned tokens can be pruned. Release is identity-checked and idempotent; a stale token cannot clear a replacement owner.

The arbiter owns no provider policy, RMF selection, cooldown, persistence, retry timing, or view lifecycle.

### Modal lifecycle

After the existing launch-source and unrelated-UIKit gates pass, `PromoCoordinationService` acquires the modal owner before calling the manager. Provider evaluation can have side effects, so a blocked modal request never queries providers.

`ModalPromptCoordinationManager` carries the same lease through:

```text
evaluating -> committed -> presentationActive -> idle
```

It preserves the existing provider order, onboarding checks, remotely tunable modal-to-modal cooldown, pending prepared work, and named `0.1`-second presentation delay used for keyboard/OmniBar ordering. Prepared work is revalidated through one presentation-validity contract; only providers that explicitly support safe replacement may prepare a replacement.

An accepted modal remains the owner until a checkpoint proves that its exact root is detached. Nested child presentation does not end the attempt. Confirmed presentation history remains separate from transient attempt state.

### RMF lifecycle

Each NTP model owns its candidate, stable surface identity, gate identity, render-session identity, and physical mount identities. Coordinated admission requires all of the following:

- the app and foreground interaction are ready;
- the model is loaded and not torn down;
- the host says the surface is renderable;
- the view is attached to a window; and
- the matching SwiftUI gate is mounted.

The card is built and published only after the service grants `PromoQueueRemoteMessageAdmission`. A blocked candidate remains retained and unaccounted.

Logical withdrawal first removes the inner card. The admission moves to identity-keyed outgoing state and remains strongly held until every matching pending or visible card mount has disappeared and one following main-queue turn has settled. Only then is the global owner released. Same-ID refresh keeps one session; changed-ID replacement cannot release or overwrite a newer session through stale callbacks.

Successful current-owner release may hand the slot to another active registered NTP. The registry is weak, stable-order, mutation-safe, reentrancy-guarded, and gated on current app/UI readiness. Visible-RMF release never initiates modal evaluation.

## Q3 directional cooldown design

### Policy

Cooldowns are a separate service-owned policy layered after global-owner acquisition. They are not arbiter state and are not added to RMF.

| Previous confirmed appearance | Next requested appearance | Required elapsed time |
| --- | --- | --- |
| Launch modal | NTP RMF | fixed 10 minutes |
| NTP RMF | NTP RMF | fixed 10 minutes, global across IDs and NTP instances |
| NTP RMF | Launch modal | fixed 24 hours |
| Launch modal | Launch modal | existing `PromptCooldownManager` interval, remotely tunable and currently/default 24 hours |

`PromoQueueCooldownPolicy` is a pure main-actor decision component with an injected clock. RMF admission uses the later of the modal→RMF and RMF→RMF boundaries. Modal admission checks only RMF→modal; the existing modal manager remains the sole owner of modal→modal policy.

Exact equality is eligible. A timestamp in the future, including after a backward wall-clock change, conservatively keeps the request in cooldown until that timestamp plus its interval.

### Confirmed history and persistence

The policy reuses the same `PromptCooldownStore` instance used by the modal manager and adds one persisted last-confirmed-RMF timestamp. Store source-event times, not expiry dates.

A modal source event is the manager's existing confirmed-presentation event: accepted UIKit presentation or adoption of the already attached prepared root. An RMF source event is the first matching physical card appearance of an admitted render session.

Selection, mapping, owner acquisition alone, cooldown denial, build failure, withdrawal before appearance, pending modal work, and refused presentation do not write history.

The RMF store must behave predictably under failure:

- an initial read failure is treated as no known history and may be retried;
- a successful read, including `nil`, is cached;
- a later read failure uses the last successful cached value; and
- after a failed write, the attempted value is authoritative for the current process, while a new process sees only the last persisted value.

### RMF transaction

```text
readiness and renderability
  -> reconcile a stale modal root
  -> acquire the singular RMF owner
  -> evaluate modal->RMF and RMF->RMF boundaries
  -> denied: release the raw owner, retain candidate, write/account nothing
  -> eligible: return an identity-bound admission
  -> first matching card appearance: confirm RMF history once, then run normal shown accounting
  -> final physical removal: release owner once and offer NTP handoff
```

The admission state becomes `pending -> consumed -> released`. Confirmation is synchronous, identity-bound, and exactly once. Confirmation records history but does not release ownership.

Because Q2 permits only one global owner, no provisional cooldown reservation or second lease is needed. Acquiring the owner before policy evaluation serializes competing requests.

### Modal transaction

```text
existing service gates
  -> acquire the singular modal owner
  -> evaluate RMF->modal boundary
  -> denied: release the raw owner, evaluate no provider, write/account nothing
  -> eligible: enter the existing manager flow
  -> manager applies existing modal->modal cooldown and provider policy
```

A cooldown-denied raw rollback is not a successful visible-owner handoff and must not recursively drain the RMF retry registry.

### Checkpoint-only reconsideration

Cooldown passage is not an event. Q3 adds no deadline timer, boundary scheduler, or boundary map. Retained work is reconsidered only at real checkpoints already justified by app or UI state, including:

- initial RMF configuration load and configuration-change notification;
- explicit model refresh;
- gate mount/remount;
- window attachment, host exposure, or full foreground-readiness change;
- temporary resign-active return only when foreground readiness was not lost;
- successful modal or RMF owner release;
- same-surface retry after final physical removal; and
- the existing eligible standard-foreground modal pass.

Time reaching 10 minutes or 24 hours by itself does nothing. A static eligible candidate may wait beyond its exact boundary until the next checkpoint.

## Debugging and operations

Extend the existing Modal Prompt Coordination screen with a read-only Promo Queue snapshot showing:

- process mode and the force-quit/relaunch requirement;
- singular active owner and identity;
- modal attempt phase, pending work, and suppression state;
- app/UI readiness and retry-registration count where useful;
- last confirmed modal and RMF timestamps; and
- derived next-RMF and next-modal eligibility boundaries.

The UI must state that boundaries do not schedule retries. Do not show stale live-transition, plural-lease, provisional-reservation, or scheduled-timer rows. Do not add lease/history mutation controls as part of the new queue diagnostics. The existing modal cooldown reset control may remain as existing debug behavior.

## Known hosts

The standard NTP, suggestion tray, and unified-input/favorites hosts use one centralized exposure predicate and outgoing-before-incoming handoff. Async animation/completion callbacks are generation- or identity-checked.

Any future overlay or host that can cover, retain, or expose an NTP must explicitly participate in this contract. This obligation is not compiler-enforced.

## Accepted deviations from the original design

The following changes are agreed, but remain important rollout or maintenance concerns:

| Change | Consequence / concern |
| --- | --- |
| Live flag transitions replaced with a startup latch | A remote kill switch does not change a running or suspended process. Rollback takes effect after force-quit/relaunch. |
| Per-surface RMF leases replaced with one global owner | A second RMF cannot appear after 10 minutes while the first remains physically mounted. A hidden host that retains ownership can starve all promos. |
| Exact-boundary RMF timer removed | Eligibility can be delayed indefinitely until another real checkpoint occurs. |
| Future-host coverage remains manual | A new overlay can accidentally retain or expose an NTP incorrectly unless its owner integrates the common exposure seam. |
| Default Browser retained validation uses cached status | An external default-browser change after selection can make retained validation stale. This is an accepted system-check budget trade-off. |
| Atomic unique-shown reservation removed from core scope | The existing asynchronous `hasShown`/write sequence can still race across sequential configurations. It is an optional independent correctness fix, not a cooldown prerequisite. |

One change is not accepted: coordinated RMF currently uses `.transition(.identity)`, removing the legacy scale/opacity removal animation. Q3 must restore the existing visual behavior while keeping the owner until truthful physical removal. If SwiftUI timing cannot satisfy both, stop for explicit product/design approval rather than silently changing the animation.

## Testing and definition of done

Iteration one is complete when tests and real-host characterization prove:

- the factory reads the feature flag once and does not subscribe to live updates;
- legacy mode preserves established modal and RMF behavior;
- any active owner blocks every other coordinated request;
- providers are never queried before modal ownership and fixed RMF→modal admission;
- blocked or cooldown-denied RMF work is retained, unrendered, and unaccounted;
- modal ownership survives scheduling, UIKit handoff, nested presentation, and exact-root lifetime;
- RMF ownership survives logical withdrawal, animation, overlapping mounts, stale callbacks, and the following settling turn;
- all known NTP hosts report exposure and hand off in the correct order;
- all cooldown rows pass just-before, exact-boundary, and just-after cases;
- confirmed history, persistence failures, relaunch, and backward-clock cases are deterministic;
- duplicate RMF appearance confirms once, while withdrawal before appearance confirms never;
- time passage alone causes no retry, while each documented checkpoint can reconsider retained work;
- the scale/opacity removal animation is preserved without early owner release;
- the debug screen reports the current architecture without mutation or stale timer/transition concepts; and
- no new Promo Queue telemetry or privacy-config rollout change is included.

See `Q3_IMPLEMENTATION_PLAN.md` for the remaining implementation sequence and `ADDING_PROMOS.md` for the integration contract.
