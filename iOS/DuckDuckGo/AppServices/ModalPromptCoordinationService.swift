//
//  ModalPromptCoordinationService.swift
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

// MARK: - Modal Prompt Presenter

@MainActor
protocol ModalPromptPresenter: AnyObject {
    var presentedViewController: UIViewController? { get }
    var modalPromptPresentationViewController: UIViewController? { get }

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
}

extension MainViewController: ModalPromptPresenter {
    var modalPromptPresentationViewController: UIViewController? { self }
}

// MARK: - Promo Queue Feature State

enum PromoQueueFeatureTargetState: Equatable {
    case disabled
    case enabled

    init(isEnabled: Bool) {
        self = isEnabled ? .enabled : .disabled
    }
}

enum PromoQueueFeatureState: Equatable {
    case disabled
    case transitioning(to: PromoQueueFeatureTargetState)
    case enabled

    init(targetState: PromoQueueFeatureTargetState) {
        switch targetState {
        case .disabled:
            self = .disabled
        case .enabled:
            self = .enabled
        }
    }

    var isTransitioning: Bool {
        if case .transitioning = self {
            return true
        }
        return false
    }
}

enum VisiblePromoAdmissionResult {
    case acquired(PromoQueueVisiblePromoLease)
    case blockedByModal
    case blockedByVisiblePromos(Set<VisiblePromoIdentity>)
    case occupiedSurfaceSlot(VisiblePromoIdentity)
    case featureDisabled
    case unavailableDuringTransition
}

@MainActor
protocol NewTabPagePromoRetrying: AnyObject {
    var isActiveForPromoRetry: Bool { get }

    func retryVisiblePromoAdmission()
}

@MainActor
final class NewTabPagePromoRetryRegistration {
    private var deregistrationHandler: (@MainActor () -> Void)?

    init(deregistrationHandler: (@MainActor () -> Void)? = nil) {
        self.deregistrationHandler = deregistrationHandler
    }

    func deregister() {
        let deregistrationHandler = deregistrationHandler
        self.deregistrationHandler = nil
        deregistrationHandler?()
    }
}

@MainActor
protocol NewTabPagePromoCoordinating: AnyObject {
    var promoQueueFeatureState: PromoQueueFeatureState { get }

    func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult
    func releaseVisiblePromoLease(_ lease: PromoQueueVisiblePromoLease)
    func registerVisiblePromoRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration
}

extension NewTabPagePromoCoordinating {
    func admitVisiblePromo(_ identity: VisiblePromoIdentity) -> VisiblePromoAdmissionResult {
        .featureDisabled
    }

    func releaseVisiblePromoLease(_ lease: PromoQueueVisiblePromoLease) {
        lease.release()
    }

    func registerVisiblePromoRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration {
        NewTabPagePromoRetryRegistration()
    }
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

@MainActor
final class ModalPromptCoordinationService {
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

        let initialTargetState = PromoQueueFeatureTargetState(isEnabled: featureFlagger.isFeatureOn(.promoQueue))
        promoQueueFeatureState = PromoQueueFeatureState(targetState: initialTargetState)
        subscribeToPromoQueueFeatureState(initialTargetState: initialTargetState)
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
            let disposition = modalPromptCoordinationManager.presentModalPromptIfNeeded(
                from: viewController,
                with: lease
            )
            if disposition == .released {
                retryActiveVisiblePromoRegistrations()
            }
        case .blockedByModal:
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt - A coordinated modal attempt already owns the slot.")
        case .blockedByVisiblePromos:
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt - One or more visible promos own the slot.")
        case .occupiedSurfaceSlot:
            assertionFailure("Modal lease acquisition cannot be blocked by an occupied surface slot.")
        }
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

        let didReleaseModalLease = modalPromptCoordinationManager.reconcilePresentedModal()
        let result: VisiblePromoAdmissionResult
        switch promoQueueLeaseArbiter.acquireVisiblePromoLease(for: identity) {
        case .acquired(let lease):
            result = .acquired(lease)
        case .blockedByModal:
            result = .blockedByModal
        case .blockedByVisiblePromos(let identities):
            result = .blockedByVisiblePromos(identities)
        case .occupiedSurfaceSlot(let identity):
            result = .occupiedSurfaceSlot(identity)
        }

        if didReleaseModalLease {
            retryActiveVisiblePromoRegistrations(excluding: identity.surfaceID)
        }
        return result
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

        promoRetryRegistrations.removeAll { $0.surfaceID == surfaceID }
        promoRetryRegistrations.append(registration)

        return NewTabPagePromoRetryRegistration { [weak self] in
            self?.deregisterVisiblePromoRetry(
                for: surfaceID,
                registrationID: registrationID
            )
        }
    }

    private func subscribeToPromoQueueFeatureState(initialTargetState: PromoQueueFeatureTargetState) {
        promoQueueFeatureStateCancellable = featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .map { [featureFlagger] in
                PromoQueueFeatureTargetState(isEnabled: featureFlagger.isFeatureOn(.promoQueue))
            }
            .prepend(initialTargetState)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] targetState in
                self?.transitionPromoQueueFeature(to: targetState)
            }
    }

    private func transitionPromoQueueFeature(to targetState: PromoQueueFeatureTargetState) {
        guard !promoQueueFeatureState.isTransitioning else {
            pendingPromoQueueFeatureTargetState = targetState
            return
        }

        guard promoQueueFeatureState != PromoQueueFeatureState(targetState: targetState) else {
            return
        }

        promoQueueFeatureState = .transitioning(to: targetState)
        defer {
            promoQueueFeatureState = PromoQueueFeatureState(targetState: targetState)

            if let pendingTargetState = pendingPromoQueueFeatureTargetState {
                pendingPromoQueueFeatureTargetState = nil
                transitionPromoQueueFeature(to: pendingTargetState)
            }
        }

        modalPromptCoordinationManager.promoQueueWillTransition(to: targetState)

        promoQueueLeaseArbiter.invalidateAllLeases()

        modalPromptCoordinationManager.promoQueueDidTransition(to: targetState)

        promoQueueFeatureState = PromoQueueFeatureState(targetState: targetState)
        if targetState == .enabled {
            retryActiveVisiblePromoRegistrations()
        }
    }

    private func deregisterVisiblePromoRetry(for surfaceID: UUID, registrationID: UUID) {
        promoRetryRegistrations.removeAll {
            $0.surfaceID == surfaceID && $0.id == registrationID
        }
    }

    private func retryActiveVisiblePromoRegistrations(excluding excludedSurfaceID: UUID? = nil) {
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
            target.retryVisiblePromoAdmission()
        }
    }

}

extension ModalPromptCoordinationService: NewTabPagePromoCoordinating {}

extension ModalPromptCoordinationService: RecentModalPromptStatusProviding {
    var wasModalPromptRecentlyPresented: Bool { modalPromptCoordinationManager.didPresentModalPromptThisSession }
}
