//
//  ModalPromptCoordinationManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit

@MainActor
protocol ModalPromptCoordinationManaging {
    var didPresentModalPromptThisSession: Bool { get }

    func setCoordinatedAttemptReleaseHandler(_ handler: (@MainActor () -> Void)?)
    func presentModalPromptIfNeeded(from presenter: ModalPromptPresenter)
    func presentModalPromptIfNeeded(
        from presenter: ModalPromptPresenter,
        with lease: PromoQueueModalLease
    ) -> ModalPromptLeaseDisposition
    func reconcilePresentedModal() -> Bool
    func promoQueueWillTransition(to targetState: PromoQueueFeatureTargetState)
    func promoQueueDidTransition(to targetState: PromoQueueFeatureTargetState)
    func applicationWillResignActive()
    func applicationDidBecomeActive()
    func applicationDidEnterBackground()
}

enum ModalPromptLeaseDisposition: Equatable {
    /// The manager retained the lease for pending or active modal work.
    case retained
    /// The manager released the lease because no coordinated modal work remains.
    case released
}

enum ModalPromptAttemptPhase: Equatable {
    /// No coordinated modal attempt owns a lease.
    case idle
    /// Providers are being evaluated for the identified lease acquisition.
    case evaluating(PromoQueueModalAttemptIdentity)
    /// A prepared modal is waiting for its scheduled presentation attempt.
    case committed(PromoQueueModalAttemptIdentity)
    /// UIKit handoff is being verified or the presented root has been accepted.
    case presentationActive(PromoQueueModalAttemptIdentity)
}

/// Manages the coordination and presentation of modal prompts based on priority and cooldown rules.
///
/// This manager is responsible for:
/// - Enforcing global cooldown periods between modal presentations.
/// - Presenting the first eligible modal.
/// - Track when modals were last presented.
///
/// App-lifecycle concerns, such as launch source checks, belong to `PromoCoordinationService`.
@MainActor
final class ModalPromptCoordinationManager: ModalPromptCoordinationManaging {
    // MARK: - Attempt Model

    /// A prepared prompt paired with its provider and idempotent presentation accounting.
    private final class PreparedItem {
        let configuration: ModalPromptConfiguration
        let provider: any ModalPromptProvider
        var didRecordPresentation = false

        init(configuration: ModalPromptConfiguration, provider: any ModalPromptProvider) {
            self.configuration = configuration
            self.provider = provider
        }
    }

    /// Retains the exact root during UIKit handoff and weakly tracks the presenter and intended host.
    private final class VerifyingPresentation {
        let preparedItem: PreparedItem
        let exactRoot: UIViewController
        weak var presenter: ModalPromptPresenter?
        weak var intendedHost: UIViewController?

        init(
            preparedItem: PreparedItem,
            exactRoot: UIViewController,
            presenter: ModalPromptPresenter,
            intendedHost: UIViewController?
        ) {
            self.preparedItem = preparedItem
            self.exactRoot = exactRoot
            self.presenter = presenter
            self.intendedHost = intendedHost
        }
    }

    /// Weakly tracks an accepted root so sparse reconciliation does not retain dismissed UI.
    private final class WeakPresentedRoot {
        private(set) weak var viewController: UIViewController?

        init(_ viewController: UIViewController) {
            self.viewController = viewController
        }
    }

    /// The UIKit host path selected immediately before coordinated presentation.
    private enum PresentationRoute {
        /// Present through the supplied presenter, optionally exposing its UIKit host for attachment validation.
        case presenter(UIViewController?)
        /// Present directly over the currently attached OmniBar editing controller.
        case omniBar(UIViewController)

        var intendedHost: UIViewController? {
            switch self {
            case .presenter(let host):
                return host
            case .omniBar(let host):
                return host
            }
        }
    }

    private struct CoordinatedAttempt {
        let lease: PromoQueueModalLease
    }

    private struct CommittedAttempt {
        let attempt: CoordinatedAttempt
        let preparedItem: PreparedItem
        let presenter: ModalPromptPresenter
    }

    private struct PresentationActiveAttempt {
        enum State {
            /// UIKit received the root, but physical attachment or completion has not yet confirmed presentation.
            case verifying(VerifyingPresentation)
            /// The exact root was observed attached and is now tracked weakly until dismissal.
            case accepted(WeakPresentedRoot)
        }

