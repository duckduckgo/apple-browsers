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

/// Coordinates app-launch modal prompts with visible new-tab promos.
///
/// Foreground and promo-admission checkpoints reconcile dismissed modals, then weakly registered active promo surfaces
/// are retried when a slot may be free. The process-wide coordination mode is immutable for this service's lifetime.
@MainActor
final class PromoCoordinationService {
    private final class WeakRemoteMessageRetryRegistration {
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
    private var remoteMessageRetryRegistrations = [WeakRemoteMessageRetryRegistration]()
    private var isRetryingRemoteMessageRegistrations = false
    private var isApplicationActive = false
    private var isWaitingForForegroundInteractionReadiness = true
    private var foregroundReadinessToken = PromoCoordinationForegroundReadinessToken()
    private weak var deferredModalPromptPresenter: ModalPromptPresenter?

    let promoCoordinationMode: PromoCoordinationMode

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
            self?.retryActiveRemoteMessageRegistrations()
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
        retryActiveRemoteMessageRegistrations()
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
            retryActiveRemoteMessageRegistrations()
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
                "[Modal Prompt Coordination] - Skipping modal prompt - Modal attempt \(attemptIdentity.debugIdentifier, privacy: .public) owns the global slot."
            )
        case .blockedByVisiblePromo(let identity):
            Logger.modalPrompt.debug(
                "[Modal Prompt Coordination] - Skipping modal prompt - Visible promo \(identity.promoID, privacy: .public) owns the global slot."
            )
        }
    }

    private func admitCoordinatedRemoteMessage(_ identity: VisiblePromoIdentity) -> PromoQueueRemoteMessageAdmissionResult {
        let didReleaseModalLease = modalPromptCoordinationManager.reconcilePresentedModal()
        let result: PromoQueueRemoteMessageAdmissionResult
        switch promoQueueLeaseArbiter.acquireVisiblePromoLease(for: identity) {
        case .acquired(let lease):
            result = .acquired(makeRemoteMessageAdmission(
                lease: lease,
                surfaceID: identity.surfaceID
            ))
        case .blockedByModal(let attemptIdentity):
            Logger.modalPrompt.debug(
                "[Promo Queue] - Deferring RMF while modal attempt \(attemptIdentity.debugIdentifier, privacy: .public) owns the global slot."
            )
            result = .deferred
        case .blockedByVisiblePromo(let occupyingIdentity):
            Logger.modalPrompt.debug(
                "[Promo Queue] - Deferring RMF while visible promo \(occupyingIdentity.promoID, privacy: .public) owns the global slot."
            )
            result = .deferred
        }

        if didReleaseModalLease {
            // Excludes the *requesting* surface, whose admission this call has just completed, rather than any identity
            // carried back by the arbiter's answer.
            retryActiveRemoteMessageRegistrations(excluding: identity.surfaceID)
        }
        return result
    }

    private func makeRemoteMessageAdmission(
        lease: PromoQueueVisiblePromoLease,
        surfaceID: UUID
    ) -> PromoQueueRemoteMessageAdmission {
        PromoQueueRemoteMessageAdmission { [weak self, lease] in
            guard lease.release() else {
                return
            }
            self?.offerRemoteMessageReleaseHandoff(excluding: surfaceID)
        }
    }

    private func deregisterRemoteMessageRetry(for surfaceID: UUID, registrationID: UUID) {
        remoteMessageRetryRegistrations.removeAll {
            $0.surfaceID == surfaceID && $0.id == registrationID
        }
    }

    private func retryActiveRemoteMessageRegistrations(excluding excludedSurfaceID: UUID? = nil) {
        retryActiveRemoteMessageRegistrations(
            excluding: excludedSurfaceID,
            using: admitRemoteMessage
        )
    }

    private func retryActiveRemoteMessageRegistrations(
        excluding excludedSurfaceID: UUID?,
        using admissionHandler: PromoQueueRemoteMessageAdmissionHandler
    ) {
        guard promoCoordinationMode == .coordinated,
              isApplicationActive,
              !isWaitingForForegroundInteractionReadiness,
              !isRetryingRemoteMessageRegistrations else {
            return
        }

        isRetryingRemoteMessageRegistrations = true
        defer {
            isRetryingRemoteMessageRegistrations = false
            remoteMessageRetryRegistrations.removeAll { $0.target == nil }
        }

        let registrationsSnapshot = remoteMessageRetryRegistrations
        for registration in registrationsSnapshot {
            guard registration.surfaceID != excludedSurfaceID,
                  remoteMessageRetryRegistrations.contains(where: { $0.id == registration.id }),
                  let target = registration.target,
                  target.isActiveForPromoRetry else {
                continue
            }
            target.retryRemoteMessageAdmission(using: admissionHandler)
        }
    }

    private func offerRemoteMessageReleaseHandoff(excluding surfaceID: UUID) {
        retryActiveRemoteMessageRegistrations(excluding: surfaceID)
    }

}

extension PromoCoordinationService: NewTabPagePromoCoordinating {
    func admitRemoteMessage(_ identity: VisiblePromoIdentity) -> PromoQueueRemoteMessageAdmissionResult {
        switch promoCoordinationMode {
        case .legacy:
            return .deferred
        case .coordinated:
            break
        }

        guard isApplicationActive,
              !isWaitingForForegroundInteractionReadiness else {
            return .deferred
        }

        return admitCoordinatedRemoteMessage(identity)
    }

    func registerRemoteMessageRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration {
        let registrationID = UUID()
        let registration = WeakRemoteMessageRetryRegistration(
            id: registrationID,
            surfaceID: surfaceID,
            target: target
        )

        remoteMessageRetryRegistrations.removeAll { $0.surfaceID == surfaceID || $0.target == nil }
        remoteMessageRetryRegistrations.append(registration)

        return NewTabPagePromoRetryRegistration { [weak self] in
            self?.deregisterRemoteMessageRetry(
                for: surfaceID,
                registrationID: registrationID
            )
        }
    }
}

extension PromoCoordinationService: RecentModalPromptStatusProviding {
    var shouldSuppressOtherSessionPromos: Bool { modalPromptCoordinationManager.shouldSuppressOtherSessionPromos }
}
