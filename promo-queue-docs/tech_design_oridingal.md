Author: @Bartosz
Reviewer: @Alessandro
Stakeholders: @Cristian (away through Aug 28) @Marcos @Chris Thelwell (away through today)@Stephen (away through today)@Dominik@Diego (away through today)
Project: [iOS] Prevent conflicts between RMFs and Modal Sheets on NTP (Iteration 1)
Context
This revised tech design reflects the discussion in the parent task. I left the parent task description unchanged to preserve context.
Background & Requirements
Previous TD with alternative Recommended Approach: ✓ Tech Design: [iOS] Prevent conflicts between RMFs and Modal Sheets on NTP
Overview
iOS can currently show an RMF message on the NTP while a launch-modal promo is also visible. The ✓ macOS: Implement promo queue for CTAs (popover, message, dialog) prevents similar overlaps, but its current contracts and behavior do not map cleanly to the existing iOS modal flow (reusing it would be extra work). Iteration 1 will therefore add targeted iOS cross-surface coordination around the existing modal and NTP implementations.
Goal
Prevent NTP RMF messages and launch-modal promos from being visible together on iOS while preserving current provider eligibility, priority, cooldown, presentation, and launch-provider accounting behavior.
Scope (Iteration 1 Only)
In scope:
Add a small app-scoped transactional lease arbiter for mutual exclusion between launch modals and NTP RMF messages rendered in an active NTP.
Keep onboarding, launch-source, and unrelated-UIKit-modal gates in ModalPromptCoordinationService, then atomically acquire a modal-evaluation lease before evaluating providers.
Keep provider-priority enforcement, cooldown, presentation, and the evaluating/committed/presentation-active phases in ModalPromptCoordinationManager. The manager retains the same identity-bearing modal lease until the selected root is gone. The arbiter and NTP do not need the detailed phase: every active modal phase simply means that the slot is held.
Connect per-NTP controller/model/view lifecycle to the arbiter so multiple NTP instances are represented correctly and inactive controllers cannot suppress modals.
Prevent a blocked RMF message from being marked shown, dismissed, or consumed.
Preserve onboarding exclusion and the current launch-modal provider behavior.
Release behind an iOS feature flag whose rollout default is chosen deliberately.