        let attempt: CoordinatedAttempt
        let state: State

        var exactRoot: UIViewController? {
            switch state {
            case .verifying(let presentation):
                return presentation.exactRoot
            case .accepted(let root):
                return root.viewController
            }
        }
    }

    private enum AttemptState {
        /// No coordinated attempt owns a lease.
        case idle
        /// Holds the lease while providers are evaluated.
        case evaluating(CoordinatedAttempt)
        /// Holds the prepared prompt and lease until scheduled presentation begins.
        case committed(CommittedAttempt)
        /// Holds the lease while UIKit handoff is verified or the accepted root remains attached.
        case presentationActive(PresentationActiveAttempt)
    }

    // MARK: - Dependencies

    private let providers: [any ModalPromptProvider]
    private let cooldownManager: PromptCooldownManaging
    private let scheduler: ModalPromptScheduling
    private let onboardingStatusProvider: ContextualDaxDialogStatusProvider
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbitrating
    private let rootAttachmentChecker: ModalPromptRootAttachmentChecking

    // MARK: - State

    private var attemptState = AttemptState.idle
    private var pendingPreparedItem: PreparedItem?
    private var scheduledPresentationTask: ModalPromptScheduledTask?
    private var attachmentVerificationTask: ModalPromptScheduledTask?
    private var attachmentVerificationRequestID: UUID?
    private var legacyActiveAttemptIDs = Set<UUID>()
    /// The latest exact root handed to UIKit, used to adopt an attached presentation when coordination enables.
    private weak var lastPresentedExactRoot: UIViewController?
    private var isPromoQueueEnabled = false
    /// Safe to seed as active: the app state machine runs `Foreground.didReturn()` synchronously right after
    /// `onTransition()`, so `applicationDidBecomeActive()` lands before a scheduled presentation's 0.1s delay
    /// can reach its fire-time validation.
    private var isApplicationActive = true

    private(set) var didActuallyPresentModalPromptThisSession = false
    private var coordinatedAttemptReleaseHandler: (@MainActor () -> Void)?

    var didPresentModalPromptThisSession: Bool {
        didActuallyPresentModalPromptThisSession || hasActiveOrPendingModalAttempt
    }

    var hasActiveOrPendingModalAttempt: Bool {
        !legacyActiveAttemptIDs.isEmpty || modalAttemptPhase != .idle || pendingPreparedItem != nil
    }

    var modalAttemptPhase: ModalPromptAttemptPhase {
        switch attemptState {
        case .idle:
            return .idle
        case .evaluating(let attempt):
            return .evaluating(attempt.lease.attemptIdentity)
        case .committed(let committedAttempt):
            return .committed(committedAttempt.attempt.lease.attemptIdentity)
        case .presentationActive(let activeAttempt):
            return .presentationActive(activeAttempt.attempt.lease.attemptIdentity)
        }
    }

    // MARK: - Initialization

    init(
        providers: [any ModalPromptProvider],
        cooldownManager: PromptCooldownManaging,
        onboardingStatusProvider: ContextualDaxDialogStatusProvider,
        promoQueueLeaseArbiter: PromoQueueLeaseArbitrating,
        // Optional rather than a default argument: `ModalPromptScheduler` is `@MainActor`, and default
        // argument expressions are evaluated in a nonisolated context.
        modalPromptScheduling: ModalPromptScheduling? = nil,
        rootAttachmentChecker: ModalPromptRootAttachmentChecking? = nil
    ) {
        self.providers = providers
        self.cooldownManager = cooldownManager
        self.onboardingStatusProvider = onboardingStatusProvider
        self.promoQueueLeaseArbiter = promoQueueLeaseArbiter
        self.scheduler = modalPromptScheduling ?? ModalPromptScheduler()
        self.rootAttachmentChecker = rootAttachmentChecker ?? ModalPromptRootAttachmentChecker()
    }

    // MARK: - Lifecycle

    /// Clears legacy and coordinated bookkeeping before either feature-state transition direction.
    func promoQueueWillTransition(to targetState: PromoQueueFeatureTargetState) {
        isPromoQueueEnabled = false
        latchActualPresentationHistoryIfModalIsAttached()
        pendingPreparedItem = nil
        legacyActiveAttemptIDs.removeAll()
        releaseCoordinationAttempt()
    }

