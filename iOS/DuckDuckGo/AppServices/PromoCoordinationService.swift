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

import Combine
import Core
import Persistence
import PrivacyConfig
import UIKit
import FeatureFlags_iOS

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

struct PromoQueueDebugSnapshot: Equatable {
    let isFeatureEnabled: Bool
    let featureState: PromoQueueFeatureState
    let hasModalLease: Bool
    let modalAttemptPhase: ModalPromptAttemptPhase
    let hasPendingModalPrompt: Bool
    let activeVisiblePromoLeaseCount: Int
}

@MainActor
protocol PromoQueueDebugSnapshotProviding: AnyObject {
    var promoQueueDebugSnapshot: PromoQueueDebugSnapshot { get }
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

/// Coordinates app-launch modal prompts with visible new-tab promos.
///
/// The transitioning state blocks admission while leases and manager state are reset. Foreground and promo-admission
/// checkpoints reconcile dismissed modals, then weakly registered active promo surfaces are retried when a slot may be free.
@MainActor
final class PromoCoordinationService {
    private final class WeakPromoRetryRegistration {
        let id: UUID
        let surfaceID: UUID
        weak var target: NewTabPagePromoRetrying?

        init(id: UUID, surfaceID: UUID, target: NewTabPagePromoRetrying) {
            self.id = id
            self.surfaceID = surfaceID
            self.target = target
        }
    }

    private let modalPromptCoordinationManager: ModalPromptCoordinationManaging
    private let launchSourceManager: LaunchSourceManaging
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbitrating
    private let featureFlagger: FeatureFlagger
    private var promoQueueFeatureStateCancellable: AnyCancellable?
    private var pendingPromoQueueFeatureTargetState: PromoQueueFeatureTargetState?
    private var promoRetryRegistrations = [WeakPromoRetryRegistration]()
    private var isRetryingVisiblePromoRegistrations = false
    private let promoQueueFeatureStateSubject: CurrentValueSubject<PromoQueueFeatureState, Never>

    private(set) var promoQueueFeatureState: PromoQueueFeatureState

    convenience init(
        launchSourceManager: LaunchSourceManaging,
        keyValueStore: ThrowingKeyValueStoring,
        contextualOnboardingStatusProvider: ContextualDaxDialogStatusProvider,
        privacyConfigManager: PrivacyConfigurationManaging,
        providers: ModalPromptProviders,
        featureFlagger: FeatureFlagger,
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
            onboardingStatusProvider: contextualOnboardingStatusProvider,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )

        self.init(
            launchSourceManager: launchSourceManager,
            modalPromptCoordinationManager: modalPromptCoordinationManager,
            featureFlagger: featureFlagger,
            promoQueueLeaseArbiter: promoQueueLeaseArbiter
        )
    }

    init(
        launchSourceManager: LaunchSourceManaging,
        modalPromptCoordinationManager: ModalPromptCoordinationManaging,
        featureFlagger: FeatureFlagger,
        promoQueueLeaseArbiter: PromoQueueLeaseArbitrating
    ) {
        self.launchSourceManager = launchSourceManager
        self.modalPromptCoordinationManager = modalPromptCoordinationManager
        self.featureFlagger = featureFlagger
        self.promoQueueLeaseArbiter = promoQueueLeaseArbiter

        let initialTargetState = PromoQueueFeatureTargetState(isEnabled: featureFlagger.isFeatureOn(.promoPresentationCoordination))
        let initialFeatureState = PromoQueueFeatureState(targetState: initialTargetState)
        promoQueueFeatureState = initialFeatureState
        promoQueueFeatureStateSubject = CurrentValueSubject(initialFeatureState)
        modalPromptCoordinationManager.setCoordinatedAttemptReleaseHandler { [weak self] in
            guard self?.promoQueueFeatureState == .enabled else {
                return
            }
            self?.retryActiveVisiblePromoRegistrations()
        }
        subscribeToPromoQueueFeatureState(initialTargetState: initialTargetState)
    }

