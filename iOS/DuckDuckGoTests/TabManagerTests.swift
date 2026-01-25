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
import BrowserServicesKitTestsUtils
import Combine

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

    // MARK: - Tab History Cleanup Tests
    
    func testWhenTabRemoved_ThenTabHistoryIsCleared() async throws {
        let tabsModel = TabsModel(desktop: false)
        let tabToRemove = Tab(link: Link(title: "example", url: URL(string: "https://example.com")!))
        tabsModel.add(tab: tabToRemove)
        let tabID = tabToRemove.uid
        
        let mockHistoryManager = MockHistoryManager()
        mockHistoryManager.removeTabHistoryExpectation = expectation(description: "removeTabHistory called")
        let manager = try makeManager(tabsModel, historyManager: mockHistoryManager)
        
        manager.remove(at: 1)
        
        await fulfillment(of: [mockHistoryManager.removeTabHistoryExpectation!], timeout: 5.0)
        
        XCTAssertEqual(mockHistoryManager.removeTabHistoryCalls.count, 1)
        XCTAssertEqual(mockHistoryManager.removeTabHistoryCalls.first, [tabID])
    }
    
    func testWhenAllTabsRemoved_ThenTabHistoryIsCleared() async throws {
        let tabsModel = TabsModel(desktop: false)
        let initialTab = tabsModel.get(tabAt: 0)
        let tab1 = Tab(link: Link(title: "example1", url: URL(string: "https://example1.com")!))
        tabsModel.add(tab: tab1)
        let tabIDs = [initialTab.uid, tab1.uid]
        
        let mockHistoryManager = MockHistoryManager()
        mockHistoryManager.removeTabHistoryExpectation = expectation(description: "removeTabHistory called")
        let manager = try makeManager(tabsModel, historyManager: mockHistoryManager)
        
        manager.removeAll()
        
        await fulfillment(of: [mockHistoryManager.removeTabHistoryExpectation!], timeout: 5.0)
        
        XCTAssertEqual(mockHistoryManager.removeTabHistoryCalls.count, 1)
        XCTAssertEqual(Set(mockHistoryManager.removeTabHistoryCalls.first ?? []), Set(tabIDs))
    }
    
    func testWhenViewModelRequested_ThenReturnsViewModelForTab() throws {
        let tabsModel = TabsModel(desktop: false)
        let tab = tabsModel.get(tabAt: 0)
        
        let mockHistoryManager = MockHistoryManager()
        let manager = try makeManager(tabsModel, historyManager: mockHistoryManager)
        
        let viewModel = manager.viewModel(for: tab)
        
        XCTAssertEqual(viewModel.tab.uid, tab.uid)
    }

    func makeManager(_ model: TabsModel,
                     previewsSource: TabPreviewsSource = MockTabPreviewsSource(),
                     historyManager: MockHistoryManager = MockHistoryManager()) throws -> TabManager {
        let tabsPersistence = TabsModelPersistence(store: MockKeyValueFileStore(),
                                                   legacyStore: MockKeyValueStore())
        return TabManager(model: model,
                          persistence: tabsPersistence,
                          previewsSource: previewsSource,
                          interactionStateSource: TabInteractionStateDiskSource(),
                          privacyConfigurationManager: MockPrivacyConfigurationManager(),
                          bookmarksDatabase: MockBookmarksDatabase.make(prepareFolderStructure: false),
                          historyManager: historyManager,
                          syncService: MockDDGSyncing(),
                          userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
                          contentBlockingAssetsPublisher: PassthroughSubject<ContentBlockingUpdating.NewContent, Never>().eraseToAnyPublisher(),
                          subscriptionDataReporter: MockSubscriptionDataReporter(),
                          contextualOnboardingPresenter: ContextualOnboardingPresenterMock(),
                          contextualOnboardingLogic: ContextualOnboardingLogicMock(),
                          onboardingPixelReporter: OnboardingPixelReporterMock(),
                          featureFlagger: MockFeatureFlagger(),
                          contentScopeExperimentManager: MockContentScopeExperimentManager(),
                          appSettings: AppSettingsMock(),
                          textZoomCoordinator: MockTextZoomCoordinator(),
                          websiteDataManager: MockWebsiteDataManager(),
                          fireproofing: MockFireproofing(),
                          maliciousSiteProtectionManager: MockMaliciousSiteProtectionManager(),
                          maliciousSiteProtectionPreferencesManager: MockMaliciousSiteProtectionPreferencesManager(),
                          featureDiscovery: MockFeatureDiscovery(),
                          keyValueStore: MockKeyValueFileStore(),
                          daxDialogsManager: DummyDaxDialogsManager(),
                          aiChatSettings: MockAIChatSettingsProvider(),
                          productSurfaceTelemetry: MockProductSurfaceTelemetry(),
                          privacyStats: MockPrivacyStats(),
                          voiceSearchHelper: MockVoiceSearchHelper())
    }

}