    func promoQueueDidTransition(to targetState: PromoQueueFeatureTargetState) {
        isPromoQueueEnabled = targetState == .enabled
        guard targetState == .enabled,
              let lastPresentedExactRoot,
              isExactRootAttached(lastPresentedExactRoot),
              case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            return
        }

        attemptState = .presentationActive(
            PresentationActiveAttempt(
                attempt: CoordinatedAttempt(lease: lease),
                state: .accepted(WeakPresentedRoot(lastPresentedExactRoot))
            )
        )
    }

    func applicationWillResignActive() {
        isApplicationActive = false
    }

    func applicationDidBecomeActive() {
        isApplicationActive = true

        guard case .presentationActive(let activeAttempt) = attemptState,
              case .verifying(let presentation) = activeAttempt.state else {
            return
        }

        scheduleAttachmentVerification(
            attemptIdentity: activeAttempt.attempt.lease.attemptIdentity,
            exactRoot: presentation.exactRoot
        )
    }

    func applicationDidEnterBackground() {
        isApplicationActive = false

        guard case .committed(let committedAttempt) = attemptState else {
            return
        }

        pendingPreparedItem = committedAttempt.preparedItem
        cancelScheduledPresentation()
        attemptState = .idle
        committedAttempt.attempt.lease.release()
    }

    func setCoordinatedAttemptReleaseHandler(_ handler: (@MainActor () -> Void)?) {
        coordinatedAttemptReleaseHandler = handler
    }

    // MARK: - Presentation

    /// Attempts to present a modal prompt if one is eligible.
    ///
    /// The manager will:
    /// 1. Check cooldown period and skip presenting if it is active.
    /// 2. Iterate through providers in priority order.
    /// 3. Check if provider has a modal to show.
    /// 4. Present the first eligible modal.
    /// 5. Save the modal presentation date.
    ///
    /// - Parameter presenter: The view controller to present from.
    func presentModalPromptIfNeeded(from presenter: ModalPromptPresenter) {
        guard let preparedItem = selectModalPrompt() else { return }

        let scheduledAttemptID = UUID()
        legacyActiveAttemptIDs.insert(scheduledAttemptID)
        Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal from \(type(of: preparedItem.provider))")
        presentLegacyModalPrompt(
            modalPromptConfiguration: preparedItem.configuration,
            from: presenter,
            scheduledAttemptID: scheduledAttemptID
        ) { [weak self] in
            self?.legacyActiveAttemptIDs.remove(scheduledAttemptID)
            self?.didActuallyPresentModalPromptThisSession = true
            self?.saveModalPromptLastPresentationDate()
            preparedItem.provider.didPresentModal()
        }
    }

    func presentModalPromptIfNeeded(
        from presenter: ModalPromptPresenter,
        with lease: PromoQueueModalLease
    ) -> ModalPromptLeaseDisposition {
        guard modalAttemptPhase == .idle else {
            assertionFailure("A coordinated modal lease cannot replace an active modal attempt.")
            lease.release()
            return .released
        }

        isPromoQueueEnabled = true
        let attempt = CoordinatedAttempt(lease: lease)
        attemptState = .evaluating(attempt)

        if let pendingPreparedItem {
            self.pendingPreparedItem = nil
            guard let preparedItem = selectModalPrompt(pendingPreparedItem: pendingPreparedItem) else {
                releaseCoordinationAttempt()
                return .released
            }

            let committedAttempt = CommittedAttempt(
                attempt: attempt,
                preparedItem: preparedItem,
                presenter: presenter
            )
            attemptState = .committed(committedAttempt)
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Retrying modal presentation after pending work.")
            presentCoordinatedModal(committedAttempt)
            return .retained
        }

        guard let preparedItem = selectModalPrompt() else {
            releaseCoordinationAttempt()
            return .released
        }

        let committedAttempt = CommittedAttempt(
            attempt: attempt,
            preparedItem: preparedItem,
            presenter: presenter
        )
        attemptState = .committed(committedAttempt)
        Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal from \(type(of: preparedItem.provider))")
        presentCoordinatedModal(committedAttempt)
        return .retained
    }

    /// Releases a coordinated modal only after the exact selected root is no longer attached.
    ///
    /// A child presented by that root does not affect this check because attachment is evaluated
    /// against the retained root itself rather than the topmost view controller.
    func reconcilePresentedModal() -> Bool {
        guard case .presentationActive(let activeAttempt) = attemptState else {
            return false
        }

        switch activeAttempt.state {
        case .verifying:
            return reconcileVerifyingPresentation(activeAttempt)
        case .accepted:
            if let exactRoot = activeAttempt.exactRoot,
               isExactRootAttached(exactRoot) {
                return false
            }

            cancelAttachmentVerification()
            attemptState = .idle
            activeAttempt.attempt.lease.release()
            return true
        }
    }
}

