//
//  PromoCoordinationService.swift
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

import Core
import Persistence
import PrivacyConfig
import UIKit

// MARK: - Modal Prompt Presenter

@MainActor
protocol ModalPromptPresenter: AnyObject {
    var presentedViewController: UIViewController? { get }
    /// UIKit host whose attachment is validated before presenting; test presenters may return `nil`.
    var modalPromptPresentationViewController: UIViewController? { get }

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
}

extension MainViewController: ModalPromptPresenter {
    var modalPromptPresentationViewController: UIViewController? { self }
}

/// Identifies one full foreground cycle so stale asynchronous readiness callbacks cannot open promo admission.
struct PromoCoordinationForegroundReadinessToken: Equatable {
    fileprivate let id = UUID()
}

// MARK: - Service

struct ModalPromptProviders {
    let newAddressBarPicker: ModalPromptProvider
    let defaultBrowser: ModalPromptProvider
    let winBackOffer: ModalPromptProvider
    let subscriptionPromo: ModalPromptProvider
    let subscriptionPromoExistingUser: ModalPromptProvider
    let whatsNew: ModalPromptProvider
    let cookiePopupProtectionOptIn: ModalPromptProvider
}

enum PromoQueueRemoteMessageLogicalStateSnapshot: Equatable {
    case idle
    case owned
    case draining
}

enum PromoQueueRemoteMessageDrainContinuationSnapshot: Equatable {
    case transferSameMessageIfAvailable
    case endSession
}

struct PromoQueueRemoteMessageRendererSnapshot: Equatable {
    let rendererID: UUID
    let registrationGenerationID: UUID
    let candidate: PromoQueueRemoteMessageCandidateState
    let isLocallyReady: Bool
    let isAttachedToWindow: Bool
    let isEffectivelyEligible: Bool
    let isDeregistered: Bool
}

/// Read-only projection of the service-owned RMF state for focused tests and later debug UI integration.
struct PromoQueueRemoteMessageCoordinationSnapshot: Equatable {
    let state: PromoQueueRemoteMessageLogicalStateSnapshot
    let messageID: String?
    let sessionID: UUID?
    let rendererID: UUID?
    let registrationGenerationID: UUID?
    let presentationID: UUID?
    let isQueueAppearanceConfirmed: Bool
    let isPresentationAppearanceReported: Bool?
    let removalID: UUID?
    let removalTerminal: PromoQueueRemoteMessageRemovalTerminal?
    let drainContinuation: PromoQueueRemoteMessageDrainContinuationSnapshot?
    let selectedRemoteMessageRendererID: UUID?
    let renderers: [PromoQueueRemoteMessageRendererSnapshot]
    let registeredRendererCount: Int
    let eligibleRendererCount: Int
}

/// Coordinates app-launch modal prompts with one service-owned logical NTP remote-message session.
///
/// Foreground, readiness, modal-release, and renderer checkpoints reconcile weak renderer registrations through one
/// non-reentrant state machine. The process-wide coordination mode is immutable for this service's lifetime.
@MainActor
final class PromoCoordinationService {
    private struct RemoteMessageRegistrationIdentity: Equatable {
        let rendererID: UUID
        let generationID: UUID
    }

    private final class WeakRemoteMessageRendererRegistration {
        let identity: RemoteMessageRegistrationIdentity
        let stableOrder: UInt64
        weak var target: NewTabPagePromoRendering?
        var candidate = PromoQueueRemoteMessageCandidateState.none
        var isLocallyReady = false
        var isDeregistered = false

        init(
            identity: RemoteMessageRegistrationIdentity,
            stableOrder: UInt64,
            target: NewTabPagePromoRendering
        ) {
            self.identity = identity
            self.stableOrder = stableOrder
            self.target = target
        }
    }

    private struct LogicalRemoteMessageSession {
        let identity: PromoQueueRemoteMessageSession
        var isQueueAppearanceConfirmed = false
    }

    private struct OwnedRemoteMessageState {
        var logicalSession: LogicalRemoteMessageSession
        let lease: PromoQueueRemoteMessageLease
        let registrationIdentity: RemoteMessageRegistrationIdentity
        let presentationID: UUID
        var isCurrentPresentationAppearanceReported = false
    }

    private enum RemoteMessageDrainContinuation {
        case transferSameMessageIfAvailable
        case endSession

