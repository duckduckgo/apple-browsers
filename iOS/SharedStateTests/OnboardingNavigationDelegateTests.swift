//
//  OnboardingNavigationDelegateTests.swift
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

import XCTest
import Persistence
import Bookmarks
import DDGSync
import History
import BrowserServicesKit
import RemoteMessaging
import Configuration
import Combine
import SubscriptionTestingUtilities
import Common
@testable import DuckDuckGo
@testable import Core
import PersistenceTestingUtils

// swiftlint:disable force_try

final class OnboardingNavigationDelegateTests: XCTestCase {

    var mainVC: MainViewController!
    var onboardingPixelReporter: OnboardingPixelReporterMock!
    let keyValueStore: ThrowingKeyValueStoring = try! MockKeyValueFileStore()

    override func setUpWithError() throws {
        throw XCTSkip("Potentially flaky")
        try super.setUpWithError()
        let db = CoreDataDatabase.bookmarksMock
        let bookmarkDatabaseCleaner = BookmarkDatabaseCleaner(bookmarkDatabase: db, errorEvents: nil)
        let dataProviders = SyncDataProviders(
            bookmarksDatabase: db,
            secureVaultFactory: AutofillSecureVaultFactory,
            secureVaultErrorReporter: SecureVaultReporter(),
            settingHandlers: [],
            favoritesDisplayModeStorage: MockFavoritesDisplayModeStoring(),
            syncErrorHandler: SyncErrorHandler(),
            faviconStoring: MockFaviconStore(),
            tld: TLD()
        )
        
        let remoteMessagingClient = RemoteMessagingClient(
            bookmarksDatabase: db,
            appSettings: AppSettingsMock(),
            internalUserDecider: DefaultInternalUserDecider(),
            configurationStore: MockConfigurationStoring(),
            database: db,
            errorEvents: nil,
            remoteMessagingAvailabilityProvider: MockRemoteMessagingAvailabilityProviding(),
            duckPlayerStorage: MockDuckPlayerStorage()
        )
        let homePageConfiguration = HomePageConfiguration(remoteMessagingClient: remoteMessagingClient, privacyProDataReporter: MockPrivacyProDataReporter())
        let tabsModel = TabsModel(desktop: true)
        onboardingPixelReporter = OnboardingPixelReporterMock()
        let tabsPersistence = try TabsModelPersistence()
        mainVC = MainViewController(
            bookmarksDatabase: db,
            bookmarksDatabaseCleaner: bookmarkDatabaseCleaner,
            historyManager: MockHistoryManager(historyCoordinator: MockHistoryCoordinator(), isEnabledByUser: true, historyFeatureEnabled: true),
            homePageConfiguration: homePageConfiguration,
            syncService: MockDDGSyncing(authState: .active, isSyncInProgress: false),
            syncDataProviders: dataProviders,
            appSettings: AppSettingsMock(),
            previewsSource: MockTabPreviewsSource(),
            tabsModel: tabsModel,
            tabsPersistence: tabsPersistence,
            syncPausedStateManager: CapturingSyncPausedStateManager(),
            privacyProDataReporter: MockPrivacyProDataReporter(),
            variantManager: MockVariantManager(),
            contextualOnboardingPresenter: ContextualOnboardingPresenterMock(),
            contextualOnboardingLogic: ContextualOnboardingLogicMock(),
            contextualOnboardingPixelReporter: onboardingPixelReporter,
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock.enabled,
            voiceSearchHelper: MockVoiceSearchHelper(isSpeechRecognizerAvailable: true, voiceSearchEnabled: true),
            featureFlagger: MockFeatureFlagger(),
            contentScopeExperimentsManager: MockContentScopeExperimentManager(),
            fireproofing: MockFireproofing(),
            subscriptionCookieManager: SubscriptionCookieManagerMock(),
            textZoomCoordinator: MockTextZoomCoordinator(),
            websiteDataManager: MockWebsiteDataManager(),
            appDidFinishLaunchingStartTime: nil,
            maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
            maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
            aiChatSettings: MockAIChatSettingsProvider(),
            themeManager: MockThemeManager(),
            keyValueStore: keyValueStore
        )
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.rootViewController?.present(mainVC, animated: false, completion: nil)

        let viewLoadedExpectation = expectation(description: "View is loaded")
        DispatchQueue.main.async {
            XCTAssertNotNil(self.mainVC.view, "The view should be loaded")
            viewLoadedExpectation.fulfill()
        }
        waitForExpectations(timeout: 5, handler: nil)
        mainVC.loadQueryInNewTab("try something")
    }

