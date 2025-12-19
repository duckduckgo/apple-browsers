//
//  RemoteMessagingConfigMatcherProvider.swift
//  DuckDuckGo
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

import Common
import Core
import Foundation
import BrowserServicesKit
import PrivacyConfig
import Persistence
import Bookmarks
import RemoteMessaging
import VPN
import Subscription
import DDGSync

extension DefaultVPNActivationDateStore: VPNActivationDateProviding {}

final class RemoteMessagingConfigMatcherProvider: RemoteMessagingConfigMatcherProviding {

    init(
        bookmarksDatabase: CoreDataDatabase,
        appSettings: AppSettings,
        internalUserDecider: InternalUserDecider,
        duckPlayerStorage: DuckPlayerStorage,
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
        themeManager: ThemeManaging = ThemeManager.shared,
        syncService: DDGSyncing,
        winBackOfferService: WinBackOfferService
    ) {
        self.bookmarksDatabase = bookmarksDatabase
        self.appSettings = appSettings
        self.internalUserDecider = internalUserDecider
        self.duckPlayerStorage = duckPlayerStorage
        self.featureFlagger = featureFlagger
        self.themeManager = themeManager
        self.syncService = syncService
        self.winBackOfferService = winBackOfferService
    }

    let bookmarksDatabase: CoreDataDatabase
    let appSettings: AppSettings
    let duckPlayerStorage: DuckPlayerStorage
    let internalUserDecider: InternalUserDecider
    let featureFlagger: FeatureFlagger
    let themeManager: ThemeManaging
    let syncService: DDGSyncing
    let winBackOfferService: WinBackOfferService
    func refreshConfigMatcher(using store: RemoteMessagingStoring) async -> RemoteMessagingConfigMatcher {

        var bookmarksCount = 0
        var favoritesCount = 0
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            bookmarksCount = BookmarkUtils.numberOfBookmarks(in: context)
            favoritesCount = BookmarkUtils.numberOfFavorites(for: appSettings.favoritesDisplayMode, in: context)
        }

        let statisticsStore = StatisticsUserDefaults()
        let featureDiscovery = DefaultFeatureDiscovery()
        let variantManager = DefaultVariantManager()
        let subscriptionManager = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge
        let isDuckDuckGoSubscriber = subscriptionManager.isUserAuthenticated
        let isSubscriptionEligibleUser = subscriptionManager.isSubscriptionPurchaseEligible

        let activationDateStore = DefaultVPNActivationDateStore()
        let daysSinceNetworkProtectionEnabled = activationDateStore.daysSinceActivation() ?? -1
        let autofillUsageStore = AutofillUsageStore()

        var subscriptionDaysSinceSubscribed: Int = -1
        var subscriptionDaysUntilExpiry: Int = -1
        var subscriptionPurchasePlatform: String?
        var isSubscriptionActive: Bool = false
        var isSubscriptionExpiring: Bool = false
        var isSubscriptionExpired: Bool = false
        var subscriptionFreeTrialActive: Bool = false

        var isDuckPlayerOnboarded: Bool {
            duckPlayerStorage.userInteractedWithDuckPlayer
        }
        var isDuckPlayerEnabled: Bool {
            appSettings.duckPlayerMode != .disabled
        }
        var isSyncEnabled: Bool {
            syncService.authState != .inactive
        }

        let shouldShowWinBackOfferUrgencyMessage = winBackOfferService.shouldShowUrgencyMessage

        let surveyActionMapper: DefaultRemoteMessagingSurveyURLBuilder

