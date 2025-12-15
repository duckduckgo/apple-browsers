//
//  NewTabPageCoordinatorTests.swift
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

import AutoconsentStats
import BrowserServicesKit
import Combine
import Common
import History
import HistoryView
import NewTabPage
import PersistenceTestingUtils
import PixelKit
import PrivacyStats
import SharedTestUtilities
import XCTest
import RemoteMessagingTestsUtils
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

final class MockPrivacyStats: PrivacyStatsCollecting {

    let statsUpdatePublisher: AnyPublisher<Void, Never> = Empty<Void, Never>().eraseToAnyPublisher()

    func recordBlockedTracker(_ name: String) async {}
    func fetchPrivacyStats() async -> [String: Int64] { [:] }
    func fetchPrivacyStatsTotalCount() async -> Int64 { 0 }
    func clearPrivacyStats() async {}
    func handleAppTermination() async {}
}

final class MockAutoconsentStats: AutoconsentStatsCollecting {
    let statsUpdatePublisher: AnyPublisher<Void, Never> = Empty<Void, Never>().eraseToAnyPublisher()

    func recordAutoconsentAction(clicksMade: Int64, timeSpent: TimeInterval) async {}

    var totalCookiePopUpsBlocked: Int64 = 0
    func fetchTotalCookiePopUpsBlocked() async -> Int64 {
        return totalCookiePopUpsBlocked
    }

    func fetchAutoconsentDailyUsagePack() async -> AutoconsentDailyUsagePack {
        AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: totalCookiePopUpsBlocked,
            totalClicksMadeBlockingCookiePopUps: 0,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )
    }
    func clearAutoconsentStats() async {}
    func isEnabled() async -> Bool { true }
}

final class NewTabPageCoordinatorTests: XCTestCase {
    var coordinator: NewTabPageCoordinator!
    var appearancePreferences: AppearancePreferences!
    var customizationModel: NewTabPageCustomizationModel!
    var notificationCenter: NotificationCenter!
    var keyValueStore: MockKeyValueFileStore!
    var firePixelCalls: [PixelKitEvent] = []
    var featureFlagger: FeatureFlagger!
    var windowControllersManager: (WindowControllersManagerProtocol & AIChatTabManaging)!
    var tabsPreferences: TabsPreferences!
    var subscriptionCardVisibilityManager: MockHomePageSubscriptionCardVisibilityManaging!
    var homePageContinueSetUpModelPersisting: MockHomePageContinueSetUpModelPersisting!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        subscriptionCardVisibilityManager = MockHomePageSubscriptionCardVisibilityManaging()
        homePageContinueSetUpModelPersisting = MockHomePageContinueSetUpModelPersisting()
        notificationCenter = NotificationCenter()
        keyValueStore = try MockKeyValueFileStore()
        firePixelCalls.removeAll()
        featureFlagger = MockFeatureFlagger()

        let appearancePreferencesPersistor = AppearancePreferencesPersistorMock()
        appearancePreferences = AppearancePreferences(
            persistor: appearancePreferencesPersistor,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: featureFlagger
        )

        customizationModel = NewTabPageCustomizationModel(
            appearancePreferences: appearancePreferences,
            userBackgroundImagesManager: nil,
            sendPixel: { _ in },
            openFilePanel: { nil },
            showAddImageFailedAlert: {}
        )

        windowControllersManager = WindowControllersManagerMock()

        tabsPreferences = TabsPreferences(persistor: MockTabsPreferencesPersistor(), windowControllersManager: WindowControllersManagerMock())

        featureFlagger = MockFeatureFlagger()

