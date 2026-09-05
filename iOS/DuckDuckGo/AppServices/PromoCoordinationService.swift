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
import UIKit

// MARK: - Modal Prompt Presenter

@MainActor
protocol ModalPromptPresenter: AnyObject {
    var presentedViewController: UIViewController? { get }

    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)
}

extension MainViewController: ModalPromptPresenter {}

// MARK: - Service

struct ModalPromptProviders {
    let appRatingPrompt: ModalPromptProvider
    let newAddressBarPicker: ModalPromptProvider
    let defaultBrowser: ModalPromptProvider
    let winBackOffer: ModalPromptProvider
    let subscriptionPromo: ModalPromptProvider
    let subscriptionPromoExistingUser: ModalPromptProvider
    let whatsNew: ModalPromptProvider
    let cookiePopupProtectionOptIn: ModalPromptProvider

    /// Highest-to-lowest launch-promo priority used by the modal manager.
    var ordered: [ModalPromptProvider] {
        [
            appRatingPrompt,
            winBackOffer,
            subscriptionPromo,
            subscriptionPromoExistingUser,
            newAddressBarPicker,
            defaultBrowser,
            whatsNew,
            cookiePopupProtectionOptIn,
        ]
    }
}

struct PromoCoordinationDiagnosticSnapshot: Equatable {
    let mode: PromoCoordinationMode
    let owner: PromoQueueLeaseOwnerSnapshot?
    let cooldown: PromoQueueCooldownSnapshot
    let unredeemedAppRatingSlots: Int
}

@MainActor
protocol PromoCoordinationDiagnosticsProviding: AnyObject {
    var diagnosticSnapshot: PromoCoordinationDiagnosticSnapshot { get }
}

@MainActor
protocol PromoCoordinationCooldownResetting: AnyObject {
    func resetModalCooldown()
    func resetRemoteMessageCooldown()
    func resetAppRatingPrompt()
}

/// Coordinates app-launch modal prompts with the shared new-tab remote-message source.
@MainActor
final class PromoCoordinationService {
    private let modalPromptCoordinationManager: ModalPromptCoordinationManaging
    private let launchSourceManager: LaunchSourceManaging
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbitrating
    private let promoQueueCooldownPolicy: PromoQueueCooldownPolicying
    private let appRatingPromptCoordinator: AppRatingPromptCoordinating

    let mode: PromoCoordinationMode

    init(
        launchSourceManager: LaunchSourceManaging,
        modalPromptCoordinationManager: ModalPromptCoordinationManaging,
        mode: PromoCoordinationMode,
        promoQueueLeaseArbiter: PromoQueueLeaseArbitrating,
        promoQueueCooldownPolicy: PromoQueueCooldownPolicying,
        appRatingPromptCoordinator: AppRatingPromptCoordinating
    ) {
        self.launchSourceManager = launchSourceManager
        self.modalPromptCoordinationManager = modalPromptCoordinationManager
        self.mode = mode
        self.promoQueueLeaseArbiter = promoQueueLeaseArbiter
        self.promoQueueCooldownPolicy = promoQueueCooldownPolicy
        self.appRatingPromptCoordinator = appRatingPromptCoordinator
    }

    func presentModalPromptIfNeeded(from viewController: ModalPromptPresenter) {
        if mode == .coordinated {
            modalPromptCoordinationManager.reconcilePresentedModal()
        }

        guard launchSourceManager.source == .standard else {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Skipping modal prompt - Launched from non-standard source.")
            return
        }

        let presented = viewController.presentedViewController
        guard presented == nil || presented?.isBeingDismissed == true else {
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt - A modal is already presented.")
            return
        }

        Logger.modalPrompt.info("[Modal Prompt Coordination] - ✓ App Launched from standard source.")
        let presentationStatusMessage: String
        if presented?.isBeingDismissed == true {
            presentationStatusMessage = "A modal is being dismissed; evaluating modal prompts."
        } else {
            presentationStatusMessage = "No Modal is currently presented."
        }
        Logger.modalPrompt.info("[Modal Prompt Coordination] - ✓ \(presentationStatusMessage, privacy: .public)")

        guard mode == .coordinated else {
            modalPromptCoordinationManager.presentModalPromptIfNeeded(from: viewController)
            return
        }

        switch promoQueueLeaseArbiter.acquireModalLease() {
        case .acquired(let lease):
            guard promoQueueCooldownPolicy.evaluateModalAdmission() == .eligible else {
                lease.release()
                Logger.modalPrompt.debug("[Promo Queue] - Skipping modal prompt during the RMF-to-modal cooldown.")
                return
            }

            modalPromptCoordinationManager.presentModalPromptIfNeeded(from: viewController, with: lease)
        case .blockedByModal:
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt - A coordinated modal attempt already owns the slot.")
        case .blockedByRemoteMessage:
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt - A remote message owns the slot.")
        }
    }
    
