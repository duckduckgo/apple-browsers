//
//  ModalPromptCoordinationFactory.swift
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

import Foundation
import Persistence
import SetDefaultBrowserUI
import BrowserServicesKit
import enum Common.DevicePlatform
import AIChat
import RemoteMessaging

// MARK: - Factory

@MainActor
enum ModalPromptCoordinationFactory {

    static func makeService(
        dependency: Dependency
    ) -> ModalPromptCoordinationService {

        let newAddressBarPickerModalPromptProvider = makeNewAddressBarPickerModalPromptProvider(dependency: dependency)
        let defaultBrowserModalPromptProvider = DefaultBrowserModalPromptProvider(presenter: dependency.defaultBrowserPromptPresenter)
        let winBackOfferModalPromptProvider = WinBackOfferModalPromptProvider()
        let whatsNewModalPromptProvider = WhatsNewCoordinator(remoteMessageStore: dependency.remoteMessagingStore, remoteMessageActionHandler: dependency.remoteMessagingActionHandler)

        return ModalPromptCoordinationService(
            launchSourceManager: dependency.launchSourceManager,
            keyValueStore: dependency.keyValueFileStoreService,
            contextualOnboardingStatusProvider: dependency.contextualOnboardingStatusProvider,
            privacyConfigManager: dependency.privacyConfigurationManager,
            providers: .init(
                newAddressBarPicker: newAddressBarPickerModalPromptProvider,
                defaultBrowser: defaultBrowserModalPromptProvider,
                winBackOffer: winBackOfferModalPromptProvider,
                whatsNew: whatsNewModalPromptProvider
            )
        )
    }

}

// MARK: - New Address Bar Picker

private extension ModalPromptCoordinationFactory {

    static func makeNewAddressBarPickerModalPromptProvider(dependency: Dependency) -> NewAddressBarPickerModalPromptProvider {

        let store = NewAddressBarPickerStore()
        let aiChatSettings = dependency.aiChatSettings

        let validator = NewAddressBarPickerDisplayValidator(
            aiChatSettings: aiChatSettings,
            featureFlagger: dependency.featureFlagger,
            experimentalAIChatManager: dependency.experimentalAIChatManager,
            appSettings: dependency.appSettings,
            pickerStorage: store
        )

        return NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: DevicePlatform.isIpad
        )
    }

}

// MARK: - Dependencies

extension ModalPromptCoordinationFactory {

    struct Dependency {
        let launchSourceManager: LaunchSourceManager
        let contextualOnboardingStatusProvider: ContextualDaxDialogStatusProvider
        let keyValueFileStoreService: ThrowingKeyValueStoring
        let privacyConfigurationManager: PrivacyConfigurationManaging
        let featureFlagger: FeatureFlagger
        let remoteMessagingStore: RemoteMessagingStoring
        let remoteMessagingActionHandler: RemoteMessagingActionHandling
        let appSettings: AppSettings
        let aiChatSettings: AIChatSettingsProvider
        let experimentalAIChatManager: ExperimentalAIChatManager
        let defaultBrowserPromptPresenter: DefaultBrowserPromptPresenting
    }

}