        var snapshot: PromoQueueRemoteMessageDrainContinuationSnapshot {
            switch self {
            case .transferSameMessageIfAvailable:
                return .transferSameMessageIfAvailable
            case .endSession:
                return .endSession
            }
        }
    }

    private struct DrainingRemoteMessageState {
        let logicalSession: LogicalRemoteMessageSession
        let lease: PromoQueueRemoteMessageLease
        let outgoingRegistrationIdentity: RemoteMessageRegistrationIdentity
        let outgoingPresentationID: UUID
        let wasOutgoingPresentationAppearanceReported: Bool
        let removalID: UUID
        let acceptedRemovalTerminal: PromoQueueRemoteMessageRemovalTerminal?
        let continuation: RemoteMessageDrainContinuation
    }

    private enum RemoteMessageState {
        case idle
        case owned(OwnedRemoteMessageState)
        case draining(DrainingRemoteMessageState)
    }

    private let modalPromptCoordinationManager: ModalPromptCoordinationManaging
    private let launchSourceManager: LaunchSourceManaging
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbitrating
    private var remoteMessageRendererRegistrations = [WeakRemoteMessageRendererRegistration]()
    private var nextRemoteMessageRegistrationOrder: UInt64 = 0
    private var remoteMessageState = RemoteMessageState.idle
    private var isReconcilingRemoteMessages = false
    private var needsRemoteMessageReconciliation = false
    private var scheduledRemoteMessageSettlementRemovalID: UUID?
    private var remoteMessageRemovalReadyForSettlementID: UUID?
    private var selectedRemoteMessageRendererID: UUID?
    private var isApplicationActive = false
    private var isWaitingForForegroundInteractionReadiness = true
    private var foregroundReadinessToken = PromoCoordinationForegroundReadinessToken()
    private weak var deferredModalPromptPresenter: ModalPromptPresenter?

    let promoCoordinationMode: PromoCoordinationMode

    var remoteMessageCoordinationSnapshot: PromoQueueRemoteMessageCoordinationSnapshot {
        let rendererSnapshots = remoteMessageRendererRegistrations
            .sorted { $0.stableOrder < $1.stableOrder }
            .map { registration in
                PromoQueueRemoteMessageRendererSnapshot(
                    rendererID: registration.identity.rendererID,
                    registrationGenerationID: registration.identity.generationID,
                    candidate: registration.candidate,
                    isLocallyReady: registration.isLocallyReady,
                    isAttachedToWindow: registration.target?.isRemoteMessageRendererAttachedToWindow == true,
                    isEffectivelyEligible: isEffectivelyEligible(registration),
                    isDeregistered: registration.isDeregistered
                )
            }
        let registeredRendererCount = remoteMessageRendererRegistrations.count
        let eligibleRendererCount = remoteMessageRendererRegistrations.filter { registration in
            guard isEffectivelyEligible(registration),
                  case .available = registration.candidate else {
                return false
            }
            return true
        }.count

        switch remoteMessageState {
        case .idle:
            return PromoQueueRemoteMessageCoordinationSnapshot(
                state: .idle,
                messageID: nil,
                sessionID: nil,
                rendererID: nil,
                registrationGenerationID: nil,
                presentationID: nil,
                isQueueAppearanceConfirmed: false,
                isPresentationAppearanceReported: nil,
                removalID: nil,
                removalTerminal: nil,
                drainContinuation: nil,
                selectedRemoteMessageRendererID: selectedRemoteMessageRendererID,
                renderers: rendererSnapshots,
                registeredRendererCount: registeredRendererCount,
                eligibleRendererCount: eligibleRendererCount
            )
        case .owned(let ownedState):
            return PromoQueueRemoteMessageCoordinationSnapshot(
                state: .owned,
                messageID: ownedState.logicalSession.identity.messageID,
                sessionID: ownedState.logicalSession.identity.id,
                rendererID: ownedState.registrationIdentity.rendererID,
                registrationGenerationID: ownedState.registrationIdentity.generationID,
                presentationID: ownedState.presentationID,
                isQueueAppearanceConfirmed: ownedState.logicalSession.isQueueAppearanceConfirmed,
                isPresentationAppearanceReported: ownedState.isCurrentPresentationAppearanceReported,
                removalID: nil,
                removalTerminal: nil,
                drainContinuation: nil,
                selectedRemoteMessageRendererID: selectedRemoteMessageRendererID,
                renderers: rendererSnapshots,
                registeredRendererCount: registeredRendererCount,
                eligibleRendererCount: eligibleRendererCount
            )
        case .draining(let drainingState):
            return PromoQueueRemoteMessageCoordinationSnapshot(
                state: .draining,
                messageID: drainingState.logicalSession.identity.messageID,
                sessionID: drainingState.logicalSession.identity.id,
                rendererID: drainingState.outgoingRegistrationIdentity.rendererID,
                registrationGenerationID: drainingState.outgoingRegistrationIdentity.generationID,
                presentationID: drainingState.outgoingPresentationID,
                isQueueAppearanceConfirmed: drainingState.logicalSession.isQueueAppearanceConfirmed,
                isPresentationAppearanceReported: drainingState.wasOutgoingPresentationAppearanceReported,
                removalID: drainingState.removalID,
                removalTerminal: drainingState.acceptedRemovalTerminal,
                drainContinuation: drainingState.continuation.snapshot,
                selectedRemoteMessageRendererID: selectedRemoteMessageRendererID,
                renderers: rendererSnapshots,
                registeredRendererCount: registeredRendererCount,
                eligibleRendererCount: eligibleRendererCount
            )
        }
    }