// MARK: - Private

private extension ModalPromptCoordinationManager {
    // MARK: - Selection and Preflight

    private enum PrePresentationValidationResult {
        /// Presentation can proceed through the resolved UIKit route.
        case ready(PresentationRoute)
        /// The prepared root is already attached and can be adopted without another presentation call.
        case alreadyAttached
        /// Current conditions prevent presentation but allow the prepared prompt to be retried.
        case recoverableFailure
        /// The prepared prompt must be discarded rather than retried.
        case terminalFailure
    }

    private func selectModalPrompt(pendingPreparedItem: PreparedItem? = nil) -> PreparedItem? {
        // A pending item continues an attempt that already cleared cooldown when it was selected, and every new
        // coordinated attempt consumes the pending item before selecting, so this bypass cannot skip a cooldown
        // started by a different modal.
        guard pendingPreparedItem != nil || !cooldownManager.isInCooldownPeriod else {
            let cooldownInfo = cooldownManager.cooldownInfo
            let lastPresentationDate = cooldownInfo.lastPresentationDate.flatMap(String.init) ?? "-"
            Logger.modalPrompt.debug(
                """
                [Modal Prompt Coordination] - Is in cooldown period. Last presentation: \(lastPresentationDate, privacy: .public) \
                Can Present modal again: \(cooldownInfo.nextPresentationDate, privacy: .public)
                """
            )
            return nil
        }

        let invalidPendingPreparedItem: PreparedItem?
        if let pendingPreparedItem {
            if isRetainedPreparedItemStillValid(pendingPreparedItem) {
                return pendingPreparedItem
            }
            invalidPendingPreparedItem = pendingPreparedItem
        } else {
            invalidPendingPreparedItem = nil
        }

        let isOnboardingComplete = onboardingStatusProvider.hasSeenOnboarding
        for provider in providers {
            guard provider.isEligibleToPresent(isOnboardingComplete: isOnboardingComplete) else {
                Logger.modalPrompt.debug(
                    """
                    [Modal Prompt Coordination] - \(type(of: provider)) is not eligible to present \
                    (isOnboardingComplete: \(isOnboardingComplete)).
                    """
                )
                continue
            }
            let configuration: ModalPromptConfiguration?
            if let invalidPendingPreparedItem,
               provider === invalidPendingPreparedItem.provider {
                configuration = provider.provideReplacementModalPrompt(for: invalidPendingPreparedItem.configuration)
            } else {
                configuration = provider.provideModalPrompt()
            }
            guard let configuration else { continue }

            return PreparedItem(configuration: configuration, provider: provider)
        }

        Logger.modalPrompt.debug("[Modal Prompt Coordination] - No provider is eligible to present a modal.")
        return nil
    }

    // MARK: - Presentation Scheduling

    private func presentCoordinatedModal(_ committedAttempt: CommittedAttempt) {
        scheduledPresentationTask = scheduler.schedule(after: 0.1) { [weak self] in
            guard let self,
                  case .committed(let currentAttempt) = self.attemptState,
                  currentAttempt.attempt.lease.attemptIdentity == committedAttempt.attempt.lease.attemptIdentity else {
                return
            }

            self.scheduledPresentationTask = nil
            switch self.validatePrePresentation(committedAttempt) {
            case .ready(let route):
                self.beginPresentation(committedAttempt, using: route)
            case .alreadyAttached:
                self.adoptAttachedRoot(committedAttempt)
            case .recoverableFailure:
                self.finishPreVisibleAttempt(
                    committedAttempt,
                    retainAsPending: true,
                    notifyRelease: true
                )
            case .terminalFailure:
                self.finishPreVisibleAttempt(
                    committedAttempt,
                    retainAsPending: false,
                    notifyRelease: true
                )
            }
        }
    }

