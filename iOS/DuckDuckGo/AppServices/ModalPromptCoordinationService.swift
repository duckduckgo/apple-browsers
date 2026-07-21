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

import UIKit
import Persistence
import protocol PrivacyConfig.PrivacyConfigurationManaging

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
}

@MainActor
final class ModalPromptCoordinationService {
    private let modalPromptCoordinationManager: ModalPromptCoordinationManaging
    private let launchSourceManager: LaunchSourceManaging

    convenience init(
        launchSourceManager: LaunchSourceManaging,
        keyValueStore: ThrowingKeyValueStoring,
        contextualOnboardingStatusProvider: ContextualDaxDialogStatusProvider,
        privacyConfigManager: PrivacyConfigurationManaging,
        providers: ModalPromptProviders
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

        self.init(launchSourceManager: launchSourceManager, modalPromptCoordinationManager: modalPromptCoordinationManager)
    }

    init(
        launchSourceManager: LaunchSourceManaging,
        modalPromptCoordinationManager: ModalPromptCoordinationManaging
    ) {
        self.launchSourceManager = launchSourceManager
        self.modalPromptCoordinationManager = modalPromptCoordinationManager
    }

    func presentModalPromptIfNeeded(from viewController: ModalPromptPresenter) {
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
        modalPromptCoordinationManager.presentModalPromptIfNeeded(from: viewController)
    }

}

extension ModalPromptCoordinationService: RecentModalPromptStatusProviding {
    var wasModalPromptRecentlyPresented: Bool { modalPromptCoordinationManager.didPresentModalPromptThisSession }
}