        let fireCoordinator = FireCoordinator(tld: TLD(),
                                              featureFlagger: Application.appDelegate.featureFlagger,
                                              historyCoordinating: HistoryCoordinatingMock(),
                                              visualizeFireAnimationDecider: nil,
                                              onboardingContextualDialogsManager: nil,
                                              fireproofDomains: MockFireproofDomains(),
                                              faviconManagement: FaviconManagerMock(),
                                              windowControllersManager: windowControllersManager,
                                              pixelFiring: nil,
                                              historyProvider: MockHistoryViewDataProvider())
        let cookiePopupProtectionPreferences = CookiePopupProtectionPreferences(persistor: MockCookiePopupProtectionPreferencesPersistor(), windowControllersManager: windowControllersManager)
        let visualizeFireAnimationDecider = MockVisualizeFireAnimationDecider()
        let settingsMigrator = NewTabPageProtectionsReportSettingsMigrator(legacyKeyValueStore: UserDefaultsWrapper<Any>.sharedDefaults)
        let protectionsReportModel = NewTabPageProtectionsReportModel(
            privacyStats: MockPrivacyStats(),
            autoconsentStats: MockAutoconsentStats(),
            keyValueStore: keyValueStore,
            burnAnimationSettingChanges: visualizeFireAnimationDecider.shouldShowFireAnimationPublisher,
            showBurnAnimation: visualizeFireAnimationDecider.shouldShowFireAnimation,
            isAutoconsentEnabled: { cookiePopupProtectionPreferences.isAutoconsentEnabled },
            getLegacyIsViewExpandedSetting: settingsMigrator.isViewExpanded,
            getLegacyActiveFeedSetting: settingsMigrator.activeFeed
        )

        coordinator = NewTabPageCoordinator(
            appearancePreferences: appearancePreferences,
            customizationModel: customizationModel,
            bookmarkManager: MockBookmarkManager(),
            faviconManager: FaviconManagerMock(),
            duckPlayerHistoryEntryTitleProvider: MockDuckPlayerHistoryEntryTitleProvider(),
            activeRemoteMessageModel: ActiveRemoteMessageModel(
                remoteMessagingStore: MockRemoteMessagingStore(),
                remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProvider(),
                openURLHandler: { _ in },
                navigateToFeedbackHandler: { }
            ),
            historyCoordinator: HistoryCoordinatingMock(),
            contentBlocking: ContentBlockingMock(),
            fireproofDomains: MockFireproofDomains(domains: []),
            privacyStats: MockPrivacyStats(),
            autoconsentStats: MockAutoconsentStats(),
            cookiePopupProtectionPreferences: cookiePopupProtectionPreferences,
            freemiumDBPPromotionViewCoordinator: FreemiumDBPPromotionViewCoordinator(
                freemiumDBPUserStateManager: MockFreemiumDBPUserStateManager(),
                freemiumDBPFeature: MockFreemiumDBPFeature(),
                freemiumDBPPresenter: MockFreemiumDBPPresenter(),
                notificationCenter: notificationCenter,
                dataBrokerProtectionFreemiumPixelHandler: MockDataBrokerProtectionFreemiumPixelHandler(),
                contextualOnboardingPublisher: Just(false).eraseToAnyPublisher()
            ),
            tld: Application.appDelegate.tld,
            fireCoordinator: fireCoordinator,
            keyValueStore: keyValueStore,
            notificationCenter: notificationCenter,
            visualizeFireAnimationDecider: visualizeFireAnimationDecider,
            featureFlagger: featureFlagger,
            windowControllersManager: windowControllersManager,
            tabsPreferences: tabsPreferences,
            newTabPageAIChatShortcutSettingProvider: MockNewTabPageAIChatShortcutSettingProvider(),
            winBackOfferPromotionViewCoordinator: WinBackOfferPromotionViewCoordinator(winBackOfferVisibilityManager: MockWinBackOfferVisibilityManager()),
            subscriptionCardVisibilityManager: subscriptionCardVisibilityManager,
            protectionsReportModel: protectionsReportModel,
            homePageContinueSetUpModelPersistor: homePageContinueSetUpModelPersisting,
            fireDailyPixel: { self.firePixelCalls.append($0) }
        )
    }

    override func tearDown() {
        appearancePreferences = nil
        coordinator = nil
        customizationModel = nil
        featureFlagger = nil
        firePixelCalls = []
        keyValueStore = nil
        notificationCenter = nil
        tabsPreferences = nil
        windowControllersManager = nil
        subscriptionCardVisibilityManager = nil
        homePageContinueSetUpModelPersisting = nil
    }

    func testWhenNewTabPageAppearsThenPixelIsSent() {
        notificationCenter.post(name: .newTabPageWebViewDidAppear, object: nil)
        XCTAssertEqual(firePixelCalls.count, 1)
    }
}
