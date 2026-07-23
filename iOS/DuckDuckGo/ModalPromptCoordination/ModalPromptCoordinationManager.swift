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
    var didActuallyPresentModalPromptThisSession: Bool { get }
    var hasActiveOrPendingModalAttempt: Bool { get }
    var modalAttemptPhase: ModalPromptAttemptPhase { get }

    func presentModalPromptIfNeeded(from presenter: ModalPromptPresenter)
    func presentModalPromptIfNeeded(
        from presenter: ModalPromptPresenter,
        with lease: PromoQueueModalLease
    ) -> ModalPromptLeaseDisposition
    func reconcilePresentedModal() -> Bool
    func promoQueueWillTransition(to targetState: PromoQueueFeatureTargetState)
    func promoQueueDidTransition(to targetState: PromoQueueFeatureTargetState)
}

enum ModalPromptLeaseDisposition: Equatable {
    case retained
    case released
}

enum ModalPromptAttemptPhase: Equatable {
    case idle
    case evaluating(PromoQueueModalAttemptIdentity)
    case committed(PromoQueueModalAttemptIdentity)
    case presentationActive(PromoQueueModalAttemptIdentity)
}

@MainActor
protocol ModalPromptRootAttachmentChecking {
    func isAttached(_ root: UIViewController) -> Bool
    func isAttached(_ root: UIViewController, to intendedPresenter: UIViewController?) -> Bool
}

struct ModalPromptRootAttachmentChecker: ModalPromptRootAttachmentChecking {
    func isAttached(_ root: UIViewController) -> Bool {
        root.isBeingPresented || root.presentingViewController != nil || root.viewIfLoaded?.window != nil
    }

    func isAttached(_ root: UIViewController, to intendedPresenter: UIViewController?) -> Bool {
        guard isAttached(root), let intendedPresenter else {
            return isAttached(root)
        }

        return root.presentingViewController === intendedPresenter
            || intendedPresenter.presentedViewController === root
    }
}

/// Manages the coordination and presentation of modal prompts based on priority and cooldown rules.
///
/// This manager is responsible for:
/// - Enforcing global cooldown periods between modal presentations.
/// - Presenting the first eligible modal.
/// - Track when modals were last presented.
///
/// The manager does NOT handle app-lifecycle level concerns like launch source checking. Those are handled by the `ModalPromptsCoordinationService`.
@MainActor
final class ModalPromptCoordinationManager: ModalPromptCoordinationManaging {
    private struct CoordinatedAttempt {
        let lease: PromoQueueModalLease
    }

    private struct CommittedAttempt {
        let attempt: CoordinatedAttempt
        let configuration: ModalPromptConfiguration
        let provider: any ModalPromptProvider
    }

    private enum AttemptState {
        case idle
        case evaluating(CoordinatedAttempt)
        case committed(CommittedAttempt)
        case presentationActive(CoordinatedAttempt, exactRoot: UIViewController)
    }

    private let providers: [any ModalPromptProvider]
    private let cooldownManager: PromptCooldownManaging
    private let scheduler: ModalPromptScheduling
    private let onboardingStatusProvider: ContextualDaxDialogStatusProvider
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbitrating
    private let rootAttachmentChecker: ModalPromptRootAttachmentChecking

    private var attemptState = AttemptState.idle
    private var legacyActiveAttemptIDs = Set<UUID>()
    private var lastSelectedExactRoot: UIViewController?
    private weak var lastSelectedPresentationHost: UIViewController?

    private(set) var didActuallyPresentModalPromptThisSession = false

    var didPresentModalPromptThisSession: Bool {
        didActuallyPresentModalPromptThisSession || hasActiveOrPendingModalAttempt
    }

    var hasActiveOrPendingModalAttempt: Bool {
        !legacyActiveAttemptIDs.isEmpty || modalAttemptPhase != .idle
    }

    var modalAttemptPhase: ModalPromptAttemptPhase {
        switch attemptState {
        case .idle:
            return .idle
        case .evaluating(let attempt):
            return .evaluating(attempt.lease.attemptIdentity)
        case .committed(let committedAttempt):
            return .committed(committedAttempt.attempt.lease.attemptIdentity)
        case .presentationActive(let attempt, _):
            return .presentationActive(attempt.lease.attemptIdentity)
        }
    }

    init(
        providers: [any ModalPromptProvider],
        cooldownManager: PromptCooldownManaging,
        onboardingStatusProvider: ContextualDaxDialogStatusProvider,
        promoQueueLeaseArbiter: PromoQueueLeaseArbitrating,
        modalPromptScheduling: ModalPromptScheduling = ModalPromptScheduler(),
        rootAttachmentChecker: ModalPromptRootAttachmentChecking? = nil
    ) {
        self.providers = providers
        self.cooldownManager = cooldownManager
        self.onboardingStatusProvider = onboardingStatusProvider
        self.promoQueueLeaseArbiter = promoQueueLeaseArbiter
        self.scheduler = modalPromptScheduling
        self.rootAttachmentChecker = rootAttachmentChecker ?? ModalPromptRootAttachmentChecker()
    }

    func promoQueueWillTransition(to targetState: PromoQueueFeatureTargetState) {
        legacyActiveAttemptIDs.removeAll()
        releaseCoordinationAttempt()
    }

