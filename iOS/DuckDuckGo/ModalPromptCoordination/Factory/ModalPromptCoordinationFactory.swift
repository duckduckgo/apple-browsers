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

// MARK: - Factory

@MainActor
enum ModalPromptCoordinationFactory {

    static func makeService(
        launchSourceManager: LaunchSourceManager,
        daxDialogs: DaxDialogs,
        keyValueFileStoreService: ThrowingKeyValueStoring,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        providersDependency: ProvidersDependency,
    ) -> ModalPromptCoordinationService {

        let newAddressBarPickerModalPromptProvider = makeNewAddressBarPickerModalPromptProvider(dependency: providersDependency.newAddressBarPicker)
        let defaultBrowserModalPromptProvider = DefaultBrowserModalPromptProvider(presenter: providersDependency.defaultBrowserPrompt.presenter)
        let winBackOfferModalPromptProvider = WinBackOfferModalPromptProvider(presenter: providersDependency.winBackOffer.presenter, coordinator: providersDependency.winBackOffer.coordinator)

        return ModalPromptCoordinationService(
            launchSourceManager: launchSourceManager,
            keyValueStore: keyValueFileStoreService,
            contextualOnboardingStatusProvider: daxDialogs,
            privacyConfigManager: privacyConfigurationManager,
            providers: .init(
                newAddressBarPicker: newAddressBarPickerModalPromptProvider,
                defaultBrowser: defaultBrowserModalPromptProvider,
                winBackOffer: winBackOfferModalPromptProvider
            )
        )
    }

}

// MARK: - New Address Bar Picker

private extension ModalPromptCoordinationFactory {

    static func makeNewAddressBarPickerModalPromptProvider(dependency: ProvidersDependency.NewAddressBarPickerDependency) -> NewAddressBarPickerModalPromptProvider {

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

    struct ProvidersDependency {
        let newAddressBarPicker: NewAddressBarPickerDependency
        let defaultBrowserPrompt: DefaultBrowserDependency
        let winBackOffer: WinBackOfferDependency
    }

}

extension ModalPromptCoordinationFactory.ProvidersDependency {

    struct NewAddressBarPickerDependency {
        let featureFlagger: FeatureFlagger
        let appSettings: AppSettings
        let aiChatSettings: AIChatSettingsProvider
        let experimentalAIChatManager: ExperimentalAIChatManager
    }

    struct DefaultBrowserDependency {
        let presenter: DefaultBrowserPromptPresenting
    }

    struct WinBackOfferDependency {
        let presenter: WinBackOfferPresenting
        let coordinator: WinBackOfferCoordinating
    }

}