    /// Frees a deferred slot that was never redeemed during the session.
    func handleAppBackgrounded() {
        modalPromptCoordinationManager.releaseDeferredModal()
    }
}

extension PromoCoordinationService: PromoGating {
    func tryAcquireRemoteMessageLease(for messageID: String) -> PromoQueueRemoteMessageLease? {
        guard mode == .coordinated else { return nil }

        modalPromptCoordinationManager.reconcilePresentedModal()
        guard case .acquired(let arbiterLease) = promoQueueLeaseArbiter.acquireRemoteMessageLease(for: messageID) else {
            return nil
        }

        guard promoQueueCooldownPolicy.evaluateRemoteMessageAdmission() == .eligible else {
            arbiterLease.release()
            Logger.modalPrompt.debug("[Promo Queue] - Deferring RMF during the directional cooldown.")
            return nil
        }

        return PromoQueueRemoteMessageLease(
            arbiterLease: arbiterLease,
            cooldownPolicy: promoQueueCooldownPolicy
        )
    }
}

// MARK: - App Rating Prompt

@MainActor
protocol AppRatingPromptGating: AnyObject {
    /// Records a page load towards the usage-day counter.
    func registerAppRatingPromptUsage()

    /// Whether to request the dialog now.
    ///
    /// With coordination on this redeems a slot the deferred provider took at foreground, so the
    /// request only happens if the prompt already owns it. With it off, existing behaviour.
    func shouldRequestAppRatingPrompt() -> Bool

    /// Records that the dialog was requested, consuming one of the two per-install chances.
    func didRequestAppRatingPrompt()
}

extension PromoCoordinationService: AppRatingPromptGating {

    func registerAppRatingPromptUsage() {
        appRatingPromptCoordinator.registerUsage()
    }

    func shouldRequestAppRatingPrompt() -> Bool {
        guard appRatingPromptCoordinator.isCoordinationEnabled else {
            return appRatingPromptCoordinator.shouldRequestUncoordinated()
        }

        return modalPromptCoordinationManager.redeemDeferredModal()
    }

    func didRequestAppRatingPrompt() {
        appRatingPromptCoordinator.didRequestRating()
    }
}

extension PromoCoordinationService: RecentModalPromptStatusProviding {
    var wasModalPromptRecentlyPresented: Bool { modalPromptCoordinationManager.didPresentModalPromptThisSession }
}

extension PromoCoordinationService: PromoCoordinationDiagnosticsProviding {
    var diagnosticSnapshot: PromoCoordinationDiagnosticSnapshot {
        PromoCoordinationDiagnosticSnapshot(
            mode: mode,
            owner: promoQueueLeaseArbiter.snapshot.owner,
            cooldown: promoQueueCooldownPolicy.snapshot,
            unredeemedAppRatingSlots: appRatingPromptCoordinator.unredeemedSlotCount
        )
    }
}

extension PromoCoordinationService: PromoCoordinationCooldownResetting {
    func resetModalCooldown() {
        promoQueueCooldownPolicy.resetModalCooldown()
    }

    func resetAppRatingPrompt() {
        modalPromptCoordinationManager.releaseDeferredModal()
        appRatingPromptCoordinator.resetForDebug()
    }

    func resetRemoteMessageCooldown() {
        promoQueueCooldownPolicy.resetRemoteMessageCooldown()
    }
}