    func applicationWillResignActive() {
        modalPromptCoordinationManager.applicationWillResignActive()
    }

    func applicationDidBecomeActive() {
        modalPromptCoordinationManager.applicationDidBecomeActive()
    }

    func applicationDidEnterBackground() {
        modalPromptCoordinationManager.applicationDidEnterBackground()
    }

    func presentModalPromptIfNeeded(from viewController: ModalPromptPresenter) {
        guard !promoQueueFeatureState.isTransitioning else {
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt during promo queue feature transition.")
            return
        }

        if promoQueueFeatureState == .enabled {
            _ = modalPromptCoordinationManager.reconcilePresentedModal()
            retryActiveVisiblePromoRegistrations()
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

        guard promoQueueFeatureState == .enabled else {
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
        case .blockedByModal:
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt - A coordinated modal attempt already owns the slot.")
        case .blockedByVisiblePromos:
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt - One or more visible promos own the slot.")
        }
    }

    private func admitCoordinatedVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult {
        let didReleaseModalLease = modalPromptCoordinationManager.reconcilePresentedModal()
        let result: VisiblePromoAdmissionResult
        switch promoQueueLeaseArbiter.acquireVisiblePromoLease(for: identity) {
        case .acquired(let lease):
            result = .acquired(lease)
        case .blockedByModal:
            result = .blockedByModal
        case .occupiedSurfaceSlot(let occupyingIdentity):
            result = .occupiedSurfaceSlot(occupyingIdentity)
        }

        if didReleaseModalLease {
            // Excludes the *requesting* surface, whose admission this call has just completed, rather than any identity
            // carried back by the arbiter's answer.
            retryActiveVisiblePromoRegistrations(excluding: identity.surfaceID)
        }
        return result
    }

    private func subscribeToPromoQueueFeatureState(initialTargetState: PromoQueueFeatureTargetState) {
        promoQueueFeatureStateCancellable = featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .map { [featureFlagger] in
                PromoQueueFeatureTargetState(isEnabled: featureFlagger.isFeatureOn(.promoPresentationCoordination))
            }
            .prepend(initialTargetState)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] targetState in
                self?.transitionPromoQueueFeature(to: targetState)
            }

