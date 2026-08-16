# Promo Queue: simplified iOS implementation plan

## Objective

Implement one app-scoped, main-actor promo slot that prevents launch-promo modal sheets and NTP RMF cards from being admitted together. Admit a modal before provider evaluation. Admit RMF at the shared `HomePageConfiguration` before publication, retain it by source/message lifecycle, and unpublish then release it on app background. Add no renderer visibility, coverage, handoff, or lease callbacks. This plan contains the complete architecture contract, requirements, phases, verification, and handoff instructions needed to execute the stack.

The local implementation handoff is complete when:

1. the coordinated behavior is implemented and verified;
2. internal diagnostics are available;
3. the three local branch diffs are clean, focused, and ready for human review; and
4. rollout requirements and evidence are recorded for the external owner.

The project success criterion is broader: humans must later review and merge the stack, ship it, and remotely roll `.promoPresentationCoordination` out to 100% of supported iOS users. This plan records that follow-through but does not authorize the implementation agent to push, open PRs, merge, or edit the external configuration repository.

## Current execution checkpoint — 2026-08-15

Phase 0 and Phase 1 have been implemented and verified locally on `bartosz/promo-q-simp-2`; Phase 2 implementation has not started. Before Phase 2 work begins on `bartosz/promo-q-simp-3`, complete the small Phase 1 alignment in section 1.8 and reconcile the local stack so the Phase 2 branch contains it. Phase 0 needs no follow-up change.

This plan remains the full standalone execution contract. Completed sections document the required final state and should be validated, not reimplemented wholesale.

## Review validation update — 2026-08-15

This revision applies the validated review findings: cold-start RMF deferral, explicit normal/background launch initialization, one configuration-owned selection observer and source signal, activation-only coverage for every conditional-host family, preparation-policy/selected-filter pinning, one RMF ownership aggregate, complete main-actor isolation, identity-safe asynchronous dismissal, explicit appearance-to-history wiring, pre-admission renderability, per-acquisition SwiftUI identity, accurate best-effort persistence, background release and cooldown consequences, one modal identity, one-way modal lease transfer, minimal diagnostics, post-rollout cleanup, current repository state, and Xcode project membership. The automated matrix is intentionally focused on architectural seams rather than exhaustive lifecycle permutations.

## Product decisions confirmed — 2026-08-15

- **Modal scope:** “modal sheets” means launch-promo providers routed through `PromoCoordinationService`, not every UIKit sheet. The stack deliberately does not intercept arbitrary presentations; any future expansion requires a separately reviewed architecture change.
- **NTP integration seam:** `prepareForNTP(openedAfterIdle:)` is the only new Promo Queue-specific method called by an NTP container, once per content activation before the activation-time eligibility resolution that can make its content visible. A conditional container may also observe the shared content publisher as normal data-source wiring. It must not acquire/release leases or report visibility, coverage, handoff, or lifecycle state.
- **Mixed triggers:** keep the first admitted message and actual selected trigger filter pinned while that ownership remains valid. An after-idle request may fall back to a no-trigger message; that owner is pinned as no-trigger. Later renderer loads do not replace it.
- **Persistence semantics:** retain best-effort dismissal and unique-shown behavior. Do not widen the store API, add an in-process/cross-process unique reservation, or add telemetry.

## End-state architecture contract

The implementation has one startup-latched `.legacy` or `.coordinated` mode and one app-scoped, main-actor owner: none, one typed modal ownership, or an RMF message acquisition. The complete shared NTP configuration/protocol/model, selection, publication, callbacks, and source-signal path is `@MainActor`. The seven coordinated launch-promo provider categories are the new address-bar picker, default-browser prompt, win-back offer, subscription promo, existing-user subscription promo, What's New, and cookie-popup-protection opt-in. Arbitrary UIKit sheets are not intercepted.

`PromoCoordinationService` is the thin typed facade around the identity-safe lease arbiter, directional cooldown policy, and existing modal manager. Modal admission occurs before provider evaluation and retains the exact selected root through scheduling and attachment. RMF admission occurs once in the shared `HomePageConfiguration` before the candidate enters `homeMessages`; all current NTP renderers consume that same gated source.

The complete imperative container contract is one `prepareForNTP(openedAfterIdle:)` call per content activation before the activation-time eligibility resolution that can make content visible. Conditional containers also observe the normal configuration-scoped content publisher so they can reevaluate after shared data changes. Pure construction-time reads, `canShow`, `hasMessages`, computed getters, and signal sinks never prepare. Containers never acquire, confirm, or release leases and never report visibility, coverage, handoff, or lifecycle. Existing card appearance, dismissal, and action callbacks continue through `NewTabPageMessagesModel` and are handled centrally.

RMF ownership is one optional aggregate containing the admitted message/content, actual selected trigger filter, service-owned lease, and opaque callback context. The last preparation/fallback policy is separate. Same-owner refreshes reuse the aggregate and acquisition identity; invalidation tears down before fresh selection. Appearance confirms queue history once per acquisition. All ownership endings unpublish the RMF, synchronously signal consumers, then release. Background performs that sequence, clears preparation state, and disarms reacquisition until a later explicit preparation; ordinary NTP disappearance does not release.

Cooldowns are based on confirmed appearances: launch modal → RMF 10 minutes, RMF → RMF 10 minutes, RMF → launch modal 24 hours, while launch modal → launch modal remains with the existing remotely configured modal policy. Work blocked by ownership or cooldown remains scheduled and retries only at natural checkpoints. There are no timers, waiters, renderer registries, retain counts, or release broadcasts.

## Starting point

- Phase 0 and Phase 1 base branch: `bartosz/promo-q-simp-2`.
- Phase 2 branch: `bartosz/promo-q-simp-3`.
- At the Phase 2 planning checkpoint on 2026-08-15, the Phase 1 branch ended at `fbd1dd2ef5`; Phase 0/1 production implementation is in `ab23ea75d5`, and `bartosz/promo-q-simp-3` was created from that head before the documentation update. Phase 2 production work had not started. Treat this as a historical snapshot and rerun read-only status/divergence checks before editing because documentation or another agent may have advanced either branch.
- PR #6087 is already merged as `7fdd4719a1345c8805d3bbb9639c618f7dbb562d`.
- Preserve every pre-existing tracked or untracked change; do not delete or rewrite unrelated documentation or code.
- Only PR #6087 is an implementation baseline. Do not merge or wholesale cherry-pick the old `bartosz/promo-q-2` or `bartosz/promo-q-3` implementations. Small pieces such as cooldown constants or storage semantics may be ported only after confirming that they implement Phase 1.3's exact durations, boundary, key, and failure-fallback requirements without bringing over discarded surface or debug machinery.

Before editing, re-read the repository's `AGENTS.md` and only the relevant rules it permits. Run a read-only status/divergence preflight and inspect any project memory required by the active agent instructions. Present the exact current branch and divergence and obtain any permission required by repository instructions before rebasing, merging, creating branches, running tests, or performing another git write. Preserve all completed Phase 0/1 commits and concurrent documentation changes whichever stack-reconciliation strategy the user chooses.

All implementation changes must remain local on the appropriate stack branch. Do **not** push branches, open pull requests, retarget pull requests, or make changes in external repositories. Commits and local branch creation also require the permission mandated by repository instructions. Preserve existing pixels rather than defining new ones and use injected `ThrowingKeyValueStoring` for the RMF cooldown timestamp.

## Proposed PR-sized local stack

Use three stacked, locally reviewable units. They are sized as eventual pull requests, but this plan authorizes no push or PR action. This keeps the cleanup reviewable, gives the end-to-end behavior its own review, and leaves the internal debug change isolated as requested.

| Review unit | Local branch | Local parent | Purpose |
| --- | --- | --- | --- |
| PR 1 | `bartosz/promo-q-simp-2` | `main` | Phase zero cleanup plus the minimal app-scoped gate, cooldown policy, and modal foundation |
| PR 2 | `bartosz/promo-q-simp-3` | `bartosz/promo-q-simp-2` | Shared `HomePageConfiguration` RMF integration and end-to-end behavior |
| PR 3 | `bartosz/promo-q-simp-4` | `bartosz/promo-q-simp-3` | Existing debug-screen extension, manual-test support, and rollout readiness |

