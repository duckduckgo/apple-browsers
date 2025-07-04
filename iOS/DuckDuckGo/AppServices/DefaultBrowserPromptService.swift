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

@MainActor
final class DefaultBrowserPromptService {
    private weak var presentingController: UIViewController?
    private let userActivityManager: DefaultBrowserPromptUserActivityRecorder & DefaultBrowserPromptUserActivityManager
    private let presenter: DefaultBrowserPromptPresenting
    private let featureFlagAdapter: DefaultBrowserPromptFeatureFlagAdapter

    init(
        presentingController: UIViewController,
        featureFlagger: FeatureFlagger,
        privacyConfigManager: PrivacyConfigurationManaging,
        keyValueFilesStore: ThrowingKeyValueStoring
    ) {
        self.presentingController = presentingController

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
            checkDefaultBrowserDebugEventMapper: checkDefaultBrowserPixelHandler,
            promptUserInteractionEventMapper: promptActivityPixelHandler,
            isOnboardingCompletedProvider: { !DaxDialogs.shared.isEnabled },
            installDateProvider: { StatisticsUserDefaults().installDate },
            currentDateProvider: defaultBrowserDateProvider
        )
    }

    func resume() {
        // Application has been launched or brought to foreground.
        guard featureFlagAdapter.isDefaultBrowserPromptsFeatureEnabled else { return }
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Record User Activity If Needed.")
        userActivityManager.recordActivity()
    }

    func presentDefaultBrowserPromptIfNeeded() {
        guard let presentingController else { return }
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Attempt to present default browser prompt.")
        presenter.tryPresentDefaultModalPrompt(from: presentingController)
    }
}

// MARK: - Adapters

extension DefaultBrowserInfoStore: DefaultBrowserContextStorage {

    var defaultBrowserContext: DefaultBrowserContext? {
        get {
            defaultBrowserInfo.flatMap(DefaultBrowserContext.init)
        }
        set {
            guard let newValue else { return }
            defaultBrowserInfo = DefaultBrowserInfo(with: newValue)
        }
    }

}

// Remove when DefaultBrowserInfo is not used anymore as duplicate in Onboarding
extension DefaultBrowserContext {

    init(with info: DefaultBrowserInfo) {
        self.init(
            isDefaultBrowser: info.isDefaultBrowser,
            lastSuccessfulCheckDate: info.lastSuccessfulCheckDate,
            lastAttemptedCheckDate: info.lastAttemptedCheckDate,
            numberOfTimesChecked: info.numberOfTimesChecked,
            nextRetryAvailableDate: info.nextRetryAvailableDate
        )
    }

}

extension DefaultBrowserInfo {

    init(with context: DefaultBrowserContext) {
        self.init(
            isDefaultBrowser: context.isDefaultBrowser,
            lastSuccessfulCheckDate: context.lastSuccessfulCheckDate,
            lastAttemptedCheckDate: context.lastAttemptedCheckDate,
            numberOfTimesChecked: context.numberOfTimesChecked,
            nextRetryAvailableDate: context.nextRetryAvailableDate
        )
    }
}
