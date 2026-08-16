# Promo Queue: simplified iOS technical design

## Status and source of truth

This is the self-contained source of truth for the final iOS Promo Queue architecture. It contains the complete problem statement, decisions, behavior, limitations, rollout, and verification strategy.

Only [PR #6087](https://github.com/duckduckgo/apple-browsers/pull/6087) is part of the merged iOS baseline. A larger renderer-coordination implementation was explored but is not the target architecture. The scope is iOS only. Android is a reference implementation, not a delivery target.

Implementation is complete across the three open stacked production pull-request branches: `bartosz/promo-q-simp-2`, `bartosz/promo-q-simp-3`, and `bartosz/promo-q-simp-4`. The known SharedState compilation issue and coordinated-preparation leak into legacy mode were fixed before the final branch tips. Independent final review, the manual validation matrix, human integration, and external rollout remain pending. This implementation status is informational; the architecture below defines the complete intended end state without depending on another document.

## Documentation ownership — 2026-08-16

`bartosz/promo-q-simp-master` is the sole source branch for Promo Queue project documentation. Maintain `project_log.md`, `project_lessons/`, `promo-queue-docs/`, executive/review reports, and project-only handoff notes there.

The open production branches `bartosz/promo-q-simp-2`, `bartosz/promo-q-simp-3`, and `bartosz/promo-q-simp-4` must remain free of those files so their pull-request diffs contain only production code, tests, and required Xcode project wiring. Read documentation from the master branch with `git show`, or use a separate worktree; do not copy or cherry-pick documentation commits into a production branch.

Documentation edits may be committed locally on `bartosz/promo-q-simp-master`. Do not push that branch or its documentation commits unless the user later gives explicit instructions. If a production fix changes the implemented behavior, update the documentation on the master branch after inspecting the final production diff.

## Review validation update — 2026-08-15

The following corrections are incorporated into this revision:

- coordinated initialization cannot claim RMF before an NTP-capable path requests content;
- `HomePageConfiguration` owns remote-message refreshes and emits a distinct source-change signal;
- the admitted message and its actual selected trigger filter stay pinned for one ownership;
- appearance confirmation and cooldown persistence have an explicit service-owned wiring path;
- unsupported RMF content is rejected before admission;
- each returned RMF lease exposes one opaque acquisition identity through its production contract for callback validation and SwiftUI identity;
- dismissal and unique-shown guarantees match the existing best-effort store APIs;
- backgrounding unpublishes RMF, signals consumers, releases ownership, and disarms RMF admission until another explicit NTP preparation;
- normal and background launch initialize RMF admission explicitly without waiting for the first foreground callback;
- all conditional NTP host families prepare only at an activation seam that can make content visible;
- the shared configuration, protocol, model, selection, publication, and callbacks are fully main-actor isolated;
- an after-idle request's fallback policy is distinct from the actual trigger filter pinned by an admitted message;
- asynchronous dismissal uses identity-safe completion and authoritative refresh without an in-flight ownership sub-state;
- modal ownership uses one opaque identity and manager lease transfer has no returned disposition; and
- background/reacquisition cooldown consequences, expected shown-volume changes, minimal diagnostics, and deferred post-rollout cleanup are explicit.

## Product decisions confirmed — 2026-08-15

- **Modal scope:** “modal sheets” means launch-promo providers routed through `PromoCoordinationService`, not every arbitrary UIKit sheet.
- **NTP integration seam:** an NTP container has one Promo Queue-specific integration point: call `prepareForNTP(openedAfterIdle:)` once per content activation, before the activation-time eligibility resolution that can make its content visible. Lease ownership, cooldowns, refresh, release, background handling, and accounting remain central. No surface reports visibility or lifecycle state.
- **Mixed triggers:** the first admitted message and the actual filter that selected it stay authoritative for that ownership. An after-idle request may fall back to no-trigger, and that no-trigger result remains pinned. A later renderer request cannot replace a still-valid owner; dismissal, expiry, replacement, onboarding suppression, backgrounding, or another real invalidation ends the pin.
- **Persistence semantics:** existing dismissal and unique-shown behaviors remain best effort. This iteration does not widen shared store APIs, add a unique-shown reservation, or add telemetry for stronger guarantees.

## Decision summary

Use one app-scoped, main-actor promo slot. A launch-modal attempt or an NTP RMF message may own it, but not both.

Current iOS NTP renderers will not register themselves with the coordinator or report whether they are active, renderable, visible, or covered. Instead, the shared `HomePageConfiguration` will acquire and retain the RMF lease before it publishes a remote message into `homeMessages`. All current NTP renderers already read from that same configuration, so they need no per-renderer lease or visibility integration. Conditional containers perform one shared-source preparation before their activation-time eligibility decision can make content visible.

RMF ownership follows the active message, not the physical view:

- the same message ID reuses the current lease;
- a dismissed, expired, or replaced message releases it;
- leaving the NTP does not release it;
- backgrounding first unpublishes the RMF and then releases it; and
- process termination clears all in-memory ownership.

This deliberately trades renderer-level precision for a smaller source-owned contract: claim before publishing NTP view state, do not track which physical renderer is visible, and accept that an active card can over-hold the slot until message invalidation or backgrounding. iOS centralizes the decision in its shared message source. Ownership is keyed by message ID, and RMF cooldown history begins only on actual appearance rather than on selection or disappearance.

The result is a coordination seam, not a scheduler or general-purpose queue.

## Goal

Prevent launch-promo modal sheets managed by `PromoCoordinationService` and NTP RMF cards from being admitted together on iOS, while keeping the implementation small, maintainable, and easy to inherit when the NTP UI changes. The coordinated launch-promo set currently consists of the new address-bar picker, default-browser prompt, win-back offer, subscription promo, existing-user subscription promo, What's New, and cookie-popup-protection opt-in providers.

## In scope

- Atomic mutual exclusion between coordinated launch-modal attempts and NTP RMF messages.
- Admission before modal-provider evaluation and before RMF publication.
- The existing modal provider order, eligibility, presentation, cooldown, and accounting behavior.
- Existing `RecentModalPromptStatusProviding` behavior used to suppress other session promos while a modal attempt is pending or active.
- Source-owned RMF ownership in the shared `HomePageConfiguration`, terminated by message lifecycle or the one app-scoped background checkpoint.
- Directional Promo Queue cooldowns: launch modal → RMF 10 minutes, RMF → RMF 10 minutes, and RMF → launch modal 24 hours; launch modal → launch modal remains owned by the existing remotely configured policy.
- Existing RMF event definitions, metric-eligibility checks, dismissal, and action handling. In coordinated mode, regular shown fires once per ownership after actual appearance; unique-shown is evaluated at that point and preserves the existing best-effort first-ever-message semantics. Legacy-mode frequency remains unchanged.
- A startup-latched feature mode behind `.promoPresentationCoordination`.
- Focused behavior-level tests and internal diagnostics.
- A remote-config rollout to all iOS users after validation.

## Out of scope

- Coordinating arbitrary UIKit sheets or overlays that are not launch-modal providers.
- Guaranteeing that only one physical copy of an RMF card is mounted across current NTP renderers.
- Tracking NTP host visibility, coverage, window attachment, or renderer priority.
- Renderer selection, renderer handoff, drain state, or exact SwiftUI removal completion.
- A general promo priority queue, fairness, preemption, caps, restoration, or retry timers.
- Changes to RMF targeting, scheduling, dismissal, or campaign configuration.
- Changes to macOS `PromoService` or Android code.
- New Promo Queue telemetry.
- Atomic cross-process `remoteMessageShownUnique` reservation.

## Background

PR #6087 established a correct but broad foundation: `PromoQueueLeaseArbiter`, modal attempt phases, exact-root reconciliation, live feature transitions, per-surface RMF identities, and retry registration. A later, unmerged renderer-coordination approach added explicit exposure reporting from the standard NTP, suggestion tray, unified input, and overlays; renderer selection; logical sessions; handoff/drain state; and exact removal terminals.

That approach solved more than the product problem. It attempted to prove which physical NTP renderer was visible at every moment. It consequently required every current and future host or covering overlay to report the correct state. A missing integration would fail silently.

The product requirement does not need that proof. It needs an atomic decision before either conflicting kind of promo is admitted.

## Evolution from the initial simplified direction

The initial simplified direction can be stated without any external context: use one app-scoped slot; acquire it before publishing a launch modal or NTP RMF; prefer message-lifecycle RMF ownership over physical-view tracking; let actual card appearance confirm the impression; release on message removal and app background; and use weak-token recovery. The final design preserves that center.

The following table is the complete list of material architectural or behavioral differences, factual corrections, and previously unspecified final choices. Naming, file placement, and ordinary implementation detail are not counted.

| Initial simplified direction | Final choice | Why the final design chooses it |
| --- | --- | --- |
| Each NTP messages model asks the gate and retains a lease. | The one shared `HomePageConfiguration` asks once and owns the lease before publishing to every model. | iOS already has one app-scoped source feeding every current renderer. Owning at that source removes duplicate acquisition, release, and surface-integration work while preserving pre-publication admission. |
| Each physical surface can join an owner with the same message ID; view-lifetime mode would use a retain count. | Current renderers share one source-owned lease, with no per-surface join or retain count. Same-ID reuse occurs within that source. | There is only one logical RMF source today. Modeling several owners would recreate the view bookkeeping this design is intended to remove. A future independent RMF source gets a deliberate source adapter rather than implicit joining. |
| RMF selection starts when an NTP model decides to render. | Coordinated initialization is RMF-inert; `prepareForNTP(openedAfterIdle:)` requests selection only at an NTP activation/content-loading seam while admission is enabled. | `HomePageConfiguration` is created before launch-modal evaluation, including when a website tab is restored. Eager acquisition could invisibly claim the slot and starve a launch modal. Conditional hosts also need content prepared before activation-time eligibility resolution can make NTP UI visible. |
| Initial app-active state and startup ordering are unspecified. | The composition root initializes normal launches as admission-enabled/unprepared and true background launches as admission-disabled/unprepared, using the existing background-launch fact. Foreground only enables later preparation. | The initial NTP can attach before the first foreground callback, so always-inactive startup would discard valid preparation. Always-active startup would let a true background launch claim RMF. One initial boolean avoids a lifecycle state machine. |
| Existing models react independently to `remoteMessagesDidChange`. | `HomePageConfiguration` is the sole coordinated production observer responsible for NTP candidate selection and ownership, and emits a separate synchronous, object-scoped content signal. Models and conditional hosts only consume the resulting array. | Several models selecting into one mutable source would be duplicate and order-dependent. A distinct source signal also updates hosts that inspect `homeMessages` before creating a model without notification recursion. Passive debug observers may continue observing the global notification. |
| A different selected message replaces the old one and asks afresh; trigger interactions are unspecified. | The first admitted message and actual selected trigger filter remain pinned while valid. A competing preparation policy cannot replace it. | iOS entry points can request different trigger policies. Last-caller-wins replacement could release an appeared card, hit RMF-to-RMF cooldown, and blank every renderer. Pinning one actual filter inside the ownership aggregate is not a renderer state machine. |
| After-idle fallback and store-driven retry have no defined trigger semantics. | The source stores the last preparation policy (`noTriggerOnly` or `afterIdleThenNoTrigger`) separately from the actual selected filter (`noTrigger` or `afterIdle`) pinned in current ownership. | An after-idle request can fall back to a no-trigger candidate. Pinning the actual filter prevents a later after-idle candidate from displacing that still-valid fallback owner, while retaining the last request policy makes ownerless store retry deterministic. |
| The generic gate checks onboarding along with ownership and cooldown. | Existing RMF selection keeps onboarding policy; the gate owns only mutual exclusion and cross-promo cooldowns. | Onboarding is already an RMF eligibility concern with an established source. Keeping policy with its existing owner makes the gate smaller and avoids duplicating product rules. |
| No supported-content/buildability precheck is specified before acquisition; physical invisibility in Fire/layout states is accepted. | A pure builder-backed structural renderability predicate runs before acquisition, while Fire/offscreen/layout over-hold remains accepted. | Missing or unsupported content can produce no card and therefore no `onAppear`. Acquiring it would let an unbuildable candidate hold the slot indefinitely. This content check adds no physical visibility reporting. |
| Message disappearance releases the card; background also frees it. | All endings use unpublish → synchronous source signal → release. Background additionally disarms acquisition and clears preparation state; foreground only enables the next explicit preparation. A previously appeared card remains subject to both persisted cooldowns when reconsidered. | Ordered teardown prevents a modal from acquiring while stale RMF content is still published. Disarming prevents a store notification from immediately reacquiring in the background. Preserving confirmed history makes background release safe without a same-ID resume exemption. |
| Release terminals are dismissal, expiry, or replacement. | Onboarding suppression and loss of eligible/renderable content are also source-lifecycle terminals; ordinary NTP disappearance, tab switching, Fire/layout changes, and window detachment are not. | A source that can no longer publish a valid card must not keep ownership. View-derived terminals would reintroduce the callbacks and ambiguity the simpler approach removes. |
| Releasing on ordinary view disappearance is presented as a small optional upgrade because the model is assumed to receive that signal. | Ordinary view disappearance is explicitly not a terminal, and no RMF `viewDidDisappear` contract is added. | The current RMF model has no such signal, and several physical renderers may represent one source-owned message. A safe last-view release would require identities or retain counting, reintroducing the machinery being removed. |
| Message ID is the relevant lease identity. | Every RMF acquisition also has an opaque identity used for stale-callback validation and SwiftUI diffing. Modal ownership uses one separate typed opaque identity throughout its lifetime. | Releasing and rapidly reacquiring the same RMF ID must make old asynchronous callbacks inert and force a fresh card identity. One modal identity removes redundant attempt/acquisition state without weakening stale-callback protection. |
| `markShown()` on a lease both confirms and records the first impression. | The raw arbiter token only confirms once; a service-owned wrapper records cooldown history; `HomePageConfiguration` fires existing RMF events. | This explicitly connects appearance to persistence without putting storage or analytics in the mutual-exclusion primitive. It also gives each responsibility one owner. |
| Shown uniqueness and dismissal-persistence guarantees are unspecified; dismissal is treated as a lifecycle terminal. | Regular shown is once per admitted ownership; unique-shown and dismissal persistence retain their existing best-effort semantics. Dismissal validates before its `await`, but does not freeze ownership while suspended; completion tears down directly only if its context is still current and always requests authoritative source reconciliation. | The existing store performs an asynchronous check/update for unique-shown and exposes dismissal as `async Void` while swallowing persistence failures. Acquisition identity already makes stale completion safe, so an in-flight dismissal sub-state would add complexity without improving mutual exclusion. |
| A modal needs to ask before presentation; the exact admission point is unspecified. | The service acquires and checks cross-promo cooldown before it asks any provider to evaluate. | `provideModalPrompt()` may mutate eligibility or accounting. Evaluation must not consume or side-effect a modal that RMF ownership already prevents from showing. |
| A modal releases when dismissed. | An admitted modal retains the same lease through evaluation, scheduling, and attachment; existing checkpoints release it only after its exact root detaches. | UIKit may present nested children, and provider-specific dismissal callbacks would broaden integration. Exact-root ownership already exists and cheaply prevents early release; lazy reconciliation accepts bounded over-hold. |
| “Only the holder can be on screen” can be read as a frame-perfect rendering guarantee. | The contract guarantees admission ordering and source removal before release, not proof that every SwiftUI exit-animation pixel has disappeared. | A frame-perfect guarantee and immediate modal retry would require exact physical-renderer removal coordination. The product issue is prevented without rebuilding that state machine. |
| Cooldown is one gate condition without directional values or persistence details. | The policy explicitly defines modal→RMF 10 minutes, RMF→RMF 10 minutes, RMF→modal 24 hours, and existing modal→modal behavior, based on confirmed appearances. | Stating the inherited directional policy makes this document complete. Persisting only confirmed source events avoids consuming cooldown for a denied or never-mounted promo. |
| The interface is a generic `PromoGate` and `PromoLease`. | iOS uses typed, main-actor, synchronous, fail-fast modal and RMF admission contracts with identity-safe weak tokens. The manager's transferred-modal-lease operation returns `Void`; after transfer the manager alone retains or releases it. | Typed ownership prevents cross-kind misuse, and non-yielding admission preserves atomicity. A one-way ownership transfer removes a reporting enum and prevents the service from making a second post-transfer lease decision. |
| The shared-source concurrency boundary is unspecified. | The complete configuration/protocol/model selection and publication path is `@MainActor`, and global store notifications explicitly enter that actor before touching source state. | The mutual-exclusion argument depends on selection, lease retention, publication, and synchronous signaling being one serialized operation. One actor boundary is simpler to maintain than scattered method annotations or locks. |
| Option B is presented as matching Android, while iOS separately proposes background release. | Android is used only as evidence for claim-before-publication and source-owned over-hold. iOS preserves its background-release choice but deliberately differs on message identity, cooldown confirmation, and modal-root lifetime. | Inspection showed Android's app-scoped coordinator is type-keyed, its NTP claim is not released on background, and its selection model does not have iOS's multiple independently acting NTP entry points with different preparation policies. Copying those assumptions would be unsafe on iOS. |
| The exact launch-modal provider boundary is not enumerated. | Coordination covers the seven launch-promo provider categories routed through `PromoCoordinationService`, not arbitrary UIKit presentations. | This states the confirmed product scope and preserves a small blast radius. Intercepting every UIKit sheet would require central presentation interception or widespread integrations. |
| Retry timing is not specified beyond existing lifecycle/configuration events. | Retries occur only at the natural checkpoints listed in this document. | This makes delayed progress explicit without adding a waiter, timer, release broadcast, or renderer registration. |
| Feature-mode transition behavior is not specified. | Mode is startup-latched behind the existing feature flag. | Requiring relaunch is a chosen simplification that avoids live-mode migration, re-adoption, and lease-invalidation state for an initially disabled feature. |
| Fire mode and constrained landscape are both described as possible invisible-card states. | Fire-mode suppression is an accepted over-hold; landscape is manual behavior discovery, not a special ownership rule. | Current iOS source confirms Fire suppression but no explicit landscape suppression. The design should not add lifecycle machinery for an unverified condition. |
| Operational diagnostics and rollout are not defined. | The existing internal debug screen exposes only the mode, owner/appearance, cooldown values, refresh, and matching reset controls; remote rollout remains external, and legacy cleanup is deferred until after 100% rollout plus a soak/rollback window. | Focused diagnostics make long cooldowns testable without force-acquire hooks or telemetry. Deferring cleanup preserves rollback while preventing rollout scaffolding from becoming permanent afterward. |

### Fidelity assessment

This is a faithful implementation of the initial simplified direction, not a literal transcription of its sample interfaces. It keeps every defining idea: one app-scoped slot, admission before modal presentation and RMF publication, message/source-lifetime RMF ownership, background release, no renderer visibility or handoff state, actual-appearance confirmation, weak-token recovery, and acceptance of bounded over-hold. iOS strengthens modal timing by admitting before provider side effects.

The largest adaptation—moving lease ownership from each model to the already-shared source—makes the initial simplified direction even simpler in the actual iOS architecture. Most changes close concrete lifecycle or API gaps at that same seam; the remaining choices deliberately simplify live-mode/retry behavior or complete diagnostics and rollout. None requires surface registration, coverage callbacks, retain counting, renderer selection, or a retry scheduler. The design therefore remains true to that direction's intended trade: less physical-view precision in exchange for a much smaller and more maintainable system.

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
| Live owner | Prompt type only | One typed modal ownership identity or RMF message/acquisition identity |
| Busy acquisition | Waits up to one second | Synchronous, fail-fast main-actor admission |
| RMF release | Active message becomes `null` | Message is dismissed, expires, or is replaced |
| Background/view disappearance | Neither releases | Background releases RMF; ordinary view disappearance does not |
| Modal ownership | Released when an evaluator reports `ModalShown`; some evaluators have only enqueued activity launch at that point, so cooldown provides the remaining spacing | Retained until the exact modal root is reconciled as detached |
| RMF cooldown confirmation | Raw active-message flow becomes `null`, regardless of physical appearance | First actual admitted appearance |
| Renderer visibility | Not tracked | Not tracked |

Message identity and exact modal-root ownership are retained because they are already inexpensive on iOS and make stale callbacks safer. Android's one-second wait, type-only identity, early modal release, and background retention are not copied. The iOS background choice deliberately favors freeing the ownership slot so modal admission can be reconsidered, while preserving any confirmed cooldown history.

## Design principles

1. **Coordinate at shared sources, not views.** New NTP renderers using `HomePageConfiguration` inherit coordination automatically.
2. **Ask before side effects.** Providers are not queried and RMF UI is not published until the slot is acquired.
3. **Serialize the complete shared path on the main actor.** `HomePageMessagesConfiguration`, `HomePageConfiguration`, `NewTabPageMessagesModel`, candidate selection, publication, callbacks, and source-signal delivery are `@MainActor`; global notifications enter that actor before source state is touched. Acquisition, selection, publication, confirmation, and release do not yield across the check-and-mutate boundary.
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
modal(ownershipID)
remoteMessage(messageID, acquisitionID, hasAppeared)
```

It owns no provider order, RMF targeting, onboarding policy, presentation, persistence, or view lifecycle.

The implementation keeps distinct typed modal and RMF lease tokens. A single generic token is not a goal; type safety is preferable to saving a few declarations. Modal ownership has one opaque typed UUID, used consistently for arbiter matching, lease identity, manager phases, stale scheduled-callback validation, and diagnostics. It does not carry a second attempt or acquisition identity. RMF retains its separate acquisition identity because that identity is part of callback validation and SwiftUI remounting. Both raw tokens must provide:

- identity-checked, idempotent release;
- stale-token protection through their one ownership/acquisition identity; and
- weak-token recovery so an abandoned owner cannot wedge the process forever.

The requesting component retains its token strongly for the complete ownership lifetime. The arbiter retains only a weak reference.

The raw RMF token exposes `confirmAppearance() -> Bool`. It returns `true` only for the first valid confirmation of the current acquisition and owns no persistence or event reporting. This keeps the arbiter a pure mutual-exclusion primitive.

The read-only snapshot consumed by the existing internal debug screen contains only the current owner, its diagnostic identity, and whether the current RMF ownership has confirmed an appearance. Tests may exercise this production diagnostic contract, but fields must not be added merely for test inspection.

### `PromoCoordinationService`

`PromoCoordinationService` is the thin gate around the arbiter, directional cooldown policy, and modal manager. It has two typed admission routes.

For modals, `presentModalPromptIfNeeded`:

1. Preserves the existing launch-source and unrelated-presented-controller checks.
2. Lazily reconciles a previously presented coordinated modal.
3. Acquires the modal slot.
4. Evaluates the RMF-to-modal cooldown.
5. Only then asks `ModalPromptCoordinationManager` to evaluate providers.
6. Releases directly, without recording history, if the cross-promo cooldown denies admission.
7. Otherwise transfers lease ownership to the manager through a `Void`-returning operation. The manager releases it if provider evaluation selects no modal, or retains that same lease if a modal is selected.

Acquisition and cooldown denial occur before provider evaluation because `provideModalPrompt()` may have side effects.

For RMF, a narrow `PromoGating` protocol exposes coordinated mode and synchronous acquisition by message ID. `HomePageConfiguration` is the sole current client. Before RMF acquisition the service lazily reconciles an exact modal root, then checks the slot and modal/RMF-to-RMF cooldowns. If the cooldown denies a request after temporary slot acquisition, the service releases that acquisition synchronously before returning no lease.

The service returns a small RMF lease wrapper that strongly retains the raw arbiter token and exposes its opaque, hashable acquisition identity through the production gate contract. Its no-argument `markShown() -> Bool` calls the raw token's `confirmAppearance()` and, only when that returns `true`, records the RMF cooldown timestamp through the injected history component. It remains nonthrowing and returns `true` for that first valid appearance even if durable persistence fails; the history component keeps its in-process value authoritative and logs/absorbs the storage error. Release forwards to the raw token. `HomePageConfiguration` retains only this wrapper and remains responsible for firing existing RMF shown events after a successful `markShown()`. This assigns persistence explicitly without putting it in the arbiter.

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

Once the service passes the cross-promo cooldown and calls the manager, the manager owns the modal lease. That transferred-lease operation returns `Void`: release/retain decisions and their outcome logging belong entirely to the manager. It releases the lease if modal-to-modal cooldown or provider evaluation selects nothing. Otherwise it carries the same lease through evaluation, committed scheduling, and presentation. The lease is released when an existing checkpoint proves the exact selected root is no longer attached. A nested child does not end the modal attempt. The service never branches on a returned disposition and never releases a lease after transferring it to the manager.

`didPresentModalPromptThisSession` must continue to suppress dependent session promos while a modal is evaluating, committed, or attached, and after an actual presentation. An evaluation that selects nothing returns to idle and stops temporary suppression when there is no earlier presentation history; it must not erase earlier actual-presentation history. No new pre-presentation cancellation mechanism is introduced.

The design does not add a dismissal callback to every modal provider. If dismissal is not observed immediately, the detached modal may over-hold the slot until the next foreground or RMF admission attempt. This is safer and much smaller than wiring every dismissal path.

### `HomePageConfiguration`

`HomePageConfiguration` is created once in `MainCoordinator` and is already passed to the standard NTP, legacy/iPad suggestion tray, `OmniBarEditingStateViewController`/`SuggestionTrayManager`, and unified-input paths. It becomes the sole logical owner of the RMF lease. The complete shared path—`HomePageMessagesConfiguration`, `HomePageConfiguration`, `NewTabPageMessagesModel`, selection, ownership, publication, callbacks, and configuration-signal delivery—is `@MainActor`.

In coordinated mode, initialization builds only non-RMF home messages. It must not fetch or acquire RMF while `MainCoordinator` is being constructed; doing so would let a scheduled card claim the slot before launch-modal evaluation, even when a website tab is restored. The composition root passes the existing background-launch fact into the shared configuration:

- a normal launch starts admission-enabled but unprepared, so an initial NTP attachment may prepare even if it precedes the first foreground callback;
- a true background launch starts admission-disabled and unprepared, so an incidental preparation cannot acquire or record a preparation policy; and
- foregrounding only enables a later explicit preparation. It does not replay an earlier request or publish RMF itself.

This needs one admission-enabled boolean, not a general lifecycle state machine. In both launch modes, RMF selection begins only when an NTP-capable path explicitly calls `prepareForNTP(openedAfterIdle:)`.

The standard NTP calls this operation at its existing home-screen attachment refresh. Each conditional-host family calls it once at the activation/content-loading seam immediately before the activation-time eligibility resolution that can make NTP content visible:

- the legacy/iPad suggestion tray owned by `MainViewController`;
- `OmniBarEditingStateViewController` with `SuggestionTrayManager`; and
- unified input, before its activation resolution signal.

Construction-time reads that cannot display UI remain pure and do not prepare. `canShow`, `hasMessages`, computed eligibility getters, and configuration-signal sinks must remain pure; none calls `prepareForNTP`. These activation calls are source loading, not renderer visibility, lease, disappearance, or lifecycle callbacks. A future renderer that directly consumes an already-prepared shared model needs no Promo Queue call. A new conditional container needs the same one activation-time preparation plus ordinary observation of the shared content signal—nothing else.

In coordinated mode, `HomePageConfiguration` is the sole coordinated production observer responsible for NTP candidate selection and RMF ownership when the global `remoteMessagesDidChange` notification arrives. Passive debug observers may remain. The global notification must explicitly enter the main actor before source state is read or mutated. After the configuration refreshes `homeMessages`, it emits a separate object-scoped configuration signal. `NewTabPageMessagesModel` and host-level consumers observe that signal and rebuild or reevaluate from the shared array; they do not run candidate selection. Model delivery remains synchronous on the main actor so teardown's unpublish/signal/release ordering is real; host layout reactions may still schedule UI work. Legacy mode retains the existing notification path. The global store notification must not be reused as the configuration signal.

Keep current ownership as one private optional `RMFOwnership` aggregate containing the current message/content, the actual trigger filter that selected it, the service-owned lease, and the opaque callback/presentation context. Keep the last preparation policy outside that aggregate. Build and strongly retain the complete aggregate before publishing RMF; never publish while the arbiter's weak token has no strong source owner. A same-owner refresh updates content without changing the lease or identity.

Use one teardown sequence everywhere an ownership ends: remove the current RMF from shared `homeMessages`, synchronously signal consumers to rebuild from that source, then release and clear the aggregate. If the source did not change or there is no ownership, the corresponding step is a no-op. This aggregate and non-yielding main-actor ordering prevent parallel optionals from drifting and preserve safe weak-token recovery without additional state.

Represent selection with two distinct private concepts:

- the last preparation policy: `noTriggerOnly` or `afterIdleThenNoTrigger`; and
- the current ownership's actual selected filter: `noTrigger` or `afterIdle`.

An after-idle preparation tries the after-idle filter first and falls back to no-trigger, matching current behavior. The selector returns both candidate and actual filter. If fallback selected a no-trigger candidate, the ownership is pinned as no-trigger; a later after-idle candidate cannot displace it while it remains valid.

Its coordinated selection flow is:

1. Build the existing non-RMF messages and apply onboarding rules.
2. If onboarding suppresses RMF, run the teardown sequence and return the non-RMF messages.
3. If an owner exists, reevaluate it using its actual selected filter. If the same message remains scheduled and passes the pure renderability predicate, keep its lease/acquisition identity, publish refreshed content, signal if needed, and return. A later renderer request with a different policy does not replace it.
4. If the current owner is no longer valid, run the ordered teardown before any fresh selection, even when another policy could return the same message ID.
5. Fetch a fresh candidate using the explicit preparation policy or, for an enabled store-driven refresh, the last preparation policy. Record the actual filter that selected it.
6. If there is no candidate or `HomeMessageViewModelBuilder.canBuild(for:)` (or its equivalent pure predicate) returns false, publish only the non-RMF messages. The predicate must use the same content-to-display conversion as the full builder; do not invoke the side-effecting builder as a probe or duplicate another support switch.
7. Attempt to acquire a lease for the new ID.
8. On success, build and retain the complete ownership aggregate before publishing the candidate into `homeMessages`, then signal models to rebuild.
9. On failure, publish no RMF and leave the underlying scheduled message untouched.

The configuration releases its lease when a refresh observes dismissal, expiry, replacement, no eligible/renderable message, or onboarding suppression. It does not release when a renderer disappears, the user leaves the NTP, or one of several physical cards disappears.

An explicit `prepareForNTP` updates the last preparation policy only when admission is enabled. A disabled call is a no-op for RMF state and cannot be replayed later. Coordinated store refreshes use the retained policy only when fresh selection is needed; background clears it. Therefore an ownerless store notification after foreground cannot select RMF until a new enabled preparation establishes a policy. This gives later store-driven retry a defined request/fallback policy even when a previous enabled attempt was denied and no owner exists.

On app background, the configuration uses the same ordered teardown, clears the last preparation policy, and disables RMF admission. Store notifications while disabled may refresh non-RMF data but cannot reacquire RMF. Foregrounding only enables future preparation; it does not publish a card. This is one app-scoped lifecycle integration through `MainCoordinator`, not a callback from every renderer.

Whenever coordinated `homeMessages` changes, `HomePageConfiguration` emits one configuration-level change signal so every `NewTabPageMessagesModel` converges on the same shared value. Observers rebuild from that value; they do not trigger another candidate refresh. This is a content update, not renderer registration: it carries no renderer identity, ordering, visibility, acknowledgement, or retry intent. When ending RMF ownership, the shared source removes the old message and emits that signal before releasing the lease.

The same shared configuration supplies all renderers, so same-ID reuse requires neither a surface ID nor a retain count.

For each coordinated RMF view-model mapping, the configuration supplies an opaque presentation context containing the message ID and the returned lease's acquisition identity. Appearance and dismissal callbacks capture and return that context. The configuration validates it before confirming appearance, mutating RMF lifecycle state, or releasing ownership. A same-ID content refresh keeps the context and SwiftUI identity stable because it is the same ownership; releasing and later reacquiring the same message ID creates a new lease identity, so callbacks from the old physical view become no-ops and SwiftUI constructs a new card.

Coordinated dismissal validates the message/acquisition context before starting the asynchronous store operation. It adds no dismissal-in-progress marker and does not freeze ownership across the `await`; ordinary store refresh, invalidation, or replacement may proceed while it is suspended. On completion, the old callback performs direct ordered teardown only if its context is still current, and it always triggers the existing authoritative source reconciliation once. A stale completion cannot directly mutate or release a replacement ownership, while the resulting store state is still reconciled normally.

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

The next configuration refresh removes the card from the shared source, signals all models to rebuild, and then releases its lease. Before an explicit dismissal starts, its context must be current. Ownership is not frozen while the store call awaits. Completion performs direct ordered teardown only if the context is still current, and every validly started dismissal requests one authoritative source reconciliation. A stale completion does not directly mutate a newer lease; subsequent store state is reconciled normally. The current store API does not report persistence success. Modal evaluation is not triggered immediately; it remains a foreground operation.

### RMF replaced

The old ID is unpublished from every model snapshot and released before the new ID is considered. The new ID is a new acquisition and must pass the RMF incoming cooldown. A same-ID content refresh keeps the current ownership and appearance state while still notifying models when the shared content changed.

### Background and foreground

Backgrounding removes the coordinated RMF from `homeMessages`, emits the configuration signal, then releases and clears its ownership aggregate and last preparation policy. It records no new shown or cooldown history and does not clear history already confirmed on appearance. RMF admission remains disabled while the app is inactive, so a store notification cannot immediately reacquire the same card.

Foregrounding re-enables future explicit NTP preparation but does not itself select or publish RMF. A never-appeared owner wrote no history, so its still-scheduled message may reacquire at the next valid preparation. An appeared owner wrote the single RMF timestamp used by both directional checks: reconsidering the same ID is a fresh RMF acquisition subject to the 10-minute RMF-to-RMF cooldown, while a launch modal remains subject to the 24-hour RMF-to-modal cooldown. A denied preparation does not schedule a timer; an already-mounted NTP can therefore remain without RMF beyond ten minutes until another natural checkpoint. No same-ID resume exemption or automatic foreground retry is added. Ordinary NTP disappearance still does not release ownership.

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

The first valid returned-lease `markShown()` call records the RMF timestamp through the service-owned wrapper. RMF acquisition, denial, mapping, dismissal, background teardown, or lease release does not.

There is no cooldown timer. Reaching a boundary does not itself cause a retry.

## Reconsideration checkpoints

Blocked work is reconsidered only when an existing event causes evaluation:

- an explicit NTP source preparation or refresh;
- a coordinated `remoteMessagesDidChange` refresh while RMF admission is enabled;
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

Coordinated-mode regular `remoteMessageShown` volume is expected to decrease because reporting moves from eager/repeated mapping and mounts to once per actually appeared ownership. Rollout monitoring must treat that as an expected measurement discontinuity, not automatically as a regression; no replacement telemetry is added.

After 100% rollout and an agreed soak/rollback window, create a separately owned cleanup task to remove the legacy RMF source/accounting branches, duplicate legacy observer behavior, obsolete mode plumbing, and superseded tests. That cleanup is deliberately outside this implementation stack so the feature flag remains a usable rollback path during rollout.

## Debugging

Extend the existing Modal Prompt Coordination internal debug screen rather than adding a new screen. Its simplified Promo Queue section should expose:

- startup-latched mode and the relaunch requirement;
- current owner kind and identity;
- active RMF message ID and whether appearance was confirmed;
- last confirmed modal and RMF timestamps;
- derived next RMF and next modal eligibility boundaries.

Do not add modal-phase or last-denial plumbing. Mode, owner, RMF appearance confirmation, cooldown values, refresh, and resets are sufficient for rollout validation.

Provide an explicit refresh action. Keep the existing modal cooldown reset and add an explicit internal-only RMF cooldown reset for manual testing. The reset must go through the authoritative RMF history component and clear both its durable timestamp and any in-process value used for failure fallback. It must not release an active owner or dismiss a message. Do not add force-acquire controls that can manufacture impossible production ownership.

Diagnostics add no telemetry and must use side-effect-free reads except for explicit reset actions.

## Adding future promo entry points

### A new NTP implementation

Use the existing shared `HomePageConfiguration`/`NewTabPageMessagesModel` path. The complete imperative Promo Queue integration contract is one `prepareForNTP(openedAfterIdle:)` call per content activation, immediately before the activation-time eligibility resolution that can make the container visible. A conditional container also observes the ordinary configuration content-change publisher so it can reevaluate eligibility. Pure construction-time reads and signal sinks never prepare.

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
- After an appeared RMF backgrounds, the same scheduled ID is a fresh acquisition and is blocked by the 10-minute RMF-to-RMF cooldown; launch modals are independently blocked for 24 hours. Foreground does not republish, and no boundary timer exists, so an NTP may remain blank beyond ten minutes until another natural checkpoint. A never-appeared RMF has no such history and may reacquire at the next valid preparation.
- Fire mode can suppress the card while source ownership remains. No explicit constrained-landscape suppression exists today; landscape is a QA case, not a designed lease rule.
- Two physical copies of the same RMF can be mounted briefly during renderer handoff. The system guarantees cross-kind admission, not one physical RMF renderer.
- Candidate selection across shared refreshes is checkpoint-driven and not a fair queue.
- A dismissed modal may over-hold until lazy exact-root reconciliation.
- A blocked promo may remain hidden after its cooldown expires until another natural checkpoint.
- RMF release follows removal from the shared source, not proof that every exit-animation pixel is gone. No immediate modal retry is triggered from RMF release, which keeps the normal removal path safe without an exact-removal state machine.
- In coordinated mode, `.remoteMessageShown` runs once per admitted ownership after actual appearance. Its aggregate volume will likely be lower than legacy eager/repeated accounting. Unique-shown preserves the existing best-effort first-ever behavior; it is not made atomically exact across rapid reacquisitions. Legacy mapping/on-appear duplicates are intentionally not reproduced.
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

### Testability and access control

Test externally observable behavior through contracts used by production code. Here, “public behavior” means behavior observable at a real component or module boundary; it does not mean declarations must use Swift's `public` access level.

- Do not change `private` or `fileprivate` declarations to `internal`/`public`, add state getters or test hooks, expose retained ownership state, or expand a production protocol solely to make a test assertion possible.
- Prefer assertions on `homeMessages`, the configuration content publisher, lease grant/confirmation/release results, provider invocation or non-invocation, modal attachment, history writes, and existing event-reporting effects.
- Prefer test-target spies/fakes and injected dependencies that have a production purpose, such as the clock, storage, history, provider, gate, and lifecycle entry point. Do not build a mock that duplicates the production state machine.
- `@testable import` may exercise a small internal production abstraction through its real contract. It is not permission to access private state or to make that state less private.
- Do not expose the ownership teardown helper, preparation policy, actual selected filter, retained ownership aggregate or callback context, observer bookkeeping, arbiter owner records, or identity-generator state. Drive preparation, store changes, appearance, dismissal, and background events, then assert their observable effects.
- The narrow justified direct-test cases are production abstractions whose invariants are otherwise difficult to cover: the arbiter's token contract, cooldown/history policy boundaries, and service-owned lease wrapper. Verify exact-root retention through the manager's production reconciliation/checker contract, not a private helper. The opaque acquisition identity exists because production callback validation and SwiftUI diffing require it; the diagnostic snapshot exists because the internal debug UI consumes it. None needs `public` visibility.
- If a case cannot be verified through a production contract, prefer focused manual or static verification. Tests alone never justify an access-level change. If a genuine production caller requires a wider contract, document that caller and rationale in PR-description metadata kept on the master documentation branch; tests may then use that production contract.

Use focused unit and integration coverage for externally observable behavior:

- atomic modal/RMF exclusion and identity-safe release;
- provider chains not queried when RMF owns the slot;
- RMF not published or accounted when a modal owns the slot;
- same-ID reuse and different-ID replacement;
- release and same-ID reacquisition rejecting callbacks from the earlier acquisition;
- exactly one confirmed appearance per RMF ownership;
- regular shown once per ownership while unique-shown retains best-effort first-ever-message behavior;
- a compact startup table proves normal-launch initial NTP preparation works, restored-website launch remains unprepared, and true background launch cannot acquire or record a preparation policy; foreground plus an ownerless store notification still cannot select until a new enabled preparation occurs;
- unsupported content cannot acquire a lease;
- one configuration-owned store refresh updates all model and direct-array consumers;
- an after-idle request that falls back to no-trigger pins that actual filter, and later competing requests do not replace the valid owner;
- background teardown unpublishes before release and disarms reacquisition until explicit preparation, with appeared and never-appeared same-ID outcomes covered together;
- a store update during suspended dismissal may replace ownership; the stale completion cannot directly mutate it and requests one authoritative reconciliation;
- returned lease/acquisition identity is stable within ownership and changes on same-ID reacquisition;
- the four cooldown directions and exact boundaries;
- no history update for denial or never-appeared content, and a first storage read failure with no cached value behaves as no known history;
- modal lease retention through scheduling, nested presentation, and exact-root detachment;
- pending/active modal suppression and actual-presentation session history;
- message dismissal, expiry, replacement, `afterIdle`, and onboarding behavior;
- startup-latched legacy/coordinated behavior; and
- weak-token recovery.

Fold these cases into the smallest existing behavior groups. Do not recreate broad suites for renderer order, host exposure propagation, handoff/drain identities, exact SwiftUI removal terminals, one-physical-card enforcement, every notification ordering, or every background/cooldown permutation. Do not build a new UIKit harness for each host merely to prove a one-line activation call.

Manual/static validation must exercise the standard NTP plus all three conditional-host families: legacy/iPad `MainViewController` suggestion tray, `OmniBarEditingStateViewController`/`SuggestionTrayManager`, and unified input. Also cover Fire mode, landscape as behavior discovery, appeared versus never-appeared background release/reacquisition, and delayed-retry behavior. Add a cheap host-level automated assertion only where an existing harness already makes it natural.