`bartosz/promo-q-simp-3` already exists locally. Validate that it descends from the reviewed/aligned head of `bartosz/promo-q-simp-2`; do not create, recreate, reset, or overwrite it. Stop and report if its graph contains unexpected production work. After permission for git writes, create local `bartosz/promo-q-simp-4` only from the reviewed head of `bartosz/promo-q-simp-3`. Keep each branch diff limited to its unit and hand off the local stack for human review. Do not push or open PRs.

Because the Phase 1 alignment was identified after `bartosz/promo-q-simp-3` was first created, apply it to local `bartosz/promo-q-simp-2` before Phase 2. Then, with the required git-write permission and a clean worktree, rebase the existing documentation-only `bartosz/promo-q-simp-3` onto that reviewed Phase 1 head while preserving its documentation commit(s). Do not recreate or reset the branch. Do not start Phase 2 on a branch that lacks section 1.8. If Phase 2 work has already appeared by the time of execution, stop and report the exact graph instead of rewriting concurrent commits.

At the end of each unit, the implementing agent must suggest a final future-PR title and produce a ready-to-paste draft description based on the actual local diff. Each description must include:

- the problem and user-visible outcome;
- the main architectural/code changes and deliberate deletions;
- accepted limitations and explicit non-goals relevant to that unit;
- focused automated, build, and manual evidence actually completed;
- feature-flag/rollout risk where applicable;
- the stack dependency and what follows next, if anything; and
- any access-level change, with the production caller and rationale that required it. Tests alone are not a rationale, and the expected default is “none.”

These title/description drafts are local handoff metadata only. Producing them does not authorize `git push`, `gh`, PR creation, retargeting, merging, or any external mutation. If the implemented scope differs from the title suggested below, update the suggestion to describe the actual diff.

If PR 2 proves smaller than expected, do not fold it into PR 1 merely to reduce the PR count: the distinction between coordination primitives and the behavior-changing RMF integration is useful. The three-unit topology remains authoritative. Split PR 2 only after explicit approval when measured churn and reviewability justify an independently correct, tested follow-up unit; size alone and arbitrary file count are insufficient. Before creating any follow-up branch, revise this plan's stack table, titles/descriptions, later PR numbering, final-verification wording, rollout handoff, and definitions of done to match the approved topology.

## Invariants to preserve throughout the stack

- The complete coordinated `HomePageMessagesConfiguration`/`HomePageConfiguration`/`NewTabPageMessagesModel` path, including selection, ownership, publication, callbacks, and source-signal delivery, is main-actor isolated. Global store notifications enter the main actor before touching source state.
- All coordinated admission and lease mutation is main-actor, synchronous, and non-yielding.
- Modal admission happens before provider evaluation.
- RMF admission happens before a remote message enters `homeMessages`.
- One owner exists at most: modal or RMF.
- A blocked RMF remains scheduled and records no shown, dismissed, action, or cooldown state.
- A never-appeared admitted RMF records no shown or cooldown state.
- A stale or duplicate ownership context cannot release, dismiss, or confirm a replacement owner, including when the replacement has the same message ID.
- Existing launch-source, presented-controller, provider order, onboarding, modal-to-modal cooldown, and provider accounting behavior remains with its current owner.
- Existing pending/active modal suppression and actual-presentation session history remain observable through `RecentModalPromptStatusProviding`.
- Existing RMF action/dismissal event definitions and metric checks remain unchanged; no new Promo Queue pixel is added. In coordinated mode, regular shown intentionally fires once per admitted ownership after actual appearance instead of preserving today's eager/repeated calls. Unique-shown retains the existing best-effort first-ever guard; exact-once behavior across rapid reacquisitions is not added.
- Legacy behavior remains available when `.promoPresentationCoordination` is disabled.
- No NTP renderer or covering overlay reports active/renderable/visible/covered state.
- For the shared NTP RMF source, one `prepareForNTP` call per content activation, before activation-time eligibility resolution can make content visible, is the complete imperative Promo Queue integration. No container calls the gate, `markShown`, or lease release.
- The first admitted message and actual selected trigger filter remain pinned until the ownership becomes invalid or the app backgrounds. The last preparation/fallback policy remains separate.
- App backgrounding unpublishes the coordinated RMF and releases ownership through one app-scoped lifecycle path. Ordinary view disappearance does not release it.
- No timers, wait queues, renderer registries, retain counts, handoff state, or exact RMF removal state are introduced.
- Every added or removed Swift source, test, and mock has matching references and correct target membership in `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj`. Add shared mocks only to targets that consume them; prefer repurposing an existing file when its responsibility remains accurate.

## Accepted simplifications

- Only the seven launch-promo provider categories routed through `PromoCoordinationService` are coordinated. Arbitrary UIKit presentations may still cover an RMF.
- An active RMF may hold the slot while the user is off the NTP until message invalidation or background. Background releases live ownership but never clears already-confirmed RMF cooldown history.
- After an appeared RMF backgrounds, its same scheduled ID is a fresh acquisition subject to the 10-minute RMF-to-RMF cooldown, while launch modals remain subject to the 24-hour RMF-to-modal cooldown. Foreground does not republish it, and no timer retries at the boundary; an NTP may remain blank until another checkpoint. A never-appeared RMF may reacquire at the next valid preparation.
- Two physical copies of the same RMF may be mounted briefly. The guarantee is cross-kind admission, not selection of one physical renderer or proof that every exit-animation pixel is gone.
- Fire mode can suppress a source-owned card. Landscape is behavior-discovery QA, not a special lease rule.
- Progress is checkpoint-driven, with no fairness guarantee, boundary timer, waiter, release broadcast, or immediate modal retry after RMF removal.
- A dismissed modal may retain its lease until a later checkpoint observes its exact root detached.
- Dismissal persistence and unique-shown accounting keep their existing best-effort semantics.
- Feature mode is startup-latched and requires relaunch after a flag change.
- No new overlap, denial, fairness, or retry telemetry is added.
- Coordinated regular-shown volume is expected to decrease because accounting becomes once per actual appeared ownership; rollout treats this as an expected measurement discontinuity rather than automatically as a regression.

## Testing policy — production behavior first

“Public behavior” in this plan means observable behavior through a contract used by production code; it does not require Swift `public` visibility.

- Do not widen `private`/`fileprivate` access, add state getters or test hooks, expose retained ownership state, or add a production protocol requirement solely for tests.
- Prefer driving `PromoGating`, the returned RMF lease, `HomePageMessagesConfiguration`, `PromoCoordinationService.presentModalPromptIfNeeded`, store notifications, and app-lifecycle entry points. Assert `homeMessages`, synchronous content signals, provider calls, history writes, lease outcomes, attachment, and existing reporting effects.
- Prefer test-target spies/fakes and real dependency-injection seams: clock, `ThrowingKeyValueStoring`, RMF history, provider, gate, and app-lifecycle route. Post the real store notification or drive the production refresh entry point; do not introduce a notification protocol merely for tests. A mock must not reimplement the production state machine.
- `@testable import` may exercise a small internal production primitive through its real contract. It is not permission to expose private state. Direct internal tests are justified for the arbiter token contract, cooldown/history boundary policy, and service-owned lease wrapper. Verify exact-root behavior through the manager's production reconciliation/checker contract, not a private helper.
- The acquisition identity is part of the production callback/SwiftUI contract. The read-only diagnostic snapshot is part of the internal debug UI contract. Neither exists merely to make tests convenient, and neither needs Swift `public` access.
- Never expose the private ownership teardown helper, `lastPreparationPolicy`, the actual selected filter, retained ownership aggregate/context, observer bookkeeping, arbiter owner records, or identity-generator state. Drive the corresponding event and assert the observable source/service effect.
- If a case has no production-observable seam, prefer focused manual or static verification. Tests alone never justify an access-level change. If a genuine production caller requires a wider contract, keep it as narrow as possible and document that caller and rationale in the draft future-PR description; tests may then use the same contract.

