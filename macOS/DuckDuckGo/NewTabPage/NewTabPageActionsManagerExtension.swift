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

import AIChat
import AppKit
import AutoconsentStats
import BrowserServicesKit
import Common
import DDGSync
import History
import NewTabPage
import Persistence
import PrivacyConfig
import PrivacyStats
import Subscription

extension NewTabPageActionsManager {

    @MainActor
    convenience init(
        appearancePreferences: AppearancePreferences,
        visualizeFireAnimationDecider: VisualizeFireSettingsDecider,
        customizationModel: NewTabPageCustomizationModel,
        bookmarkManager: BookmarkManager & URLFavoriteStatusProviding & RecentActivityFavoritesHandling,
        faviconManager: FaviconManagement,
        duckPlayerHistoryEntryTitleProvider: DuckPlayerHistoryEntryTitleProviding,
        contentBlocking: ContentBlockingProtocol,
        trackerDataManager: TrackerDataManager,
        activeRemoteMessageModel: ActiveRemoteMessageModel,
        historyCoordinator: HistoryProviderCoordinating,
        fireproofDomains: URLFireproofStatusProviding,
        privacyStats: PrivacyStatsCollecting,
        autoconsentStats: AutoconsentStatsCollecting,
        cookiePopupProtectionPreferences: CookiePopupProtectionPreferences,
        freemiumDBPPromotionViewCoordinator: FreemiumDBPPromotionViewCoordinator,
        tld: TLD,
        fire: @escaping () async -> FireProtocol,
        keyValueStore: ThrowingKeyValueStoring,
        legacyKeyValueStore: KeyValueStoring = UserDefaultsWrapper<Any>.sharedDefaults,
        featureFlagger: FeatureFlagger,
        windowControllersManager: WindowControllersManagerProtocol & AIChatTabManaging,
        tabsPreferences: TabsPreferences,
        newTabPageAIChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding,
        winBackOfferPromotionViewCoordinator: WinBackOfferPromotionViewCoordinator,
        subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging,
        protectionsReportModel: NewTabPageProtectionsReportModel,
        homePageContinueSetUpModelPersistor: HomePageContinueSetUpModelPersisting,
        nextStepsCardsPersistor: NewTabPageNextStepsCardsPersisting,
        subscriptionCardPersistor: HomePageSubscriptionCardPersisting,
        duckPlayerPreferences: DuckPlayerPreferencesPersistor,
        syncService: DDGSyncing?
    ) {
        self.init(
            appearancePreferences: appearancePreferences,
            customizationModel: customizationModel,
            bookmarkManager: bookmarkManager,
            faviconManager: faviconManager,
            duckPlayerHistoryEntryTitleProvider: duckPlayerHistoryEntryTitleProvider,
            contentBlocking: contentBlocking,
            trackerDataManager: trackerDataManager,
            activeRemoteMessageModel: activeRemoteMessageModel,
            historyCoordinator: historyCoordinator,
            fireproofDomains: fireproofDomains,
            privacyStats: privacyStats,
            autoconsentStats: autoconsentStats,
            protectionsReportModel: protectionsReportModel,
            freemiumDBPPromotionViewCoordinator: freemiumDBPPromotionViewCoordinator,
            tld: tld,
            fire: fire,
            keyValueStore: keyValueStore,
            featureFlagger: featureFlagger,
            windowControllersManager: windowControllersManager,
            tabsPreferences: tabsPreferences,
            newTabPageAIChatShortcutSettingProvider: newTabPageAIChatShortcutSettingProvider,
            winBackOfferPromotionViewCoordinator: winBackOfferPromotionViewCoordinator,
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            homePageContinueSetUpModelPersistor: homePageContinueSetUpModelPersistor,
            nextStepsCardsPersistor: nextStepsCardsPersistor,
            subscriptionCardPersistor: subscriptionCardPersistor,
            duckPlayerPreferences: duckPlayerPreferences,
            syncService: syncService
        )
    }