    override func tearDown() {
        mainVC = nil
    }

    func testSearchForQueryLoadsQueryInCurrentTab() throws {
        // GIVEN
        let query = "Some query"
        let expectedUrl = try XCTUnwrap(URL.makeSearchURL(query: query, queryContext: nil))

        // WHEN
        mainVC.searchFromOnboarding(for: query)

        // THEN
        assertExpected(queryURL: expectedUrl)
    }

    func testNavigateToURLLoadsSiteInCurrentTab() throws {
        // GIVEN
        let site = "duckduckgo.com"
        let expectedUrl = try XCTUnwrap(URL(string: site))

        // WHEN
        mainVC.navigateFromOnboarding(to: expectedUrl)

        // THEN
        assertExpected(url: expectedUrl)
    }

    func testWhenDidRequestLoadQueryIsCalledThenLoadsQueryInCurrentTab() throws {
        // GIVEN
        let query = "Some query"
        let expectedUrl = try XCTUnwrap(URL.makeSearchURL(query: query, queryContext: nil))

        // WHEN
        mainVC.tab(.fake(), didRequestLoadQuery: query)

        // THEN
        assertExpected(queryURL: expectedUrl)
    }

    func testWhenDidRequestLoadsURLIsCalledThenLoadSiteInCurrentTab() throws {
        // GIVEN
        let site = "duckduckgo.com"
        let expectedUrl = try XCTUnwrap(URL(string: site))

        // WHEN
        mainVC.tab(.fake(), didRequestLoadURL: expectedUrl)

        // THEN
        assertExpected(url: expectedUrl)
    }

    func assertExpected(queryURL: URL) {
        XCTAssertNotNil(mainVC.currentTab?.url)
        XCTAssertEqual(mainVC.currentTab?.url?.scheme, queryURL.scheme)
        XCTAssertEqual(mainVC.currentTab?.url?.host, queryURL.host)
        XCTAssertEqual(mainVC.currentTab?.url?.query, queryURL.query)
    }

    func assertExpected(url: URL) {
        XCTAssertNotNil(mainVC.currentTab?.url)
        XCTAssertEqual(mainVC.currentTab?.url, url)
    }

    // MARK: Pixel

    func testWhenPrivacyBarIconIsPressed_AndPrivacyIconIsHighlighted_ThenFireFirstTimePrivacyDashboardUsedPixel() {
        // GIVEN
        let isHighlighted = true
        XCTAssertFalse(onboardingPixelReporter.didCallMeasurePrivacyDashboardOpenedForFirstTime)

        // WHEN
        mainVC.onPrivacyIconPressed(isHighlighted: isHighlighted)

        // THEN
        XCTAssertTrue(onboardingPixelReporter.didCallMeasurePrivacyDashboardOpenedForFirstTime)
    }

    func testWhenPrivacyBarIconIsPressed_AndPrivacyIconIsNotHighlighted_ThenDoNotFireFirstTimePrivacyDashboardUsedPixel() {
        // GIVEN
        let isHighlighted = false
        XCTAssertFalse(onboardingPixelReporter.didCallMeasurePrivacyDashboardOpenedForFirstTime)

        // WHEN
        mainVC.onPrivacyIconPressed(isHighlighted: isHighlighted)

        // THEN
        XCTAssertFalse(onboardingPixelReporter.didCallMeasurePrivacyDashboardOpenedForFirstTime)
    }

}

// swiftlint:enable force_try