---

# PR 1 — `bartosz/promo-q-simp-2`

## Goal

Replace the broad, partially merged foundation with the smallest reusable gate and cooldown primitives. Leave the branch compiling and behaviorally safe with the feature disabled. Do not integrate RMF publication yet; that belongs to the next PR.

Suggested PR title: **iOS Promo Queue: Simplify coordination foundation**

Draft-description focus: explain removal of live feature transitions and per-surface/retry machinery from PR #6087; describe the startup-latched arbiter, directional cooldown/history, and retained modal correctness; list focused primitive/service evidence; state that the production flag remains off and end-to-end RMF source integration follows in `bartosz/promo-q-simp-3`.

## Phase 0 — remove or collapse merged machinery

Phase zero is part of this PR, not a cleanup-only PR. Delete obsolete concepts before adding their replacements so old APIs do not shape the new design.

### 0.1 Remove live feature-transition state

Delete `iOS/DuckDuckGo/ModalPromptCoordination/PromoQueueFeatureState.swift` and remove the corresponding project-file entries.

In `iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift`, remove:

- the Combine feature-update subscription;
- `promoQueueFeatureStateCancellable`;
- pending target-state and transition-barrier state;
- `transitionPromoQueueFeature` and transition-only admission routes;
- lease invalidation on live flag changes; and
- tests and logging that exist only for live enable/disable transitions.

Replace the mutable state with an immutable `PromoCoordinationMode` selected by the factory at graph construction. A local debug override must state that relaunch is required.

In `ModalPromptCoordinationManager`, remove:

- `promoQueueWillTransition` / `promoQueueDidTransition`;
- legacy-root re-adoption used only when enabling live;
- transition-only attempt cleanup; and
- transition-only tests.

Keep only modal state needed during one process mode.

### 0.2 Remove per-surface RMF coordination APIs

Replace the contents and purpose of `iOS/DuckDuckGo/ModalPromptCoordination/NewTabPagePromoCoordination.swift` with a narrow source-level gate contract, or rename the file if a clearer name keeps project organization understandable.

Delete these concepts:

- `VisiblePromoIdentity.surfaceID`;
- `NewTabPagePromoRetrying`;
- `NewTabPagePromoRetryRegistration`;
- per-surface admission results;
- surface-slot occupancy;
- weak retry-registration arrays;
- registration ordering and retry passes; and
- mocks dedicated to those APIs.

Do not add replacement renderer registration, a list of listeners, or a generic overlay protocol.

### 0.3 Remove unused coordinator plumbing from NTP renderers

PR #6087 threaded `NewTabPagePromoCoordinating` through multiple controllers even though the merged `NewTabPageMessagesModel` does not yet use it. Remove that route rather than repurposing each host.

Inspect and update all affected construction paths, including:

- `iOS/DuckDuckGo/MainViewController.swift`;
- `iOS/DuckDuckGo/UICoordination/MainCoordinator.swift`;
- `iOS/DuckDuckGo/NewTabPageViewController.swift`;
- `iOS/DuckDuckGo/SuggestionTrayViewController.swift`;
- `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputContentContainerViewController.swift`;
- `iOS/DuckDuckGo/NewTabPageMessagesModel.swift`;
- `iOS/DuckDuckGo/NewTabPageView.swift` previews; and
- corresponding mocks and initializer tests under `iOS/SharedTestUtils` and `iOS/DuckDuckGoTests`.

Do not remove the already-shared `HomePageMessagesConfiguration` dependency. It is the integration seam used in PR 2.

### 0.4 Prune tests that encode the discarded architecture

Delete or rewrite tests whose only contract is:

- several RMF surface slots owning leases concurrently;
- surface IDs or occupying identities;
- retry registration and registration replacement;
- feature-transition barriers and re-entrant transition behavior;
- live enabling/disabling and root re-adoption; or
- broad real-UIKit transition behavior used only by live mode.

Keep focused existing coverage for provider order, provider accounting, exact-root attachment, nested modal roots, modal lease retention, idempotent release, and stale-token safety where those behaviors remain.

Do not preserve a large test merely because it was merged. Preserve a test only when it protects a final-design invariant.

## Phase 1 — implement the minimal coordination foundation

### 1.1 Add startup-latched mode

Add `PromoCoordinationMode` near the coordination primitives:

```swift
enum PromoCoordinationMode: Equatable {
    case legacy
    case coordinated
}
```

In `PromoCoordinationFactory`, read `.promoPresentationCoordination` once and inject the resolved mode into the service and any dependency that needs a feature-off branch.

Retain these existing flag definitions:

- `FeatureFlag.promoPresentationCoordination`;
- `iOSPromoQueueSubfeature.iOSPromoPresentationCoordination`; and
- `PrivacyFeature.promoQueue` / `PromoQueueSubfeature.featureEnabled` where used by other platforms or shared code.

Do not subscribe to `FeatureFlagger.updatesPublisher` for this feature.

### 1.2 Rewrite `PromoQueueLeaseArbiter`

Keep the file and the idea, but collapse its state to one owner:

```text
none
modal(one typed ownership identity)
remoteMessage(message ID + acquisition identity + appearance-confirmed bit)
```

Implement typed modal and RMF leases. The modal lease exposes one opaque typed ownership identity, used for arbiter matching, lease release, manager phase transitions, stale scheduled-callback validation, and diagnostics; do not add a second modal attempt/acquisition identity. RMF keeps its separate acquisition identity because it is required by production callbacks and SwiftUI diffing. Both leases must:

- release idempotently;
- validate their single ownership/acquisition identity before changing arbiter state;
- become inert after release;
- reject stale release after a replacement acquisition; and
- allow the arbiter to recover a record whose weak token deallocated.

The raw RMF arbiter token exposes a main-actor `confirmAppearance()` operation that returns `true` only for the first valid confirmation of its current acquisition. It must return `false` after release, for a stale record, and on subsequent calls. It does not persist history or fire events.

Expose a small read-only snapshot because the existing internal debug screen consumes it. Tests may validate that production diagnostic contract, but must not drive its shape. Do not include renderer, registration, handoff, drain, presentation, or removal identities.

Remove `invalidateAllLeases`; startup-latched mode does not need it.

### 1.3 Add the directional cooldown policy and RMF history store

Create a minimal file under `iOS/DuckDuckGo/ModalPromptCoordination/Cooldown/` implementing only the durations, storage semantics, exact-boundary behavior, and failure fallback specified below. Do not port unrelated debug or surface machinery.

Implement:

- incoming RMF after modal: 10 minutes;
- incoming RMF after RMF: 10 minutes;
- incoming modal after RMF: 24 hours; and
- modal after modal: leave to the existing remotely configured `PromptCooldownManager`.

Use the existing confirmed-modal timestamp source and add one injected `ThrowingKeyValueStoring`-backed last-confirmed-RMF timestamp. Keep the storage key stable if porting the old implementation:

`com.duckduckgo.promo-queue.last-confirmed-remote-message-timestamp`

Use an injected clock. Define exact-boundary behavior (`now == nextEligibility` is eligible) and future-timestamp behavior. Keep production storage reads/writes failure-tolerant and test their in-process fallback semantics.

The history component exposes the narrow record/read/reset behavior needed by the service and later diagnostics. The arbiter does not call it. Acquisition, denial, raw confirmation, and release alone do not record RMF history.

Do not add a timer or persist the current owner.

### 1.4 Simplify `PromoCoordinationService`

Keep `PromoCoordinationService` as the single app-scoped facade.

Its modal path must:

1. retain existing launch-source and unrelated-presented-controller gates;
2. use the legacy manager path when mode is `.legacy`;
3. lazily reconcile a previously attached exact root in coordinated mode;
4. acquire a modal lease before provider evaluation;
5. evaluate RMF-to-modal cooldown before provider evaluation;
6. release directly and immediately when cross-promo cooldown denies admission; and
7. otherwise transfer lease ownership to the manager, which releases it if modal-to-modal cooldown/provider evaluation selects nothing or retains it when a modal is committed.

Its source-level RMF protocol must provide only what PR 2 needs:

