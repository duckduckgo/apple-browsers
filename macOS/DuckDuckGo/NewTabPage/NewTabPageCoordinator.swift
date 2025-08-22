//
//  NewTabPageCoordinator.swift
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

import AIChat
import BrowserServicesKit
import Combine
import Common
import Foundation
import History
import NewTabPage
import Persistence
import PixelKit
import PrivacyStats
import Suggestions

typealias HistoryProviderCoordinating = HistoryCoordinating & SuggestionContainer.HistoryProvider

final class NewTabPageCoordinator {
    let actionsManager: NewTabPageActionsManager
    let newTabPageShownPixelSender: NewTabPageShownPixelSender

    @MainActor
    init(
        appearancePreferences: AppearancePreferences,
        customizationModel: NewTabPageCustomizationModel,
        bookmarkManager: BookmarkManager & URLFavoriteStatusProviding & RecentActivityFavoritesHandling,
        faviconManager: FaviconManagement,
        activeRemoteMessageModel: ActiveRemoteMessageModel,
        historyCoordinator: HistoryProviderCoordinating,
        contentBlocking: ContentBlockingProtocol,
        fireproofDomains: URLFireproofStatusProviding,
        privacyStats: PrivacyStatsCollecting,
        freemiumDBPPromotionViewCoordinator: FreemiumDBPPromotionViewCoordinator,
        tld: TLD,
        fireCoordinator: FireCoordinator,
        keyValueStore: ThrowingKeyValueStoring,
        legacyKeyValueStore: KeyValueStoring = UserDefaultsWrapper<Any>.sharedDefaults,
        notificationCenter: NotificationCenter = .default,
        visualizeFireAnimationDecider: VisualizeFireSettingsDecider,
        featureFlagger: FeatureFlagger,
        windowControllersManager: WindowControllersManagerProtocol,
        tabsPreferences: TabsPreferences,
        newTabPageAIChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding,
        fireDailyPixel: @escaping (PixelKitEvent) -> Void = { PixelKit.fire($0, frequency: .legacyDaily) }
    ) {

        let settingsMigrator = NewTabPageProtectionsReportSettingsMigrator(legacyKeyValueStore: legacyKeyValueStore)
        let protectionsReportModel = NewTabPageProtectionsReportModel(
            privacyStats: privacyStats,
            keyValueStore: keyValueStore,
            burnAnimationSettingChanges: visualizeFireAnimationDecider.shouldShowFireAnimationPublisher,
            showBurnAnimation: visualizeFireAnimationDecider.shouldShowFireAnimation,
            getLegacyIsViewExpandedSetting: settingsMigrator.isViewExpanded,
            getLegacyActiveFeedSetting: settingsMigrator.activeFeed,
        )

        actionsManager = NewTabPageActionsManager(
            appearancePreferences: appearancePreferences,
            customizationModel: customizationModel,
            bookmarkManager: bookmarkManager,
            faviconManager: faviconManager,
            contentBlocking: contentBlocking,
            trackerDataManager: contentBlocking.trackerDataManager,
            activeRemoteMessageModel: activeRemoteMessageModel,
            historyCoordinator: historyCoordinator,
            fireproofDomains: fireproofDomains,
            privacyStats: privacyStats,
            protectionsReportModel: protectionsReportModel,
            freemiumDBPPromotionViewCoordinator: freemiumDBPPromotionViewCoordinator,
            tld: tld,
            fire: { @MainActor in fireCoordinator.fireViewModel.fire },
            keyValueStore: keyValueStore,
            featureFlagger: featureFlagger,
            windowControllersManager: windowControllersManager,
            tabsPreferences: tabsPreferences,
            newTabPageAIChatShortcutSettingProvider: newTabPageAIChatShortcutSettingProvider
        )
        newTabPageShownPixelSender = NewTabPageShownPixelSender(
            appearancePreferences: appearancePreferences,
            protectionsReportVisibleFeedProvider: protectionsReportModel,
            customizationModel: customizationModel,
            fireDailyPixel: fireDailyPixel
        )

        notificationCenter.publisher(for: .newTabPageWebViewDidAppear)
            .prefix(1)
            .sink { [weak self] _ in
                self?.newTabPageShownPixelSender.firePixel()
            }
            .store(in: &cancellables)
    }

    private var cancellables: Set<AnyCancellable> = []
}
