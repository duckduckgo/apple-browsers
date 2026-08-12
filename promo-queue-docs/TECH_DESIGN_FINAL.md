# Promo Queue iteration 1 — final technical design

## Status and source of truth

This document describes the implemented iteration-one endpoint on `bartosz/promo-q-3` at `9321268231`, stacked directly on `bartosz/promo-q-2` at `9e82601a9f`.

- PR 1, [#6087](https://github.com/duckduckgo/apple-browsers/pull/6087), is merged to `main`.
- PR 2, [#6194](https://github.com/duckduckgo/apple-browsers/pull/6194), targets `main`.
- PR 3, [#6291](https://github.com/duckduckgo/apple-browsers/pull/6291), targets PR 2.
- The active delivery stack is `main` → `bartosz/promo-q-2` → `bartosz/promo-q-3`.

When sources disagree, use this order:

1. the implementation on `bartosz/promo-q-3` at `9321268231`;
2. the Q2 implementation on `bartosz/promo-q-2` at `9e82601a9f`;
3. `PROMO_QUEUE_LOGICAL_RMF_OWNER_IMPLEMENTATION_PLAN.md` for the central-owner redesign;
4. `Q3_IMPLEMENTATION_PLAN.md` for the cooldown and diagnostics implementation record; and
5. this document for the consolidated product and architecture contract.

Temporary files under `promo-queue-docs/` and `project_log.md` are project memory and must not enter either app pull request.

## Goal

Prevent launch-modal promos and NTP Remote Messaging Framework (RMF) cards from appearing together, prevent two physical RMF cards from appearing together, and apply the fixed directional cooldown matrix without changing RMF selection or modal-provider policy.

The implementation is a narrow iOS coordination seam, not a general promo scheduler. RMF still owns content, targeting, selection, dismissal, and persistence. The modal manager still owns provider order, modal-to-modal policy, preparation, validation, presentation, and provider accounting.

## Scope

Iteration one includes:

- one app-scoped, main-actor, identity-bearing promo owner;
- one service-owned logical RMF session and exactly one authorized physical renderer;
- coordinated modal admission before provider evaluation;
- coordinated RMF admission before publication;
- truthful ownership through exact modal detachment or RMF removal;
- explicit renderer eligibility for the standard NTP, suggestion tray, and unified-input hosts;
- a process-latched feature mode with an unchanged legacy path;
- fixed modal/RMF directional cooldowns based on confirmed appearances;
- checkpoint-driven reconsideration with no cooldown timer;
- read-only Promo Queue diagnostics; and
- focused unit, integration, and real-host lifecycle coverage.

Iteration one does not include:

- extracting or changing macOS `PromoService`;
- other iOS promo surfaces or a generic queue API;
- arbitrary priority, fairness, preemption, caps, restoration, or remote cooldown policy;
- Promo Queue admission, collision, fairness, or cooldown telemetry;
- the privacy-configuration rollout change; or
- atomic `remoteMessageShownUnique` reservation.

## Feature mode

`PromoCoordinationFactory` reads `.promoPresentationCoordination` once while constructing the process-wide graph and converts it to immutable `PromoCoordinationMode.legacy` or `.coordinated` behavior.

The service does not subscribe to feature-flag changes. A remote change or local override made after graph construction takes effect only in a fresh graph, which in production means force-quit and relaunch.

In legacy mode:

- modal evaluation remains lease-free;
- RMF models do not register coordinated renderers;
- cards retain direct/eager mapping and existing accounting;
- no directional Promo Queue cooldown state is read or written; and
- existing visual behavior is unchanged.

## One global owner

`PromoQueueLeaseArbiter` has one transient owner:

```text
none
modal(attemptID)
remoteMessage(messageID, logicalSessionID)
```

Any owner blocks every other coordinated request. An RMF owner identifies a logical session, not an NTP controller or renderer. The service is the only RMF lease holder. Lease tokens are identity-checked and idempotent; stale tokens cannot release replacements. Weak token observation lets the arbiter prune an abandoned token.

The arbiter is deliberately history- and policy-free. It does not select providers or renderers, evaluate cooldowns, persist timestamps, or decide when UI has disappeared.

## Modal lifecycle

After existing launch-source and unrelated-UIKit gates pass, `PromoCoordinationService` acquires the modal owner and evaluates the fixed RMF→modal cooldown before calling `ModalPromptCoordinationManager`. A blocked request does not query providers because provider evaluation can have side effects.

The manager carries the same lease through evaluating, committed, and presentation-active phases. It preserves:

- the existing provider order and onboarding/eligibility rules;
- the remotely tunable modal→modal cooldown;
- prepared-work validation and explicitly safe replacement;
- the inherited named `0.1`-second presentation delay;
- UIKit presentation and provider accounting; and
- exact-root dismissal semantics.

Nested child presentation does not end the modal attempt. Ownership ends only when an approved checkpoint proves that the exact selected modal root is detached.

## Central logical RMF lifecycle

### Roles

`PromoCoordinationService` owns:

- the single RMF lease;
- the logical RMF session;
- once-per-session queue-history confirmation;
- weak renderer registrations and stable registration order;
- selection of exactly one physical renderer;
- renderer-to-renderer transfer; and
- the one outgoing-removal barrier.

Each `NewTabPageMessagesModel` is a renderer client. It still discovers and builds its local `HomeMessage` candidate, but it does not acquire, retain, confirm, or release an independent lease. In coordinated mode it registers once, reports candidate and eligibility changes, and renders only a presentation authorized by the service.

### Identities

The implementation keeps distinct identities for distinct lifetimes:

- renderer ID: the stable NTP model/surface identity;
- registration generation ID: one attachment of that renderer to the service;
- logical session ID plus message ID: one global RMF ownership lifetime;
- presentation ID: one physical authorization inside the logical session; and
- removal ID: one exact outgoing-removal operation.

Callbacks must match every applicable identity. A stale renderer, appearance, removal, or settlement callback is a no-op.

### Service state

The service owns one RMF state machine:

```text
idle
  -> owned(logical session, lease, renderer generation, presentation)
  -> draining(same session and lease, outgoing presentation, removal, continuation)
  -> owned   // same-message transfer after exact terminal and settlement
  -> idle    // end session after exact terminal and settlement
```

Reconciliation is main-actor, non-reentrant, and coalescing. When idle, the first eligible renderer in stable registration order supplies the candidate. The service reconciles any stale modal root, acquires the global RMF owner, evaluates cooldowns, and only then authorizes publication.

If authorization is safely rejected before content is published, the service may try the next eligible renderer with the same message. If a renderer reports failure while coordinated content may still be published, ownership is retained and the system fails closed.

### Same-message transfer and session end

If another eligible renderer has the same message, the service removes the outgoing presentation, retains the same logical session and lease, waits for its exact removal terminal and one following main-queue settlement turn, then authorizes the successor.

If the candidate changes, becomes unavailable/unrenderable, or no renderer remains eligible, the service follows the same removal barrier and ends the logical session. A later return starts a new session and is subject to normal cooldown admission.

This balanced lifetime avoids letting an invisible logical RMF block modals forever. It also means a same-session handoff is continuity of one promo rather than a new queue presentation.

### Appearance and accounting

The service accepts an appearance only for the exact owned session, presentation, registration generation, eligible renderer, and attached window.

The first accepted physical appearance confirms the persisted RMF queue-history timestamp once for the logical session. Every accepted physical presentation performs ordinary RMF appearance accounting once through the renderer. Therefore a same-session renderer handoff may create another ordinary physical impression, but it does not restart the queue cooldown timestamp.

Authorization, cooldown denial, build failure, withdrawal before appearance, stale callbacks, and removal never confirm queue history.

## Host exposure and visibility

The redesign greatly reduces view-lifecycle bookkeeping but does not eliminate all visibility knowledge and does not rely on cooldowns alone.

The standard NTP, suggestion tray, and unified-input/favorites hosts still report the centralized exposure predicate. Attachment alone is insufficient because a cached NTP may remain in a window while covered. These signals determine which renderer is eligible; the service then authorizes exactly one renderer.

Any future host or overlay that can expose, retain, or cover an NTP must integrate the same exposure seam. This obligation is not compiler-enforced.

## RMF removal contract

Cooldown eligibility never proves that an outgoing card is gone. The lease remains held until one exact non-visible terminal is accepted, followed by one main-queue settlement turn.

| OS | Coordinated removal | Terminal |
| --- | --- | --- |
| iOS 17+ | Preserve scale/opacity using SwiftUI `withAnimation(..., completionCriteria: .removed)` | `.animationCompleted` after native removed completion |
| iOS 15/16 | Clear the source synchronously inside a transaction with animations disabled; use `.transition(.identity)` | `.sourceRemovedWithoutAnimation` after verifying the source is clear |
| All supported OS versions | A physically detached exact renderer may complete removal | `.hostDetached` after attachment verification |

The missing iOS 15/16 dismissal animation is an approved visual exception caused by the lack of a sufficiently reliable SwiftUI removal-completion primitive on those versions. It does not weaken collision safety. Legacy mode keeps its previous animation.

A missing, stale, or unverifiable terminal fails closed: the service retains ownership rather than releasing on a timer and risking an overlap.

## Directional cooldowns

Cooldowns are a service-owned policy layered after global-owner acquisition. They are not arbiter state and are not part of RMF itself.

| Previous confirmed appearance | Next requested appearance | Required elapsed time |
| --- | --- | --- |
| Launch modal | NTP RMF | fixed 10 minutes |
| NTP RMF | NTP RMF | fixed 10 minutes |
| NTP RMF | Launch modal | fixed 24 hours |
| Launch modal | Launch modal | existing remotely tunable interval, currently/default 24 hours |

`PromoQueueCooldownPolicy` uses an injected clock, the modal manager's existing confirmed-presentation store, and one persisted last-confirmed-RMF timestamp. It stores source-event times, not expiry dates. Exact equality is eligible. A future timestamp, including after a backward wall-clock change, conservatively remains in cooldown.

RMF admission uses the later applicable modal→RMF or RMF→RMF boundary. Modal admission checks RMF→modal before provider evaluation; the modal manager remains the sole owner of modal→modal policy.

The first accepted appearance of a logical RMF session is the RMF source event. A same-session renderer handoff does not create a new queue source event. Once the logical session ends, a future session—including for the same scheduled message—must pass the persisted RMF cooldown.

## Checkpoint-only reconsideration

Time passage is not an event. There is no deadline timer or boundary scheduler. Retained work is reconsidered only at real state changes, including:

- initial configuration and RMF configuration changes;
- explicit refresh and candidate/eligibility updates;
- window attachment and host exposure changes;
- foreground interaction readiness changes;
- successful owner release; and
- exact removal settlement and service reconciliation.

Reaching 10 minutes or 24 hours alone does nothing. An otherwise eligible promo may wait beyond its minimum boundary until the next checkpoint. A still-owned promo blocks every competing promo even after the relevant cooldown duration has elapsed.

## Debugging and operations

The existing Modal Prompt Coordination debug screen exposes a read-only Promo Queue projection containing:

- immutable process mode and the relaunch requirement;
- active global owner and identity;
- modal phase, pending work, and suppression state;
- RMF `idle` / `owned` / `draining` state;
- message/session, renderer/generation, presentation, and removal identities;
- accepted terminal and drain continuation;
- registered and eligible renderer counts;
- logical queue-history and physical-presentation appearance state; and
- confirmed modal/RMF timestamps with derived next-RMF and next-modal boundaries.

The UI states that boundaries do not schedule retries. It adds no queue/history mutation controls and no telemetry. The pre-existing modal cooldown reset remains pre-existing debug behavior.

## Requirements assessment and accepted tradeoffs

The redesign preserves the core product requirements: no modal/RMF overlap, no two physical RMFs, the complete directional cooldown matrix, confirmed-history persistence, modal/provider behavior, startup-latched flagging, checkpoint-only retry, and legacy behavior when the flag is off.

It intentionally changes these implementation or visual details from the earlier design:

| Change | Consequence |
| --- | --- |
| Per-model RMF ownership becomes one central logical owner | Removes admissions, gate/mount sets, multiple outgoing-session dictionaries, and distributed release authority. |
| Same-message renderer handoff stays in one logical session | Queue history confirms once; ordinary RMF accounting remains per accepted physical presentation. |
| Balanced lifetime ends ownership when no eligible renderer remains | A later return starts a new cooldown-governed session rather than leaving a hidden owner indefinitely. |
| Stable registration order resolves competing renderer candidates | Candidate authority remains distributed; the change does not add a new app-wide RMF source. |
| Missing exact removal evidence fails closed | A bug can strand the queue, but cannot release into a visible overlap. Diagnostics expose the state. |
| iOS 15/16 coordinated dismissal has no animation | Source removal is synchronous and verifiable; iOS 17+ retains scale/opacity. |
| Host exposure remains explicit | This is simpler than the old lifecycle graph, but not a fully view-agnostic Android implementation. |
| Startup-latched flag | A remote kill switch affects a new process graph, not an already-running process. |
| No boundary timer | Eligibility can be delayed until another real checkpoint. |

## Validation and remaining work

The branch contains focused coverage for owner serialization, renderer selection and handoff, stale identities, exact terminal settlement, teardown, readiness, legacy behavior, cooldown boundaries and storage failures, appearance accounting, real SwiftUI iOS 17 removal, and an injectable synchronous old-OS path.

No further product implementation is planned for iteration one. Review and validation should still verify:

- an owner remains authoritative even when its opposing cooldown has elapsed;
- a real iOS 15/16 simulator follows the synchronous no-animation path;
- manual behavior in the standard NTP, suggestion tray, and unified-input hosts;
- feature-off legacy behavior and process-latched enablement; and
- the final stacked diff after Q2 is rebased or merged.

Telemetry, privacy-config rollout, and atomic unique-shown accounting remain separate work, not missing iteration-one requirements.

See `Q3_IMPLEMENTATION_PLAN.md` for the Q3 implementation record and `ADDING_PROMOS.md` for the integration contract.