    convenience init(
        launchSourceManager: LaunchSourceManaging,
        keyValueStore: ThrowingKeyValueStoring,
        contextualOnboardingStatusProvider: ContextualDaxDialogStatusProvider,
        privacyConfigManager: PrivacyConfigurationManaging,
        providers: ModalPromptProviders,
        promoCoordinationMode: PromoCoordinationMode,
        promoQueueLeaseArbiter: PromoQueueLeaseArbitrating
    ) {

        // Providers are sort from highest to lowest priority, with item at index 0 being the highest priority.
        // Priority order:
        // 1. WinBack Offer
        // 2. Subscription Promo (delayed/reinstaller)
        // 3. Subscription Promo (existing user, day 7)
        // 4. AddressBar Picker
        // 5. Set As Default Browser
        //  5.1 Re-activation Prompt
        //  5.2 Default Browser Prompt
        // 6. What's New
        // 7. Cookie Pop-up Protection opt-in
        let providers: [ModalPromptProvider] = [
            providers.winBackOffer,
            providers.subscriptionPromo,
            providers.subscriptionPromoExistingUser,
            providers.newAddressBarPicker,
            providers.defaultBrowser,
            providers.whatsNew,
            providers.cookiePopupProtectionOptIn,
        ]
        
        let presentationStore = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStore, eventMapper: PromptCooldownStorePixelReporter())
        let cooldownIntervalProvider = PromptCooldownIntervalProvider(privacyConfigManager: privacyConfigManager)
        let cooldownManager = PromptCooldownManager(presentationStore: presentationStore, cooldownIntervalProvider: cooldownIntervalProvider)

        let modalPromptCoordinationManager = ModalPromptCoordinationManager(
            providers: providers,
            cooldownManager: cooldownManager,
            onboardingStatusProvider: contextualOnboardingStatusProvider
        )

        self.init(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: modalPromptCoordinationManager,
            promoCoordinationMode: promoCoordinationMode,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
    }

    init(
        launchSourceManager: LaunchSourceManaging,
        modalPromptCoordinationManager: ModalPromptCoordinationManaging,
        promoCoordinationMode: PromoCoordinationMode,
        promoQueueLeaseArbiter: PromoQueueLeaseArbitrating
    ) {
        self.launchSourceManager = launchSourceManager
        self.modalPromptCoordinationManager = modalPromptCoordinationManager
        self.promoCoordinationMode = promoCoordinationMode
        self.promoQueueLeaseArbiter = promoQueueLeaseArbiter

        modalPromptCoordinationManager.setCoordinatedAttemptReleaseHandler { [weak self] in
            guard self?.promoCoordinationMode == .coordinated else {
                return
            }
            self?.requestRemoteMessageReconciliation()
        }
    }

    func applicationWillResignActive() {
        isApplicationActive = false
        modalPromptCoordinationManager.applicationWillResignActive()
    }