        // Re-read after the subscriber is attached so a flag update emitted while the subscription was being
        // established cannot leave the initial seed stale.
        let subscribedTargetState = PromoQueueFeatureTargetState(isEnabled: featureFlagger.isFeatureOn(.promoPresentationCoordination))
        transitionPromoQueueFeature(to: subscribedTargetState)
    }

    private func transitionPromoQueueFeature(to targetState: PromoQueueFeatureTargetState) {
        guard !promoQueueFeatureState.isTransitioning else {
            pendingPromoQueueFeatureTargetState = targetState
            return
        }

        guard promoQueueFeatureState != PromoQueueFeatureState(targetState: targetState) else {
            return
        }

        updatePromoQueueFeatureState(.transitioning(to: targetState))
        defer {
            // Keep the public barrier up through manager and NTP callbacks. Publish the completed state before draining
            // a reentrant flag update so the pending transition starts from a stable source state and its result cannot
            // be overwritten by this transition.
            updatePromoQueueFeatureState(PromoQueueFeatureState(targetState: targetState))
            if let pendingTargetState = pendingPromoQueueFeatureTargetState {
                pendingPromoQueueFeatureTargetState = nil
                transitionPromoQueueFeature(to: pendingTargetState)
            }
        }

        modalPromptCoordinationManager.promoQueueWillTransition(to: targetState)
        let registrationsSnapshot = promoRetryRegistrations
        for registration in registrationsSnapshot {
            registration.target?.promoQueueWillTransition(to: targetState)
        }

        promoQueueLeaseArbiter.invalidateAllLeases()

        modalPromptCoordinationManager.promoQueueDidTransition(to: targetState)
        for registration in registrationsSnapshot {
            registration.target?.promoQueueDidTransition(to: targetState)
        }
    }

    private func updatePromoQueueFeatureState(_ state: PromoQueueFeatureState) {
        promoQueueFeatureState = state
        promoQueueFeatureStateSubject.send(state)
    }

    private func deregisterVisiblePromoRetry(for surfaceID: UUID, registrationID: UUID) {
        promoRetryRegistrations.removeAll {
            $0.surfaceID == surfaceID && $0.id == registrationID
        }
    }

    private func retryActiveVisiblePromoRegistrations(excluding excludedSurfaceID: UUID? = nil) {
        retryActiveVisiblePromoRegistrations(
            excluding: excludedSurfaceID,
            using: admitVisiblePromo
        )
    }

    private func retryActiveVisiblePromoRegistrations(
        excluding excludedSurfaceID: UUID?,
        using admissionHandler: VisiblePromoAdmissionHandler
    ) {
        guard !isRetryingVisiblePromoRegistrations else {
            return
        }

        isRetryingVisiblePromoRegistrations = true
        defer {
            isRetryingVisiblePromoRegistrations = false
            promoRetryRegistrations.removeAll { $0.target == nil }
        }

        let registrationsSnapshot = promoRetryRegistrations
        for registration in registrationsSnapshot {
            guard registration.surfaceID != excludedSurfaceID,
                  promoRetryRegistrations.contains(where: { $0.id == registration.id }),
                  let target = registration.target,
                  target.isActiveForPromoRetry else {
                continue
            }
            target.retryVisiblePromoAdmission(using: admissionHandler)
        }
    }

}

extension PromoCoordinationService: NewTabPagePromoCoordinating {
    var promoQueueFeatureStatePublisher: AnyPublisher<PromoQueueFeatureState, Never> {
        promoQueueFeatureStateSubject.eraseToAnyPublisher()
    }

    func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult {
        switch promoQueueFeatureState {
        case .disabled:
            return .featureDisabled
        case .transitioning:
            return .unavailableDuringTransition
        case .enabled:
            break
        }

        return admitCoordinatedVisiblePromo(identity)
    }

    func releaseVisiblePromoLease(_ lease: PromoQueueVisiblePromoLease) {
        lease.release()
    }

    func registerVisiblePromoRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration {
        let registrationID = UUID()
        let registration = WeakPromoRetryRegistration(
            id: registrationID,
            surfaceID: surfaceID,
            target: target
        )

        promoRetryRegistrations.removeAll { $0.surfaceID == surfaceID || $0.target == nil }
        promoRetryRegistrations.append(registration)

        return NewTabPagePromoRetryRegistration { [weak self] in
            self?.deregisterVisiblePromoRetry(
                for: surfaceID,
                registrationID: registrationID
            )
        }
    }
}

extension PromoCoordinationService: RecentModalPromptStatusProviding {
    var wasModalPromptRecentlyPresented: Bool { modalPromptCoordinationManager.didPresentModalPromptThisSession }
}

extension PromoCoordinationService: PromoQueueDebugSnapshotProviding {
    var promoQueueDebugSnapshot: PromoQueueDebugSnapshot {
        let leaseSnapshot = promoQueueLeaseArbiter.snapshot
        return PromoQueueDebugSnapshot(
            isFeatureEnabled: featureFlagger.isFeatureOn(.promoPresentationCoordination),
            featureState: promoQueueFeatureState,
            hasModalLease: leaseSnapshot.hasModalLease,
            modalAttemptPhase: modalPromptCoordinationManager.modalAttemptPhase,
            hasPendingModalPrompt: modalPromptCoordinationManager.hasPendingModalPrompt,
            activeVisiblePromoLeaseCount: leaseSnapshot.visiblePromoCount
        )
    }
}
