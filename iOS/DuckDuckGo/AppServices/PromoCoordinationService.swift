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

/// Coordinates app-launch modal prompts with the shared new-tab remote-message source.
@MainActor
final class PromoCoordinationService {
    private let modalPromptCoordinationManager: ModalPromptCoordinationManaging
    private let launchSourceManager: LaunchSourceManaging
    private let promoQueueLeaseArbiter: PromoQueueLeaseArbitrating
    private let promoQueueCooldownPolicy: PromoQueueCooldownPolicying

    let mode: PromoCoordinationMode

    init(
        launchSourceManager: LaunchSourceManaging,
        modalPromptCoordinationManager: ModalPromptCoordinationManaging,
        mode: PromoCoordinationMode,
        promoQueueLeaseArbiter: PromoQueueLeaseArbitrating,
        promoQueueCooldownPolicy: PromoQueueCooldownPolicying
    ) {
        self.launchSourceManager = launchSourceManager
        self.modalPromptCoordinationManager = modalPromptCoordinationManager
        self.mode = mode
        self.promoQueueLeaseArbiter = promoQueueLeaseArbiter
        self.promoQueueCooldownPolicy = promoQueueCooldownPolicy
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

extension PromoCoordinationService: RecentModalPromptStatusProviding {
    var wasModalPromptRecentlyPresented: Bool { modalPromptCoordinationManager.didPresentModalPromptThisSession }
}