    private func presentLegacyModalPrompt(
        modalPromptConfiguration: ModalPromptConfiguration,
        from presenter: ModalPromptPresenter,
        scheduledAttemptID: UUID,
        completion: @escaping (() -> Void)
    ) {
        scheduler.schedule(after: 0.1) { [weak self] in
            guard let self,
                  self.legacyActiveAttemptIDs.contains(scheduledAttemptID) else {
                return
            }

            self.performPresentation(
                modalPromptConfiguration: modalPromptConfiguration,
                from: presenter,
                completion: completion
            )
        }
    }

    private func presentationRoute(from presenter: ModalPromptPresenter) -> PresentationRoute? {
        if let presented = presenter.presentedViewController,
           presented is OmniBarEditingStateViewController,
           !presented.isBeingDismissed {
            return .omniBar(presented)
        }

        guard presenter.presentedViewController == nil
                || presenter.presentedViewController?.isBeingDismissed == true else {
            return nil
        }

        return .presenter(presenter.modalPromptPresentationViewController)
    }

    private func validatePrePresentation(_ committedAttempt: CommittedAttempt) -> PrePresentationValidationResult {
        guard isPromoQueueEnabled else {
            return .terminalFailure
        }

        guard isApplicationActive else {
            return .recoverableFailure
        }

        let exactRoot = committedAttempt.preparedItem.configuration.viewController
        if isExactRootAttached(exactRoot) {
            return .alreadyAttached
        }

        guard isPreparedItemStillValid(committedAttempt.preparedItem) else {
            return .terminalFailure
        }

        guard !exactRoot.isBeingDismissed else {
            return .terminalFailure
        }

        guard let route = presentationRoute(from: committedAttempt.presenter),
              isIntendedHostAttached(route.intendedHost) else {
            return .recoverableFailure
        }

        return .ready(route)
    }

    private func isPreparedItemStillValid(_ preparedItem: PreparedItem) -> Bool {
        let isOnboardingComplete = onboardingStatusProvider.hasSeenOnboarding
        return preparedItem.provider.isEligibleToPresent(isOnboardingComplete: isOnboardingComplete)
            && preparedItem.provider.isPreparedModalPromptStillValid(preparedItem.configuration)
    }

    private func isRetainedPreparedItemStillValid(_ preparedItem: PreparedItem) -> Bool {
        let isOnboardingComplete = onboardingStatusProvider.hasSeenOnboarding
        return preparedItem.provider.isEligibleToPresent(isOnboardingComplete: isOnboardingComplete)
            && preparedItem.provider.isRetainedPreparedModalPromptStillValid(preparedItem.configuration)
    }

    private func isIntendedHostAttached(_ intendedHost: UIViewController?) -> Bool {
        guard let intendedHost else {
            // Protocol-only presenters used by tests do not necessarily expose their UIKit host.
            return true
        }

        return rootAttachmentChecker.isAttached(intendedHost)
    }

    // MARK: - UIKit Handoff and Verification

    private func beginPresentation(_ committedAttempt: CommittedAttempt, using route: PresentationRoute) {
        let exactRoot = committedAttempt.preparedItem.configuration.viewController
        let presentation = VerifyingPresentation(
            preparedItem: committedAttempt.preparedItem,
            exactRoot: exactRoot,
            presenter: committedAttempt.presenter,
            intendedHost: route.intendedHost
        )
        let activeAttempt = PresentationActiveAttempt(
            attempt: committedAttempt.attempt,
            state: .verifying(presentation)
        )
        attemptState = .presentationActive(activeAttempt)
        rememberPresentedRoot(exactRoot)
        let attemptIdentity = committedAttempt.attempt.lease.attemptIdentity

        performPresentation(
            committedAttempt.preparedItem.configuration,
            using: route,
            presenter: committedAttempt.presenter
        ) { [weak self, attemptIdentity, preparedItem = committedAttempt.preparedItem, exactRoot] in
            self?.recordPresentationCompletion(
                attemptIdentity: attemptIdentity,
                preparedItem: preparedItem,
                exactRoot: exactRoot
            )
        }

        guard case .presentationActive(let currentAttempt) = attemptState,
              currentAttempt.attempt.lease.attemptIdentity == attemptIdentity,
              case .verifying = currentAttempt.state else {
            return
        }

        scheduleAttachmentVerification(attemptIdentity: attemptIdentity, exactRoot: exactRoot)
    }