    func applicationDidBecomeActive() {
        isApplicationActive = true
        modalPromptCoordinationManager.applicationDidBecomeActive()

        guard !isWaitingForForegroundInteractionReadiness else {
            return
        }

        if let deferredModalPromptPresenter {
            self.deferredModalPromptPresenter = nil
            presentModalPromptIfNeeded(
                from: deferredModalPromptPresenter,
                readinessToken: foregroundReadinessToken
            )
            return
        }
        requestRemoteMessageReconciliation()
    }

    func applicationDidEnterBackground() {
        isApplicationActive = false
        isWaitingForForegroundInteractionReadiness = true
        foregroundReadinessToken = PromoCoordinationForegroundReadinessToken()
        deferredModalPromptPresenter = nil
        modalPromptCoordinationManager.applicationDidEnterBackground()
    }

    func captureForegroundReadinessToken() -> PromoCoordinationForegroundReadinessToken {
        foregroundReadinessToken
    }

    func presentModalPromptIfNeeded(
        from viewController: ModalPromptPresenter,
        readinessToken: PromoCoordinationForegroundReadinessToken
    ) {
        if promoCoordinationMode == .coordinated {
            // `onAppReadyForInteractions` is asynchronous and can finish after this foreground has already moved to
            // the background. Only the token captured for the current full foreground cycle may open admission. A
            // matching callback received during temporary inactivity still establishes readiness, but its presentation
            // checkpoint is deferred until the app becomes active again.
            guard readinessToken == foregroundReadinessToken else {
                return
            }

            isWaitingForForegroundInteractionReadiness = false
            guard isApplicationActive else {
                deferredModalPromptPresenter = viewController
                return
            }

            deferredModalPromptPresenter = nil
            _ = modalPromptCoordinationManager.reconcilePresentedModal()
            requestRemoteMessageReconciliation()
        }

        guard launchSourceManager.source == .standard else {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Skipping modal prompt - Launched from non-standard source.")
            return
        }

        let presented = viewController.presentedViewController
        let isOmniBarEditing = presented is OmniBarEditingStateViewController
        guard presented == nil || presented?.isBeingDismissed == true || isOmniBarEditing else {
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt - A modal is already presented.")
            return
        }

        Logger.modalPrompt.info("[Modal Prompt Coordination] - ✓ App Launched from standard source.")
        let presentationStatusMessage: String
        if isOmniBarEditing {
            presentationStatusMessage = "OmniBar editing sheet is presented; evaluating modal prompts."
        } else if presented?.isBeingDismissed == true {
            presentationStatusMessage = "A modal is being dismissed; evaluating modal prompts."
        } else {
            presentationStatusMessage = "No Modal is currently presented."
        }
        Logger.modalPrompt.info("[Modal Prompt Coordination] - ✓ \(presentationStatusMessage, privacy: .public)")

        guard promoCoordinationMode == .coordinated else {
            modalPromptCoordinationManager.presentModalPromptIfNeeded(from: viewController)
            return
        }

        switch promoQueueLeaseArbiter.acquireModalLease() {
        case .acquired(let lease):
            switch modalPromptCoordinationManager.presentModalPromptIfNeeded(from: viewController, with: lease) {
            case .retained:
                Logger.modalPrompt.debug("[Modal Prompt Coordination] - The coordinated modal attempt holds the slot.")
            case .released:
                Logger.modalPrompt.debug("[Modal Prompt Coordination] - The coordinated modal attempt released the slot without presenting.")
            }
        case .blockedByModal(let attemptIdentity):
            Logger.modalPrompt.debug(
                """
                [Modal Prompt Coordination] - Skipping modal prompt - \
                Modal attempt \(attemptIdentity.debugIdentifier, privacy: .public) owns the global slot.
                """
            )
        case .blockedByRemoteMessage(let session):
            Logger.modalPrompt.debug(
                "[Modal Prompt Coordination] - Skipping modal prompt - Remote message \(session.messageID, privacy: .public) owns the global slot."
            )
        }
    }

    private func updateRemoteMessageRenderer(
        identity: RemoteMessageRegistrationIdentity,
        candidate: PromoQueueRemoteMessageCandidateState,
        isLocallyReady: Bool
    ) {
        guard let registration = remoteMessageRendererRegistration(matching: identity),
              !registration.isDeregistered else {
            return
        }

        registration.candidate = candidate
        registration.isLocallyReady = isLocallyReady
        requestRemoteMessageReconciliation()
    }

