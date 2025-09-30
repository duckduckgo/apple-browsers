//
//  RemoteMessagingConfigMatcherProvider.swift
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

import Foundation
import BrowserServicesKit
import Persistence
import Bookmarks
import RemoteMessaging
import VPN
import Subscription
import Freemium
import FeatureFlags

extension DefaultWaitlistActivationDateStore: VPNActivationDateProviding {}

final class RemoteMessagingConfigMatcherProvider: RemoteMessagingConfigMatcherProviding {

    convenience init(
        database: CoreDataDatabase,
        bookmarksDatabase: CoreDataDatabase,
        appearancePreferences: AppearancePreferences,
        startupPreferences: StartupPreferences,
        duckPlayerPreferencesPersistor: @escaping @autoclosure () -> DuckPlayerPreferencesPersistor = DuckPlayerPreferencesUserDefaultsPersistor(),
        pinnedTabsManagerProvider: PinnedTabsManagerProviding,
        internalUserDecider: InternalUserDecider,
        subscriptionManager: any SubscriptionAuthV1toV2Bridge,
        featureFlagger: FeatureFlagger,
        visualStyle: VisualStyleProviding
    ) {
        self.init(
            bookmarksDatabase: bookmarksDatabase,
            appearancePreferences: appearancePreferences,
            startupPreferences: startupPreferences,
            duckPlayerPreferencesPersistor: duckPlayerPreferencesPersistor(),
            pinnedTabsManagerProvider: pinnedTabsManagerProvider,
            internalUserDecider: internalUserDecider,
            statisticsStore: LocalStatisticsStore(pixelDataStore: LocalPixelDataStore(database: database)),
            variantManager: DefaultVariantManager(database: database),
            subscriptionManager: subscriptionManager,
            featureFlagger: featureFlagger,
            visualStyle: visualStyle
        )
    }

    init(
        bookmarksDatabase: CoreDataDatabase,
        appearancePreferences: AppearancePreferences,
        startupPreferences: StartupPreferences,
        duckPlayerPreferencesPersistor: @escaping @autoclosure () -> DuckPlayerPreferencesPersistor = DuckPlayerPreferencesUserDefaultsPersistor(),
        pinnedTabsManagerProvider: PinnedTabsManagerProviding,
        internalUserDecider: InternalUserDecider,
        statisticsStore: @escaping @autoclosure () -> StatisticsStore,
        variantManager: @escaping @autoclosure () -> VariantManager,
        subscriptionManager: any SubscriptionAuthV1toV2Bridge,
        featureFlagger: FeatureFlagger,
        visualStyle: VisualStyleProviding
    ) {
        self.bookmarksDatabase = bookmarksDatabase
        self.appearancePreferences = appearancePreferences
        self.startupPreferences = startupPreferences
        self.duckPlayerPreferencesPersistor = duckPlayerPreferencesPersistor
        self.pinnedTabsManagerProvider = pinnedTabsManagerProvider
        self.internalUserDecider = internalUserDecider
        self.statisticsStore = statisticsStore
        self.variantManager = variantManager
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.visualStyle = visualStyle
    }

    let bookmarksDatabase: CoreDataDatabase
    let appearancePreferences: AppearancePreferences
    let startupPreferences: StartupPreferences
    let duckPlayerPreferencesPersistor: () -> DuckPlayerPreferencesPersistor
    let pinnedTabsManagerProvider: PinnedTabsManagerProviding
    let internalUserDecider: InternalUserDecider
    let statisticsStore: () -> StatisticsStore
    let variantManager: () -> VariantManager
    let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    let featureFlagger: FeatureFlagger
    let visualStyle: VisualStyleProviding

    func refreshConfigMatcher(using store: RemoteMessagingStoring) async -> RemoteMessagingConfigMatcher {

        var bookmarksCount = 0
        var favoritesCount = 0
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            bookmarksCount = BookmarkUtils.numberOfBookmarks(in: context)
            favoritesCount = BookmarkUtils.numberOfFavorites(for: appearancePreferences.favoritesDisplayMode, in: context)
        }

        let isDuckDuckGoSubscriber = subscriptionManager.isUserAuthenticated
        let isSubscriptionEligibleUser = subscriptionManager.canPurchase

        let activationDateStore = DefaultWaitlistActivationDateStore(source: .netP)
        let daysSinceNetworkProtectionEnabled = activationDateStore.daysSinceActivation() ?? -1

        let autofillUsageStore = AutofillUsageStore(standardUserDefaults: .standard, appGroupUserDefaults: nil)

        var subscriptionDaysSinceSubscribed = -1
        var subscriptionDaysUntilExpiry = -1
        var isSubscriptionActive = false
        var isSubscriptionExpiring = false
        var isSubscriptionExpired = false
        var subscriptionPurchasePlatform: String?
        let surveyActionMapper: RemoteMessagingSurveyActionMapping

