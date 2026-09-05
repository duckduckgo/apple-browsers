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

    func presentModalPromptIfNeeded(from presenter: ModalPromptPresenter)
    func presentModalPromptIfNeeded(
        from presenter: ModalPromptPresenter,
        with lease: PromoQueueModalLease
    )
    func reconcilePresentedModal()

    /// Starts the cooldown, notifies the provider, and frees the slot.
    /// - Returns: `true` if a deferred slot was held and is now redeemed.
    func redeemDeferredModal() -> Bool

    /// Frees a held deferred slot without a cooldown, because nothing was shown.
    func releaseDeferredModal()
}

enum ModalPromptAttemptPhase: Equatable {
    /// No coordinated modal owns a lease.
    case idle
    /// A modal is being selected; carries this lease acquisition's identity.
    case evaluating(PromoQueueModalOwnershipIdentity)
    /// A modal was selected and scheduled; carries this lease acquisition's identity.
    case committed(PromoQueueModalOwnershipIdentity)
    /// The modal root was handed to UIKit; carries this lease acquisition's identity.
    case presentationActive(PromoQueueModalOwnershipIdentity)
    /// A deferred promo holds the slot pending an external event.
    case deferred(PromoQueueModalOwnershipIdentity)
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
    private enum SelectedPrompt {
        case modal(configuration: ModalPromptConfiguration, provider: any ModalPromptProvider)
        case deferred(provider: any ModalPromptProvider)
    }

    private struct CommittedAttempt {
        let lease: PromoQueueModalLease
        let configuration: ModalPromptConfiguration
        let provider: any ModalPromptProvider
    }

    /// Weak holder for a presented modal root, since an enum payload cannot itself be `weak`.
    ///
    /// Checkpoints are sparse (foreground and NTP promo admission), so a strong payload would leave the manager the
    /// sole owner of a dismissed modal's whole view hierarchy for as long as the user keeps browsing. The providers that
    /// keep the presented controller keep it weakly for the same reason.
    private final class PresentedModalRoot {
        weak var viewController: UIViewController?

        init(_ viewController: UIViewController) {
            self.viewController = viewController
        }
    }

    private enum AttemptState {
        /// No coordinated modal owns a lease.
        case idle
        /// Holds the lease while providers are evaluated.
        case evaluating(PromoQueueModalLease)
        /// Holds the lease and selected prompt until scheduled presentation begins.
        case committed(CommittedAttempt)
        /// Holds the lease and exact presented root until reconciliation observes its dismissal.
        case presentationActive(PromoQueueModalLease, exactRoot: PresentedModalRoot)
        /// Holds the lease until redeemed or released. No root to observe, so reconciliation
        /// deliberately leaves this state alone.
        case deferred(PromoQueueModalLease, provider: any ModalPromptProvider)
    }

    private let providers: [any ModalPromptProvider]
    private let cooldownManager: PromptCooldownManaging
    private let scheduler: ModalPromptScheduling
    private let onboardingStatusProvider: ContextualDaxDialogStatusProvider
    private let rootAttachmentChecker: ModalPromptRootAttachmentChecking

    private var attemptState = AttemptState.idle
    private var legacyActiveAttemptIDs = Set<UUID>()

    private(set) var didActuallyPresentModalPromptThisSession = false

    var didPresentModalPromptThisSession: Bool {
        didActuallyPresentModalPromptThisSession || hasActiveOrPendingModalAttempt
    }

    /// Whether a modal is on its way to the screen.
    ///
    /// A held deferred slot is excluded: it means a promo owns the slot, not that the user saw
    /// anything. This feeds `didPresentModalPromptThisSession`, read as "recently saw a prompt".
    var hasActiveOrPendingModalAttempt: Bool {
        if case .deferred = attemptState {
            return !legacyActiveAttemptIDs.isEmpty
        }
        return !legacyActiveAttemptIDs.isEmpty || modalAttemptPhase != .idle
    }

    var modalAttemptPhase: ModalPromptAttemptPhase {
        switch attemptState {
        case .idle:
            return .idle
        case .evaluating(let lease):
            return .evaluating(lease.ownershipIdentity)
        case .committed(let committedAttempt):
            return .committed(committedAttempt.lease.ownershipIdentity)
        case .presentationActive(let lease, _):
            return .presentationActive(lease.ownershipIdentity)
        case .deferred(let lease, _):
            return .deferred(lease.ownershipIdentity)
        }
    }

