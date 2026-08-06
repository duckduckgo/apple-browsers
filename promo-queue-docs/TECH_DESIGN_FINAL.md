## Context

This revised tech design reflects the discussion in the parent task. I left the parent task description unchanged to preserve context.

It supersedes the earlier draft's permission-check coordinator with a transactional-lease model. The scope, product policy, and ownership remain unchanged; the final implementation also extends the provider adapter contract to revalidate prepared or retained work safely.

## Background & Requirements

### Overview

Before iteration 1, iOS could show an RMF message on the NTP while a launch-modal promo was also visible. The [macOS: Implement promo queue for CTAs (popover, message, dialog)](https://app.asana.com/1/137249556945/project/72649045549333/task/1208645854909942?focus=true) prevents similar overlaps, but its contracts and behavior do not map cleanly to the existing iOS modal flow (reusing it would be extra work). Iteration 1 therefore adds targeted iOS cross-surface coordination around the existing modal and NTP implementations.

### Goal

Prevent NTP RMF messages and launch-modal promos from being visible together on iOS while preserving current provider eligibility, priority, cooldown, presentation, and launch-provider accounting behavior. RMF shown accounting is corrected so it reflects admitted render appearances rather than view-model mapping.

### Scope (Iteration 1 Only)

In scope:

- Add a small app-scoped transactional lease arbiter for mutual exclusion between launch modals and NTP RMF messages rendered in an active NTP.
- Keep launch-source and unrelated-UIKit-modal gates in `PromoCoordinationService` and provider-level onboarding gates in `ModalPromptCoordinationManager`, then, on the feature-enabled path, atomically acquire a modal-evaluation lease before evaluating providers. Feature off preserves the legacy overload.
- Keep provider-priority enforcement, cooldown, presentation, and the evaluating/committed/presentation-active phases in `ModalPromptCoordinationManager`. The manager retains the same identity-bearing modal lease until an evaluation checkpoint confirms the selected root is gone. The arbiter and NTP do not need the detailed phase: every active modal phase simply means that the slot is held.
- Connect per-NTP controller/model/view lifecycle to the arbiter so multiple NTP instances are represented correctly and inactive controllers cannot suppress modals.
- Prevent a blocked RMF message from being marked shown, dismissed, or consumed.
- Preserve onboarding exclusion and the current launch-modal provider behavior.
- Release behind an iOS feature flag whose rollout default is chosen deliberately.

Out of scope:

- Extracting or changing macOS `PromoService`.
- Generalizing the coordinator into a complete promo queue with promo IDs, contexts, severity, history, restoration, or trigger policy.
- Other iOS promo surfaces not involved in the current NTP overlap.
- [RMF Gap Analysis and Fixes (iteration 2)](https://app.asana.com/1/137249556945/project/72649045549333/task/1216396156310211?focus=true), planned for iteration 2.
- Adding onboarding to promo arbitration or coordinating unrelated UIKit modals through it.
- Choosing the long-term promo-coordination model. RMF, client-side, and hybrid options will be considered after iteration 2.
- Android or other platform work.

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

### Behavioral Rules

1. **RMF first:** if an active NTP holds an RMF lease, modal admission fails. Providers are not queried, so no prompt state or cooldown is changed. The modal is reconsidered on the next eligible standard foreground, not immediately when RMF disappears. An undismissed card therefore defers launch modals on every foreground where it is rendered in the active NTP; deferral is bounded by user dismissal, `dismissAfterDaysShown` expiry where configured, or RMF config replacement/removal.
2. **Modal evaluation first:** after the existing service gates pass, the evaluation lease immediately blocks new RMF rendering. If no provider is eligible, it is released synchronously. If a provider is selected, the same attempt becomes committed before the existing presentation delay.
3. **Modal first:** a committed or presentation-active modal prevents the NTP render gate from acquiring a lease. The candidate may remain selected, but it is not rendered, marked shown, dismissed, or consumed by the coordinated UI path.
4. **RMF changes during modal presentation:** candidate mapping is allowed, but the visible card is built only after the render gate atomically acquires a lease. This closes both the animation-window race and the check-to-`onAppear` race.
5. **Modal dismissal:** providers are not modified to report dismissal. The attempt remains active until the next checkpoint — the next eligible standard foreground or any render-gate admission attempt, including mount, reactivation, or configuration retry — where the manager verifies that the exact selected promo root is gone before releasing the attempt. Generic disappearance is not sufficient because provider modals can present nested flows that must not finish the promo session. A blocked RMF therefore reappears at a checkpoint rather than immediately at dismissal; this delay is accepted. At foreground, reconciliation and the waiting RMF retry run before launch-modal evaluation, so a newly eligible modal cannot take the freed slot ahead of a blocked RMF; a still-eligible RMF then renders and records its normal shown state.
6. **Multiple NTP instances:** leases are keyed by stable surface instance and promo identity — the NTP instance and message ID in iteration 1. One instance disappearing must not clear another instance's lease. Existing global RMF dismissal still updates all instances.
7. **Onboarding, external launches, and unrelated UIKit modals:** existing gates remain authoritative. The arbiter does not duplicate them.
8. **Feature disabled:** the coordination and corrected-accounting paths are bypassed. Live flag changes invalidate stale scheduled work and coordination-only reservations. No new persistent queue history is introduced.
9. **Backgrounding and termination:** the displayed NTP remains in its UIKit hierarchy while the app backgrounds, so its lease intentionally survives and is revalidated on foreground. A committed-but-not-presented modal schedule is cancelled or generation-invalidated and cannot fire after the attempt loses admission. All arbiter state is in-memory and clears on termination.

Admission and lifecycle transitions execute on the main actor, and lease acquisition, provider selection, and commit do not yield. This invariant already holds structurally: the provider protocol, service, and manager are main-actor-bound, `provideModalPrompt()` is synchronous, and the manager already commits ahead of the presentation delay. Every attempt and lease has a stable identity with explicit, idempotent release, so stale callbacks for an older attempt or lease cannot mutate current state.

### Design-Level Change Inventory

- Add one app-scoped, main-actor transactional lease arbiter with identity-bearing modal and visible-promo acquire/release APIs, keyed by surface instance and promo type so a non-RMF CTA can be added later; iteration 1 integrates only per-NTP RMF leases. It is the single mutual-exclusion authority and owns no detailed modal lifecycle or persistent history.
- Construct and inject it through `Launching`/app dependencies into `PromoCoordinationService`, `ModalPromptCoordinationManager`, and the NTP controller/model/view creation path.
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
- A blocked RMF remains scheduled, records no shown or dismissed state, and renders at the first checkpoint after modal dismissal if still eligible; foreground reconciliation and the RMF retry run before launch-modal evaluation.
- Shown accounting fires exactly once per admitted appearance on the coordinated path; the pre-coordination map-time and `onAppear` double fire is removed. A config refresh that adds a new message to an already-active NTP records shown state through the admitted inner card's `onDidAppear`. Tests enforce that a same-ID refresh does not start a new appearance. Unique shown accounting has an atomic first-transition winner across NTP instances.
- Multiple NTP instances acquire and release independent leases; inactive, covered, animation-hidden, or off-window NTP controllers cannot block modal admission. Per-mount identities and next-main-turn release prevent stale SwiftUI callbacks from affecting replacement sessions.
- `afterIdle` RMF selection waits correctly behind a committed modal.
- Onboarding, deep-link/shortcut, unrelated-modal, OmniBar, and cooldown behavior remain unchanged.
- Backgrounding preserves and later revalidates the active NTP lease; committed-but-unpresented schedules are cancelled or generation-invalidated, and stale delayed callbacks cannot present after cancellation; termination clears all in-memory state and introduces no restoration behavior.
- The existing provider order and provider accounting are preserved. The AI Chat sync promo remains suppressed during an active or retained-pending modal attempt and after an actual modal presentation. A terminal pre-presentation cancellation with no pending work stops suppression, while cancellation cannot erase an earlier actual presentation from session history.
- Disabling the feature flag restores the existing modal overload and direct NTP mapping/eager-accounting path. Re-enabling withdraws legacy UI and re-adopts an attached modal before stable gate remount/readmission; it does not synchronously invoke every registered NTP retry from inside the transition.
