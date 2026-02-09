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
import PrivacyConfig
import enum Common.DevicePlatform
import AIChat
import RemoteMessaging

// MARK: - Factory

@MainActor
enum ModalPromptCoordinationFactory {

    static func makeService(
        dependency: Dependency
    ) -> ModalPromptCoordinationService {

        let isIPad = DevicePlatform.isIpad

        let newAddressBarPickerModalPromptProvider = makeNewAddressBarPickerModalPromptProvider(dependency: dependency, isIPad: isIPad)
        let defaultBrowserModalPromptProvider = DefaultBrowserModalPromptProvider(presenter: dependency.defaultBrowserPromptPresenter)
        let winBackOfferModalPromptProvider = WinBackOfferModalPromptProvider(presenter: dependency.winBackOfferPresenter, coordinator: dependency.winBackOfferCoordinator)
        let whatsNewModalPromptProvider = WhatsNewCoordinator(
            displayContext: .scheduled,
            repository: dependency.whatsNewRepository,
            remoteMessageActionHandler: dependency.remoteMessagingActionHandler,
            isIPad: isIPad,
            pixelReporter: dependency.remoteMessagingPixelReporter,
            userScriptsDependencies: dependency.userScriptsDependencies,
            imageLoader: dependency.remoteMessagingImageLoader,
            featureFlagger: dependency.featureFlagger
        )

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

    static func makeNewAddressBarPickerModalPromptProvider(dependency: Dependency, isIPad: Bool) -> NewAddressBarPickerModalPromptProvider {

        let store = NewAddressBarPickerStore()
        let aiChatSettings = dependency.aiChatSettings
        let searchExperienceOnboardingProvider = OnboardingSearchExperience()

        let validator = NewAddressBarPickerDisplayValidator(
            aiChatSettings: aiChatSettings,
            featureFlagger: dependency.featureFlagger,
            experimentalAIChatManager: dependency.experimentalAIChatManager,
            appSettings: dependency.appSettings,
            pickerStorage: store,
            searchExperienceOnboardingProvider: searchExperienceOnboardingProvider
        )

        return NewAddressBarPickerModalPromptProvider(
            validator: validator,
            store: store,
            aiChatSettings: aiChatSettings,
            isIPad: isIPad
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
        let whatsNewRepository: WhatsNewMessageRepository
        let remoteMessagingActionHandler: RemoteMessagingActionHandling
        let remoteMessagingPixelReporter: RemoteMessagingPixelReporting
        let remoteMessagingImageLoader: RemoteMessagingImageLoading
        let appSettings: AppSettings
        let aiChatSettings: AIChatSettingsProvider
        let experimentalAIChatManager: ExperimentalAIChatManager
        let defaultBrowserPromptPresenter: DefaultBrowserPromptPresenting
        let winBackOfferPresenter: WinBackOfferPresenting
        let winBackOfferCoordinator: WinBackOfferCoordinating
        let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    }

}
