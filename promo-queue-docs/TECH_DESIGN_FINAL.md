## Context

This revised tech design reflects the discussion in the parent task. I left the parent task description unchanged to preserve context.

It supersedes the earlier draft's permission-check coordinator with a transactional-lease model. The final implementation also extends the provider adapter contract to revalidate prepared or retained work safely. An August 2026 product decision adds one deliberately limited iteration-one policy: directional cooldowns between confirmed launch-modal and admitted NTP RMF appearances. PR 3 implements that policy in `06a2417373`. This does not turn RMF or the lease arbiter into a general frequency engine.

## Background & Requirements

### Overview

Before iteration 1, iOS could show an RMF message on the NTP while a launch-modal promo was also visible. The [macOS: Implement promo queue for CTAs (popover, message, dialog)](https://app.asana.com/1/137249556945/project/72649045549333/task/1208645854909942?focus=true) prevents similar overlaps, but its contracts and behavior do not map cleanly to the existing iOS modal flow (reusing it would be extra work). Iteration 1 therefore adds targeted iOS cross-surface coordination around the existing modal and NTP implementations.

### Goal

Prevent NTP RMF messages and launch-modal promos from being visible together on iOS, enforce the directional cooldown matrix below, and otherwise preserve current provider eligibility, priority, presentation, and launch-provider accounting behavior. RMF shown accounting is corrected so it reflects admitted render appearances rather than view-model mapping.

### Scope (Iteration 1 Only)

In scope:

- Add a small app-scoped transactional lease arbiter for mutual exclusion between launch modals and NTP RMF messages rendered in an active NTP.
- Keep launch-source and unrelated-UIKit-modal gates in `PromoCoordinationService` and provider-level onboarding gates in `ModalPromptCoordinationManager`, then, on the feature-enabled path, atomically acquire a modal-evaluation lease before evaluating providers. Feature off preserves the legacy overload.
- Keep provider-priority enforcement, cooldown, presentation, and the evaluating/committed/presentation-active phases in `ModalPromptCoordinationManager`. The manager retains the same identity-bearing modal lease until an evaluation checkpoint confirms the selected root is gone. The arbiter and NTP do not need the detailed phase: every active modal phase simply means that the slot is held.
- Connect per-NTP controller/model/view lifecycle to the arbiter so multiple NTP instances are represented correctly and inactive controllers cannot suppress modals.
- Prevent a blocked RMF message from being marked shown, dismissed, or consumed.
- Enforce the iteration-one directional cooldown policy between confirmed modal presentations and admitted NTP RMF appearances.
- Preserve onboarding exclusion and the current launch-modal provider behavior.
- Release behind an iOS feature flag whose rollout default is chosen deliberately.

Out of scope:

- Extracting or changing macOS `PromoService`.
- Generalizing the coordinator into a complete promo queue with arbitrary promo IDs, contexts, severity, restoration, or configurable trigger/frequency policy. The two persisted source-event timestamps required by the fixed matrix below are the only new history.
- Other iOS promo surfaces not involved in the current NTP overlap.
- [RMF Gap Analysis and Fixes (iteration 2)](https://app.asana.com/1/137249556945/project/72649045549333/task/1216396156310211?focus=true), planned for iteration 2.
- Adding onboarding to promo arbitration or coordinating unrelated UIKit modals through it.
- Choosing the long-term promo-coordination model. RMF, client-side, and hybrid options will be considered after iteration 2.
- Android or other platform work.
- New Promo Queue admission, collision, or cooldown telemetry. Commit `1f12bf8a66` removes the two previously proposed collision pixels; measurement is deferred to a separate project.

## Problem Statement

In the pre-coordination baseline, iOS managed launch-modal promos and NTP RMF messages separately. `PromoCoordinationService` evaluated launch modals once per eligible foreground, while each NTP instance independently built RMF view models from shared scheduled-message state. Neither path knew whether the other had committed to presentation, so their asynchronous timing could produce an overlap.

The baseline app had shared scheduled and selected RMF state, but no reliable app-level signal that an RMF was rendered in an active, on-window NTP. Scheduled, selected, rendered, and actually visible are different states and must not be treated interchangeably.

## Recommended Approach

### Why a Lease Model

A permission check followed by later visibility reporting left two race windows open in the pre-iteration code:

1. SwiftUI view-model publication and `onAppear` occur in separate callbacks. A modal can commit after an RMF render check but before the RMF registers visibility.
2. The modal was committed before a non-cancellable `0.1`-second scheduling delay. Backgrounding, presenter changes, or failed UIKit presentation could orphan committed state or allow a stale delayed closure to present after RMF admission.

Expressing mutual exclusion as atomically acquired, explicitly released leases closes both: admission is a check-and-mutate operation, not a Boolean query followed by a later report.

### Ownership

- `Foreground` and `UIInteractionManager` continue to own readiness for foreground interaction.
- `PromoCoordinationService` continues to own launch-source and unrelated-UIKit-modal gates. On the feature-enabled path, after those gates pass it atomically acquires a modal-evaluation lease before calling the manager; providers are not queried on that coordinated path unless the lease is acquired. Feature off calls the legacy lease-free manager overload.
- `ModalPromptCoordinationManager` continues to enforce provider-level onboarding eligibility and priority (the ordered provider list is assembled in `PromoCoordinationService`), own the existing `PromptCooldownManager`, track the detailed modal phase, and perform UIKit presentation. It receives the acquired modal lease from the service and releases it only when that attempt finishes. Session history that records an actual presentation is kept separate from the active or pending attempt state used to stop the AI Chat sync promo from appearing during the scheduling and presentation window.
- A new app-scoped, main-actor arbiter is the single authority for mutual exclusion. It tracks an identity-bearing modal lease and per-surface visible-promo leases — in iteration 1, per-NTP RMF render/visibility leases — but not the modal's detailed lifecycle. It does not know provider priority, cooldown, history, onboarding, or RMF targeting rules.
- `HomePageConfiguration` and `RemoteMessagingStore` continue to own RMF selection and persistence. Per-NTP controller/model/view code reports controller activity and obtains a retained render lease before constructing visible RMF UI.
- Existing provider shown, seen, dismissed, cooldown, impression, and action accounting is preserved. Providers revalidate delayed prepared/retained work and may replace it only where repeating preparation is safe. RMF shown accounting moves from eager mapping to the admitted appearance.
- A separate service-owned cooldown policy/store, not the arbiter or RMF framework, reads the existing last-confirmed-modal timestamp and one new last-confirmed-RMF timestamp. It stores source-event times, not expiry dates, and applies only the compiled iteration-one matrix below.

### Iteration-One Cooldown Policy

| Previous confirmed appearance | Next requested appearance | Required elapsed time |
| --- | --- | --- |
| Launch modal | NTP RMF | 10 minutes, fixed |
| NTP RMF | NTP RMF | 10 minutes, fixed and global across message IDs and NTP instances |
| NTP RMF | Launch modal | 24 hours, fixed |
| Launch modal | Launch modal | Existing `PromptCooldownManager` interval, remotely tunable and currently/default 24 hours |

A modal source event is recorded only at the existing confirmed-presentation point: UIKit presentation completion or adoption of the already-attached prepared root. An RMF source event is recorded only on the first `onAppear` of an admitted render session. Selection, mapping, lease acquisition by itself, a denied admission, pending modal work, and failed/refused presentation never write history.

The existing modal timestamp remains the single source for modal history and is not duplicated. One new last-confirmed-RMF timestamp is persisted across relaunch. Eligibility is inclusive at the exact boundary (`now >= timestamp + interval`); backward wall-clock movement conservatively extends the remaining cooldown, matching the existing modal behavior.

RMF admission takes one global provisional reservation before publishing the inner card so two NTPs cannot both pass the 10-minute check. The matching first appearance promotes that reservation to the persisted RMF timestamp. Withdrawal before appearance releases it without writing. Duplicate `onAppear`, physical remount, and same-ID refresh within one admitted render session do not restart the cooldown; a later newly admitted render session, even for the same message ID, is a new appearance. Once 10 minutes elapse another RMF may be admitted even if an earlier RMF remains visible. Existing active RMF leases nevertheless continue to block modal admission until all matching visible leases release, even after the 24-hour time boundary.

For an eligible, active NTP candidate blocked only by RMF-target cooldown, the service schedules one retry at the earliest 10-minute eligibility boundary and cancels or replaces that timer as state changes. Existing lifecycle, configuration, and render checkpoints remain valid retry sources. Modal work blocked by the fixed RMF-to-modal 24-hour rule remains pending/reconsiderable but is retried only by the existing foreground/checkpoint flow after the boundary; no new 24-hour timer is introduced.

### Behavioral Rules

1. **RMF first:** if an active NTP holds an RMF lease, modal admission fails. Providers are not queried, so no prompt state or cooldown is changed. After every RMF lease releases, the fixed 24-hour RMF-to-modal cooldown still applies from the latest confirmed RMF appearance. The modal is reconsidered on an eligible standard foreground/checkpoint after that boundary, not immediately when RMF disappears. An active undismissed card continues to defer launch modals even after 24 hours because visibility exclusion remains authoritative.
2. **Modal evaluation first:** after the existing service gates pass, the evaluation lease immediately blocks new RMF rendering. If no provider is eligible, it is released synchronously. If a provider is selected, the same attempt becomes committed before the existing presentation delay.
3. **Modal first:** a committed or presentation-active modal prevents the NTP render gate from acquiring a lease. The candidate may remain selected, but it is not rendered, marked shown, dismissed, or consumed by the coordinated UI path.
4. **RMF changes during modal presentation:** candidate mapping is allowed, but the visible card is built only after the render gate atomically acquires a lease. This closes both the animation-window race and the check-to-`onAppear` race.
5. **Modal dismissal:** providers are not modified to report dismissal. The attempt remains active until a checkpoint verifies that the exact selected promo root is gone. Generic disappearance is not sufficient because provider modals can present nested flows that must not finish the promo session. Once released, an RMF that is still within 10 minutes of the modal's confirmed presentation remains blocked by cooldown and is retried at the earliest eligibility boundary; it is not accounted before admission. At foreground, reconciliation and waiting-RMF evaluation run before launch-modal evaluation, while both lease exclusion and cooldown checks remain authoritative.
6. **Multiple NTP instances:** leases are keyed by stable surface instance and promo identity — the NTP instance and message ID in iteration 1. One instance disappearing must not clear another instance's lease. Existing global RMF dismissal still updates all instances.
7. **Onboarding, external launches, and unrelated UIKit modals:** existing gates remain authoritative. The arbiter does not duplicate them.
8. **Feature disabled:** the coordination, cross-surface cooldown, timer, provisional-reservation, and corrected-accounting paths are bypassed. Disabling clears provisional/timer state but retains confirmed persisted timestamps; no RMF history is written while disabled. Legacy direct RMF behavior and the existing modal-only cooldown remain unchanged. Re-enabling resumes any remaining cooldown from confirmed history.
9. **Backgrounding and termination:** the displayed NTP remains in its UIKit hierarchy while the app backgrounds, so its lease intentionally survives and is revalidated on foreground. A committed-but-not-presented modal schedule is cancelled or generation-invalidated and cannot fire after the attempt loses admission. All arbiter state is in-memory and clears on termination.

Admission and lifecycle transitions execute on the main actor, and lease acquisition, provider selection, and commit do not yield. This invariant already holds structurally: the provider protocol, service, and manager are main-actor-bound, `provideModalPrompt()` is synchronous, and the manager already commits ahead of the presentation delay. Every attempt and lease has a stable identity with explicit, idempotent release, so stale callbacks for an older attempt or lease cannot mutate current state.

### Design-Level Change Inventory

- Add one app-scoped, main-actor transactional lease arbiter with identity-bearing modal and visible-promo acquire/release APIs, keyed by surface instance and promo type so a non-RMF CTA can be added later; iteration 1 integrates only per-NTP RMF leases. It is the single mutual-exclusion authority and remains transient/history-free.
- Add a separate service-owned directional cooldown policy/store. Reuse the existing persisted modal timestamp, persist one last-confirmed-RMF timestamp, own the one global provisional RMF admission reservation and one earliest-boundary RMF retry timer, and return typed cooldown denial/next-eligible data without reporting a lease collision.
- Continue constructing/injecting the arbiter through `Launching` and app dependencies. Construct the production cooldown policy inside `PromoCoordinationService` from the existing modal store plus the new RMF store; its designated initializer accepts policy/scheduler doubles for tests. NTP consumers receive only the identity-bound admission wrapper through `NewTabPagePromoCoordinating`; the manager, views, and providers never receive the cooldown store directly.
- Add atomic lease acquisition to `PromoCoordinationService` after its existing launch-source and unrelated-modal gates; release it synchronously when no provider is eligible.
- Extend `ModalPromptCoordinationManager` to own the evaluating, committed, and presentation-active phases while retaining the same arbiter lease until the matching attempt finishes. Preserve provider order, `PromptCooldownManager`, and confirmed-presentation accounting: UIKit completion or adoption of an already-attached prepared root records provider/cooldown/history exactly once. Keep the existing protection against the AI Chat sync promo appearing during modal scheduling. Track actual-presentation session history separately from the active or pending attempt that temporarily suppresses the sync promo. A terminal cancellation that leaves no pending configuration and no earlier presentation stops suppressing the sync promo without clearing earlier session history.
- Make `ModalPromptScheduling` cancellable or generation-aware, and revalidate the attempt (identity, app active, presenter attached, existing modal/OmniBar rules) immediately before UIKit presentation. A failed pre-presentation attempt retains at most one prepared configuration as in-memory pending work for a later eligible foreground. It does not hold the RMF arbitration slot, but it continues to suppress the AI Chat sync promo until it is retried or discarded.
- Keep provider product policy unchanged and add no dismissal signal to `ModalPromptConfiguration`. Extend `ModalPromptProvider` with prepared/retained revalidation and optional safe replacement; all providers use the contract, including cached-versus-fresh Default Browser validation. The manager retains the exact presented root and releases the attempt through checkpoint reconciliation at foreground and every render-gate admission. Generic disappearance alone is rejected because provider modals can present nested flows that must not finish the promo session.
- Update `NewTabPageMessagesModel` and all three NTP hosts with stable surface, gate, render-session, and per-physical-mount identities. Admission requires composed owner activity, render-location readiness, explicit visibility/coverage, window attachment, and a mounted gate before constructing `HomeMessageView`. Reuse the existing `onDidAppear` appearance path behind the lease, remove eager map-time `didAppear` only when the flag is enabled, and release identity-matched leases after physical removal on the next main turn. Same-ID refreshes are one continuous appearance; changed IDs withdraw and release before replacement.
- Make first-shown/unique accounting atomic across concurrent NTP instances, either through a store API that reports the first shown transition or a shared main-actor reservation.
- Map the disabled-by-default iOS `FeatureFlag.promoPresentationCoordination` in the `FeatureFlags-iOS` package to `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination` and stage rollout through the iOS privacy-config override.
- Add focused unit/integration tests (see Testing).

## Notes

### Brief Notes on Iterations 2–3

- Iteration 2 will extend RMF to other promo surfaces. Those surfaces may use the same narrow lease boundary where overlap prevention is required; the generic lease identity (surface instance plus promo type) lets a non-RMF CTA such as the AI Chat sync promo be integrated later as a contained change rather than a redesign.
- No approach has been chosen for iteration 3. If RMF becomes the long-term owner, the targeted arbiter remains small and removable. If a client-side or hybrid queue is chosen, its active-surface signals can become inputs to that system and `PromoService` extraction can be reconsidered with concrete requirements.

## Testing

Testing will verify:

- RMF-first lease acquisition blocks provider evaluation and changes no modal shown, cooldown, or impression state.
- A modal-evaluation lease blocks RMF before provider selection; no eligible provider releases it synchronously.
- Modal commit occurs before the presentation delay and prevents an RMF selected during animation from rendering; candidate mapping followed by later SwiftUI appearance cannot admit both surfaces.
- A presentation-active modal is never retracted for RMF; active state clears only when a checkpoint confirms the selected promo root is gone, and nested child flows do not finish the promo session.
- A blocked RMF remains scheduled and records no shown/dismissed state. After modal checkpoint release it renders only when the 10-minute modal-to-RMF boundary is eligible; the earliest-boundary retry and foreground reconciliation run before later modal evaluation.
- Shown accounting fires exactly once per admitted appearance on the coordinated path; the pre-coordination map-time and `onAppear` double fire is removed. A config refresh that adds a new message to an already-active NTP records shown state through the admitted inner card's `onDidAppear`. Tests enforce that a same-ID refresh does not start a new appearance. Unique shown accounting has an atomic first-transition winner across NTP instances.
- Multiple NTP instances acquire and release independent leases; inactive, covered, animation-hidden, or off-window NTP controllers cannot block modal admission. Per-mount identities and next-main-turn release prevent stale SwiftUI callbacks from affecting replacement sessions.
- `afterIdle` RMF selection waits correctly behind a committed modal.
- Onboarding, deep-link/shortcut, unrelated-modal, OmniBar, provider order, and modal-to-modal cooldown behavior remain unchanged. Add boundary tests for all four directional cooldown rows, persistence/relaunch, backward-clock movement, provisional RMF serialization, and fixed-versus-remotely-tunable interval ownership.
- Cooldown denial retains pending/candidate work and records no provider or RMF shown/dismissed state. RMF-target denial schedules exactly one retry for the earliest 10-minute boundary; modal-target denial waits for a later eligible foreground/checkpoint. Iteration one emits no Promo Queue admission/cooldown telemetry.
- Backgrounding preserves and later revalidates the active NTP lease; committed-but-unpresented schedules are cancelled or generation-invalidated, and stale delayed callbacks cannot present after cancellation; termination clears all in-memory state and introduces no restoration behavior.
- The existing provider order and provider accounting are preserved. The AI Chat sync promo remains suppressed during an active or retained-pending modal attempt and after an actual modal presentation. A terminal pre-presentation cancellation with no pending work stops suppression, while cancellation cannot erase an earlier actual presentation from session history.
- Disabling the feature flag restores the existing modal overload and direct NTP mapping/eager-accounting path, cancels provisional/timer state, and retains confirmed timestamps without new RMF writes. Re-enabling withdraws legacy UI, re-adopts an attached modal, and resumes any unelapsed cooldown before stable gate remount/readmission; it does not synchronously invoke every registered NTP retry from inside the transition.
