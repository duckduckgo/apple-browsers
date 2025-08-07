//
//  DefaultBrowserPromptService.swift
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
import BrowserServicesKit
import Persistence
import Core
import SetDefaultBrowserCore
import SetDefaultBrowserUI
import SystemSettingsPiPTutorial

@MainActor
final class DefaultBrowserPromptService {
    let presenter: DefaultBrowserPromptPresenting
    private let userActivityManager: DefaultBrowserPromptUserActivityRecorder & DefaultBrowserPromptUserActivityManager
    private let featureFlagAdapter: DefaultBrowserPromptFeatureFlagAdapter

    init(
        featureFlagger: FeatureFlagger,
        privacyConfigManager: PrivacyConfigurationManaging,
        keyValueFilesStore: ThrowingKeyValueStoring,
        systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManager,
        isOnboardingCompletedProvider: @escaping () -> Bool
    ) {

#if DEBUG || ALPHA
        let debugDateProvider = DefaultBrowserPromptDebugDateProvider()
        let defaultBrowserDateProvider: () -> Date = { debugDateProvider.simulatedTodayDate }
#else
        let defaultBrowserDateProvider: () -> Date = Date.init
#endif

        featureFlagAdapter = DefaultBrowserPromptFeatureFlagAdapter(featureFlagger: featureFlagger, privacyConfigurationManager: privacyConfigManager)
        let userTypeStore = DefaultBrowserPromptUserTypeStore(keyValueFilesStore: keyValueFilesStore)
        let userTypeManager = DefaultBrowserPromptUserTypeManager(store: userTypeStore)
        userTypeManager.persistUserType()
        let checkDefaultBrowserInfoStorage = DefaultBrowserInfoStore()
        let promptTypeKeyValueFilesStore = DefaultBrowserPromptActivityKeyValueFilesStore(keyValueFilesStore: keyValueFilesStore)
        let userActivityStore = DefaultBrowserPromptUserActivityKeyValueFilesStore(keyValueFilesStore: keyValueFilesStore)
        userActivityManager = DefaultBrowserPromptUserActivityManager(store: userActivityStore, dateProvider: defaultBrowserDateProvider)
        let checkDefaultBrowserPixelHandler = DefaultBrowserPromptManagerDebugPixelHandler()
        let promptActivityPixelHandler = DefaultBrowserPromptPixelHandler()

        presenter = DefaultBrowserPromptFactory.makeDefaultBrowserPromptPresenter(
            featureFlagProvider: featureFlagAdapter,
            featureFlagSettingsProvider: featureFlagAdapter,
            promptActivityStore: promptTypeKeyValueFilesStore,
            userTypeProviding: userTypeManager,
            userActivityManager: userActivityManager,
            checkDefaultBrowserContextStorage: checkDefaultBrowserInfoStorage,
            defaultBrowserSettingsNavigator: systemSettingsPiPTutorialManager,
            checkDefaultBrowserDebugEventMapper: checkDefaultBrowserPixelHandler,
            promptUserInteractionEventMapper: promptActivityPixelHandler,
            uiProvider: DefaultBrowserPromptUIProvider(),
            isOnboardingCompletedProvider: isOnboardingCompletedProvider,
            installDateProvider: { StatisticsUserDefaults().installDate },
            currentDateProvider: defaultBrowserDateProvider
        )
    }

    func resume() {
        // Application has been launched or brought to foreground.
        guard shouldRecordActivity() else { return }
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Record User Activity If Needed.")
        userActivityManager.recordActivity()
    }

    private func shouldRecordActivity() -> Bool {
        // True if either active/inactive prompt features is enabled
        featureFlagAdapter.isDefaultBrowserPromptsForActiveUsersFeatureEnabled || featureFlagAdapter.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled
    }
}

// MARK: - Adapters

extension SystemSettingsPiPTutorialManager: @retroactive DefaultBrowserPromptSettingsNavigating {

    public func navigateToSetDefaultBrowserSettings() {
        playPiPTutorialAndNavigateTo(destination: .defaultBrowser)
    }

}