        if let subscription = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst) {
            subscriptionDaysSinceSubscribed = Calendar.current.numberOfDaysBetween(subscription.startedAt, and: Date()) ?? -1
            subscriptionDaysUntilExpiry = Calendar.current.numberOfDaysBetween(Date(), and: subscription.expiresOrRenewsAt) ?? -1
            subscriptionPurchasePlatform = subscription.platform.rawValue
            subscriptionFreeTrialActive = subscription.hasActiveTrialOffer

            switch subscription.status {
            case .autoRenewable, .gracePeriod:
                isSubscriptionActive = true
            case .notAutoRenewable:
                isSubscriptionExpiring = true
            case .expired, .inactive:
                isSubscriptionExpired = true
            case .unknown:
                break // Not supported in RMF
            }

            surveyActionMapper = DefaultRemoteMessagingSurveyURLBuilder(statisticsStore: statisticsStore,
                                                                        vpnActivationDateStore: DefaultVPNActivationDateStore(),
                                                                        subscriptionDataProvider: subscription,
                                                                        autofillUsageStore: autofillUsageStore)
        } else {
            surveyActionMapper = DefaultRemoteMessagingSurveyURLBuilder(statisticsStore: statisticsStore,
                                                                        vpnActivationDateStore: DefaultVPNActivationDateStore(),
                                                                        subscriptionDataProvider: nil,
                                                                        autofillUsageStore: autofillUsageStore)
        }

        let dismissedMessageIds = store.fetchDismissedRemoteMessageIDs()
        let shownMessageIds = store.fetchShownRemoteMessageIDs()

        let enabledFeatureFlags: [String] = FeatureFlag.allCases.filter { flag in
            flag.cohortType == nil && featureFlagger.isFeatureOn(for: flag)
        }.map(\.rawValue)

        return RemoteMessagingConfigMatcher(
            appAttributeMatcher: AppAttributeMatcher(statisticsStore: statisticsStore,
                                                     variantManager: variantManager,
                                                     isInternalUser: internalUserDecider.isInternalUser),
            userAttributeMatcher: UserAttributeMatcher(statisticsStore: statisticsStore,
                                                       featureDiscovery: featureDiscovery,
                                                       variantManager: variantManager,
                                                       bookmarksCount: bookmarksCount,
                                                       favoritesCount: favoritesCount,
                                                       appTheme: appSettings.currentThemeStyle.rawValue,
                                                       isWidgetInstalled: await appSettings.isWidgetInstalled(),
                                                       daysSinceNetPEnabled: daysSinceNetworkProtectionEnabled,
                                                       isSubscriptionEligibleUser: isSubscriptionEligibleUser,
                                                       isDuckDuckGoSubscriber: isDuckDuckGoSubscriber,
                                                       subscriptionDaysSinceSubscribed: subscriptionDaysSinceSubscribed,
                                                       subscriptionDaysUntilExpiry: subscriptionDaysUntilExpiry,
                                                       subscriptionPurchasePlatform: subscriptionPurchasePlatform,
                                                       isSubscriptionActive: isSubscriptionActive,
                                                       isSubscriptionExpiring: isSubscriptionExpiring,
                                                       isSubscriptionExpired: isSubscriptionExpired,
                                                       subscriptionFreeTrialActive: subscriptionFreeTrialActive,
                                                       isDuckPlayerOnboarded: isDuckPlayerOnboarded,
                                                       isDuckPlayerEnabled: isDuckPlayerEnabled,
                                                       dismissedMessageIds: dismissedMessageIds,
                                                       shownMessageIds: shownMessageIds,
                                                       enabledFeatureFlags: enabledFeatureFlags,
                                                       isSyncEnabled: isSyncEnabled,
                                                       shouldShowWinBackOfferUrgencyMessage: shouldShowWinBackOfferUrgencyMessage),
            percentileStore: RemoteMessagingPercentileUserDefaultsStore(keyValueStore: UserDefaults.standard),
            surveyActionMapper: surveyActionMapper,
            dismissedMessageIds: dismissedMessageIds
        )
    }
}

extension DuckDuckGoSubscription: @retroactive SubscriptionSurveyDataProviding {
    public var subscriptionStatus: String? {
        return status.remoteMessagingFrameworkValue
    }

    public var subscriptionPlatform: String? {
        return platform.rawValue
    }

    public var subscriptionBilling: String? {
        return billingPeriod.remoteMessagingFrameworkValue
    }

    public var subscriptionStartDate: Date? {
        return startedAt
    }

    public var subscriptionExpiryDate: Date? {
        return expiresOrRenewsAt
    }

    public var subscriptionTrialActive: Bool? {
        return hasActiveTrialOffer
    }
}