    private func adoptAttachedRoot(_ committedAttempt: CommittedAttempt) {
        let exactRoot = committedAttempt.preparedItem.configuration.viewController
        attemptState = .presentationActive(
            PresentationActiveAttempt(
                attempt: committedAttempt.attempt,
                state: .accepted(WeakPresentedRoot(exactRoot))
            )
        )
        rememberPresentedRoot(exactRoot)
        recordPresentation(for: committedAttempt.preparedItem)
    }

    private func verifyPresentationAttachment(
        attemptIdentity: PromoQueueModalAttemptIdentity,
        exactRoot: UIViewController
    ) {
        guard case .presentationActive(let activeAttempt) = attemptState,
              activeAttempt.attempt.lease.attemptIdentity == attemptIdentity,
              case .verifying(let presentation) = activeAttempt.state,
              presentation.exactRoot === exactRoot else {
            return
        }

        if reconcileVerifyingPresentation(activeAttempt) {
            coordinatedAttemptReleaseHandler?()
        }
    }

    private func scheduleAttachmentVerification(
        attemptIdentity: PromoQueueModalAttemptIdentity,
        exactRoot: UIViewController
    ) {
        guard attachmentVerificationRequestID == nil else {
            return
        }

        let requestID = UUID()
        attachmentVerificationRequestID = requestID
        let task = scheduler.scheduleOnNextMainTurn { [weak self] in
            guard let self,
                  self.attachmentVerificationRequestID == requestID else {
                return
            }

            self.attachmentVerificationRequestID = nil
            self.attachmentVerificationTask = nil
            self.verifyPresentationAttachment(attemptIdentity: attemptIdentity, exactRoot: exactRoot)
        }

        if attachmentVerificationRequestID == requestID {
            attachmentVerificationTask = task
        } else {
            task.cancel()
        }
    }

    private func recordPresentationCompletion(
        attemptIdentity: PromoQueueModalAttemptIdentity,
        preparedItem: PreparedItem,
        exactRoot: UIViewController
    ) {
        let isCurrentAttempt: Bool
        if case .presentationActive(let activeAttempt) = attemptState {
            isCurrentAttempt = activeAttempt.attempt.lease.attemptIdentity == attemptIdentity
                && activeAttempt.exactRoot === exactRoot
        } else {
            isCurrentAttempt = false
        }

        guard isCurrentAttempt || isExactRootAttached(exactRoot) else {
            return
        }

        if isCurrentAttempt,
           case .presentationActive(let activeAttempt) = attemptState,
           case .verifying = activeAttempt.state {
            acceptPresentation(activeAttempt, exactRoot: exactRoot)
        }

        recordPresentation(for: preparedItem)
    }

    private func finishPreVisibleAttempt(
        _ committedAttempt: CommittedAttempt,
        retainAsPending: Bool,
        notifyRelease: Bool
    ) {
        pendingPreparedItem = retainAsPending ? committedAttempt.preparedItem : nil
        attemptState = .idle
        committedAttempt.attempt.lease.release()
        if notifyRelease {
            coordinatedAttemptReleaseHandler?()
        }
    }

    // MARK: - Presentation Execution

    private func performPresentation(
        _ modalPromptConfiguration: ModalPromptConfiguration,
        using route: PresentationRoute,
        presenter: ModalPromptPresenter,
        completion: @escaping (() -> Void)
    ) {
        switch route {
        case .omniBar(let host):
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal on top of OmniBarEditingStateViewController")
            host.present(
                modalPromptConfiguration.viewController,
                animated: modalPromptConfiguration.animated,
                completion: completion
            )
        case .presenter:
            presenter.present(
                modalPromptConfiguration.viewController,
                animated: modalPromptConfiguration.animated,
                completion: completion
            )
        }
    }