- immutable mode;
- synchronous acquisition by message ID; and
- read-only diagnostic state if that is best exposed from the service.

Before RMF acquisition, reconcile a detached exact modal root. Then acquire the slot and evaluate the incoming RMF cooldown. If cooldown evaluation denies the request after acquisition, release that temporary acquisition synchronously before returning no lease. A denial must leave the arbiter idle unless another valid owner already existed.

On admission, return a small service-owned RMF lease wrapper that strongly retains the raw arbiter token and exposes one opaque, hashable acquisition identity. Its no-argument `markShown() -> Bool` calls `confirmAppearance()` and records RMF history exactly when that first confirmation succeeds. It stays nonthrowing and returns `true` for the first valid appearance even when durable persistence fails; the history component keeps the in-process value authoritative and logs/absorbs the storage error. Its release forwards to the raw token. This wrapper is the only connection between appearance confirmation and cooldown persistence; `HomePageConfiguration` later retains only the wrapper.

Do not add waiters, retry arrays, a release publisher, or surface-specific APIs. A caller will retry through natural configuration checkpoints.

### 1.5 Reduce `ModalPromptCoordinationManager` to retained modal correctness

Keep the existing provider-selection and legacy behavior. In coordinated mode, retain only the state needed to carry one lease through:

```text
idle -> evaluating -> committed -> presentationActive -> idle
```

Requirements:

- no provider query before the service has admitted the modal;
- when modal-to-modal cooldown or provider evaluation selects nothing, the manager releases its transferred lease synchronously and records no presentation history;
- the selected attempt retains the same identity through the presentation delay;
- a stale scheduled callback cannot mutate a replacement attempt;
- the exact selected root remains authoritative even if it presents a child; and
- reconciliation releases only after that exact root is detached or deallocated.

Preserve `didPresentModalPromptThisSession` semantics: pending or active attempts suppress dependent session promos; a completed presentation remains session history; and an evaluation that selects nothing returns to idle without erasing earlier presentation history. Do not add a pre-presentation cancellation mechanism solely for Promo Queue.

Keep `ModalPromptRootAttachmentChecker.swift` if it remains the smallest way to express exact-root reconciliation.

Remove the manager's direct arbiter dependency if it only existed for live feature re-adoption. The service acquires and transfers the token through a `Void`-returning manager operation; from that call onward the manager alone releases or retains the lease and logs the outcome. Delete `ModalPromptLeaseDisposition`. The service must not branch or release a second time after transfer.

Do not add dismissal callbacks to every modal provider in this iteration. Lazy reconciliation is the accepted simpler behavior.

### 1.6 Simplify composition

Update:

- `PromoCoordinationFactory.Dependency`;
- `iOS/DuckDuckGo/AppLifecycle/AppStates/Launching.swift`; and
- service/manager mocks.

Construct exactly one mode, arbiter, directional cooldown policy, RMF history component, manager, and service for the app graph. Retain the existing modal `PromptCooldownKeyValueFilesStore`/`PromptCooldownManager` graph separately; the directional policy reads its confirmed modal history and the new RMF history. Avoid duplicate policy/history instances in debug code or NTP previews.

Update `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` as part of the same change: remove build-phase/group references for deleted Swift files and add new source/test/mock files only to the targets that compile them.

### 1.7 Focused PR 1 tests

Exercise small internal primitives only through their production token/policy contracts and assert returned behavior or effects, never private arbiter/history fields. Do not widen access for direct state inspection.

Keep this suite compact and table-driven where practical:

- Arbiter: cover cross-kind mutual exclusion, identity-safe/idempotent release, weak-token recovery, and first valid `confirmAppearance()` in one small parameterized group.
- Cooldown: table-test the three new directional rules at just-before/equality/after boundaries. Keep storage failure compact: prove cached-read fallback, failed-write in-process authority, and a fresh first-read failure with no cache behaving as no known history.
- Service/manager: prove providers are not queried when the slot or RMF-to-modal cooldown blocks them; prove no-selection releases; and preserve one exact-root/nested-child retention test and the legacy route.
- Service wrapper: with a real arbiter and spying history component, two `markShown()` calls record once, while stale or post-release confirmation records nothing; a durable-write failure still returns `true` once and leaves the in-process timestamp authoritative.

Delete transition/surface fixtures rather than adapting them into another abstraction layer. Add only a regression case when it protects behavior changed by this unit.

### 1.8 Align the completed Phase 1 foundation before Phase 2

Phase 0 needs no patch. Apply these three narrow Phase 1 changes to `bartosz/promo-q-simp-2` before Phase 2 begins:

1. In `PromoQueueLeaseArbiter.swift`, replace the modal attempt/acquisition identity pair with one opaque typed modal ownership identity. Use it consistently in the modal lease, weak owner record, identity-checked release, manager phases, stale scheduled-callback validation, and diagnostic snapshot. Keep the RMF acquisition identity unchanged. Do not expose the UUID or widen access for tests.
2. In `ModalPromptCoordinationManager.swift`, make the transferred-lease presentation operation return `Void` and delete `ModalPromptLeaseDisposition`. The manager releases synchronously when another attempt is active, cooldown blocks, or no provider is selected; otherwise it retains the lease. In `PromoCoordinationService`, replace the disposition switch with one direct call and never release after transfer. Convert every call site to a direct call, removing disposition assignments and redundant `_ =` discards. Retain existing manager decision logs without adding replacement logging state. Update mocks and tests to assert observable ownership, provider, phase, and presentation behavior rather than a reporting enum.
3. In `PromoQueueCooldownPolicyTests.swift`, add one focused public-contract case: a fresh history whose first storage read fails returns no last confirmed RMF appearance. Reuse the existing fixture; do not expose cache state or add reset-failure permutations.

Expected touched files are the arbiter, modal manager, promo service, their existing mocks/unit tests, `iOS/IntegrationTests/ModalPromptCoordination/ModalPromptCoordinationManagerIntegrationTests.swift`, and the cooldown policy tests. No project-file change should be necessary because this alignment adds or removes no files.

Run the existing arbiter, modal-manager Promo Queue, real-UIKit modal, promo-service Promo Queue, and cooldown-policy suites through `iOS Unit Tests`, plus `ModalPromptCoordinationManagerIntegrationTests` through `iOS Integration Tests`; then run the relevant iOS build and `git diff --check`, after obtaining required test/git permission. Static completion checks:

- no `PromoQueueModalAttemptIdentity` remains;
- no `ModalPromptLeaseDisposition` remains;
- no coordinated transferred-lease call assigns or discards a return value, including with `_ =`;
- the transferred manager operation returns `Void`;
- modal ownership is still identity-safe through evaluation, scheduling, presentation, and release; and
- no access level was widened for testing.

## PR 1 completion criteria

- No live feature-state or per-surface retry types remain.
- No NTP host accepts a promo coordinator solely for this feature.
- The app graph contains one startup-latched gate.
- The arbiter has one owner, not a dictionary of surface slots.
- Modal ownership uses one typed identity and manager transfer returns `Void`; no disposition-reporting API remains.
- Directional cooldown policy is independently tested.
- Storage fallback includes the no-cache first-read failure without exposing history internals.
- Modal-first correctness remains behind the disabled-by-default flag.
- Focused affected tests and an iOS build pass after obtaining permission to run them.
- Local handoff notes include the final suggested future-PR title and ready-to-paste description, state that end-to-end RMF gating follows on `bartosz/promo-q-simp-3`, and state that the production flag remains off.

---

# PR 2 — `bartosz/promo-q-simp-3`

## Branch point and goal

Use the already-existing local `bartosz/promo-q-simp-3` only after the Phase 1 alignment has landed on `bartosz/promo-q-simp-2` and the child branch has been safely reconciled onto that reviewed head. Validate ancestry; do not create, recreate, reset, or overwrite the branch. Stop and report unexpected production work. Keep its diff relative to `bartosz/promo-q-simp-2`; do not push or open a PR.

Goal: integrate RMF once at the shared `HomePageConfiguration` boundary and deliver the actual no-overlap behavior for all existing NTP renderers.

