//
//  TabManagerTests.swift
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

import XCTest
import Core
@testable import DuckDuckGo
import SubscriptionTestingUtilities
import BrowserServicesKit
import PersistenceTestingUtils

// swiftlint:disable force_try

@MainActor
final class TabManagerTests: XCTestCase {

    func testWhenClosingOnlyOpenTabThenASingleEmptyTabIsAdded() async throws {

        let tabsModel = TabsModel(desktop: false)
        XCTAssertEqual(1, tabsModel.count)

        let originalTab = tabsModel.get(tabAt: 0)
        XCTAssertTrue(originalTab === tabsModel.get(tabAt: 0))

        let manager = try makeManager(tabsModel)
        manager.remove(at: 0)

        XCTAssertEqual(1, tabsModel.count)
        XCTAssertFalse(originalTab === tabsModel.get(tabAt: 0))
    }

    func testWhenTabOpenedFromOtherTabThenRemovingTabSetsIndexToPreviousTab() async throws {
        let tabsModel = TabsModel(desktop: false)
        tabsModel.add(tab: Tab(link: Link(title: "example", url: URL(string: "https://example.com")!)))
        tabsModel.add(tab: Tab())
        XCTAssertEqual(3, tabsModel.count)

        tabsModel.select(tabAt: 1)

        let manager = try makeManager(tabsModel)

        // We expect the new tab to be the index after whatever was current (ie zero)
        XCTAssertEqual(1, tabsModel.currentIndex)
        XCTAssertEqual("https://example.com", tabsModel.tabs[1].link?.url.absoluteString)

        XCTAssertEqual(3, tabsModel.count)

        manager.remove(at: 1)
        // We expect the new current index to be the previous index
        XCTAssertEqual(0, tabsModel.currentIndex)
    }

    func testWhenAppBecomesActiveAndExcessPreviewsThenCleanUpHappens() async throws {
        let mock = MockTabPreviewsSource(totalStoredPreviews: 4)
        let tabsModel = TabsModel(desktop: false)
        tabsModel.add(tab: Tab())
        tabsModel.add(tab: Tab())
        let manager = try makeManager(tabsModel, previewsSource: mock)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(interval: 0.5)
        XCTAssertEqual(1, mock.removePreviewsWithIdNotInCalls.count)

        // This is just to keep a reference to the manager to supress the unused warning and keep it from being deinit
        manager.removeAll()
    }

    func makeManager(_ model: TabsModel,
                     previewsSource: TabPreviewsSource = MockTabPreviewsSource()) throws -> TabManager {
        let tabsPersistence = try TabsModelPersistence()
        return TabManager(model: model,
                          persistence: tabsPersistence,
                          previewsSource: previewsSource,
                          interactionStateSource: TabInteractionStateDiskSource(),
                          bookmarksDatabase: MockBookmarksDatabase.make(prepareFolderStructure: false),
                          historyManager: MockHistoryManager(),
                          syncService: MockDDGSyncing(),
                          privacyProDataReporter: MockPrivacyProDataReporter(),
                          contextualOnboardingPresenter: ContextualOnboardingPresenterMock(),
                          contextualOnboardingLogic: ContextualOnboardingLogicMock(),
                          onboardingPixelReporter: OnboardingPixelReporterMock(),
                          featureFlagger: MockFeatureFlagger(),
                          contentScopeExperimentManager: MockContentScopeExperimentManager(),
                          subscriptionCookieManager: SubscriptionCookieManagerMock(),
                          appSettings: AppSettingsMock(),
                          textZoomCoordinator: MockTextZoomCoordinator(),
                          websiteDataManager: MockWebsiteDataManager(),
                          fireproofing: MockFireproofing(),
                          maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
                          maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
                          featureDiscovery: MockFeatureDiscovery(),
                          keyValueStore: try! MockKeyValueFileStore())
    }

}

// swiftlint:enable force_try