    private func performPresentation(
        modalPromptConfiguration: ModalPromptConfiguration,
        from presenter: ModalPromptPresenter,
        completion: @escaping (() -> Void)
    ) {
        if let presented = presenter.presentedViewController, presented is OmniBarEditingStateViewController, !presented.isBeingDismissed {
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal on top of OmniBarEditingStateViewController")
            rememberPresentedRoot(modalPromptConfiguration.viewController)
            presented.present(modalPromptConfiguration.viewController, animated: modalPromptConfiguration.animated, completion: completion)
        } else {
            rememberPresentedRoot(modalPromptConfiguration.viewController)
            presenter.present(modalPromptConfiguration.viewController, animated: modalPromptConfiguration.animated, completion: completion)
        }
    }

    // MARK: - Reconciliation and Accounting

    private func rememberPresentedRoot(_ exactRoot: UIViewController) {
        lastPresentedExactRoot = exactRoot
    }

    private func reconcileVerifyingPresentation(_ activeAttempt: PresentationActiveAttempt) -> Bool {
        guard isApplicationActive,
              case .verifying(let presentation) = activeAttempt.state else {
            return false
        }

        if isExactRootAttached(presentation.exactRoot) {
            acceptPresentation(activeAttempt, exactRoot: presentation.exactRoot)
            return false
        }

        // UIKit establishes the presentation relationship before the transition finishes attaching the root.
        // Keep the lease while that relationship exists so a checkpoint during the animation cannot admit RMF.
        guard !isPresentationInProgress(presentation) else {
            return false
        }

        cancelAttachmentVerification()
        // If UIKit attaches after this relationship-free rejection, the next pending retry will adopt the root.
        pendingPreparedItem = presentation.preparedItem.didRecordPresentation ? nil : presentation.preparedItem
        attemptState = .idle
        activeAttempt.attempt.lease.release()
        return true
    }

    private func recordPresentation(for preparedItem: PreparedItem) {
        guard !preparedItem.didRecordPresentation else {
            return
        }

        preparedItem.didRecordPresentation = true
        didActuallyPresentModalPromptThisSession = true
        saveModalPromptLastPresentationDate()
        preparedItem.provider.didPresentModal()
    }

    private func acceptPresentation(_ activeAttempt: PresentationActiveAttempt, exactRoot: UIViewController) {
        cancelAttachmentVerification()
        attemptState = .presentationActive(
            PresentationActiveAttempt(
                attempt: activeAttempt.attempt,
                state: .accepted(WeakPresentedRoot(exactRoot))
            )
        )
    }

    private func isExactRootAttached(_ exactRoot: UIViewController) -> Bool {
        rootAttachmentChecker.isAttached(exactRoot)
    }

    private func isPresentationInProgress(_ presentation: VerifyingPresentation) -> Bool {
        if presentation.presenter?.presentedViewController === presentation.exactRoot {
            return true
        }

        guard let intendedHost = presentation.intendedHost else {
            return false
        }

        return intendedHost.presentedViewController === presentation.exactRoot
            || presentation.exactRoot.presentingViewController === intendedHost
    }

    // MARK: - Cleanup

    private func releaseCoordinationAttempt() {
        switch attemptState {
        case .idle:
            return
        case .evaluating(let attempt):
            attemptState = .idle
            attempt.lease.release()
        case .committed(let committedAttempt):
            cancelScheduledPresentation()
            attemptState = .idle
            committedAttempt.attempt.lease.release()
        case .presentationActive(let activeAttempt):
            cancelAttachmentVerification()
            attemptState = .idle
            activeAttempt.attempt.lease.release()
        }
    }

    /// Preserves session history before a feature transition forgets an exact root that UIKit attached.
    private func latchActualPresentationHistoryIfModalIsAttached() {
        guard let lastPresentedExactRoot,
              isExactRootAttached(lastPresentedExactRoot) else {
            return
        }

        didActuallyPresentModalPromptThisSession = true
    }

    private func cancelScheduledPresentation() {
        scheduledPresentationTask?.cancel()
        scheduledPresentationTask = nil
    }

    private func cancelAttachmentVerification() {
        attachmentVerificationRequestID = nil
        attachmentVerificationTask?.cancel()
        attachmentVerificationTask = nil
    }

    private func saveModalPromptLastPresentationDate() {
        cooldownManager.recordLastPromptPresentationTimestamp()
    }

}