Suggested PR title: **iOS Promo Queue: Gate NTP RMF at the shared message source**

Draft-description focus: explain shared-source admission for the standard NTP and all conditional-host families, launch-state initialization, centralized store refresh, actual-filter pinning, appearance/dismissal identity, and ordered background release; call out accepted over-hold, checkpoint retry, appeared-card background cooldown/blank behavior, best-effort persistence, expected lower regular-shown volume, and no new telemetry; include focused and manual evidence; state the dependency on PR 1 and that debug-only diagnostics follow in PR 3.

### Expected PR 2 size

Plan for approximately **1,700–1,900 changed lines** (`insertions + deletions`) relative to `bartosz/promo-q-simp-2`. The practical likely range is **1,400–2,150**, with a wider risk tail near 2,400; at planning time there is roughly a 40% chance of exceeding 2,000. This is an estimate, not a line-count target. The Phase 1 gate/wrapper exists, but the alignment patch and the exact amount of host/test scaffolding still create uncertainty.

Expected contributors are:

- production source integration: roughly 540–830 lines of churn;
- tests, test support, and project wiring: roughly 820–1,300 lines of churn; and
- a central case near 1,750 total changed lines.

Most risk is in focused `HomePageConfiguration` test scaffolding, not the three conditional-host-family integrations. Keep the unit intact initially, as requested. Do not trim behavior-critical tests merely to meet 2,000 lines, and do not add host-by-host UIKit harnesses or lifecycle permutations to inflate it.

If the measured branch diff materially exceeds 2,000 **and** conditional-host integration is independently reviewable, pause and propose—do not automatically perform—this logical split:

1. shared ownership, standard-NTP path, source publisher, renderability/identity, appearance/dismissal/background handling, and their tests; then
2. conditional-host adoption for the legacy/iPad `MainViewController` suggestion tray, `OmniBarEditingStateViewController`/`SuggestionTrayManager`, and unified input, with one focused consumer-convergence test.

Keep production and its tests together; never split by arbitrary file count. The conditional-host follow-up is expected to be only about 200–400 changed lines, so retaining one PR is preferable unless the actual diff and reviewability justify the extra branch. If approved, the tentative sequence is core `bartosz/promo-q-simp-3`, conditional-host adoption `bartosz/promo-q-simp-4`, and debug `bartosz/promo-q-simp-5`. Revise every affected section and add an actual-diff title/description for all four units before creating either follow-up branch. Until then, the three-unit sequence is the only instruction to execute.

## Phase 2 — shared RMF integration

### 2.1 Inject the gate into the shared configuration

`HomePageConfiguration` is constructed once in `MainCoordinator` and shared by every NTP render path. Add the narrow `PromoGating` dependency there, not to each renderer.

Update the production initializer and test initializers with an inert/legacy default only if a default does not hide required production injection. Prefer explicit production injection and a small mock in tests.

Keep the existing `isStillOnboarding` closure. It is the correct RMF eligibility signal and is not interchangeable with a generic `hasSeenOnboarding` property.

Mark the complete shared path `@MainActor`: `HomePageMessagesConfiguration`, `HomePageConfiguration`, `NewTabPageMessagesModel`, coordinated selection, ownership, publication, callbacks, and configuration-signal delivery. Explicitly marshal global store notifications onto the main actor before reading or mutating source state. Do not use partial method isolation, locks around UI-owned state, or an `@unchecked Sendable` escape hatch to avoid fixing call sites.

In coordinated mode, change initialization to build only non-RMF messages. Do not fetch or acquire RMF during `MainCoordinator` construction. Add one source-level operation, named to expose its side effect (for example, `prepareForNTP(openedAfterIdle:)`), that performs selection only when admission is enabled.

Initialize that enabled state from the existing background-launch fact supplied by `Launching` through the composition root:

- normal launch: enabled but unprepared, so an initial NTP can prepare before the first foreground callback;
- true background launch: disabled and unprepared, so a preparation cannot acquire or record `lastPreparationPolicy`; and
- foreground: enable future preparation only—do not replay an earlier request or publish automatically.

One boolean plus the optional last preparation policy is sufficient; do not introduce a general lifecycle state machine. A preparation received while disabled is an RMF-state no-op and is not replayed after foreground. Because background clears the policy, an ownerless store notification after foreground cannot select RMF until a new enabled preparation establishes one.

Call it only at these existing activation/content-loading seams, immediately before the activation-time eligibility resolution that can make content visible:

- replace the standard NTP's existing `HomePageConfiguration.refresh` call in `MainViewController.attachHomeScreen`;
- add one activation-only preparation for the legacy/iPad `MainViewController` suggestion-tray path before its visible eligibility resolution;
- add one activation-only preparation for `OmniBarEditingStateViewController`/`SuggestionTrayManager` before its visible eligibility resolution; and
- call it once at unified input's activation/content-loading seam, before `activationResolveTrigger.send(())`.

Keep `canShow`, `hasRemoteMessages`, `hasMessages`, computed eligibility getters, and publisher/signal sinks as pure reads. Inert construction-time reads that cannot display content do not prepare. The three conditional-host-family calls bootstrap RMF-only content before visible activation; they are not visibility, lease, disappearance, or lifecycle callbacks. Do not add them to leaf views.

Treat this as the complete NTP-container integration contract. Containers do not call `tryAcquire`, `markShown`, or `release`; they do not report active/renderable/visible/covered state; and they do not forward background or disappearance to Promo Queue. The shared configuration, service, existing messages model, and one composition-root lifecycle hook own everything else. If implementation requires another container callback, stop and move that responsibility into the shared source.

Route app lifecycle once through the composition root: `Background.onTransition` → `MainCoordinator.onBackground` → `HomePageConfiguration.handleAppBackgrounded`, and `Foreground.onTransition` → `MainCoordinator.onForeground` → `HomePageConfiguration.handleAppForegrounded`. Foreground handling only enables a future explicit preparation; it neither replays selection nor publishes RMF. Do not create an RMF/model `viewDidDisappear` signal; none exists today, and this architecture centralizes background teardown at the composition root.

### 2.2 Implement the centralized RMF ownership algorithm

In coordinated mode, make `HomePageConfiguration` the sole coordinated production observer responsible for NTP candidate selection and RMF ownership when global `remoteMessagesDidChange` arrives. The existing debug screen and other passive observers may remain, but they must not select or publish RMF. After updating `homeMessages`, emit a distinct, object-scoped configuration publisher. `NewTabPageMessagesModel` observes that publisher and only rebuilds from the shared value; it must not select another candidate. Keep the current global-notification behavior behind the legacy branch.

Update direct consumers to react only after the shared source changes:

- update the legacy/iPad `MainViewController` suggestion-tray path so activation prepares once and subsequent configuration signals only rerun its pure visibility/eligibility resolution;
- update `OmniBarEditingStateViewController`/`SuggestionTrayManager` so activation prepares once and its existing initial-suggestions and Dax-visibility updates run from the configuration signal in coordinated mode;
- merge the configuration publisher into unified input's existing search-state reevaluation; and
- keep all eligibility closures and signal sinks pure.

Do not republish `remoteMessagesDidChange` as the configuration signal; that would make update order and recursion ambiguous. Config-signal sinks reevaluate already-published state and must not call `prepareForNTP` from inside `hasMessages` or another publisher mapping closure.

Represent coordinated ownership state with one `currentRMFOwnership: RMFOwnership?` aggregate containing the selected message/content, the actual selected trigger filter, the strongly retained service-owned lease, and opaque callback context. Alongside it, keep only the required admission-enabled boolean and `lastPreparationPolicy: RMFPreparationPolicy?` for coordination, where policy means `noTriggerOnly` or `afterIdleThenNoTrigger`. Normal publisher/cancellable and non-RMF source state are not part of this ownership model.

The current owner's actual filter is `noTrigger` or `afterIdle`; it is not the same concept as the request/fallback policy. The selector should return both candidate and actual filter. An after-idle request tries after-idle first and then no-trigger, matching current behavior. If it falls back, pin the admitted ownership as no-trigger.