Out of scope:
Extracting or changing macOS PromoService.
Other iOS promo surfaces not involved in the current NTP overlap.
Next Steps: RMF Gap Analysis and Fixes, planned for iteration 2.
Adding onboarding to promo arbitration or coordinating unrelated UIKit modals through it.
Choosing the long-term promo-coordination model. RMF, client-side, and hybrid options will be considered after iteration 2.
Android or other platform work.
Problem Statement
iOS manages launch-modal promos and NTP RMF messages separately. ModalPromptCoordinationService evaluates launch modals once per eligible foreground, while each NTP instance independently builds RMF view models from shared scheduled-message state. Neither path knows whether the other has committed to presentation, so their asynchronous timing can produce an overlap.
The app has shared scheduled and selected RMF state, but no reliable app-level signal that an RMF is rendered in an active, on-window NTP. Scheduled, selected, rendered, and actually visible are different states and must not be treated interchangeably.
Recommended Approach
Why a Lease Model
A permission check followed by later visibility reporting leaves two race windows open in the current code:
SwiftUI view-model publication and onAppear occur in separate callbacks. A modal can commit after an RMF render check but before the RMF registers visibility.
The modal is committed before a non-cancellable 0.1-second scheduling delay. Backgrounding, presenter changes, or failed UIKit presentation can orphan committed state or allow a stale delayed closure to present after RMF has been admitted.
Expressing mutual exclusion as atomically acquired, explicitly released leases closes both: admission is a check-and-mutate operation, not a Boolean query followed by a later report.
Ownership
Foreground and UIInteractionManager continue to own readiness for foreground interaction.
ModalPromptCoordinationService continues to own onboarding, launch-source, and unrelated-UIKit-modal gates. After those gates pass, it atomically acquires a modal-evaluation lease before calling the manager. Providers are not queried unless that lease is acquired.
ModalPromptCoordinationManager continues to enforce provider priority (the ordered provider list is assembled in ModalPromptCoordinationService), own the existing PromptCooldownManager, track the detailed modal phase, and perform UIKit presentation. It receives the acquired modal lease from the service and releases it only when that attempt finishes. Session history that records an actual presentation is kept separate from the active or pending attempt state used to stop the AI Chat sync promo from appearing during the scheduling and presentation window.
A new app-scoped, main-actor arbiter is the single authority for mutual exclusion. It tracks an identity-bearing modal lease and per-NTP RMF render/visibility leases, but not the modal's detailed lifecycle. It does not know provider priority, cooldown, history, onboarding, or RMF targeting rules.
HomePageConfiguration and RemoteMessagingStore continue to own RMF selection and persistence. Per-NTP controller/model/view code reports controller activity and obtains a retained render lease before constructing visible RMF UI.
Existing provider shown, seen, dismissed, cooldown, impression, and action accounting is preserved. RMF shown accounting moves from eager mapping to the admitted appearance.
Behavioral Rules
RMF first: if an active NTP holds an RMF lease, modal admission fails. Providers are not queried, so no prompt state or cooldown is changed. The modal is reconsidered on the next eligible standard foreground, not immediately when RMF disappears. An undismissed card therefore defers launch modals on every foreground where it is rendered in the active NTP; deferral is bounded by user dismissal, dismissAfterDaysShown expiry where configured, or RMF config replacement/removal.
Modal evaluation first: after the existing service gates pass, the evaluation lease immediately blocks new RMF rendering. If no provider is eligible, it is released synchronously. If a provider is selected, the same attempt becomes committed before the existing presentation delay.
Modal first: a committed or presentation-active modal prevents the NTP render gate from acquiring a lease. The candidate may remain selected, but it is not rendered, marked shown, dismissed, or consumed by the coordinated UI path.
RMF changes during modal presentation: candidate mapping is allowed, but the visible card is built only after the render gate atomically acquires a lease. This closes both the animation-window race and the check-to-onAppear race.
Modal dismissal: the attempt remains active throughout the dismissal animation. Normal provider close, CTA, interactive, and programmatic paths send an exactly-once signal after dismissal completes; the manager then verifies that the selected promo root is gone before releasing the attempt. Exact-root reconciliation is the fallback for external or missed dismissals. Waiting NTP gates are then notified; a still-eligible RMF may render and record its normal shown state.
Multiple NTP instances: leases are keyed by stable NTP instance and message identity. One instance disappearing must not clear another instance's lease. Existing global RMF dismissal still updates all instances.
Onboarding, external launches, and unrelated UIKit modals: existing gates remain authoritative. The arbiter does not duplicate them.
Feature disabled: the coordination and corrected-accounting paths are bypassed. Live flag changes invalidate stale scheduled work and coordination-only reservations. No new persistent queue history is introduced.
Backgrounding and termination: the displayed NTP remains in its UIKit hierarchy while the app backgrounds, so its lease intentionally survives and is revalidated on foreground. A committed-but-not-presented modal schedule is cancelled or generation-invalidated and cannot fire after the attempt loses admission. All arbiter state is in-memory and clears on termination.