    @MainActor
    convenience init(
        appearancePreferences: AppearancePreferences,
        customizationModel: NewTabPageCustomizationModel,
        bookmarkManager: BookmarkManager & URLFavoriteStatusProviding & RecentActivityFavoritesHandling,
        faviconManager: FaviconManagement,
        duckPlayerHistoryEntryTitleProvider: DuckPlayerHistoryEntryTitleProviding,
        contentBlocking: ContentBlockingProtocol,
        trackerDataManager: TrackerDataManager,
        activeRemoteMessageModel: ActiveRemoteMessageModel,
        historyCoordinator: HistoryProviderCoordinating,
        fireproofDomains: URLFireproofStatusProviding,
        privacyStats: PrivacyStatsCollecting,
        autoconsentStats: AutoconsentStatsCollecting,
        protectionsReportModel: NewTabPageProtectionsReportModel,
        freemiumDBPPromotionViewCoordinator: FreemiumDBPPromotionViewCoordinator,
        tld: TLD,
        fire: @escaping () async -> FireProtocol,
        keyValueStore: ThrowingKeyValueStoring,
        featureFlagger: FeatureFlagger,
        windowControllersManager: WindowControllersManagerProtocol  & AIChatTabManaging,
        tabsPreferences: TabsPreferences,
        newTabPageAIChatShortcutSettingProvider: NewTabPageAIChatShortcutSettingProviding,
        winBackOfferPromotionViewCoordinator: WinBackOfferPromotionViewCoordinator,
        subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging,
        homePageContinueSetUpModelPersistor: HomePageContinueSetUpModelPersisting,
        nextStepsCardsPersistor: NewTabPageNextStepsCardsPersisting,
        subscriptionCardPersistor: HomePageSubscriptionCardPersisting,
        duckPlayerPreferences: DuckPlayerPreferencesPersistor,
        syncService: DDGSyncing?
    ) {
        let availabilityProvider = NewTabPageSectionsAvailabilityProvider(featureFlagger: featureFlagger)
        let favoritesPublisher = bookmarkManager.listPublisher.map({ $0?.favoriteBookmarks ?? [] }).eraseToAnyPublisher()
        let favoritesModel = NewTabPageFavoritesModel(
            actionsHandler: DefaultFavoritesActionsHandler(bookmarkManager: bookmarkManager),
            favoritesPublisher: favoritesPublisher,
            faviconsDidLoadPublisher: faviconManager.faviconsLoadedPublisher.filter({ $0 }).asVoid().eraseToAnyPublisher(),
            getLegacyIsViewExpandedSetting: UserDefaultsWrapper<Bool>(key: .homePageShowAllFavorites, defaultValue: true).wrappedValue
        )

        let themePopoverPersistor = ThemePopoverUserDefaultsPersistor(keyValueStore: keyValueStore)
        let themePopoverDecider = ThemePopoverDecider(appearancePreferences: appearancePreferences,
                                                      featureFlagger: featureFlagger,
                                                      firstLaunchDate: AppDelegate.firstLaunchDate,
                                                      persistor: themePopoverPersistor)

        let customizationProvider = NewTabPageCustomizationProvider(
            customizationModel: customizationModel,
            appearancePreferences: appearancePreferences,
            themePopoverDecider: themePopoverDecider
        )
        let freemiumDBPBannerProvider = NewTabPageFreemiumDBPBannerProvider(model: freemiumDBPPromotionViewCoordinator)
        let winBackOfferBannerProvider = NewTabPageWinBackOfferBannerProvider(model: winBackOfferPromotionViewCoordinator)

        let privacyStatsModel = NewTabPagePrivacyStatsModel(
            visibilityProvider: protectionsReportModel,
            privacyStats: privacyStats,
            trackerDataProvider: PrivacyStatsTrackerDataProvider(contentBlocking: contentBlocking),
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
            actionsHandler: DefaultRecentActivityActionsHandler(
                favoritesHandler: bookmarkManager,
                burner: RecentActivityItemBurner(fireproofStatusProvider: fireproofDomains, tld: tld, fire: fire)
            )
        )
        let suggestionContainer = SuggestionContainer(
            historyProvider: historyCoordinator,
            bookmarkProvider: SuggestionsBookmarkProvider(bookmarkManager: bookmarkManager),
            burnerMode: .regular,
            isUrlIgnored: { _ in false }
        )
        let suggestionsProvider = NewTabPageOmnibarSuggestionsProvider(suggestionContainer: suggestionContainer)
        let omnibarActionHandler = NewTabPageOmnibarActionsHandler(
            windowControllersManager: windowControllersManager,
            tabsPreferences: tabsPreferences
        )
        let omnibarConfigProvider = NewTabPageOmnibarConfigProvider(
            keyValueStore: keyValueStore,
            aiChatShortcutSettingProvider: newTabPageAIChatShortcutSettingProvider
        )
        let stateProvider = NewTabPageStateProvider(
            windowControllersManager: windowControllersManager,
            featureFlagger: featureFlagger
        )
        let dataImportProvider = BookmarksAndPasswordsImportStatusProvider(bookmarkManager: bookmarkManager)
        let nextStepsPixelHandler = NewTabPageNextStepsCardsPixelHandler()

        self.init(scriptClients: [
            NewTabPageConfigurationClient(
                sectionsAvailabilityProvider: availabilityProvider,
                sectionsVisibilityProvider: appearancePreferences,
                omnibarConfigProvider: omnibarConfigProvider,
                customBackgroundProvider: customizationProvider,
                linkOpener: NewTabPageLinkOpener(),
                eventMapper: NewTabPageConfigurationEventHandler(),
                stateProvider: stateProvider
            ),
            NewTabPageCustomBackgroundClient(model: customizationProvider),
            NewTabPageRMFClient(remoteMessageProvider: activeRemoteMessageModel),
            NewTabPageFreemiumDBPClient(provider: freemiumDBPBannerProvider),
            NewTabPageNextStepsCardsClient(
                model: NewTabPageNextStepsCardsProviderFacade(
                    featureFlagger: featureFlagger,
                    dataImportProvider: dataImportProvider,
                    subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
                    legacyPersistor: homePageContinueSetUpModelPersistor,
                    pixelHandler: nextStepsPixelHandler,
                    cardActionsHandler: NewTabPageNextStepsCardsActionHandler(
                        defaultBrowserProvider: SystemDefaultBrowserProvider(),
                        dockCustomizer: DockCustomizer(),
                        dataImportProvider: dataImportProvider,
                        tabOpener: NewTabPageTabOpener(),
                        privacyConfigurationManager: contentBlocking.privacyConfigurationManager,
                        pixelHandler: nextStepsPixelHandler,
                        newTabPageNavigator: DefaultNewTabPageNavigator()
                    ),
                    appearancePreferences: appearancePreferences,
                    legacySubscriptionCardPersistor: subscriptionCardPersistor,
                    persistor: nextStepsCardsPersistor,
                    duckPlayerPreferences: duckPlayerPreferences,
                    syncService: syncService
                )
            ),
            NewTabPageFavoritesClient(favoritesModel: favoritesModel, preferredFaviconSize: Int(Favicon.SizeCategory.medium.rawValue)),
            NewTabPageProtectionsReportClient(model: protectionsReportModel),
            NewTabPagePrivacyStatsClient(model: privacyStatsModel),
            NewTabPageRecentActivityClient(model: recentActivityModel),
            NewTabPageOmnibarClient(configProvider: omnibarConfigProvider,
                                    suggestionsProvider: suggestionsProvider,
                                    actionHandler: omnibarActionHandler),
            NewTabPageWinBackOfferClient(provider: winBackOfferBannerProvider)
        ])
    }
}

struct NewTabPageTabOpener: NewTabPageNextStepsCardsTabOpening {
    @MainActor
    func openTab(_ tab: Tab) {
        Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel.insertOrAppend(tab: tab, selected: true)
    }
}
