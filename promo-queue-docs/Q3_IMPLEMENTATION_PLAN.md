# Promo Queue iteration 1 — Q3 implementation record

## Outcome

Q3 completes iteration one on top of the central logical RMF owner implemented in `bartosz/promo-q-2`. It adds directional cooldown policy and persistence, integrates confirmed appearance with the service-owned RMF session, exposes read-only diagnostics, and adds focused time-limit coverage.

The implementation is on `bartosz/promo-q-3` at `9321268231`, based directly on `bartosz/promo-q-2` at `9e82601a9f`, and is open as [#6291](https://github.com/duckduckgo/apple-browsers/pull/6291).

Q3 does not implement RMF ownership or removal animation. Those now belong to Q2's central-owner redesign. In particular:

- iOS 17+ preserves coordinated scale/opacity removal with native `.removed` completion;
- iOS 15/16 intentionally clears synchronously with animations disabled and has no coordinated dismissal animation; and
- every OS retains the lease through the exact terminal and one service settlement turn.

## Implemented commits

1. `02ae39b217` — add the fixed directional cooldown policy and persisted RMF history.
2. `a1207bf6ef` — integrate owner-first admission and logical-session appearance confirmation.
3. `a770166f88` — add the read-only Promo Queue debug projection.
4. `75717015b3` — make diagnostic projection side-effect free.
5. `9321268231` — add focused Promo Queue time-limit coverage.

## Q2 contract consumed by Q3

Q3 assumes and preserves these Q2 invariants:

- one immutable process-latched `PromoCoordinationMode`;
- one singular global owner across modals and RMF;
- only `PromoCoordinationService` retains the RMF lease;
- one logical RMF session can authorize at most one physical renderer;
- renderer registration and reconciliation are weak, stable-order, coalescing, and main-actor;
- same-message transfer retains the logical session and lease;
- release follows an exact removal terminal plus one main-queue settlement turn;
- missing or stale lifecycle evidence fails closed;
- modal ownership follows the exact UIKit root; and
- feature-off models do not register or execute new queue/history behavior.

Q3 does not reintroduce per-model admissions, gate or mount identities, an outgoing-session dictionary, a retry registry, provisional cooldown reservations, or animation-duration guesses.

## Directional cooldown policy

### Matrix

| Previous confirmed appearance | Next requested appearance | Required elapsed time |
| --- | --- | --- |
| Launch modal | NTP RMF | fixed 10 minutes |
| NTP RMF | NTP RMF | fixed 10 minutes |
| NTP RMF | Launch modal | fixed 24 hours |
| Launch modal | Launch modal | existing remotely tunable interval, currently/default 24 hours |

`PromoQueueCooldownPolicy` is a main-actor decision component with an injected clock. RMF admission uses the later applicable modal→RMF or RMF→RMF boundary. Modal admission checks RMF→modal; the existing `PromptCooldownManager` remains the sole owner of modal→modal policy.

Exact boundary equality is eligible. Future timestamps, including those caused by a backward wall-clock change, conservatively remain in cooldown until the timestamp plus its interval.

### Persistence

The service construction path reuses the modal manager's `PromptCooldownStore` and creates one production `PromoQueueRemoteMessageCooldownKeyValueFilesStore` for the last confirmed RMF timestamp.

Stores contain source-event timestamps rather than expiry dates. RMF read/write behavior is deterministic:

- an initial read failure behaves as no known history and may be retried;
- a successful read, including `nil`, is cached;
- a later read failure uses the most recent successful cached value;
- after a failed write, the attempted value remains authoritative in that process; and
- a fresh process observes only successfully persisted history.

Diagnostic snapshot reads are side-effect free and do not change policy cache or storage behavior.

## Admission and appearance integration

### RMF sequence

```text
candidate and renderer eligibility checkpoint
  -> reconcile stale modal root
  -> mint logical RMF session
  -> acquire singular RMF owner
  -> evaluate modal->RMF and RMF->RMF policy
  -> denied: release raw owner, retain candidate, publish/account/write nothing
  -> eligible: authorize exactly one renderer presentation
  -> first accepted presentation appearance: confirm queue history once for the session
  -> each accepted physical presentation: perform ordinary RMF appearance accounting once
  -> exact removal terminal + settlement: transfer same session or end and release
```

The owner is acquired before cooldown evaluation, which serializes competing requests without a provisional reservation. A cooldown denial is a raw rollback, not a successful visible-owner release, and does not recursively trigger reconciliation.

Appearance is accepted only if session, presentation, registration generation, eligibility, attachment, and current service state all match.

Queue history confirms once per logical session. A same-message transfer to another physical renderer does not restart the 10-minute or 24-hour queue timestamp; it is continuity of one promo. Ordinary RMF shown accounting remains once per accepted physical presentation. Authorization, denial, build failure, withdrawal before appearance, and stale callbacks write nothing.

### Modal sequence

```text
existing launch and UIKit gates
  -> acquire singular modal owner
  -> evaluate RMF->modal policy
  -> denied: release raw owner, query no provider, write/account nothing
  -> eligible: enter the existing manager flow
  -> manager evaluates modal->modal policy and providers
```

The fixed cross-type policy does not replace provider eligibility or the existing modal cooldown.

## Checkpoint-only liveness

Q3 adds no deadline scheduler or timer. Reaching a timestamp does not execute code. Retained work is reconsidered when existing application or UI facts change:

- RMF configuration load/change and explicit refresh;
- renderer candidate or eligibility update;
- window attachment or host exposure update;
- foreground interaction readiness;
- successful owner release; and
- exact RMF removal terminal and service settlement.

Consequences:

- a static candidate can wait beyond its 10-minute or 24-hour boundary;
- a still-owned RMF blocks a modal even after 24 hours;
- a still-owned modal blocks RMF even after 10 minutes; and
- an opposing promo is reconsidered only after ownership ends and another checkpoint occurs.

This is intentional and keeps timing policy separate from lifecycle safety.

## Read-only diagnostics

The existing Modal Prompt Coordination debug screen includes a `PromoQueueDebugSnapshot` with:

- process-latched mode and relaunch guidance;
- active arbiter owner;
- modal phase, pending work, suppression, and readiness;
- logical RMF `idle` / `owned` / `draining` state;
- message/session, renderer/generation, presentation, and removal identities;
- queue-history confirmation and physical-presentation appearance state;
- accepted removal terminal and drain continuation;
- registered and eligible renderer counts; and
- last confirmed modal/RMF timestamps plus derived eligibility boundaries.

The projection is observational. It schedules no retries, reads no history in legacy mode, and adds no queue/history mutation controls or pixels. The existing modal cooldown reset control remains unrelated pre-existing behavior.

The current projection shows timestamps, derived boundaries, terminal, and drain continuation, but it does not add a separately labeled cooldown wait-reason or detailed drain-reason row proposed in the central-owner planning checklist. The canonical iteration-one design treats the implemented fields as sufficient unless final review identifies a concrete debugging need; this is diagnostic polish, not a safety or cooldown gap.

## Coverage included

Focused Q3 tests cover:

- all directional rows just before, at, and after their inclusive boundaries;
- the maximum of modal→RMF and RMF→RMF boundaries;
- absent and future history;
- persistence reconstruction, initial/later read failures, and write failures;
- owner acquisition before policy evaluation;
- no policy/provider call on lease conflict;
- cooldown denial with no publication, accounting, or history write;
- exactly-once logical-session confirmation;
- per-presentation ordinary appearance accounting;
- stale or duplicate appearance rejection;
- checkpoint-only reconsideration; and
- side-effect-free diagnostic snapshots.

Q2 contains the complementary lifecycle tests for single-renderer authorization, same-message transfer, removal terminals and settlement, stale identities, host detachment, readiness, legacy mode, real SwiftUI iOS 17 removal, and the injected old-OS synchronous path.

## Deliberate non-goals

Q3 does not include:

- live feature-flag transitions;
- cooldown-boundary scheduling;
- provisional leases or reservations;
- per-surface or per-renderer owners;
- Promo Queue telemetry or pixels;
- privacy-configuration rollout;
- production in-memory fallback stores;
- atomic `remoteMessageShownUnique` reservation; or
- new promo surfaces.

## Review and validation still required

The implementation is feature-complete against `TECH_DESIGN_FINAL.md`, but review should confirm:

- Q3 remains a clean five-commit layer after any Q2 rebase;
- ownership still wins over elapsed time in both directions;
- logical-session versus physical-presentation accounting is intentional and correctly tested;
- the implemented diagnostic boundaries/continuation are sufficient without a separate wait-reason row;
- a real iOS 15/16 simulator exercises synchronous no-animation removal;
- standard NTP, suggestion tray, and unified-input manual flows; and
- feature-off behavior performs no new registration, arbitration, or history access.

No product implementation remains after those checks. Telemetry, rollout, and atomic unique-shown accounting are separate follow-up decisions.

## Definition of done

1. All four cooldown rows use confirmed source events and inclusive boundaries.
2. Modal history is reused and confirmed RMF history persists with defined failure semantics.
3. Competing requests acquire the singular owner before policy evaluation.
4. The first valid physical appearance confirms a logical RMF session once.
5. Same-session handoff does not restart queue history; ordinary accounting remains per presentation.
6. Denied or abandoned work consumes no provider/RMF accounting or timestamp.
7. No time-boundary timer or provisional reservation exists.
8. Q2's exact removal ownership and OS-specific visual behavior remain intact.
9. Diagnostics match the central logical-owner model and are side-effect free.
10. Feature-off behavior remains legacy.
11. Focused policy, lifecycle, and integration coverage passes when run with approval.
12. No telemetry or privacy-config rollout change is bundled.