Build and strongly retain the complete ownership aggregate before publishing RMF. Implement one private teardown helper whose ordering is always: remove the coordinated RMF from `homeMessages`, emit the configuration signal, then release and clear the aggregate. Never publish while the arbiter's weak token lacks this strong source owner. Ordinary ownership teardown does not clear `lastPreparationPolicy`, allowing a later enabled store refresh to use the most recent explicit policy; background clears it.

During explicit preparation or an enabled coordinated store refresh:

1. Build non-RMF home messages as today.
2. If onboarding suppresses RMF, run the teardown helper and return the non-RMF messages.
3. If the current owner remains scheduled and renderable under its actual selected trigger filter, reuse the aggregate, publish any refreshed same-owner content, and stop fresh selection. Ignore a later renderer's competing preparation policy for this ownership.
4. Otherwise tear down the invalid owner, then select using the current explicit preparation policy or, for a store-driven refresh, `lastPreparationPolicy`; return both the candidate and actual filter selected by the existing after-idle-then-no-trigger fallback.
5. If no renderable candidate exists, publish only non-RMF content.
6. Ask the gate for the new message ID.
7. On success, construct and retain the complete aggregate with the actual selected filter before publishing the candidate and emitting the configuration signal.
8. If admission fails, append nothing and do not mutate `RemoteMessagingStore`.

Keep the fetch, release/acquire, and `homeMessages` publication ordering synchronous on the main actor so a modal cannot interleave between the decision and publication.

### 2.3 Define same-ID and replacement semantics explicitly

- A same-ID refresh under the ownership's actual selected filter is one continuous ownership. It bypasses a new cooldown check and retains its appearance state and acquisition identity.
- A preparation from another renderer with a different policy cannot replace a valid owner. The first admitted actual filter remains authoritative until that ownership ends.
- An `afterIdleThenNoTrigger` request that selects its no-trigger fallback stores `noTrigger` in the ownership. A later after-idle candidate cannot displace that still-valid fallback owner.
- A different ID ends the old ownership before attempting the new ID.
- If the old message appeared, the new message must pass RMF-to-RMF cooldown.
- If the old message never appeared, releasing it writes no history; the new message can acquire if the slot is otherwise free.
- If the new message is denied, the store remains authoritative and a later natural refresh can retry it.

Do not define same-ID joining for a future independent RMF source in this iteration. Such a source needs a separately reviewed source-level lifecycle contract.

### 2.4 Reject unrenderable content and reuse acquisition identity in SwiftUI

Add a pure `HomeMessageViewModelBuilder.canBuild(for:)` (or equivalently named) check that uses the builder's existing content-to-display conversion. Call it before RMF acquisition. Missing content and unsupported `.cardsList` content must acquire no lease, publish no card, and mutate no store state. Do not maintain a second independent support switch.

Use the returned wrapper's production acquisition identity for both callback validation and SwiftUI diffing; do not mint a second presentation UUID. Carry it opaquely through `HomeMessageViewModel`, keep it stable across same-owner refreshes, and key coordinated RMF content by message plus acquisition identity. A release/reacquisition naturally produces a new identity even for the same message ID. Preserve current identity behavior for legacy and non-RMF messages.

### 2.5 Move coordinated shown accounting to actual appearance

In `NewTabPageMessagesModel`, retain the existing `HomeMessageViewModelBuilder` `onDidAppear` callback and remove coordinated eager map-time appearance accounting. When mapping an RMF, capture the opaque context supplied by the configuration in its appearance and dismissal closures. The model forwards but does not interpret that value.

In `HomePageConfiguration.didAppear`:

1. In legacy mode, preserve the current path deliberately.
2. In coordinated mode, require a current lease matching both the RMF ID and captured acquisition identity.
3. After configuration validation succeeds, call the service-owned lease wrapper's no-argument `markShown()`. That wrapper independently rejects stale raw state, confirms with the arbiter, and records RMF cooldown history only on the first valid confirmation.
4. Only when it returns `true`, fire the regular `remoteMessageShown` event once, then run the existing best-effort first-ever guard for `remoteMessageShownUnique` and its store update.
5. Ignore stale, mismatched, repeated, or post-release callbacks.

Do not add a new pixel, parameter, or in-process unique-shown reservation. Preserve existing metric-enabled checks and randomized subscription parameters. Mapping no longer fires an impression; the first actual appearance fires regular shown once for that ownership. Because the store's unique check and asynchronous update are not atomic, rapid same-ID reacquisition may still duplicate unique-shown. The flag-off path retains today's behavior.

Because the configuration is shared, appearance callbacks from a second physical mount of the same message reach the same lease and do not start queue history again.

### 2.6 Implement terminal and background teardown

Release when a refresh observes:

- dismissal/removal in authoritative store state, or completion of a dismissal attempt whose presentation context is still current; otherwise authoritative source reconciliation determines ownership;
- expiry/removal from scheduled messages;
- replacement by a different message ID;
- onboarding suppression; or
- no eligible or renderable candidate.

Before starting coordinated dismissal, validate the callback's message ID and acquisition identity. A callback already stale does nothing and must not call the store. Add no dismissal-in-progress marker and do not freeze ownership while asynchronous `dismissRemoteMessage` awaits; normal store refresh, invalidation, or replacement may proceed. After the attempt completes, run direct ordered teardown only if the context is still current. Regardless of whether it became stale, preserve the existing one authoritative source-reconciliation notification. A stale completion cannot directly mutate or release a replacement owner, while the resulting scheduled-message state is still reconciled normally. The store API returns `Void` and logs persistence failures, so do not claim a successful dismissal.

On background:

1. disable RMF admission;
2. remove the coordinated RMF from `homeMessages`;
3. synchronously emit the configuration signal; and
4. release and clear the ownership aggregate and last preparation policy without recording new history.

An outstanding dismissal completion then fails context validation and cannot directly release or confirm a newer lease. The already-started store operation may still change scheduled-message state; its notification is reconciled normally and may make a reacquired same-ID owner ineligible. Do not add cancellation or reservation machinery. Store notifications while inactive may update non-RMF state but must not reacquire RMF. Foreground only re-enables a future explicit `prepareForNTP`; it must not automatically publish RMF.

Document and implement the consequence without an exemption: a never-appeared RMF wrote no history and may reacquire at the next valid explicit preparation. An appeared RMF's same scheduled ID is a fresh acquisition blocked by the 10-minute RMF-to-RMF cooldown, and a launch modal is independently blocked by the 24-hour RMF-to-modal cooldown. No boundary timer runs, so if preparation is denied an attached NTP can stay blank beyond ten minutes until another natural checkpoint. Do not add same-ID resume, foreground replay, or timer state.

Do not release from:

- `viewDidDisappear`;
- SwiftUI `onDisappear`;
- tab switching;
- conditional-host transitions or handoffs;
- window detachment; or
- Fire-mode or layout changes.

Do not add a retain count. `HomePageConfiguration`, not a physical renderer, owns the lease.

### 2.7 Keep retry checkpoint-driven

Do not register every NTP model for retries. A blocked RMF is reconsidered on:

- explicit `prepareForNTP` from an NTP-capable path;
- a coordinated `remoteMessagesDidChange` while admission is enabled;
- an `afterIdle` refresh;
- a later RMF admission attempt that reconciles a detached modal.

Modal work remains a foreground operation and is not immediately retried when RMF ownership ends.

Do not add a service-to-configuration release callback in this stack. If checkpoint-driven retry proves insufficient in production, treat that as evidence for a separately reviewed design amendment; it is not permission to add a release publisher, renderer registration, or retry ordering during implementation.

### 2.8 Update protocols, target membership, and test doubles

Mark the `HomePageMessagesConfiguration` protocol, `HomePageConfiguration`, and `NewTabPageMessagesModel` `@MainActor`. Fix the scoped UI call sites the compiler identifies; do not annotate entire unrelated controller hierarchies merely because they consume the protocol. Adjust the protocol only as much as needed to expose the configuration-scoped change publisher, supply and round-trip the opaque presentation context, and express the coordinated/legacy accounting branch. Its coordinated publisher must deliver model updates synchronously on the main actor; do not insert a `receive(on:)` hop before `NewTabPageMessagesModel` rebuilds. Host layout reactions may remain scheduled. Add the publisher to relevant mocks with an explicit inert value. If a mode property is added, provide an explicit legacy default for previews and unrelated mocks. Do not expose the lease itself, the ownership aggregate, or the preparation policy to `NewTabPageMessagesModel`.