    func promoQueueDidTransition(to targetState: PromoQueueFeatureTargetState) {
        guard targetState == .enabled,
              let lastSelectedExactRoot,
              rootAttachmentChecker.isAttached(
                lastSelectedExactRoot,
                to: lastSelectedPresentationHost
              ) else {
            return
        }

        guard case .acquired(let lease) = promoQueueLeaseArbiter.acquireModalLease() else {
            return
        }

        let attempt = CoordinatedAttempt(lease: lease)
        attemptState = .presentationActive(attempt, exactRoot: lastSelectedExactRoot)
    }

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
        guard !cooldownManager.isInCooldownPeriod else {
            let cooldownInfo = cooldownManager.cooldownInfo
            let lastPresentationDate = cooldownInfo.lastPresentationDate.flatMap(String.init) ?? "-"
            Logger.modalPrompt.debug(
                """
                [Modal Prompt Coordination] - Is in cooldown period. Last presentation: \(lastPresentationDate, privacy: .public) \
                Can Present modal again: \(cooldownInfo.nextPresentationDate, privacy: .public)
                """
            )
            return
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
            guard let modalPromptConfiguration = provider.provideModalPrompt() else { continue }

            let scheduledAttemptID = UUID()
            lastSelectedExactRoot = modalPromptConfiguration.viewController
            legacyActiveAttemptIDs.insert(scheduledAttemptID)
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal from \(type(of: provider))")
            presentLegacyModalPrompt(
                modalPromptConfiguration: modalPromptConfiguration,
                from: presenter,
                scheduledAttemptID: scheduledAttemptID
            ) { [weak self] in
                guard let self else { return }
                self.legacyActiveAttemptIDs.remove(scheduledAttemptID)
                self.didActuallyPresentModalPromptThisSession = true
                self.saveModalPromptLastPresentationDate()
                provider.didPresentModal()
            }
            return
        }

        Logger.modalPrompt.debug("[Modal Prompt Coordination] - No provider is eligible to present a modal.")
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

        let attempt = CoordinatedAttempt(lease: lease)
        attemptState = .evaluating(attempt)

        guard !cooldownManager.isInCooldownPeriod else {
            let cooldownInfo = cooldownManager.cooldownInfo
            let lastPresentationDate = cooldownInfo.lastPresentationDate.flatMap(String.init) ?? "-"
            Logger.modalPrompt.debug(
                """
                [Modal Prompt Coordination] - Is in cooldown period. Last presentation: \(lastPresentationDate, privacy: .public) \
                Can Present modal again: \(cooldownInfo.nextPresentationDate, privacy: .public)
                """
            )
            releaseCoordinationAttempt()
            return .released
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
            guard let modalPromptConfiguration = provider.provideModalPrompt() else { continue }

            lastSelectedExactRoot = modalPromptConfiguration.viewController
            let committedAttempt = CommittedAttempt(
                attempt: attempt,
                configuration: modalPromptConfiguration,
                provider: provider
            )
            attemptState = .committed(committedAttempt)
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal from \(type(of: provider))")
            presentCoordinatedModal(committedAttempt, from: presenter)
            return .retained
        }

        Logger.modalPrompt.debug("[Modal Prompt Coordination] - No provider is eligible to present a modal.")
        releaseCoordinationAttempt()
        return .released
    }

    /// Releases a coordinated modal only after the exact selected root is no longer attached.
    ///
    /// A child presented by that root does not affect this check because attachment is evaluated
    /// against the retained root itself rather than the topmost view controller.
    func reconcilePresentedModal() -> Bool {
        guard case .presentationActive(let attempt, let exactRoot) = attemptState,
              !rootAttachmentChecker.isAttached(exactRoot) else {
            return false
        }

        attemptState = .idle
        attempt.lease.release()
        return true
    }
}

// MARK: - Private

private extension ModalPromptCoordinationManager {

    private func presentCoordinatedModal(_ committedAttempt: CommittedAttempt, from presenter: ModalPromptPresenter) {
        scheduler.schedule(after: 0.1) { [weak self] in
            guard let self,
                  case .committed(let currentAttempt) = self.attemptState,
                  currentAttempt.attempt.lease.attemptIdentity == committedAttempt.attempt.lease.attemptIdentity else {
                return
            }

            self.attemptState = .presentationActive(
                committedAttempt.attempt,
                exactRoot: committedAttempt.configuration.viewController
            )
            self.performPresentation(
                modalPromptConfiguration: committedAttempt.configuration,
                from: presenter
            ) { [weak self] in
                self?.didActuallyPresentModalPromptThisSession = true
                self?.saveModalPromptLastPresentationDate()
                committedAttempt.provider.didPresentModal()
            }
        }
    }

    func presentLegacyModalPrompt(
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

    func performPresentation(
        modalPromptConfiguration: ModalPromptConfiguration,
        from presenter: ModalPromptPresenter,
        completion: @escaping (() -> Void)
    ) {
        if let presented = presenter.presentedViewController, presented is OmniBarEditingStateViewController, !presented.isBeingDismissed {
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal on top of OmniBarEditingStateViewController")
            lastSelectedPresentationHost = presented
            presented.present(modalPromptConfiguration.viewController, animated: modalPromptConfiguration.animated, completion: completion)
        } else {
            lastSelectedPresentationHost = presenter.modalPromptPresentationViewController
            presenter.present(modalPromptConfiguration.viewController, animated: modalPromptConfiguration.animated, completion: completion)
        }
    }

    func releaseCoordinationAttempt() {
        switch attemptState {
        case .idle:
            return
        case .evaluating(let attempt), .presentationActive(let attempt, _):
            attemptState = .idle
            attempt.lease.release()
        case .committed(let committedAttempt):
            attemptState = .idle
            committedAttempt.attempt.lease.release()
        }
    }

    func saveModalPromptLastPresentationDate() {
        cooldownManager.recordLastPromptPresentationTimestamp()
    }

}
