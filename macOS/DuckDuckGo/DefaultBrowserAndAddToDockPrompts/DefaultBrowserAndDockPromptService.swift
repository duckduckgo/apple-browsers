//
//  DefaultBrowserAndDockPromptService.swift
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
import BrowserServicesKit
import Persistence

final class DefaultBrowserAndDockPromptService {
    let presenter: DefaultBrowserAndDockPromptPresenting
    let featureFlagger: DefaultBrowserAndDockPromptFeatureFlagger
    let store: DefaultBrowserAndDockPromptKeyValueStore
    let userActivityManager: DefaultBrowserAndDockPromptUserActivityManager

    init(
        featureFlagger: FeatureFlagger,
        privacyConfigManager: PrivacyConfigurationManaging,
        keyValueStore: ThrowingKeyValueStoring,
        isOnboardingCompletedProvider: @escaping () -> Bool
    ) {

#if DEBUG || REVIEW
        let defaultBrowserAndDockPromptDebugStore = DefaultBrowserAndDockPromptDebugStore()
        let defaultBrowserAndDockPromptDateProvider: () -> Date = { defaultBrowserAndDockPromptDebugStore.simulatedTodayDate }
#else
        let defaultBrowserAndDockPromptDateProvider: () -> Date = Date.init
#endif

        self.featureFlagger = DefaultBrowserAndDockPromptFeatureFlag(privacyConfigManager: privacyConfigManager, featureFlagger: featureFlagger)
        let userActivityStore = DefaultBrowserAndDockPromptUserActivityStore(keyValueFilesStore: keyValueStore)
        userActivityManager = DefaultBrowserAndDockPromptUserActivityManager(store: userActivityStore, dateProvider: defaultBrowserAndDockPromptDateProvider)

        store = DefaultBrowserAndDockPromptKeyValueStore(keyValueStoring: keyValueStore)
        DefaultBrowserAndDockPromptStoreMigrator(
            oldStore: DefaultBrowserAndDockPromptLegacyStore(),
            newStore: store
        ).migrateIfNeeded()

        let defaultBrowserAndDockPromptDecider = DefaultBrowserAndDockPromptTypeDecider(
            featureFlagger: self.featureFlagger,
            store: store,
            installDateProvider: { LocalStatisticsStore().installDate },
            dateProvider: defaultBrowserAndDockPromptDateProvider
        )
        let coordinator = DefaultBrowserAndDockPromptCoordinator(
            promptTypeDecider: defaultBrowserAndDockPromptDecider,
            store: store,
            isOnboardingCompleted: isOnboardingCompletedProvider,
            dateProvider: defaultBrowserAndDockPromptDateProvider
        )
        let statusUpdateNotifier = DefaultBrowserAndDockPromptStatusUpdateNotifier()

        presenter = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, statusUpdateNotifier: statusUpdateNotifier)
    }

    func applicationDidBecomeActive() {
        guard shouldRecordActivity() else { return }
        userActivityManager.recordActivity()
    }

    private func shouldRecordActivity() -> Bool {
        featureFlagger.isDefaultBrowserAndDockPromptForInactiveUsersFeatureEnabled
    }
}