    private func confirmRemoteMessageAppearance(
        registrationIdentity: RemoteMessageRegistrationIdentity,
        sessionID: UUID,
        presentationID: UUID,
        isAttachedToWindow: Bool
    ) -> PromoQueueRemoteMessageAppearanceResult {
        guard case .owned(var ownedState) = remoteMessageState,
              ownedState.logicalSession.identity.id == sessionID,
              ownedState.presentationID == presentationID,
              ownedState.registrationIdentity == registrationIdentity,
              !ownedState.isCurrentPresentationAppearanceReported,
              let registration = remoteMessageRendererRegistration(matching: registrationIdentity),
              isEffectivelyEligible(registration),
              case .available(let messageID) = registration.candidate,
              messageID == ownedState.logicalSession.identity.messageID,
              isAttachedToWindow,
              let target = registration.target,
              target.isRemoteMessageRendererAttachedToWindow else {
            return .rejected
        }

        ownedState.isCurrentPresentationAppearanceReported = true
        ownedState.logicalSession.isQueueAppearanceConfirmed = true
        remoteMessageState = .owned(ownedState)
        return .accepted
    }

    private func remoteMessageRemovalDidReachTerminal(
        registrationIdentity: RemoteMessageRegistrationIdentity,
        sessionID: UUID,
        presentationID: UUID,
        removalID: UUID,
        terminal: PromoQueueRemoteMessageRemovalTerminal
    ) {
        guard case .draining(let drainingState) = remoteMessageState,
              drainingState.logicalSession.identity.id == sessionID,
              drainingState.outgoingPresentationID == presentationID,
              drainingState.outgoingRegistrationIdentity == registrationIdentity,
              drainingState.removalID == removalID,
              drainingState.acceptedRemovalTerminal == nil,
              scheduledRemoteMessageSettlementRemovalID == nil,
              remoteMessageRemovalReadyForSettlementID == nil else {
            return
        }

        if terminal == .hostDetached {
            guard let registration = remoteMessageRendererRegistration(matching: registrationIdentity),
                  let target = registration.target,
                  !target.isRemoteMessageRendererAttachedToWindow else {
                Logger.modalPrompt.error(
                    """
                    [Promo Queue] - Ignoring an unverified host-detachment terminal for remote message \
                    \(drainingState.logicalSession.identity.messageID, privacy: .public).
                    """
                )
                return
            }
        }

        remoteMessageState = .draining(
            DrainingRemoteMessageState(
                logicalSession: drainingState.logicalSession,
                lease: drainingState.lease,
                outgoingRegistrationIdentity: drainingState.outgoingRegistrationIdentity,
                outgoingPresentationID: drainingState.outgoingPresentationID,
                wasOutgoingPresentationAppearanceReported: drainingState.wasOutgoingPresentationAppearanceReported,
                removalID: drainingState.removalID,
                acceptedRemovalTerminal: terminal,
                continuation: drainingState.continuation
            )
        )
        scheduledRemoteMessageSettlementRemovalID = removalID
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  case .draining(let currentDrainingState) = remoteMessageState,
                  currentDrainingState.removalID == removalID,
                  scheduledRemoteMessageSettlementRemovalID == removalID else {
                return
            }

            scheduledRemoteMessageSettlementRemovalID = nil
            remoteMessageRemovalReadyForSettlementID = removalID
            requestRemoteMessageReconciliation()
        }
    }

    private func deregisterRemoteMessageRenderer(identity: RemoteMessageRegistrationIdentity) {
        guard let registration = remoteMessageRendererRegistration(matching: identity),
              !registration.isDeregistered else {
            return
        }

        registration.isDeregistered = true
        registration.isLocallyReady = false
        if !remoteMessageStateReferences(registration.identity) {
            removeRemoteMessageRendererRegistration(matching: identity)
        }
        requestRemoteMessageReconciliation()
    }

    private func requestRemoteMessageReconciliation() {
        guard promoCoordinationMode == .coordinated else {
            return
        }

        needsRemoteMessageReconciliation = true
        guard !isReconcilingRemoteMessages else {
            return
        }

        isReconcilingRemoteMessages = true
        defer { isReconcilingRemoteMessages = false }

        while needsRemoteMessageReconciliation {
            needsRemoteMessageReconciliation = false
            reconcileOneRemoteMessageStep()
        }
    }

    private func reconcileOneRemoteMessageStep() {
        removeUnusedRemoteMessageRendererRegistrations()

        switch remoteMessageState {
        case .idle:
            acquireRemoteMessageSessionIfPossible()
        case .owned(let ownedState):
            reconcileOwnedRemoteMessage(ownedState)
        case .draining(let drainingState):
            reconcileDrainingRemoteMessage(drainingState)
        }
    }

    private func acquireRemoteMessageSessionIfPossible() {
        guard isApplicationActive,
              !isWaitingForForegroundInteractionReadiness,
              let registration = firstEligibleRemoteMessageRenderer() else {
            return
        }

        guard case .available(let messageID) = registration.candidate else {
            return
        }

        _ = modalPromptCoordinationManager.reconcilePresentedModal()

        let session = PromoQueueRemoteMessageSession(id: UUID(), messageID: messageID)
        switch promoQueueLeaseArbiter.acquireRemoteMessageLease(for: session) {
        case .acquired(let lease):
            let logicalSession = LogicalRemoteMessageSession(identity: session)
            authorizeRemoteMessage(
                logicalSession: logicalSession,
                lease: lease,
                messageID: messageID
            )
        case .blockedByModal(let attemptIdentity):
            Logger.modalPrompt.debug(
                "[Promo Queue] - Deferring RMF while modal attempt \(attemptIdentity.debugIdentifier, privacy: .public) owns the global slot."
            )
        case .blockedByRemoteMessage(let occupyingSession):
            Logger.modalPrompt.error(
                "[Promo Queue] - Logical remote message \(occupyingSession.messageID, privacy: .public) is owned outside the service state."
            )
        }
    }

    private func authorizeRemoteMessage(
        logicalSession: LogicalRemoteMessageSession,
        lease: PromoQueueRemoteMessageLease,
        messageID: String
    ) {
        var attemptedRegistrationIdentities = Set<UUID>()

        while let registration = firstEligibleRemoteMessageRenderer(
            messageID: messageID,
            excludingGenerationIDs: attemptedRegistrationIdentities
        ) {
            attemptedRegistrationIdentities.insert(registration.identity.generationID)
            guard let target = registration.target else {
                removeRemoteMessageRendererRegistration(matching: registration.identity)
                continue
            }

            let presentationID = UUID()
            let ownedState = OwnedRemoteMessageState(
                logicalSession: logicalSession,
                lease: lease,
                registrationIdentity: registration.identity,
                presentationID: presentationID
            )
            remoteMessageState = .owned(ownedState)
            let presentation = PromoQueueRemoteMessagePresentation(
                id: presentationID,
                session: logicalSession.identity
            )

            guard !target.showRemoteMessage(presentation) else {
                return
            }

            guard !target.hasPublishedRemoteMessagePresentation else {
                Logger.modalPrompt.error(
                    "[Promo Queue] - Retaining ownership because a renderer rejected authorization while coordinated content remained published."
                )
                return
            }

            guard case .owned(let currentOwnedState) = remoteMessageState,
                  currentOwnedState.logicalSession.identity == logicalSession.identity,
                  currentOwnedState.registrationIdentity == registration.identity,
                  currentOwnedState.presentationID == presentationID else {
                return
            }

            if case .available(let currentMessageID) = registration.candidate,
               currentMessageID == messageID {
                registration.candidate = .unrenderable(messageID: messageID)
            }
        }

        remoteMessageState = .idle
        _ = lease.release()
        needsRemoteMessageReconciliation = true
    }

    private func reconcileOwnedRemoteMessage(_ ownedState: OwnedRemoteMessageState) {
        guard let registration = remoteMessageRendererRegistration(matching: ownedState.registrationIdentity) else {
            logUnexpectedRemoteMessageRendererLoss(messageID: ownedState.logicalSession.identity.messageID)
            return
        }
        guard let target = registration.target else {
            logUnexpectedRemoteMessageRendererLoss(messageID: ownedState.logicalSession.identity.messageID)
            return
        }

        let continuation: RemoteMessageDrainContinuation?
        switch registration.candidate {
        case .available(let messageID) where messageID == ownedState.logicalSession.identity.messageID:
            continuation = isEffectivelyEligible(registration) ? nil : .transferSameMessageIfAvailable
        case .available, .none, .unrenderable:
            continuation = .endSession
        }

        guard let continuation else {
            return
        }

        let removalID = UUID()
        let drainingState = DrainingRemoteMessageState(
            logicalSession: ownedState.logicalSession,
            lease: ownedState.lease,
            outgoingRegistrationIdentity: ownedState.registrationIdentity,
            outgoingPresentationID: ownedState.presentationID,
            wasOutgoingPresentationAppearanceReported: ownedState.isCurrentPresentationAppearanceReported,
            removalID: removalID,
            acceptedRemovalTerminal: nil,
            continuation: continuation
        )
        remoteMessageState = .draining(drainingState)
        let presentation = PromoQueueRemoteMessagePresentation(
            id: ownedState.presentationID,
            session: ownedState.logicalSession.identity
        )
        target.hideRemoteMessage(presentation, removalID: removalID)
    }

    private func settleDrainingRemoteMessage(_ drainingState: DrainingRemoteMessageState) {
        remoteMessageRemovalReadyForSettlementID = nil
        removeUnusedRemoteMessageRendererRegistrations()

        switch drainingState.continuation {
        case .endSession:
            remoteMessageState = .idle
            _ = drainingState.lease.release()
            needsRemoteMessageReconciliation = true
        case .transferSameMessageIfAvailable:
            let messageID = drainingState.logicalSession.identity.messageID
            guard firstEligibleRemoteMessageRenderer(messageID: messageID) != nil else {
                remoteMessageState = .idle
                _ = drainingState.lease.release()
                needsRemoteMessageReconciliation = true
                return
            }

            authorizeRemoteMessage(
                logicalSession: drainingState.logicalSession,
                lease: drainingState.lease,
                messageID: messageID
            )
            // The outgoing record was still state-referenced during the pre-settlement cleanup. Reconcile once more
            // after authorization so a deregistered or deallocated outgoing generation is removed.
            needsRemoteMessageReconciliation = true
        }
    }

    private func reconcileDrainingRemoteMessage(_ drainingState: DrainingRemoteMessageState) {
        var drainingState = drainingState
        if scheduledRemoteMessageSettlementRemovalID == nil,
           remoteMessageRemovalReadyForSettlementID == nil,
           remoteMessageRendererRegistration(matching: drainingState.outgoingRegistrationIdentity)?.target == nil {
            logUnexpectedRemoteMessageRendererLoss(messageID: drainingState.logicalSession.identity.messageID)
            return
        }

        if case .transferSameMessageIfAvailable = drainingState.continuation {
            guard let registration = remoteMessageRendererRegistration(matching: drainingState.outgoingRegistrationIdentity) else {
                logUnexpectedRemoteMessageRendererLoss(messageID: drainingState.logicalSession.identity.messageID)
                return
            }

            switch registration.candidate {
            case .available(let messageID) where messageID == drainingState.logicalSession.identity.messageID:
                break
            case .available, .none, .unrenderable:
                drainingState = DrainingRemoteMessageState(
                    logicalSession: drainingState.logicalSession,
                    lease: drainingState.lease,
                    outgoingRegistrationIdentity: drainingState.outgoingRegistrationIdentity,
                    outgoingPresentationID: drainingState.outgoingPresentationID,
                    wasOutgoingPresentationAppearanceReported: drainingState.wasOutgoingPresentationAppearanceReported,
                    removalID: drainingState.removalID,
                    acceptedRemovalTerminal: drainingState.acceptedRemovalTerminal,
                    continuation: .endSession
                )
                remoteMessageState = .draining(drainingState)
            }
        }

        guard remoteMessageRemovalReadyForSettlementID == drainingState.removalID else {
            return
        }
        settleDrainingRemoteMessage(drainingState)
    }

    private func firstEligibleRemoteMessageRenderer() -> WeakRemoteMessageRendererRegistration? {
        remoteMessageRendererRegistrations
            .filter { registration in
                guard isEffectivelyEligible(registration) else {
                    return false
                }
                guard case .available = registration.candidate else {
                    return false
                }
                return true
            }
            .min { $0.stableOrder < $1.stableOrder }
    }

    private func firstEligibleRemoteMessageRenderer(
        messageID: String,
        excludingGenerationIDs: Set<UUID> = []
    ) -> WeakRemoteMessageRendererRegistration? {
        remoteMessageRendererRegistrations
            .filter { registration in
                guard isEffectivelyEligible(registration),
                      !excludingGenerationIDs.contains(registration.identity.generationID),
                      case .available(let candidateMessageID) = registration.candidate else {
                    return false
                }
                return candidateMessageID == messageID
            }
            .min { $0.stableOrder < $1.stableOrder }
    }

    private func isEffectivelyEligible(_ registration: WeakRemoteMessageRendererRegistration) -> Bool {
        !registration.isDeregistered
            && registration.isLocallyReady
            && registration.identity.rendererID == selectedRemoteMessageRendererID
            && registration.target != nil
    }

    private func remoteMessageRendererRegistration(
        matching identity: RemoteMessageRegistrationIdentity
    ) -> WeakRemoteMessageRendererRegistration? {
        remoteMessageRendererRegistrations.first { $0.identity == identity }
    }

    private func removeRemoteMessageRendererRegistration(matching identity: RemoteMessageRegistrationIdentity) {
        remoteMessageRendererRegistrations.removeAll { $0.identity == identity }
    }

    private func removeUnusedRemoteMessageRendererRegistrations() {
        remoteMessageRendererRegistrations.removeAll { registration in
            guard registration.isDeregistered || registration.target == nil else {
                return false
            }
            return !remoteMessageStateReferences(registration.identity)
        }
    }

    private func remoteMessageStateReferences(_ identity: RemoteMessageRegistrationIdentity) -> Bool {
        switch remoteMessageState {
        case .idle:
            return false
        case .owned(let ownedState):
            return ownedState.registrationIdentity == identity
        case .draining(let drainingState):
            return drainingState.outgoingRegistrationIdentity == identity
        }
    }

    private func logUnexpectedRemoteMessageRendererLoss(messageID: String) {
        Logger.modalPrompt.error(
            "[Promo Queue] - Retaining the global owner because renderer for remote message \(messageID, privacy: .public) was unexpectedly lost."
        )
    }
}