Remove obsolete `MockNewTabPagePromoCoordinator`. Add a small test-target `MockPromoGate` capable of:

- selecting mode;
- granting or denying RMF acquisition;
- returning an identity-safe lease through the existing production gate contract; and
- recording only gate calls made through that production contract.

Use the real production wrapper/token when practical and assert release through observable reacquisition or slot availability. Use a fake lease only if the production gate contract already abstracts the lease for a production reason; do not add a lease protocol or production initializer solely to make it controllable. Any counters remain entirely in the test target. Avoid mocks that reproduce the production state machine.

For every added/deleted production file, test, or shared mock, update `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` file references and the exact app/test target memberships. Do not add a shared mock to every test target by default. Prefer keeping an existing file when its final responsibility and name remain honest.

### 2.9 Focused PR 2 tests

Drive every case through production-used configuration, gate/lease, notification, lifecycle, and reporting contracts. Do not expose private ownership, trigger, context, or observer state to make these assertions.

Prefer a handful of behavior groups over an edge-case matrix:

1. Startup: table-drive normal launch with an initial NTP, a restored website with no preparation, and a true background launch. Normal initial preparation can acquire even before the first foreground callback. A disabled background preparation records no policy; foreground alone and an ownerless store notification still cannot select until a new enabled preparation establishes one.
2. Shared refresh: one store notification enters the main actor, causes one configuration selection, two models converge synchronously from its signal, and a direct host consumer reevaluates without recursion. After an earlier denial with no owner, retry uses `lastPreparationPolicy`.
3. Trigger selection/pinning: table-drive an after-idle candidate and an after-idle request that falls back to no-trigger. Assert the actual selected filter is behaviorally pinned: a later competing request cannot replace the valid fallback owner.
4. Admission boundary: modal ownership/cooldown and unsupported content prevent publication or store mutation; a free slot publishes only after the complete ownership aggregate is retained.
5. Appearance, identity, and background: same-ownership refresh keeps acquisition identity, same-ID reacquisition changes it, and the real service wrapper writes history and regular shown once while stale callbacks do nothing. Pair appeared and never-appeared background cases: the former is cooldown-blocked on fresh same-ID acquisition, while the latter can reacquire. Retain one deterministic existing unique-guard test if that path changes; do not assert exact-once across acquisitions.
6. Ordered teardown/dismissal: table-drive expiry/replacement, onboarding suppression, and background to prove unpublish/signal precedes release and background adds no history while preserving existing history. With a suspended dismissal store, allow a store refresh to replace ownership during the `await`; resuming the old completion cannot directly mutate the replacement and requests one authoritative reconciliation.
7. Legacy regression: retain one focused action/dismissal/pixel test proving the feature-off path is unchanged.

Do not add real-UIKit tests for every host family, an exhaustive content-type suite, all startup/cooldown permutations, broad notification-order tests, or landscape lifecycle tests. Validate the shared behavior once. Use static review and manual QA for the three one-line conditional activation integrations; add a cheap host assertion only when an existing harness already supports it. One composition assertion may prove the shared instance and central lifecycle hook only through an existing production composition/behavior seam; otherwise use static review and manual QA rather than adding coordinator/configuration getters.

## Phase 2 manual validation

Use the existing feature-flag override and RMF internal tooling. Because mode is startup-latched, force-quit after changing the flag.

Validate:

1. Flag off: current modal and RMF behavior is unchanged.
2. RMF first: in a cold/restored-NTP setup where RMF wins admission before the pending launch-modal checkpoint, confirm no launch-modal provider is evaluated or presented. Treat the reverse order as the modal-first case; do not background an already shown card for this ownership check because background intentionally releases it.
3. Modal first: commit a modal, open/refresh NTP beneath it, and confirm no RMF flashes.
4. No eligible modal: confirm the temporary modal acquisition does not strand the slot.
5. Dismissed modal: confirm lazy reconciliation at the next checkpoint and observe the incoming RMF cooldown.
6. RMF dismissal, expiry, and replacement: confirm source-level release/reacquisition.
7. Standard NTP and each conditional-host family—legacy/iPad `MainViewController` suggestion tray, `OmniBarEditingStateViewController`/`SuggestionTrayManager`, and unified-input/address-bar favorites—confirm all consume the same gated result with one activation-time preparation and no per-renderer lease/visibility callbacks. Verify pure construction reads and signal-driven reevaluation do not prepare recursively.
8. `afterIdle` selection: verify both a direct after-idle candidate and fallback to no-trigger; a later after-idle candidate must not replace a still-valid fallback owner.
9. Onboarding suppression.
10. Fire tab: confirm current suppression behavior and that source ownership remains safe. Rotate through landscape as behavior discovery; confirm actual rendering and no crash without adding special lease handling.
11. Leave the NTP: confirm message ownership remains source-driven rather than tied to one renderer.
12. Background/foreground: confirm the card is unpublished before lease release and a background store update does not reacquire it. For a never-appeared card, a later explicit preparation can reacquire. For an appeared card, confirm fresh same-ID admission is denied during the 10-minute RMF cooldown, modal admission is independently denied during the 24-hour RMF-to-modal cooldown, foreground does not auto-publish, and the NTP may remain blank after the boundary until another explicit checkpoint. Use the debug reset or wait only when intentionally validating post-cooldown behavior.
13. Relaunch: confirm live owner resets while persisted confirmed cooldown history remains.

## PR 2 completion criteria

- The feature goal works end to end when the flag is enabled.
- `HomePageConfiguration` is the only current RMF lease owner.
- The full shared configuration/protocol/model path is `@MainActor`, and normal/background startup order behaves as documented.
- No NTP host, overlay, or physical renderer reports visibility.
- A blocked card never enters `homeMessages` and never records accounting.
- Same-ID ownership, after-idle fallback, actual-filter pinning, and first appearance are deterministic at the shared source.
- Cold launch cannot claim RMF before an NTP request, and background teardown releases it in the documented order.
- Focused affected tests and an iOS build pass after obtaining permission.
- No new telemetry exists.
- Local handoff notes include the final suggested future-PR title and ready-to-paste description, measured insertion/deletion counts, accepted limitations, evidence, and the dependency on PR 1.

---

# PR 3 — `bartosz/promo-q-simp-4`

## Branch point and goal

After permission for git writes, create local `bartosz/promo-q-simp-4` from the reviewed head of `bartosz/promo-q-simp-3`. Keep its diff relative to `bartosz/promo-q-simp-3`; do not push or open a PR.

Goal: make the simplified machinery easy to inspect and manually verify using the app's existing internal debug area, without changing production admission behavior.

Suggested PR title: **iOS Promo Queue: Add simplified coordination diagnostics**

Draft-description focus: state that this is an internal-only extension of the existing debug screen; list the read-only owner/cooldown diagnostics and explicit RMF cooldown reset; emphasize that admission, retry, telemetry, and production presentation behavior do not change; include focused debug/manual evidence and the dependency on PR 2; state that human review/integration and the external rollout handoff follow, while push and configuration deployment remain out of scope.

## Phase 3 — extend the existing debug screen

### 3.1 Reuse current debug wiring

Extend:

- `iOS/DuckDuckGo/ModalPromptCoordination/DebugMenu/ModalPromptCoordinationDebugMenu.swift`;
- its registration in `iOS/DuckDuckGo/DebugScreensViewModel+Screens.swift`;
- `iOS/DuckDuckGo/DebugScreen.swift` dependencies; and
- the two debug construction paths in `MainViewController+Segues.swift` and `SettingsLegacyViewProvider.swift` as needed.

Do not create another production coordinator or cooldown store. Inject a read-only snapshot provider backed by the app-scoped service and the same stores used by production.

Update `iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj` for any new debug/test files and their exact internal app/test target memberships.