        let statisticsStore = self.statisticsStore()

        do {
            let subscription = try await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
            subscriptionDaysSinceSubscribed = Calendar.current.numberOfDaysBetween(subscription.startedAt, and: Date()) ?? -1
            subscriptionDaysUntilExpiry = Calendar.current.numberOfDaysBetween(Date(), and: subscription.expiresOrRenewsAt) ?? -1
            subscriptionPurchasePlatform = subscription.platform.rawValue

            switch subscription.status {
            case .autoRenewable, .gracePeriod:
                isSubscriptionActive = true
            case .notAutoRenewable:
                isSubscriptionActive = true
                isSubscriptionExpiring = true
            case .expired, .inactive:
                isSubscriptionExpired = true
            case .unknown:
                break // Not supported in RMF
            }

            surveyActionMapper = DefaultRemoteMessagingSurveyURLBuilder(
                statisticsStore: statisticsStore,
                vpnActivationDateStore: DefaultWaitlistActivationDateStore(source: .netP),
                subscription: subscription,
                autofillUsageStore: autofillUsageStore
            )
        } catch {
            surveyActionMapper = DefaultRemoteMessagingSurveyURLBuilder(
                statisticsStore: statisticsStore,
                vpnActivationDateStore: DefaultWaitlistActivationDateStore(source: .netP),
                subscription: nil,
                autofillUsageStore: autofillUsageStore
            )
        }

        let dismissedMessageIds = store.fetchDismissedRemoteMessageIDs()
        let shownMessageIds = store.fetchShownRemoteMessageIDs()

#if APPSTORE
        let isInstalledMacAppStore = true
#else
        let isInstalledMacAppStore = false
#endif

        let duckPlayerPreferencesPersistor = duckPlayerPreferencesPersistor()

        let deprecatedRemoteMessageStorage = DefaultSurveyRemoteMessagingStorage.surveys()

        let freemiumDBPUserStateManager = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp)
        let isCurrentFreemiumDBPUser = !subscriptionManager.isUserAuthenticated && freemiumDBPUserStateManager.didActivate

        let pinnedTabsCount: Int = await MainActor.run {
            pinnedTabsManagerProvider.currentPinnedTabManagers.map { $0.tabCollection.tabs.count }.reduce(0, +)
        }

        let enabledFeatureFlags: [String] = FeatureFlag.allCases.filter { flag in
            flag.cohortType == nil && featureFlagger.isFeatureOn(for: flag)
        }.map(\.rawValue)

        return RemoteMessagingConfigMatcher(
            appAttributeMatcher: AppAttributeMatcher(statisticsStore: statisticsStore,
                                                     variantManager: variantManager(),
                                                     isInternalUser: internalUserDecider.isInternalUser,
                                                     isInstalledMacAppStore: isInstalledMacAppStore),
            userAttributeMatcher: UserAttributeMatcher(statisticsStore: statisticsStore,
                                                       variantManager: variantManager(),
                                                       bookmarksCount: bookmarksCount,
                                                       favoritesCount: favoritesCount,
                                                       appTheme: appearancePreferences.currentThemeName.rawValue,
                                                       daysSinceNetPEnabled: daysSinceNetworkProtectionEnabled,
                                                       isSubscriptionEligibleUser: isSubscriptionEligibleUser,
                                                       isDuckDuckGoSubscriber: isDuckDuckGoSubscriber,
                                                       subscriptionDaysSinceSubscribed: subscriptionDaysSinceSubscribed,
                                                       subscriptionDaysUntilExpiry: subscriptionDaysUntilExpiry,
                                                       subscriptionPurchasePlatform: subscriptionPurchasePlatform,
                                                       isSubscriptionActive: isSubscriptionActive,
                                                       isSubscriptionExpiring: isSubscriptionExpiring,
                                                       isSubscriptionExpired: isSubscriptionExpired,
                                                       dismissedMessageIds: dismissedMessageIds,
                                                       shownMessageIds: shownMessageIds,
                                                       pinnedTabsCount: pinnedTabsCount,
                                                       hasCustomHomePage: startupPreferences.launchToCustomHomePage,
                                                       isDuckPlayerOnboarded: duckPlayerPreferencesPersistor.youtubeOverlayAnyButtonPressed,
                                                       isDuckPlayerEnabled: duckPlayerPreferencesPersistor.duckPlayerModeBool != false,
                                                       isCurrentFreemiumPIRUser: isCurrentFreemiumDBPUser,
                                                       dismissedDeprecatedMacRemoteMessageIds: deprecatedRemoteMessageStorage.dismissedMessageIDs(),
                                                       enabledFeatureFlags: enabledFeatureFlags
                                                      ),
            percentileStore: RemoteMessagingPercentileUserDefaultsStore(keyValueStore: UserDefaults.standard),
            surveyActionMapper: surveyActionMapper,
            dismissedMessageIds: dismissedMessageIds
        )
    }
}
