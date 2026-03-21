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
import PrivacyConfig
import Persistence

final class DefaultBrowserAndDockPromptService {
    let coordinator: DefaultBrowserAndDockPromptCoordinator
    let presenter: DefaultBrowserAndDockPromptPresenting
    let featureFlagger: DefaultBrowserAndDockPromptFeatureFlagger
    let store: DefaultBrowserAndDockPromptKeyValueStore
    let userActivityManager: DefaultBrowserAndDockPromptUserActivityManager
    let notificationPresenter: DefaultBrowserAndDockPromptNotificationPresenting
    let uiHosting: () -> DefaultBrowserAndDockPromptUIHosting?

    init(
        privacyConfigManager: PrivacyConfigurationManaging,
        keyValueStore: ThrowingKeyValueStoring,
        notificationPresenter: DefaultBrowserAndDockPromptNotificationPresenting,
        uiHosting: @escaping () -> DefaultBrowserAndDockPromptUIHosting?,
        isOnboardingCompletedProvider: @escaping () -> Bool
    ) {

        var defaultBrowserAndDockPromptDebugStore: DefaultBrowserAndDockPromptDebugStore?
        var debugSimulatedDateStore: DebugSimulatedDateStore?
        let buildType = StandardApplicationBuildType()
        if buildType.isDebugBuild || buildType.isReviewBuild {
            debugSimulatedDateStore = DebugSimulatedDateStore(keyValueStore: keyValueStore)
            defaultBrowserAndDockPromptDebugStore = DefaultBrowserAndDockPromptDebugStore()
        }
        let defaultBrowserAndDockPromptDateProvider: () -> Date = {
            debugSimulatedDateStore?.simulatedDate ?? Date()
        }
        let defaultBrowserAndDockInstallDateProvider: () -> Date? = {
            defaultBrowserAndDockPromptDebugStore?.simulatedInstallDate ?? LocalStatisticsStore().installDate
        }

        self.featureFlagger = DefaultBrowserAndDockPromptFeatureFlag(privacyConfigManager: privacyConfigManager)
        self.notificationPresenter = notificationPresenter
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
            userActivityProvider: userActivityManager,
            installDateProvider: defaultBrowserAndDockInstallDateProvider,
            dateProvider: defaultBrowserAndDockPromptDateProvider
        )
        coordinator = DefaultBrowserAndDockPromptCoordinator(
            promptTypeDecider: defaultBrowserAndDockPromptDecider,
            store: store,
            notificationPresenter: notificationPresenter,
            featureFlagger: featureFlagger,
            isOnboardingCompleted: isOnboardingCompletedProvider,
            dateProvider: defaultBrowserAndDockPromptDateProvider
        )
        let statusUpdateNotifier = DefaultBrowserAndDockPromptStatusUpdateNotifier()
        let uiProvider = DefaultBrowserAndDockPromptUIProvider()
        self.uiHosting = uiHosting

        presenter = DefaultBrowserAndDockPromptPresenter(coordinator: coordinator, statusUpdateNotifier: statusUpdateNotifier, uiProvider: uiProvider)
    }

    func applicationDidBecomeActive() {
        userActivityManager.recordActivity()
    }

    func handleNotificationResponse(_ response: DefaultBrowserAndDockPromptNotificationIdentifier) async {
        await notificationPresenter.handleNotificationResponse(for: response)
    }

    /// DEBUG ONLY: Resets the stored state for the prompts and user activity.
    func resetDebugState() {
        store.popoverShownDate = nil
        store.bannerShownDate = nil
        store.inactiveUserModalShownDate = nil
        store.isBannerPermanentlyDismissed = false
        userActivityManager.recordActivity()
    }
}
