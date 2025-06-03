//
//  NewTabPageActionsManagerExtension.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import History
import NewTabPage
import Persistence
import PrivacyStats

extension NewTabPageActionsManager {

    convenience init(
        appearancePreferences: AppearancePreferences,
        customizationModel: NewTabPageCustomizationModel,
        bookmarkManager: BookmarkManager & URLFavoriteStatusProviding & RecentActivityFavoritesHandling,
        duckPlayerHistoryEntryTitleProvider: DuckPlayerHistoryEntryTitleProviding = DuckPlayer.shared,
        contentBlocking: ContentBlockingProtocol = ContentBlocking.shared,
        activeRemoteMessageModel: ActiveRemoteMessageModel,
        historyCoordinator: HistoryCoordinating,
        privacyStats: PrivacyStatsCollecting,
        protectionsReportModel: NewTabPageProtectionsReportModel,
        freemiumDBPPromotionViewCoordinator: FreemiumDBPPromotionViewCoordinator,
        keyValueStore: KeyValueStoring = UserDefaults.standard
    ) {
        let favoritesPublisher = bookmarkManager.listPublisher.map({ $0?.favoriteBookmarks ?? [] }).eraseToAnyPublisher()
        let favoritesModel = NewTabPageFavoritesModel(
            actionsHandler: DefaultFavoritesActionsHandler(bookmarkManager: bookmarkManager),
            favoritesPublisher: favoritesPublisher,
            getLegacyIsViewExpandedSetting: UserDefaultsWrapper<Bool>(key: .homePageShowAllFavorites, defaultValue: true).wrappedValue
        )

        let customizationProvider = NewTabPageCustomizationProvider(customizationModel: customizationModel, appearancePreferences: appearancePreferences)
        let freemiumDBPBannerProvider = NewTabPageFreemiumDBPBannerProvider(model: freemiumDBPPromotionViewCoordinator)

        let privacyStatsModel = NewTabPagePrivacyStatsModel(
            visibilityProvider: protectionsReportModel,
            privacyStats: privacyStats,
            trackerDataProvider: PrivacyStatsTrackerDataProvider(contentBlocking: ContentBlocking.shared),
            eventMapping: NewTabPagePrivacyStatsEventHandler()
        )

        let recentActivityProvider = RecentActivityProvider(
            visibilityProvider: protectionsReportModel,
            historyCoordinator: historyCoordinator,
            urlFavoriteStatusProvider: bookmarkManager,
            duckPlayerHistoryEntryTitleProvider: duckPlayerHistoryEntryTitleProvider,
            trackerEntityPrevalenceComparator: ContentBlockingPrevalenceComparator(contentBlocking: contentBlocking)
        )
        let recentActivityModel = NewTabPageRecentActivityModel(
            activityProvider: recentActivityProvider,
            actionsHandler: DefaultRecentActivityActionsHandler(favoritesHandler: bookmarkManager)
        )

        self.init(scriptClients: [
            NewTabPageConfigurationClient(
                sectionsVisibilityProvider: appearancePreferences,
                customBackgroundProvider: customizationProvider,
                linkOpener: NewTabPageLinkOpener(),
                eventMapper: NewTabPageConfigurationErrorHandler()
            ),
            NewTabPageCustomBackgroundClient(model: customizationProvider),
            NewTabPageRMFClient(remoteMessageProvider: activeRemoteMessageModel),
            NewTabPageFreemiumDBPClient(provider: freemiumDBPBannerProvider),
            NewTabPageNextStepsCardsClient(
                model: NewTabPageNextStepsCardsProvider(
                    continueSetUpModel: HomePage.Models.ContinueSetUpModel(tabOpener: NewTabPageTabOpener()),
                    appearancePreferences: appearancePreferences
                )
            ),
            NewTabPageFavoritesClient(favoritesModel: favoritesModel, preferredFaviconSize: Int(Favicon.SizeCategory.medium.rawValue)),
            NewTabPageProtectionsReportClient(model: protectionsReportModel),
            NewTabPagePrivacyStatsClient(model: privacyStatsModel),
            NewTabPageRecentActivityClient(model: recentActivityModel)
        ])
    }
}

struct NewTabPageTabOpener: ContinueSetUpModelTabOpening {
    @MainActor
    func openTab(_ tab: Tab) {
        WindowControllersManager.shared.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.insertOrAppend(tab: tab, selected: true)
    }
}