extension PromoCoordinationService: NewTabPagePromoCoordinating {
    func setSelectedRemoteMessageRendererID(_ rendererID: UUID?) {
        guard promoCoordinationMode == .coordinated,
              selectedRemoteMessageRendererID != rendererID else {
            return
        }

        selectedRemoteMessageRendererID = rendererID
        requestRemoteMessageReconciliation()
    }

    func registerRemoteMessageRenderer(
        id rendererID: UUID,
        target: NewTabPagePromoRendering
    ) -> NewTabPagePromoRendererRegistration {
        guard promoCoordinationMode == .coordinated else {
            return NewTabPagePromoRendererRegistration(isNoOpRegistration: true)
        }

        for registration in remoteMessageRendererRegistrations where registration.identity.rendererID == rendererID {
            registration.isDeregistered = true
            registration.isLocallyReady = false
        }
        removeUnusedRemoteMessageRendererRegistrations()

        let identity = RemoteMessageRegistrationIdentity(
            rendererID: rendererID,
            generationID: UUID()
        )
        let registration = WeakRemoteMessageRendererRegistration(
            identity: identity,
            stableOrder: nextRemoteMessageRegistrationOrder,
            target: target
        )
        nextRemoteMessageRegistrationOrder += 1
        remoteMessageRendererRegistrations.append(registration)
        requestRemoteMessageReconciliation()

        return NewTabPagePromoRendererRegistration(
            updateHandler: { [weak self] candidate, isLocallyReady in
                self?.updateRemoteMessageRenderer(
                    identity: identity,
                    candidate: candidate,
                    isLocallyReady: isLocallyReady
                )
            },
            appearanceHandler: { [weak self] sessionID, presentationID, isAttachedToWindow in
                self?.confirmRemoteMessageAppearance(
                    registrationIdentity: identity,
                    sessionID: sessionID,
                    presentationID: presentationID,
                    isAttachedToWindow: isAttachedToWindow
                ) ?? .rejected
            },
            removalTerminalHandler: { [weak self] sessionID, presentationID, removalID, terminal in
                self?.remoteMessageRemovalDidReachTerminal(
                    registrationIdentity: identity,
                    sessionID: sessionID,
                    presentationID: presentationID,
                    removalID: removalID,
                    terminal: terminal
                )
            },
            deregistrationHandler: { [weak self] in
                self?.deregisterRemoteMessageRenderer(identity: identity)
            }
        )
    }
}

extension PromoCoordinationService: RecentModalPromptStatusProviding {
    var shouldSuppressOtherSessionPromos: Bool { modalPromptCoordinationManager.shouldSuppressOtherSessionPromos }
}