Admission and lifecycle transitions execute on the main actor, and lease acquisition, provider selection, and commit do not yield. This invariant already holds structurally: the provider protocol, service, and manager are main-actor-bound, provideModalPrompt() is synchronous, and the manager already commits ahead of the presentation delay. Every attempt and lease has a stable identity with explicit, idempotent release, so stale callbacks for an older attempt or lease cannot mutate current state.
Design-Level Change Inventory
Add one app-scoped, main-actor transactional lease arbiter with identity-bearing modal and per-NTP RMF acquire/release APIs. It is the single mutual-exclusion authority and owns no detailed modal lifecycle or persistent history.
Construct and inject it through Launching/app dependencies into ModalPromptCoordinationService, ModalPromptCoordinationManager, and the NTP controller/model/view creation path.
Add atomic lease acquisition to ModalPromptCoordinationService after its existing onboarding, launch-source, and unrelated-modal gates; release it synchronously when no provider is eligible.
Extend ModalPromptCoordinationManager to own the evaluating, committed, and presentation-active phases while retaining the same arbiter lease until the matching attempt finishes. Preserve provider order, PromptCooldownManager, UIKit completion accounting, and the existing protection against the AI Chat sync promo appearing during modal scheduling. Track actual-presentation session history separately from the active or pending attempt that temporarily suppresses the sync promo. A terminal cancellation that leaves no pending configuration and no earlier presentation stops suppressing the sync promo without clearing earlier session history.
Make ModalPromptScheduling cancellable or generation-aware, and revalidate the attempt (identity, app active, presenter attached, existing modal/OmniBar rules) immediately before UIKit presentation. A failed pre-presentation attempt retains at most one prepared configuration as in-memory pending work for a later eligible foreground. It does not hold the RMF arbitration slot, but it continues to suppress the AI Chat sync promo until it is retried or discarded.
Add a reference-type, exactly-once dismissal signal to ModalPromptConfiguration and wire every provider's close, CTA, interactive, and programmatic completion through it as the normal dismissal notification. The manager verifies that the exact selected root is gone before release. Exact-root reconciliation remains the fallback for external application dismissals, scene/window changes, and missed callbacks. Generic disappearance alone is rejected because provider modals can present nested flows that must not finish the promo session.
Update NewTabPageMessagesModel and the NTP view/controller integration with stable instance IDs, controller active-window reporting, and a render gate that acquires a lease before constructing HomeMessageView. Reuse the existing onDidAppear appearance path behind the lease, remove the eager map-time didAppear, and add the missing disappearance signal. When a config refresh publishes a new message while the NTP is already active, the gate constructs the card only after admission and its existing onDidAppear records shown state. The implementation must define and test same-ID refreshes as the same continuous appearance rather than relying on implicit SwiftUI behavior.
Make first-shown/unique accounting atomic across concurrent NTP instances, either through a store API that reports the first shown transition or a shared main-actor reservation.
Map an iOS feature flag to the existing shared PromoQueueSubfeature.featureEnabled (no BSK change needed) and stage the rollout through the iOS privacy-config override.
Add focused unit/integration tests (see Testing).

Notes
Brief Notes on Iterations 2–3
Iteration 2 will extend RMF to other promo surfaces. Those surfaces may use the same narrow lease boundary where overlap prevention is required.
No approach has been chosen for iteration 3. If RMF becomes the long-term owner, the targeted arbiter remains small and removable. If a client-side or hybrid queue is chosen, its active-surface signals can become inputs to that system and PromoService extraction can be reconsidered with concrete requirements.
Testing
Testing will verify:
RMF-first lease acquisition blocks provider evaluation and changes no modal shown, cooldown, or impression state.
A modal-evaluation lease blocks RMF before provider selection; no eligible provider releases it synchronously.
Modal commit occurs before the presentation delay and prevents an RMF selected during animation from rendering; candidate mapping followed by later SwiftUI appearance cannot admit both surfaces.
A presentation-active modal is never retracted for RMF; active state clears only after the selected promo root is gone, and nested child flows do not finish the promo session.
A blocked RMF remains scheduled, records no shown or dismissed state, and renders after modal dismissal if still eligible.
Shown accounting fires exactly once per admitted appearance on the coordinated path; the current map-time and onAppear double fire is removed. A config refresh that adds a new message to an already-active NTP records shown state through the admitted inner card's onDidAppear. Tests enforce that a same-ID refresh does not start a new appearance. Unique shown accounting has an atomic first-transition winner across NTP instances.
Multiple NTP instances acquire and release independent leases; inactive or off-window NTP controllers cannot block modal admission.
afterIdle RMF selection waits correctly behind a committed modal.
Onboarding, deep-link/shortcut, unrelated-modal, OmniBar, and cooldown behavior remain unchanged.
Backgrounding preserves and later revalidates the active NTP lease; committed-but-unpresented schedules are cancelled or generation-invalidated, and stale delayed callbacks cannot present after cancellation; termination clears all in-memory state and introduces no restoration behavior.
The existing provider order and provider accounting are preserved. The AI Chat sync promo remains suppressed during an active or retained-pending modal attempt and after an actual modal presentation. A terminal pre-presentation cancellation with no pending work stops suppression, while cancellation cannot erase an earlier actual presentation from session history.
Disabling the feature flag restores the existing iOS coordination and accounting path, and re-enabling cannot leave stale leases.