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
import protocol BrowserServicesKit.PrivacyConfigurationManaging

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
}

@MainActor
final class ModalPromptCoordinationService {
    private let modalPromptCoordinationManager: ModalPromptCoordinationManaging
    private let launchSourceManager: LaunchSourceManaging
    private let contextualOnboardingStatusProvider: ContextualDaxDialogStatusProvider

    convenience init(
        launchSourceManager: LaunchSourceManaging,
        keyValueStore: ThrowingKeyValueStoring,
        contextualOnboardingStatusProvider: ContextualDaxDialogStatusProvider,
        privacyConfigManager: PrivacyConfigurationManaging,
        providers: ModalPromptProviders
    ) {

        // Providers are sort from highest to lowest priority, with item at index 0 being the highest priority.
        // Priority order:
        // - WinBack Offer
        // - AddressBar Picker
        // - Set As Default Browser
        // - What's New
        let providers: [ModalPromptProvider] = [
            providers.winBackOffer,
            providers.newAddressBarPicker,
            providers.defaultBrowser
        ]
        
        let presentationStore = PromptCooldownKeyValueFilesStore(keyValueStore: keyValueStore, eventMapper: PromptCooldownStorePixelReporter())
        let cooldownIntervalProvider = PromptCooldownIntervalProvider(privacyConfigManager: privacyConfigManager)
        let cooldownManager = PromptCooldownManager(presentationStore: presentationStore, cooldownIntervalProvider: cooldownIntervalProvider)

        let modalPromptCoordinationManager = ModalPromptCoordinationManager(
            providers: providers,
            cooldownManager: cooldownManager,
        )

        self.init(launchSourceManager: launchSourceManager, contextualOnboardingStatusProvider: contextualOnboardingStatusProvider, modalPromptCoordinationManager: modalPromptCoordinationManager)
    }

    init(
        launchSourceManager: LaunchSourceManaging,
        contextualOnboardingStatusProvider: ContextualDaxDialogStatusProvider,
        modalPromptCoordinationManager: ModalPromptCoordinationManaging
    ) {
        self.launchSourceManager = launchSourceManager
        self.contextualOnboardingStatusProvider = contextualOnboardingStatusProvider
        self.modalPromptCoordinationManager = modalPromptCoordinationManager
    }

    func presentModalPromptIfNeeded(from viewController: ModalPromptPresenter) {
        guard launchSourceManager.source == .standard else {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Skipping modal prompt - Launched from non-standard source.")
            return
        }

        guard contextualOnboardingStatusProvider.hasSeenOnboarding else {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Skipping modal prompt - Onboarding not completed.")
            return
        }

        guard viewController.presentedViewController == nil || viewController.presentedViewController?.isBeingDismissed == true else {
            Logger.modalPrompt.debug("[Modal Prompt Coordination] - Skipping modal prompt - A modal is already presented.")
            return
        }

        Logger.modalPrompt.info("[Modal Prompt Coordination] - ✓ App Launched from standard source.")
        Logger.modalPrompt.info("[Modal Prompt Coordination] - ✓ Onboarding has been seen.")
        Logger.modalPrompt.info("[Modal Prompt Coordination] - ✓ No Modal is currently presented.")
        modalPromptCoordinationManager.presentModalPromptIfNeeded(from: viewController)
    }

}