### 3.2 Add the simplified snapshot

Show:

- process mode (`Legacy` or `Coordinated`);
- a note that flag changes require relaunch;
- active owner (`None`, modal ownership ID, or RMF message ID/acquisition ID);
- whether the current RMF ownership confirmed appearance;
- last confirmed modal appearance;
- last confirmed RMF appearance;
- next RMF eligibility;
- next modal eligibility.

Do not add modal-phase or last-denial plumbing. Mode, owner, RMF appearance confirmation, cooldown values, refresh, and resets are sufficient.

Add a Refresh button. State clearly that eligibility dates do not schedule retries.

Do not display deleted concepts such as renderer count, eligible renderer, logical session, handoff, drain, removal ID, or exact removal terminal.

### 3.3 Manual-test controls

Keep the existing modal cooldown reset and add an explicit internal-only RMF cooldown reset because the production intervals are impractical for repeated manual validation. Route it through the same authoritative history component used by cooldown admission. It must:

- clear both the persisted RMF timestamp and any authoritative in-process fallback/cache;
- update the debug snapshot immediately;
- be clearly labeled as debug-only; and
- not release an active owner or dismiss a message.

Do not add force-modal, force-RMF, arbitrary owner mutation, or fake-visibility controls. Existing provider reset screens and Remote Messaging debug configuration remain the source of test content.

### 3.4 Debug tests

Inject the same read-only diagnostic-provider contract used by the internal debug UI. Do not reach through the provider to service, arbiter, or storage internals.

Add only two focused behavior groups:

- passive refresh/formatting for mode, owner, appearance, and cooldown values through the production diagnostic-provider contract; and
- RMF cooldown reset changing eligibility immediately while leaving ownership untouched.

Avoid snapshot tests unless layout complexity genuinely warrants them.

## PR 3 completion criteria

- The existing screen exposes every state needed for the manual matrix.
- Passive debug reads do not mutate production history or ownership; only the explicitly labeled reset actions mutate their matching cooldown history, and neither changes ownership.
- Any reset is explicit and internal-only.
- No telemetry or production retry behavior is added.
- Focused debug tests and an iOS build pass after obtaining permission.
- Local handoff notes include the final suggested future-PR title and ready-to-paste description, the complete manual validation matrix, and rollout caveats.

---

# Final stack verification

After all three branches are combined, perform one final review against this plan's Objective, Product decisions, End-state architecture contract, Invariants, Accepted simplifications, phase completion criteria, and verification checklist rather than reviewing each unit in isolation.

## Static checks

Search the final diff and repository for discarded vocabulary and investigate every remaining result:

- `setPromoSurfaceActive`
- `setPromoSurfaceRenderable`
- `setPromoSurfaceVisible`
- `setPromoSurfaceCovered`
- `NewTabPagePromoSurfaceHandoff`
- `NewTabPagePromoRetrying`
- `NewTabPagePromoRetryRegistration`
- renderer generation, handoff, drain, and removal-terminal types
- `PromoQueueFeatureState`
- live `.promoPresentationCoordination` subscriptions

Search hits outside compiled production/test targets do not justify retaining these concepts; none should remain in the final production path.

Verify the final dependency graph contains one production arbiter/service and one shared `HomePageConfiguration` instance for the three NTP renderers.

Use `git diff --check` and the repository's normal lint/build checks. Run tests only after obtaining the permission required by repository instructions.

## Focused automated suites

Run the smallest targets that include:

- Promo Queue arbiter tests;
- directional cooldown tests;
- Promo Coordination service tests;
- Modal Prompt manager/root tests;
- `HomePageConfigurationTests`;
- `NewTabPageMessagesModelTests`;
- feature-flag mapping/default tests; and
- debug view-model tests.

Then run the normal iOS build/test coverage appropriate for a change spanning app composition and presentation, subject to the repository's test-permission rule. Do not compensate for removed architecture tests by recreating a similarly large suite under new names.

## Review checklist

- Does any renderer or overlay know about leases, ownership, visibility, coverage, or lifecycle coordination? It must not.
- Does an NTP container have any imperative Promo Queue integration beyond `prepareForNTP` once per content activation? It must not; move any additional coordination responsibility to the shared source.
- Are all shared configuration/protocol/model operations and global-notification mutations on the main actor? They must be.
- Can a pure eligibility getter or configuration-signal sink call `prepareForNTP`? It must not.
- Can provider evaluation occur before modal admission? It must not.
- Can an RMF enter `homeMessages` before admission? It must not.
- Can a stale context release, dismiss, or confirm the current owner, including a reacquired owner with the same message ID? It must not.
- Does dismissal add an in-flight ownership freeze? It must not; identity validation plus authoritative reconciliation is sufficient.
- Is an RMF cooldown written before actual appearance? It must not be.
- Does ordinary NTP disappearance release RMF? It must not. Does app background unpublish and then release it? It must.
- Is time passage alone scheduling work? It must not.
- Does the feature-off path still work after a fresh graph is built? It must.
- Did the change add telemetry? It must not.
- Does modal ownership use more than one identity or return a post-transfer disposition? It must not.
- Are accepted limitations described consistently in code comments, tests, debug UI, and local handoff notes?
- Was any private declaration widened, state getter added, or production hook introduced only for tests? Remove it. If a production caller genuinely required an access change, document that caller and rationale and flag it explicitly in the draft future-PR description.

# External phase 4 — rollout handoff only

The local implementation agent must not modify or push `duckduckgo/privacy-configuration`, open a configuration PR, deploy a cohort, or change a project tracker. Instead, record a handoff for the project/feature DRI containing:

- the three local branch names and, after human integration, placeholders for merged PR links and the first containing iOS version;
- parent feature `promoQueue` and subfeature `iOSPromoPresentationCoordination`, the remote source of `.promoPresentationCoordination`;
- the completed automated and manual validation evidence;
- the startup-latched relaunch caveat;
- the expected decrease in regular `remoteMessageShown` volume caused by once-per-appeared-ownership accounting, so it is not automatically treated as a regression;
- a suggested 5% → 25% → 50% → 100% cohort sequence, subject to the rollout DRI;
- existing crash/regression, RMF/provider accounting, manual-reproduction, and support-report hold criteria; and
- named owners for privacy-config review, deployment, and iOS release confirmation; and
- an owner and trigger for a separate post-rollout cleanup task after 100% rollout and an agreed soak/rollback window.

The eventual external owner must set the first containing iOS version as the minimum supported version and must not use generated `iOS/Core/ios-config.json` as the rollout source. Rollback is the remote disable of `iOSPromoPresentationCoordination`; because mode is startup-latched, a new process graph is required. No new telemetry is added. Do not claim the product success criterion complete until the deployed flag reaches 100% of supported iOS users and that state is recorded.

The deferred cleanup is not part of this local stack. Only after the agreed soak/rollback window should its owner remove legacy source/accounting branches, duplicate legacy observer behavior, obsolete mode plumbing, and superseded tests. Keeping that work separate preserves a simple rollback path during rollout.

# Definitions of done

## Local implementation handoff

- `bartosz/promo-q-simp-2`, local `bartosz/promo-q-simp-3`, and local `bartosz/promo-q-simp-4` contain the three clean review units; no branch was pushed and no PR was opened.
- The combined local diff satisfies this plan's architecture contract, invariants, phase completion criteria, verification matrix, and accepted simplifications, and reduces PR #6087 machinery to the behavior specified here.
- Focused automated and manual validation has passed after obtaining required permission.
- The existing debug screen explains current owner and cooldown state.
- No new telemetry exists.
- A leaf renderer consuming an already-prepared shared source needs no Promo Queue call. Each independent content-activation container uses only the single preparation seam; conditional hosts additionally observe the shared content signal.
- The rollout handoff is complete and clearly marked as external work.
- Each local unit has a suggested future-PR title and ready-to-paste draft description based on its actual diff; no branch was pushed and no PR was opened.

## Project success criterion after human/external follow-through

- The three review units are reviewed, merged, and shipped.
- The coordinated flag reaches 100% of supported iOS users.
- The final rollout version and validation record are captured by the project owner.