    init(
        providers: [any ModalPromptProvider],
        cooldownManager: PromptCooldownManaging,
        onboardingStatusProvider: ContextualDaxDialogStatusProvider,
        modalPromptScheduling: ModalPromptScheduling = ModalPromptScheduler(),
        rootAttachmentChecker: ModalPromptRootAttachmentChecking? = nil
    ) {
        self.providers = providers
        self.cooldownManager = cooldownManager
        self.onboardingStatusProvider = onboardingStatusProvider
        self.scheduler = modalPromptScheduling
        self.rootAttachmentChecker = rootAttachmentChecker ?? ModalPromptRootAttachmentChecker()
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
        // Deferred promos need the coordinated route, which owns the lease they hold. So they
        // must report themselves ineligible here — see `AppRatingCoordinationCapability`.
        guard case .modal(let configuration, let provider) = selectModalPrompt() else { return }

        let scheduledAttemptID = UUID()
        legacyActiveAttemptIDs.insert(scheduledAttemptID)
        Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal from \(type(of: provider))")
        presentLegacyModalPrompt(
            modalPromptConfiguration: configuration,
            from: presenter,
            scheduledAttemptID: scheduledAttemptID
        ) { [weak self] in
            self?.legacyActiveAttemptIDs.remove(scheduledAttemptID)
            self?.didActuallyPresentModalPromptThisSession = true
            self?.saveModalPromptLastPresentationDate()
            provider.didPresentModal()
        }
    }

    func presentModalPromptIfNeeded(
        from presenter: ModalPromptPresenter,
        with lease: PromoQueueModalLease
    ) {
        guard modalAttemptPhase == .idle else {
            assertionFailure("A coordinated modal lease cannot replace an active modal attempt.")
            lease.release()
            return
        }

        attemptState = .evaluating(lease)

        guard let selectedPrompt = selectModalPrompt() else {
            releaseCoordinationAttempt()
            return
        }

        switch selectedPrompt {
        case .deferred(let provider):
            attemptState = .deferred(lease, provider: provider)
            Logger.modalPrompt.debug(
                "[Modal Prompt Coordination] - Holding the slot for \(type(of: provider)) until it is redeemed."
            )

        case .modal(let configuration, let provider):
            let committedAttempt = CommittedAttempt(
                lease: lease,
                configuration: configuration,
                provider: provider
            )
            attemptState = .committed(committedAttempt)
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Presenting modal from \(type(of: provider))")
            presentCoordinatedModal(committedAttempt, from: presenter)
        }
    }

    /// Releases a coordinated modal only after the exact selected root is no longer attached.
    ///
    /// A child presented by that root does not affect this check because attachment is evaluated
    /// against the observed root itself rather than the topmost view controller. A root that has already been
    /// deallocated counts as not attached, so a lease can never outlive the modal it was taken for.
    func reconcilePresentedModal() {
        guard case .presentationActive(let lease, let exactRoot) = attemptState else { return }

        if let root = exactRoot.viewController, rootAttachmentChecker.isAttached(root) {
            return
        }

        attemptState = .idle
        lease.release()
    }

    func redeemDeferredModal() -> Bool {
        guard case .deferred(let lease, let provider) = attemptState else { return false }

        attemptState = .idle
        didActuallyPresentModalPromptThisSession = true
        saveModalPromptLastPresentationDate()
        provider.didPresentModal()
        lease.release()
        Logger.modalPrompt.debug("[Modal Prompt Coordination] - Redeemed the slot held by \(type(of: provider)).")
        return true
    }

    func releaseDeferredModal() {
        guard case .deferred(let lease, let provider) = attemptState else { return }

        attemptState = .idle
        lease.release()
        provider.didReleaseDeferredSlot()
        Logger.modalPrompt.debug("[Modal Prompt Coordination] - Released the unredeemed slot held by \(type(of: provider)).")
    }
}

// MARK: - Private

private extension ModalPromptCoordinationManager {

    private func selectModalPrompt() -> SelectedPrompt? {
        guard !cooldownManager.isInCooldownPeriod else {
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

            if provider.presentationKind == .deferred {
                return .deferred(provider: provider)
            }

            guard let configuration = provider.provideModalPrompt() else { continue }

            return .modal(configuration: configuration, provider: provider)
        }

        Logger.modalPrompt.debug("[Modal Prompt Coordination] - No provider is eligible to present a modal.")
        return nil
    }

    private func presentCoordinatedModal(_ committedAttempt: CommittedAttempt, from presenter: ModalPromptPresenter) {
        scheduler.schedule(after: 0.1) { [weak self] in
            guard let self,
                  case .committed(let currentAttempt) = self.attemptState,
                  currentAttempt.lease.ownershipIdentity == committedAttempt.lease.ownershipIdentity else {
                return
            }

            self.attemptState = .presentationActive(
                committedAttempt.lease,
                exactRoot: PresentedModalRoot(committedAttempt.configuration.viewController)
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
        presenter.present(modalPromptConfiguration.viewController, animated: modalPromptConfiguration.animated, completion: completion)
    }

    func releaseCoordinationAttempt() {
        switch attemptState {
        case .idle:
            return
        case .evaluating(let lease), .presentationActive(let lease, _):
            attemptState = .idle
            lease.release()
        case .committed(let committedAttempt):
            attemptState = .idle
            committedAttempt.lease.release()
        case .deferred(let lease, _):
            attemptState = .idle
            lease.release()
        }
    }

    func saveModalPromptLastPresentationDate() {
        cooldownManager.recordLastPromptPresentationTimestamp()
    }

}
