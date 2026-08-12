# Promo Queue: Central Logical RMF Owner — Implementation Record

## Status

This document was the implementation handoff for simplifying the iOS Promo Queue before Q2 lands. The redesign is now implemented and is retained here as the detailed decision and verification record.

- Q2 implementation: `bartosz/promo-q-2` at `9e82601a9f`, PR [#6194](https://github.com/duckduckgo/apple-browsers/pull/6194).
- Q3 adaptation: `bartosz/promo-q-3` at `9321268231`, PR [#6291](https://github.com/duckduckgo/apple-browsers/pull/6291), based directly on Q2.
- iOS 17+ preserves the RMF scale-and-opacity removal animation.
- iOS 15/16 removes coordinated RMF synchronously with animations disabled; the missing dismissal animation is approved.
- PR 1 remains unchanged and is already merged.

Sections written as instructions describe the constraints used during implementation. The current branch heads and commit maps in this status section and in the outcome sections below supersede prospective SHA references elsewhere in this record.

The goal is to reduce the large, distributed per-NTP ownership and mount-lifecycle state machine while retaining the actual product requirement:

> A modal promo and an RMF promo must never be visibly presented at the same time, and two physical RMF cards must not be visible at the same time.

Cooldowns decide when a new presentation may begin. They do not prove that the previous presentation has stopped being visible.

## Required reading

Read the following before reviewing or extending the implementation:

- `/Users/bkunat/Desktop/ddg-workspace/apple-browsers/promo-queue-docs/TECH_DESIGN_FINAL.md`
- `/Users/bkunat/Desktop/ddg-workspace/apple-browsers/promo-queue-docs/IMPLEMENTATION_PLAN.md`
- `/Users/bkunat/Desktop/ddg-workspace/apple-browsers/promo-queue-docs/Q3_IMPLEMENTATION_PLAN.md`
- `/Users/bkunat/Desktop/ddg-workspace/apple-browsers/promo-queue-docs/ADDING_PROMOS.md`
- `/Users/bkunat/Desktop/promo-queue-shared-docs/PROMO_QUEUE_Q2_SIMPLIFICATION_IMPLEMENTATION_PLAN.md`
- `AGENTS.md`
- `.cursor/rules/general.mdc`
- `.cursor/rules/code-style.mdc`
- `.cursor/rules/anti-patterns.mdc`
- `.cursor/rules/user-defaults-storage.mdc`
- `.cursor/rules/pixels.mdc`

Treat this record as the authority for the central logical RMF owner redesign. `TECH_DESIGN_FINAL.md` is the consolidated current contract; older point-in-time research remains historical context.

Review the cumulative pull requests:

- PR1, merged: [apple-browsers #6087](https://github.com/duckduckgo/apple-browsers/pull/6087)
- Q2, open: [apple-browsers #6194](https://github.com/duckduckgo/apple-browsers/pull/6194)
- Former Q2 fixes, closed and folded into Q2: [apple-browsers #6280](https://github.com/duckduckgo/apple-browsers/pull/6280)
- Q3, draft: [apple-browsers #6291](https://github.com/duckduckgo/apple-browsers/pull/6291)

Android is an architectural reference, not an API template:

- [Android PR #9289](https://github.com/duckduckgo/Android/pull/9289)
- [Each non-null NTP emission attempts/reclaims and a null emission reports completion](https://github.com/duckduckgo/Android/blob/5ae0c0af6818a96b12315fe6632ab737312aee51/app/src/main/java/com/duckduckgo/app/browser/newtab/NewTabPageViewModel.kt#L168-L195)
- [`onMessageShown` records the RMF impression but does not release](https://github.com/duckduckgo/Android/blob/5ae0c0af6818a96b12315fe6632ab737312aee51/app/src/main/java/com/duckduckgo/app/browser/newtab/NewTabPageViewModel.kt#L224-L228)
- [Android test: shown NTP card retains its claim](https://github.com/duckduckgo/Android/blob/5ae0c0af6818a96b12315fe6632ab737312aee51/app/src/test/java/com/duckduckgo/app/browser/newtab/NewTabPageViewModelTest.kt#L156-L189)
- [Android coordinator and type-only NTP reclaims](https://github.com/duckduckgo/Android/blob/5ae0c0af6818a96b12315fe6632ab737312aee51/prompts-coordinator/prompts-coordinator-impl/src/main/java/com/duckduckgo/promptscoordinator/impl/RealPromptsCoordinator.kt#L43-L179)
- [Android modal release on `ModalShown`](https://github.com/duckduckgo/Android/blob/5ae0c0af6818a96b12315fe6632ab737312aee51/prompts-coordinator/prompts-coordinator-impl/src/main/java/com/duckduckgo/promptscoordinator/impl/ModalEvaluatorCoordinator.kt#L101-L131)

Animation references:

- [SwiftUI `withAnimation` with completion criteria](https://developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:))
- [SwiftUI `AnimationCompletionCriteria`](https://developer.apple.com/documentation/swiftui/animationcompletioncriteria)
- [SwiftUI `withTransaction`](https://developer.apple.com/documentation/swiftui/withtransaction(_:_:))
- [Core Animation `CATransaction`](https://developer.apple.com/documentation/quartzcore/catransaction)

## Verified final branch topology

As of 2026-08-12, the relevant remote topology is:

```text
PR1 #6087, merged
  └─ Q2 branch history
       └─ origin/bartosz/promo-q-2 @ 9e82601a9f
            └─ origin/bartosz/promo-q-3 @ 9321268231
```

Q3's merge base with Q2 is exactly `9e82601a9f`. PR #6280 is closed and its accepted changes are folded into Q2; it is review provenance, not an active stack layer. Q2 still needs normal synchronization with the current `main` before landing, followed by one controlled Q3 restack.

## Executive decision

Implement one app-scoped logical RMF presentation owner inside the already app-scoped `PromoCoordinationService`.

The service, not an individual `NewTabPageMessagesModel`, will own:

- The single RMF lease.
- The active logical RMF session identity.
- Exactly-once queue-history confirmation for that session.
- Weak renderer registrations.
- Selection of exactly one physical renderer.
- Renderer-to-renderer transfer.
- The one outgoing-removal barrier.

Each `NewTabPageMessagesModel` becomes a thin renderer client. It continues to discover and build its local `HomeMessage` candidate, but it no longer acquires, retains, confirms, or releases an independent lease.

Use a balanced logical lifetime for this iteration:

1. Ownership begins when an eligible renderer with a candidate is admitted.
2. Ownership remains with the same logical session across a same-message renderer handoff.
3. If there is no eligible renderer, or the selected renderer no longer reports that candidate, remove the selected card using the OS-specific path and retain ownership until the terminal-removal acknowledgement.
4. Release only after the card is no longer visibly rendered.
5. The same scheduled message may start a new session if it becomes eligible again later; normal cooldown admission applies.

This deliberately retains the current host exposure signals in the first implementation. It avoids expanding scope into `MainViewController`, suggestion-tray, unified-input, popover, and Dax-overlay behavior while centralizing the ownership state that made those integrations difficult.

### Accepted product decisions

The following observable tradeoffs were accepted for this implementation:

- **Balanced lifetime:** when no renderer remains eligible, remove the card and release after its terminal instead of allowing a hidden logical RMF to block modal promos indefinitely. After Q3, a confirmed card returning too late for same-session handoff is subject to its own 10-minute RMF cooldown.
- **Deterministic contention:** if multiple eligible renderers report candidates while idle, use stable activation/registration order rather than adding a new app-wide RMF source in this change.
- **OS-specific exit visual:** preserve scale/opacity removal on iOS 17+, where SwiftUI provides native `.removed` completion; use immediate no-animation removal on iOS 15/16.
- **Fail-closed removal:** on iOS 17+, if neither the matching animation terminal nor verified host detachment arrives, retain the lease indefinitely and surface diagnostics rather than risk a visible collision. The iOS 15/16 path clears the source item synchronously and reports its exact terminal without waiting for an animation callback; an exact-clear failure reports no terminal and also fails closed.

These choices keep the patch bounded. Changing any of them materially changes the architecture: full logical lifetime can starve modals, globally deterministic candidate selection requires a central RMF source, and restoring the animation on iOS 15/16 requires a separately proven removal-completion mechanism.

## What is copied from Android

Copy these concepts:

- One app-scoped prompt slot with serialized ownership changes.
- Acquire before publishing content.
- Live ownership is in-memory; cooldown history is persisted separately.
- Confirmed appearance and ownership release are separate events.
- An NTP emission does not release the owner merely because its view reported an appearance.

Strengthen Android's design for iOS:

- Make the RMF owner message/session-specific rather than type-only.
- Select exactly one physical renderer; Android grants all concurrent `NTP_CARD` reclaims and does not provide this guarantee.
- Model renderer handoff explicitly and retain one owner until the outgoing renderer is non-visible.

Do not copy these Android behaviors:

- Do not release an NTP claim on confirmed appearance. Android does not do this either.
- Do not use a type-only `NTP_CARD` reclaim. Use message ID plus a service-minted session ID.
- Do not let stale same-type callbacks release a newer session.
- Do not let a non-owner renderer's nil candidate, teardown, or stale completion release the selected session. Android's type-only `onClaimDone` cannot distinguish this case.
- Do not release modal ownership on `ModalShown`; retain the existing exact UIKit-root lifetime.
- Do not add Android's one-second waiter or claim fairness it does not provide.
- Do not stamp the iOS RMF cooldown at logical disappearance. Q3 retains confirmed-appearance timestamps.
- Do not claim that an in-memory owner survives process termination.

## Non-goals

Keep the change set bounded. This iteration must not:

- Introduce a movable process-owned `UIHostingController`.
- Extract a new app-wide Remote Messaging repository/source.
- Modify shared Remote Messaging storage.
- Remove the existing host exposure/coverage/handoff calls.
- Dynamically resample the feature flag.
- Add cooldown-boundary timers.
- Add timeout-based lease release.
- Change modal evaluation, provider ordering, or exact-root dismissal semantics.
- Pull Q3's persisted directional cooldown implementation into Q2.
- Preserve the old per-model ownership state alongside the new service-owned state.

The last point is important: two lifetime authorities would increase the state space and eliminate the intended simplification.

## Core invariants

The implementation must make these invariants obvious in source and directly test them:

1. The process has at most one global promo owner: modal or RMF.
2. Only `PromoCoordinationService` holds an RMF lease.
3. At most one renderer is authorized to publish an RMF session.
4. A renderer is authorized only after the service acquires the global lease.
5. A renderer transfer retains the same lease until the outgoing card reaches its terminal non-visible state.
6. The incoming renderer is not authorized before the outgoing renderer's matching removal completes.
7. Queue-history confirmation records once per logical session and never releases ownership; ordinary RMF appearance accounting records once per accepted physical presentation.
8. A missing removal acknowledgement fails closed: retain the lease and emit diagnostics; do not time-release.
9. Stale or duplicate session/removal callbacks are no-ops.
10. Modal ownership remains held until the exact presented UIKit root detaches.
11. Feature-off behavior remains byte-for-byte equivalent in effect: no coordinated registration, arbitration, cooldown/history reads, or changed RMF accounting.

The safety proof is short:

- A modal and an RMF cannot be inserted under the same mutually exclusive lease.
- The RMF lease is retained until its outgoing renderer is non-visible.
- A second RMF renderer cannot be authorized until the first is non-visible.
- Therefore neither modal/RMF nor RMF/RMF visible overlap is possible.

## Terminology and identity

Use four different identities. Do not collapse them:

- **Renderer ID:** stable UUID for one `NewTabPageMessagesModel` registration.
- **Session ID:** UUID minted by the service for one successful RMF acquisition. It is the generation that makes same-message callbacks stale-safe.
- **Presentation ID:** UUID minted each time one renderer is authorized under a session. It rejects delayed `onAppear` from an outgoing or previously authorized renderer.
- **Removal ID:** UUID minted for one transition from owned to draining.

The logical owner identity is `(messageID, sessionID)`. `surfaceID`/renderer ID must not be part of the arbiter owner identity.

If the same RMF message is shown again after its earlier session fully released, it receives a new session ID and undergoes normal admission again.

## Proposed public contracts

The following is a semantic sketch, not a requirement to preserve every spelling. Keep the final API small and `@MainActor`.

```swift
struct PromoQueueRemoteMessageSession: Equatable {
    let id: UUID
    let messageID: String
}

struct PromoQueueRemoteMessagePresentation: Equatable {
    let id: UUID
    let session: PromoQueueRemoteMessageSession
}

enum PromoQueueRemoteMessageCandidateState: Equatable {
    case none
    case available(messageID: String)
    case unrenderable(messageID: String)
}

enum PromoQueueRemoteMessageRemovalTerminal {
    case animationCompleted
    case sourceRemovedWithoutAnimation
    case hostDetached
}

@MainActor
protocol NewTabPagePromoRendering: AnyObject {
    /// Returns false if this renderer no longer owns a matching local candidate.
    func showRemoteMessage(_ presentation: PromoQueueRemoteMessagePresentation) -> Bool

    /// Starts removal. Terminal is reported through the registration using
    /// the exact presentation/removal identities supplied by the coordinator.
    func hideRemoteMessage(
        _ presentation: PromoQueueRemoteMessagePresentation,
        removalID: UUID)
}

enum PromoQueueRemoteMessageAppearanceResult {
    case accepted
    case rejected
}

@MainActor
final class NewTabPagePromoRendererRegistration {
    func update(candidate: PromoQueueRemoteMessageCandidateState, isEligible: Bool)
    func confirmAppearance(
        sessionID: UUID,
        presentationID: UUID,
        isAttachedToWindow: Bool) -> PromoQueueRemoteMessageAppearanceResult
    func removalDidReachTerminal(
        sessionID: UUID,
        presentationID: UUID,
        removalID: UUID,
        terminal: PromoQueueRemoteMessageRemovalTerminal)
    func deregister()
}

@MainActor
protocol NewTabPagePromoCoordinating: AnyObject {
    var promoCoordinationMode: PromoCoordinationMode { get }

    func registerRemoteMessageRenderer(
        id: UUID,
        target: NewTabPagePromoRendering) -> NewTabPagePromoRendererRegistration
}
```

Contract details:

- The model does not call the service registration API in legacy mode. If construction needs a token-shaped object, create a purely local no-op token rather than registering with the app-scoped service.
- `update` is the only routine renderer input needed in phase one. Existing host signals continue to compute `isEligible`.
- Each registration receives an internal service-minted **registration generation ID** in addition to its renderer ID. The registration object supplies that generation implicitly on every update, confirmation, terminal, and deregistration call. The service rejects calls from an obsolete generation.
- Re-registering a renderer ID creates a new generation and a new stable-order position. If the old generation is selected or draining, retain it as a pending-removal record until its exact terminal; do not replace it in place.
- The service owns all selection and invokes `show`/`hide` on the selected weak target.
- `show` must validate that the model still has `session.messageID`; a failed validation must not publish content.
- `confirmAppearance` succeeds only for the current owned—not draining—session, selected renderer, current presentation ID, eligible registration, and attached window, and only once for that presentation.
- Every accepted physical presentation continues through ordinary `HomePageMessagesConfiguration.didAppear` accounting, preserving today's non-unique impression behavior. The service separately records Q3 queue history only on the first accepted presentation of the logical session. `remoteMessageShownUnique` remains guarded by the RMF store as it is today.
- `removalDidReachTerminal` succeeds only for the exact current `(registrationGenerationID, rendererID, sessionID, presentationID, removalID)` while that renderer is outgoing. `.animationCompleted` is the iOS 17+ native terminal, `.sourceRemovedWithoutAnimation` is the iOS 15/16 terminal emitted after the matching source item is cleared, and `.hostDetached` is accepted only after verifying that exact renderer is no longer attached to a window and cannot contribute pixels.
- Registration teardown must not silently release a possibly visible owner. Complete removal or prove host detachment first.

## Service-owned state

Use one explicit state enum in `PromoCoordinationService`:

```text
logicalSession(
    messageID,
    sessionID,
    queueAppearanceConfirmed
)

idle

owned(
    logicalSession,
    lease,
    registrationIdentity(rendererID, registrationGenerationID),
    presentationID,
    currentPresentationAppearanceReported
)

draining(
    logicalSession,
    lease,
    outgoingRegistrationIdentity,
    outgoingPresentationID,
    removalID,
    continuation
)
```

`logicalSession` is carried intact between `owned` and `draining`; otherwise an A → B transfer can forget that queue history was already confirmed. Use an explicit drain continuation:

- `transferSameMessageIfAvailable`: only for route/eligibility loss while the outgoing renderer still reports the same candidate.
- `endSession`: candidate nil, dismissal, expiry, different ID, unrenderable/rebuild failure, or another authoritative invalidation. This continuation must release after terminal and may not resurrect the session from another renderer's stale same-ID report.

A matching late `onAppear` received while `draining` is rejected. If removal starts before the first accepted appearance, the session remains unconfirmed and must not stamp Q3 queue history.

Waiting candidates remain in renderer registration records rather than in a second ownership state. Q3 diagnostics may project a derived wait reason.

Renderer registration records need:

- Renderer ID.
- Registration generation ID.
- Stable registration order.
- Weak renderer target.
- Current candidate state.
- Current eligibility.

The service also needs a non-reentrant, coalescing reconciliation driver. Main-actor isolation serializes actor entry but does not prevent synchronous reentrancy from `show`, `hide`, immediate removal terminals, modal-release handlers, or registration updates. Every checkpoint marks reconciliation dirty; if reconciliation is already running, it returns. The outer loop continues until no dirty work remains. Do not recursively call `reconcile()` from renderer callbacks.

```swift
private func requestRemoteMessageReconciliation() {
    needsRemoteMessageReconciliation = true
    guard !isReconcilingRemoteMessages else { return }

    isReconcilingRemoteMessages = true
    defer { isReconcilingRemoteMessages = false }

    while needsRemoteMessageReconciliation {
        needsRemoteMessageReconciliation = false
        reconcileOneRemoteMessageStep()
    }
}
```

`reconcileOneRemoteMessageStep()` must leave the state valid before invoking any renderer callback. A synchronous callback may only mutate validated state and set the dirty flag; the outer loop observes the result afterward.

Keep the currently selected renderer if it remains eligible and still reports the selected message. Otherwise choose the oldest eligible registration deterministically. The existing host handoff ordering should normally ensure only one eligible renderer, but correctness must not depend on that assumption.

## State transitions

### Registration or renderer update while idle

1. Ignore in legacy mode.
2. Require application-active and foreground-readiness gates already used by Q2.
3. Select the first stable eligible registration with an `.available` candidate.
4. Reconcile stale modal ownership as Q2 currently does.
5. Mint a session ID and acquire the one RMF lease using `(messageID, sessionID)`.
6. In Q3, evaluate the directional cooldown after raw acquisition and before publication. If denied, release the raw lease and publish nothing.
7. Mint a presentation ID, store `owned(...)`, and only then call the renderer so any synchronous callback observes valid state.
8. Call `showRemoteMessage` with the session/presentation identity.
9. `false` must mean atomically that the renderer published no content. Try the next eligible renderer reporting the same message under the retained lease; mint a new presentation ID for each authorization attempt.
10. If all matching renderers reject, release that exact session without stamping and reconcile another candidate.

No blocked attempt may consume RMF shown accounting or cooldown history.

### Appearance

`HomeMessageView` continues to provide the physical mount `onAppear` seam. `onAppear` alone does not prove truthful exposure, so the service must revalidate the host state.

1. The model calls `registration.confirmAppearance(sessionID:presentationID:isAttachedToWindow:)`.
2. The service validates owned—not draining—state, registration generation, session ID, presentation ID, selected renderer ID, current eligibility, window attachment, and that this presentation has not already reported appearance.
3. The service marks this presentation's ordinary appearance accepted.
4. If this is the first accepted presentation in the logical session, the service marks queue appearance confirmed and Q3 synchronously records `lastConfirmedRemoteMessageAppearance`.
5. On every accepted physical presentation, the model calls the existing `HomePageMessagesConfiguration.didAppear` path, preserving current non-unique impression accounting. Duplicate `onAppear` for the same presentation is rejected. The RMF store continues to guard `remoteMessageShownUnique`.
6. Ownership remains unchanged.

If a session transfers before appearing, the successor may provide the first queue confirmation. If it already appeared, a successor's first truthful physical appearance still records the ordinary impression but does not rewrite the queue timestamp.

### Same-message renderer handoff

When selected renderer A becomes ineligible while it still reports the selected candidate, begin a `transferSameMessageIfAvailable` drain:

1. Mint a removal ID.
2. Store `draining(...)` before calling A.
3. Tell A to remove the exact presentation through the OS-specific path.
4. Continue retaining the same lease.
5. Carry the entire logical session, including `queueAppearanceConfirmed`, into `draining`.
6. While draining, registrations may change. Record no second owner; derive a successor when removal finishes.
7. Ignore all non-matching generation/session/presentation/removal callbacks.
8. On matching terminal, wait exactly one main-queue turn for structural settlement.
9. If the continuation permits handoff and an eligible renderer B already reports the same message ID at terminal, mint a new presentation ID, transition to `owned` with the same logical session/lease, and call B's `show`.
10. If B rejects atomically, try the remaining eligible same-ID renderers. If none accepts, release the lease, become idle, and reconcile waiting candidates.
11. If the continuation is `endSession`, always release after terminal. Never transfer that session, even if another registration still reports the same message ID.

Do not reverse an in-flight removal. If A becomes eligible again, it may be selected as the successor after its own removal finishes.

Do not wait an arbitrary extra turn hoping a successor will register. If the matching successor arrives only after terminal processing released the old session, it performs a fresh acquisition and Q3 cooldown check. Existing synchronous host handoff should normally report the successor before the service's post-terminal settlement turn finishes—during the outgoing animation on iOS 17+, or after synchronous withdrawal on iOS 15/16—but this is an optimization rather than a safety assumption.

### Candidate replacement

- Same message ID with changed payload: preserve current behavior by treating the RMF ID as the logical content identity, updating the selected renderer's local view model in place, and retaining session/lease without a new queue confirmation. The renderer must keep the old authorized presentation until the replacement view model has been built; a rebuild failure is `.unrenderable`, starts an `endSession` drain, and must not locally withdraw content while the service still says `owned`. Reusing one RMF ID for materially different campaign content is a data-contract violation and must not be used to bypass admission/accounting.
- Different message ID: drain the old session. After terminal, release it. The replacement must perform a fresh acquisition and Q3 cooldown check; it is not a reclaim.
- Nil candidate/dismissal/expiry: use `endSession`, drain, and release after terminal. Another renderer's stale same-ID report cannot turn this into a handoff.

### No eligible renderer

This plan intentionally chooses the balanced policy rather than tying lifetime to Android's per-collector null callback:

- If a selected renderer becomes ineligible and no successor is available, remove it using the OS-specific path and release after terminal.
- The scheduled RMF may remain in each model's local configuration and can be admitted again later.
- A new session is created on re-admission.

This avoids allowing a hidden/off-route card to block modal promos indefinitely. It also means current exposure/coverage signals remain necessary in this phase.

### Background and foreground

- Application-active and foreground-readiness state gates new acquisition only. Merely entering the background must not synthesize renderer ineligibility and does not release an already owned or draining session.
- No new RMF or modal acquisition begins until current foreground readiness is established.
- If a host independently reports the renderer ineligible or structurally detaches it during background/navigation, the normal drain or authoritative-detachment path still applies.
- A foreground checkpoint reconciles registrations; it must not duplicate an existing session.

### Renderer teardown

- Deregistration while idle removes the registration immediately.
- Deregistration of a non-selected registration removes it immediately and cannot affect the current session.
- Deregistration of the selected owned renderer first marks it ineligible and requests removal. Retain its registration/state until the matching terminal or verified host detachment; retain an asynchronous completion gate only for the iOS 17+ native animation path.
- Deregistration of the outgoing draining renderer marks the registration pending removal; it must not discard the matching state or release the lease. On iOS 17+, it must also retain the native completion gate.
- Normal teardown requests removal and keeps the registration alive until it reports the exact OS-specific terminal.
- On iOS 17+, the removal closure must retain the model or a dedicated completion gate until it reports terminal. The iOS 15/16 terminal is synchronous and needs no retained animation closure.
- If the containing host is already detached from its window, clear the local card and report the exact service-issued removal terminal as `.hostDetached` synchronously/idempotently.
- Registration-token deinitialization must not silently remove a selected/outgoing registration. Explicit `tearDown()` is the production path; unexpected loss fails closed and is diagnosable.
- An unexpectedly deallocated weak target must not cause an optimistic release. Fail closed and emit a diagnostic/assertion; explicit teardown should make this path exceptional.

`NewTabPageViewController.dismiss()` currently tears down the model before removing its view from the window. Preserve host files in phase one by making teardown two-phase: report ineligible, receive `hide`, retain the model/registration/completion gate, clear the matching card, acknowledge the OS-specific removal terminal or later verified detachment, and only then remove the registration record. If that ordering cannot be achieved inside the model/registration, `NewTabPageViewController.swift` becomes a mandatory production edit so it can report exact detachment after removing the view.

### Process termination

- Leases are in-memory and disappear with the process.
- Old UI disappears with the process, so there is no cross-process visible collision.
- Q3 confirmed-appearance timestamps remain the restart protection if persistence succeeded.
- This bounded refactor does not give RMF restoration priority over a modal before an NTP renderer reports its candidate after restart.

## Animation and removal contract

### Verified OS and branch facts

- The iOS application deployment target is currently iOS 15.0 (`iOS/DuckDuckGo-iOS.xcodeproj/project.pbxproj`).
- SwiftUI's completion-aware `withAnimation` overload and `AnimationCompletionCriteria` are available from iOS 17. The installed iOS 26.4 SDK still declares them `@available(iOS 17.0, ...)`; later SwiftUI releases have not back-deployed this API to iOS 15/16.
- Q2 at `9e82601a9f` preserves scale/opacity and uses native SwiftUI `.removed` on iOS 17+.
- The same Q2 endpoint uses synchronous animations-disabled source removal and `.identity` on iOS 15/16; it contains no `CATransaction` fallback.
- Q3 at `9321268231` preserves that Q2 removal contract and adds cooldowns and diagnostics rather than owning animation behavior.

### Why an exact removal terminal is still required

The central logical owner removes nearly all physical bookkeeping, but it cannot release until the outgoing card has stopped contributing pixels. On iOS 17+, logical withdrawal begins a scale/opacity transition whose tail may still be visible. On iOS 15/16, the source item is instead removed with animations disabled before terminal is reported.

Only one physical fact remains necessary:

> The selected outgoing renderer has reached a state in which it can no longer contribute visible promo pixels.

This is one renderer/session/removal acknowledgement, not per-gate or per-mount tracking.

### iOS 17 and later

SwiftUI added completion-aware animation APIs in iOS 17. Use a runtime availability check—the Swift syntax is `if #available(iOS 17, *)`, not a compile-time `#if available` check.

For iOS 17+:

```swift
guard renderedPresentation?.id == presentation.id else { return }

withAnimation(.default, completionCriteria: .removed) {
    renderedPresentation = nil
    publishRenderItems()
} completion: {
    registration.removalDidReachTerminal(
        sessionID: presentation.session.id,
        presentationID: presentation.id,
        removalID: removalID,
        terminal: .animationCompleted)
}
```

Requirements:

- Use `.removed`, not the default `.logicallyComplete`, because the full animation tail must finish.
- Keep exact registration-generation, renderer, session, presentation, and removal validation.
- Retain the model/completion gate until callback.
- Follow the common terminal order below; the service performs the one post-terminal settlement hop.
- Host detachment is also a valid terminal if the exact renderer can no longer be on-screen.

This is the preferred, native solution and removes the SwiftUI completion limitation on iOS 17+.

### iOS 15 and 16

There is no equivalent public SwiftUI completion API on iOS 15/16. Do **not** treat a `CATransaction` wrapped around `SwiftUI.withAnimation` as the correctness boundary. Apple documents completion for Core Animation animations added to that Core Animation transaction; it does not document that a later SwiftUI diff and transition joins the surrounding explicit `CATransaction`. The earlier reviewed fallback was therefore rejected; the final branch contains the synchronous no-animation path instead. Historical context: [PR #6291 discussion](https://github.com/duckduckgo/apple-browsers/pull/6291#discussion_r3762066051).

The chosen policy is therefore to **disable the RMF exit animation on iOS 15/16**. Remove the matching source item during `hide` with SwiftUI animations explicitly disabled, then report `.sourceRemovedWithoutAnimation` through the existing exact terminal API:

```swift
guard renderedPresentation?.id == presentation.id else { return }

var transaction = Transaction(animation: nil)
transaction.disablesAnimations = true
withTransaction(transaction) {
    renderedPresentation = nil
    publishRenderItems()
}

registration.removalDidReachTerminal(
    sessionID: presentation.session.id,
    presentationID: presentation.id,
    removalID: removalID,
    terminal: .sourceRemovedWithoutAnimation)
```

Requirements:

- Select this path with `if #available(iOS 17, *) { ... } else { ... }`.
- Use `.identity` as the RMF removal transition on iOS 15/16. Do not attach the scale/opacity transition, call `withAnimation`, create an `Animatable` observer, wrap SwiftUI in `CATransaction`, or wait for an elapsed duration there.
- Clear only the exact authorized presentation, with animations disabled, before reporting terminal.
- Report `.sourceRemovedWithoutAnimation` exactly once. A stale presentation/removal identity is a no-op.
- The service is already in `draining` before it calls `hide`, so this synchronous callback is safe only through the non-reentrant/coalescing reconciliation loop.
- Continue retaining the lease until the service's one post-terminal main-queue settlement turn completes. Do not authorize a modal or successor directly inside the synchronous callback.
- Verified host detachment remains an alternative exact terminal if teardown detached the renderer first.

This intentionally trades the exit visual on the two oldest supported OS versions for a smaller and more reliable correctness boundary. There is no pre-iOS-17 animation driver, progress state, timer, or completion observer to maintain.

### Common terminal order on every OS

Use one sequence:

1. Reach the OS-specific terminal: SwiftUI `.removed` on iOS 17+, matching source-item removal with animations disabled on iOS 15/16, or verified exact host detachment.
2. Clear the matching source item without animation if it is still present.
3. Report the exact `(registrationGenerationID, rendererID, sessionID, presentationID, removalID, terminalReason)` to the service.
4. The service waits exactly one main-queue turn for SwiftUI structural settlement.
5. The service transfers or releases according to the stored drain continuation.

The renderer must not add a second post-terminal settlement delay. The one explicit correctness settlement hop is step 4. On iOS 15/16 the renderer may report terminal synchronously from `hide`; on iOS 17+ the native completion reports it asynchronously.

The main-queue hop is structural settlement after an exact terminal fact, not a timer or substitute for animation completion. If the exact iOS 15/16 presentation could not be cleared, do not report `.sourceRemovedWithoutAnimation`; retain ownership unless exact host detachment is proven.

The renderer-local presentation state contains the current presentation and one removal identity/completion gate needed by the iOS 17+ callback. No pre-iOS-17 progress or mount state is required. If `show` is followed by `hide` before the first mount, iOS 17's completion fires even when no animation is created, while iOS 15/16 clears synchronously. A delayed `onAppear` for that cleared presentation is rejected by presentation identity and draining state.

Never use a fixed delay as the release terminal. The service settlement hop occurs only after an exact terminal fact. If an old-OS animation is ever restored with a UIKit animator, a deadline may only force that concrete animator to its end and physically detach its container; elapsed time alone is not proof of non-visibility.

## Candidate authority in this bounded refactor

Do not introduce a new app-scoped Remote Messaging source in Q2.

Each `NewTabPageMessagesModel` continues to:

- Refresh `HomePageMessagesConfiguration` with its existing `openedAfterIdle` context.
- Retain its current local RMF candidate and payload.
- Report candidate message ID and eligibility to its registration.
- Build the `HomeMessageViewModel` only when the service authorizes its matching candidate.
- Execute existing dismiss/action/accounting behavior.

Because normal and after-idle NTP models may report different candidates, use these deterministic rules:

- While owned/draining, the selected message ID is pinned.
- Same-ID eligible renderers may become successors.
- Different IDs wait; they never join the current lease.
- While idle, stable registration order chooses the first eligible candidate.
- A different candidate after release performs normal fresh admission.

This is intentionally smaller than extracting an authoritative source. If future behavior requires an RMF to retain priority while no NTP model exists, or requires deterministic global selection independent of renderer activation order, that is a separate follow-up requiring a central source.

## Existing host behavior retained in phase one

Keep the current `NewTabPagePromoSurfaceExposure` calculation and the existing calls in:

- `iOS/DuckDuckGo/NewTabPageViewController.swift`
- `iOS/DuckDuckGo/MainViewController.swift`
- `iOS/DuckDuckGo/SuggestionTrayViewController.swift`
- `iOS/DuckDuckGo/UnifiedToggleInput/MainViewController+UnifiedToggleInput.swift`
- `iOS/DuckDuckGo/UnifiedToggleInput/Suggestions/UnifiedSuggestionsHost.swift`
- `iOS/DuckDuckGo/UnifiedToggleInput/UnifiedInputContentContainerViewController.swift`

Reinterpret their output:

- Today, `setSurfaceRenderable` causes a model to acquire/withdraw its own lease.
- After this refactor, it updates the renderer registration's eligibility.
- The service decides whether to retain, transfer, drain, or acquire.

The host handoff still deactivates outgoing before activating incoming. Removal is asynchronous on iOS 17+ and synchronous on iOS 15/16, but the service's one settlement hop leaves a bounded window for the synchronous host handoff to register a same-ID successor before reconciliation. The service retains the lease throughout. If a host deliberately delays activation until after terminal processing releases the old session, it receives a fresh admission under the documented balanced-lifetime policy.

Host cleanup is a later optional phase after the central state machine has proven stable. Do not mix it into this change.

## File-by-file implementation map

All mandatory production changes are confined to files already added or modified by PR1–Q3.

### `iOS/DuckDuckGo/AppServices/PromoCoordinationService.swift`

Add:

- Weak renderer registration records.
- Stable registration ordering.
- Registration-generation validation.
- The `idle / owned / draining` state enum.
- Central selection and reconciliation.
- A non-reentrant/coalescing reconciliation driver.
- Service-owned strong RMF lease.
- Central appearance confirmation.
- Same-session renderer transfer.
- Exact session/removal callback guards.
- Derived diagnostics suitable for Q3.

Replace:

- `WeakRemoteMessageRetryRegistration` retry semantics.
- `retryActiveRemoteMessageRegistrations` iteration as independent admission attempts.
- `offerRemoteMessageReleaseHandoff(excluding:)`.
- Per-model `admitRemoteMessage` ownership.
- `makeRemoteMessageAdmission`.

Retain:

- App/foreground/readiness checkpoints.
- Modal reconciliation and acquisition.
- Modal-release callback as an RMF reconciliation checkpoint.
- Process-latched `PromoCoordinationMode`.

### `iOS/DuckDuckGo/ModalPromptCoordination/NewTabPagePromoCoordination.swift`

Remove/replace:

- `PromoQueueRemoteMessageAdmissionResult`.
- `PromoQueueRemoteMessageAdmission`.
- `PromoQueueRemoteMessageAdmissionHandler`.
- `NewTabPagePromoRetrying`.
- `NewTabPagePromoRetryRegistration` as a retry token.
- `admitRemoteMessage` and `registerRemoteMessageRetry`.

Add the renderer, session, and registration contracts described above. Registration remains idempotently removable.

### `iOS/DuckDuckGo/ModalPromptCoordination/Arbitration/PromoQueueLeaseArbiter.swift`

Retain:

- One global owner.
- Modal attempt identity.
- Weak-token abandoned-owner pruning.
- Per-acquisition stale-safe release ID.

Change:

- Replace renderer-bound `VisiblePromoIdentity(surfaceID, promoType, promoID)` with logical RMF identity `(messageID, sessionID)`.
- Rename `visible` terminology to `remoteMessage` or `logicalRemoteMessage` where practical.
- Keep renderer ID out of the arbiter.

Only the service acquires the RMF lease. Multiple renderers never ask the arbiter to reclaim it.

### `iOS/DuckDuckGo/NewTabPageMessagesModel.swift`

Keep:

- Local message snapshot and RMF candidate.
- Existing message actions, image loading, and pixels.
- `isLoaded`, teardown, eligibility inputs, and attachment provider.
- A single authorized presentation and one iOS 17+ removal-completion gate. The iOS 15/16 path needs exact identity validation but no animation gate or progress state.
- Legacy feature-off path exactly.

Remove:

- Per-model raw admission/lease.
- `AdmittedRemoteMessageSession` as an ownership object.
- `OutgoingAdmittedRemoteMessageSession` dictionary.
- Gate identity.
- Visible/pending gate and card mount-ID sets.
- `remoteMessageGateDidAppear`.
- `remoteMessageGateDidBeginRemoval`.
- `remoteMessageGateDidDisappear`.
- `remoteMessageCardDidAppear`.
- `remoteMessageCardDidBeginRemoval`.
- `remoteMessageDidDisappear`.
- `completePhysicalRemoval*` helper graph.
- Per-model retry conformance and admission attempts.

Add:

- One renderer registration.
- Candidate/eligibility reporting.
- `showRemoteMessage(presentation)` that validates the local candidate, builds the view model, and publishes one authorized presentation atomically or returns `false` without publishing anything.
- `hideRemoteMessage(presentation, removalID)` using native `.removed` on iOS 17+ and synchronous animations-disabled source removal on iOS 15/16.
- Central appearance confirmation before ordinary `didAppear` accounting.
- Authoritative host-detachment completion.

### `iOS/DuckDuckGo/NewTabPageView.swift`

Remove:

- Empty coordinated gate.
- `RemoteMessageGateMountView`.
- Gate/card mount IDs.
- Gate/card `onDisappear` lifecycle callbacks.

Render the one centrally authorized session directly. Retain:

- `HomeMessageView`.
- Existing maximum width.
- An OS-conditional removal transition: scale combined with opacity on iOS 17+, `.identity` on iOS 15/16. Do not introduce or change insertion animation semantics in this refactor.
- `HomeMessageView`'s real `onAppear` callback.
- Synchronous removal with animations disabled on iOS 15/16; no pre-iOS-17 progress modifier or animation completion observer.

### Files expected to remain source-identical in the minimal pass

- `iOS/DuckDuckGo/HomePageConfiguration.swift`
- `iOS/DuckDuckGo/HomePageMessagesConfiguration.swift`
- `iOS/DuckDuckGo/HomeMessageView.swift`
- Shared Remote Messaging store code.
- Host files listed in the preceding section, except for test/mocking adjustments that prove unchanged behavior.

No new production file or project-file entry is required if the state/contracts remain in the existing Q-touched files. A small dedicated file is acceptable for clarity, but is not required and should not turn into a second app-scoped coordinator.

### Compile-impact map

Update the protocol mocks and local conformers in the same commits:

- `iOS/SharedTestUtils/Mocks/DuckDuckGo/ModalPromptCoordination/MockNewTabPagePromoCoordinator.swift`
- The preview coordinator in `iOS/DuckDuckGo/NewTabPageView.swift`
- Local conformers in `NewTabPageMessagesModelTests.swift`
- Local conformers in `UnifiedInputContentContainerViewControllerTests.swift`
- Local conformers in `ModalPromptCoordinationManagerIntegrationTests.swift`

Resolve the exact test paths from the repository if they have moved. Update every `NewTabPagePromoCoordinating`/registration conformance rather than leaving an adapter for the deleted admission API.

## Q2 implementation outcome

The redesign landed as three coherent commits on Q2:

### `ea66bd7bef` — Centralize logical RMF session ownership

- Introduce logical session identity.
- Update the arbiter identity/snapshot.
- Replace admission/retry contracts with renderer registration.
- Implement service state and selection.
- Keep visuals temporarily compiling through a thin adapter if necessary.

### `ea60ee258d` — Replace logical RMF lifecycle coverage

- Remove per-model lease and gate/mount state.
- Render only a service-authorized session.
- Implement appearance confirmation.
- Restore scale/opacity in Q2 on iOS 17+ only.
- Add iOS 17 native `.removed` completion.
- Add synchronous animations-disabled source removal on iOS 15/16.
- Remove the old physical-callback graph.

### `9e82601a9f` — Cover logical RMF session integration

- Replace tests that encode per-model ownership with central service tests.
- Add renderer/model, iOS 17+ animation-driver, and iOS 15/16 synchronous-removal tests.
- Cover real transition completion, synchronous/no-animation completion, stale completion, teardown retention, and rapid removal/reinsertion.
- Retain host integration tests that remain behaviorally relevant.
- Remove obsolete gate/mount permutation tests.

Do not leave both old and new ownership routes after any final commit.

## Q3 adaptation outcome

Q3 was rebased onto the completed central-owner Q2 and now contains five commits:

| Q3 commit | Implemented responsibility |
|---|---|
| `02ae39b217` | Fixed directional cooldown policy and persisted RMF history. |
| `a1207bf6ef` | Owner-first cooldown integration and service-owned logical-session appearance confirmation. |
| `a770166f88` | Read-only central-owner diagnostics. |
| `75717015b3` | Side-effect-free diagnostic projection. |
| `9321268231` | Focused Promo Queue time-limit coverage. |

The adapted branch does not retain the removed per-model admission, gate/mount, outgoing-session, or pre-iOS-17 animation-completion architecture.

Q3 must preserve:

- Modal → RMF: 10 minutes.
- RMF → RMF: 10 minutes.
- RMF → Modal: 24 hours.
- Existing modal → modal behavior.
- Confirmed-appearance timestamp anchor.
- Acquire before cooldown/provider/RMF publication side effects.
- Checkpoint-only retry; no boundary timers.
- In-process RMF timestamp cache before attempted persistence.
- Legacy mode avoiding all new history reads and writes.

Q3 diagnostic state exposes:

- Logical RMF state: idle/owned/draining.
- Message ID and session ID.
- Selected/outgoing renderer ID plus registration generation.
- Current/outgoing presentation ID.
- Queue-appearance-confirmed and current-presentation-accounted states.
- Current removal ID.
- Removal path/terminal reason (`animationCompleted`, `sourceRemovedWithoutAnimation`, or `hostDetached`).
- Drain continuation/reason.
- Registered/eligible renderer counts.
- Arbiter owner.
- Persisted source timestamps and derived next-eligible boundaries.

It should no longer expose per-gate or per-card mount sets.

## Test plan

### Arbiter tests

- One modal or logical RMF owner globally.
- Logical identity contains message/session but no renderer.
- Stale/double RMF lease release cannot clear its replacement.
- Abandoned-token pruning remains safe.

### Central service state tests

- Candidate is acquired before renderer publication.
- Modal owner blocks all RMF publication.
- A renderer rejection releases without appearance accounting.
- Only one eligible renderer is authorized when several exist.
- Same message A → B retains one session and one lease.
- B is not shown before A's matching terminal.
- A same-ID successor rejection publishes nothing; the next matching renderer is tried, or the lease releases if all reject.
- Different message B waits for A release and performs fresh admission.
- Queue history confirms once across renderer transfer; ordinary RMF accounting fires once for each accepted physical presentation; unique accounting remains store-guarded.
- Confirming appearance does not release or drain waiters.
- Authorization followed by eligibility loss/window detachment before delayed `onAppear` rejects that appearance.
- Hide before first appearance clears safely and never stamps queue history.
- A card retained beyond 10 minutes and 24 hours still blocks another RMF/modal once Q3 is rebased.
- Selected renderer becoming ineligible with no successor enters draining, then releases.
- A becoming eligible again during its drain is reconsidered only after terminal.
- Duplicate/stale removal callbacks do nothing.
- Stale A callback cannot release session B, even for the same message ID.
- Missing terminal retains ownership and blocks modal/new RMF.
- Verified renderer detachment acts as one terminal; a late iOS 17+ animation completion or duplicate iOS 15/16 synchronous terminal is inert.
- Candidate nil/dismissal drains before release.
- A non-selected renderer's nil candidate, teardown, or stale update cannot affect the selected session.
- Candidate dismissal uses `endSession`; another renderer's stale same-ID candidate cannot resurrect it.
- Candidate A → B never treats B as a reclaim.
- Background alone retains an existing owner; an independent host `isEligible = false` update during background follows the normal drain policy; foreground does not duplicate it.
- Modal release/readiness/foreground checkpoints reconcile registrations deterministically.
- Synchronous registration updates or show/hide/terminal callbacks dirty the non-reentrant reconciliation loop without recursive transition or duplicate lease activity.
- A stale registration generation cannot update or deregister its replacement.
- Stale detachment from an earlier presentation/generation cannot finish a renderer selected again under the same logical session.
- Teardown before window removal retains the old registration/state until the exact OS-specific terminal or later verified detachment.
- Unexpected weak-target loss fails closed and is diagnosable.
- Feature-off models never call service registration; any local token-shaped dependency is a no-op and changes no behavior.
- With Q3 applied, a confirmed RMF drained for route loss is blocked by its own 10-minute RMF cooldown on immediate return; an unconfirmed session is not stamped and does not create that cooldown.

### `NewTabPageMessagesModel` tests

- Coordinated model reports candidate and eligibility but never acquires directly.
- It publishes nothing until authorized by the service.
- It rejects authorization for a stale candidate.
- It builds one matching `HomeMessageViewModel` after authorization.
- Matching `onAppear` confirms once; stale/duplicate appearance is ignored.
- `onAppear` after authorization withdrawal is rejected.
- Same-ID payload update preserves session.
- Same-ID rebuild failure retains old content until the service issues an `endSession` hide.
- On iOS 17+, hide retains the completion path through native `.removed`; on iOS 15/16, hide clears the exact local presentation synchronously while the service remains draining through its settlement hop.
- Show-then-hide-before first mount completes through the native no-animation completion on iOS 17+ or synchronous clear on iOS 15/16.
- Teardown retains the completion path or proves host detachment.
- Legacy model preserves eager refresh accounting and direct rendering.

### Removal-lifecycle tests independent of OS

Use a controllable removal terminal driver:

- The service stores `draining` before invoking `hide`, so a synchronous iOS 15/16 terminal is reentrancy-safe.
- Hide enters draining and retains lease before terminal.
- Matching terminal transfers/releases only on the next main turn.
- Immediate/no-animation terminal preserves mutation → terminal → release ordering.
- No modal or successor is authorized before the post-terminal settlement hop.
- Delayed successor registration after terminal receives a fresh session/admission rather than reviving the released session.
- Duplicate and stale completion IDs are ignored.
- Rapid remove/reinsert cannot let an old iOS 17+ completion or stale iOS 15/16 terminal remove the new session.

### iOS 17+ real SwiftUI tests

Use a real `UIWindow` and `UIHostingController` with a visibility probe inside the card:

- Before removal, the probe is attached and modal acquisition is blocked.
- During removal, the lease remains held.
- `.removed` completion occurs before transfer/release.
- At release on the following turn, the outgoing probe is no longer visibly attached.
- `animation: nil` completes once in the same safe order.
- Default animation tests event ordering rather than wall-clock duration.
- Rapid removal/reinsertion makes the old completion inert.

Run on at least one iOS 17 runtime and the current CI runtime.

### iOS 15/16 synchronous-removal tests

- The exact authorized presentation is cleared during `hide` before terminal is reported.
- The renderer selects `.identity`, not the scale/opacity removal transition.
- The SwiftUI transaction has `animation == nil` and `disablesAnimations == true`, preventing inherited or implicit exit animation.
- `.sourceRemovedWithoutAnimation` is emitted exactly once with the full service-issued identities.
- The service retains the lease until the following main-queue settlement turn.
- A successor RMF and modal remain blocked before that settlement turn.
- The synchronous callback is coalesced without recursive reconciliation or duplicate lease activity.
- A stale/mismatched hide cannot clear a replacement presentation or release its session.
- Exact host detachment and synchronous removal are idempotent alternatives; whichever arrives second is ignored.
- A delayed `onAppear` is rejected after the matching presentation was cleared.
- Show-then-hide-before first mount needs no modifier or animation callback.
- If the exact presentation cannot be cleared, no terminal is reported and ownership fails closed unless host detachment is proven.

Normal CI currently selects a modern simulator and will not naturally exercise the availability branch. Force the iOS 15/16 path through dependency injection on the current runtime and run at least one real-window smoke test on an actual iOS 15.x or iOS 16.x runtime, preferably the iOS 15 minimum. Assert that there is no exit animation, the outgoing probe is non-visible before release, and the next owner is admitted only after the service settlement hop.

### Host/integration scenarios

- Standard NTP → suggestion tray favorites → standard NTP.
- Standard NTP → unified-input favorites → standard NTP.
- Popover/overlay cover and uncover.
- Rapid stale visibility-generation completion.
- Tab switch and navigation away.
- Background and foreground.
- Multiple cached NTP controllers.
- Renderer recreation with the same candidate.
- Immediate host detachment and delayed successor registration.
- Normal and after-idle renderers reporting different candidate IDs.
- Long-lived modal blocks RMF until exact UIKit root detachment.
- Long-lived RMF blocks modal for its entire owned/draining lifetime.

## Tests to delete or rewrite

Delete tests whose only subject disappears:

- Gate mount ID balancing.
- Card mount reference counting.
- Pending mount retention.
- Multiple outgoing-session dictionaries.
- Stale `onDisappear` callbacks for gate/card mounts.
- Per-model raw admission release and retry-registration handoff.

Do not delete scenario coverage merely because the old mechanism disappears. Rewrite the corresponding behavior at the central service/renderer boundary.

## Failure policy

| Failure | Required behavior |
|---|---|
| Renderer show rejects stale candidate | Publish nothing, release/cancel without timestamp, reconcile again. |
| Duplicate appearance for one presentation | Ignore after its first successful ordinary-accounting call; queue history remains once per logical session. |
| Stale registration generation | Ignore its update, confirmation, terminal, or deregistration. |
| Stale session callback | Ignore. |
| Stale removal callback | Ignore. |
| Matching OS-specific removal terminal missing | Retain lease; block successors; emit diagnostic. |
| iOS 15/16 exact source item cannot be cleared | Do not report `.sourceRemovedWithoutAnimation`; fail closed unless exact host detachment is proven. |
| Renderer host verified detached | Treat as terminal once; late callbacks no-op. |
| Persistence write fails in Q3 | RMF attempted value remains authoritative in-process; live lease remains independent. |
| Process terminates | In-memory lease ends with old UI; rely on last durable confirmed timestamp on restart. |
| Two candidates differ | Current owned ID remains pinned; different ID waits for fresh admission. |
| Flag disabled | Do not register, acquire, read history, or alter legacy output/accounting. |

Do not introduce a timeout that calls `lease.release()`. A timeout would turn a liveness repair into a possible visible collision. If bounded liveness later becomes mandatory, force a concrete renderer to a verified non-visible/detached state first, then report terminal.

## Acceptance criteria

The Q2 redesign is complete only when:

- There is exactly one app-scoped RMF ownership state.
- Only `PromoCoordinationService` holds the RMF lease.
- At most one renderer publishes the logical session.
- Same-message handoff uses one lease and waits for outgoing removal.
- Different-message replacement performs fresh admission.
- Queue history confirms once per logical session, ordinary accounting runs once per accepted physical presentation, and neither releases ownership.
- Modal lifetime remains exact-root based.
- Scale/opacity removal remains on iOS 17+.
- iOS 17+ uses native `.removed` completion.
- iOS 15/16 clears the exact source item with animations disabled, reports `.sourceRemovedWithoutAnimation`, and retains the lease through one service-owned settlement hop.
- iOS 15/16 has no `CATransaction`, `Animatable` completion observer, progress state, or delay-based release.
- An iOS 15/16 exact-clear mismatch/error fails closed.
- Old gate/mount/outgoing-session ownership machinery is deleted.
- Existing host exposure calls still select eligibility and retain current behavior.
- Legacy mode is unchanged and coordinator work remains dormant.
- Q2 contains no Q3 persisted cooldown policy.
- Replacement tests cover the removed behavior at the new central boundary.

With the implemented Q3 layer, also require:

- Directional cooldowns use confirmed appearance.
- A still-owned card blocks after cooldown expiry.
- A still-present modal blocks after cooldown expiry.
- Diagnostics describe logical session/renderer state rather than mounts.
- History write/read failure and process reconstruction behavior remain explicit.

## Manual QA checklist

- Verify legacy flag-off behavior first.
- Verify one RMF card on standard NTP.
- Exercise suggestion-tray and unified-input handoffs slowly and rapidly.
- Cover/uncover with popovers and Dax overlays.
- Switch tabs and navigate away during publication and removal.
- Background during an owned session and during drain.
- Dismiss/act on the RMF during handoff.
- Exercise reduce-motion and disabled-animation configurations.
- Verify immediate no-animation removal and one-hop settlement on iOS 15/16.
- Verify scale/opacity plus native `.removed` ordering on iOS 17 and the current simulator OS.
- Keep a modal visible beyond ten minutes and verify RMF remains blocked.
- Keep an RMF visible beyond 24 hours and verify modal remains blocked.
- Confirm one ordinary impression per accepted physical presentation, one queue timestamp per logical session, and store-guarded unique accounting during same-session renderer transfer.

## Expected size reduction

At current Q3 head, the stacked feature diff from the Q2/main merge base `bd65c05015` is approximately:

| Area | Current net change |
|---|---:|
| Production | +2,300 LOC |
| Tests/integration tests | +4,350 LOC |
| Total | +6,660 LOC |

Expected result of this redesign, including rewritten tests:

- Net reduction: approximately 800–1,450 LOC.
- Point estimate: approximately 1,150 fewer LOC.
- Expected final stacked feature size: approximately +5,200 to +5,860 net LOC.
- Expected implementation churn: roughly 1,350–2,150 added and 2,400–3,500 deleted lines.

The largest savings should come from `NewTabPageMessagesModel` and its tests. Retained host integrations are now the main scope constraint; removing the pre-iOS-17 animation driver shortens both the implementation and its correctness proof.

Treat these as planning estimates, not acceptance criteria. The desired result is fewer independent states and a shorter safety proof, not deletion for its own sake.

## Follow-up opportunities, explicitly deferred

After the central controller ships and proves stable, separately consider:

- Replacing the five-way host exposure fold with one router-selected renderer ID.
- Extracting a single authoritative app-scoped RMF source.
- Retaining logical ownership while no NTP route exists, if product accepts hidden-card modal starvation.
- Moving one physical hosted card between NTP slots.
- Removing duplicate RMF fetches from `HomePageConfiguration`.
- Restoring an iOS 15/16 exit animation with a separately proven mechanism, such as a UIKit-owned animated container, if product requirements change.
- Raising the deployment target to iOS 17+, after which the availability split and synchronous legacy branch can be removed.

None of these are prerequisites for the bounded Q2 simplification described here.

## Documentation outcome

The current architecture and stable commit identities are reflected in:

- `TECH_DESIGN_FINAL.md`: branch/PR status, logical owner, renderer selection, animation split, state machine, failure policy, diagnostics, and tests.
- `IMPLEMENTATION_PLAN.md`: actual branch topology and final Q2/Q3 commit map.
- `Q3_IMPLEMENTATION_PLAN.md`: central-session acquisition/confirmation and removal of per-model admissions.
- `ADDING_PROMOS.md`: candidate/renderer registration, appearance, ownership, and host rules.
- point-in-time research and review artifacts through explicit supersession notes rather than silent historical rewrites.

Correct the Android description in those documents: every non-null NTP Flow emission attempts/reclaims the type-level `NTP_CARD` slot, every null emission calls `onClaimDone`, and collector/ViewModel cancellation does not release; appearance does not release; modal ownership is released on show; same-type concurrent NTP reclaims are granted; the NTP coordinator timestamp is anchored to that null callback rather than a proven app-global logical disappearance; and the live claim does not survive process death.

## Reviewer summary

The implementation should be explainable in these terms:

> We adopted Android's useful abstraction—one app-scoped logical NTP promo owner—but not its type-only reclaim or modal release semantics. One service owns the RMF lease and authorizes one renderer. Appearance records history but does not release. Renderer handoff retains the same lease until native `.removed` on iOS 17+ or synchronous animations-disabled source removal plus one settlement hop on iOS 15/16. This eliminates per-model admissions, gate/card mount IDs, pre-iOS-17 animation-completion machinery, and outgoing-session bookkeeping while keeping existing host exposure as renderer eligibility.
