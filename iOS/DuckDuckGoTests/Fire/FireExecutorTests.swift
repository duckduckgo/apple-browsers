//
//  FireExecutorTests.swift
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
@testable import DuckDuckGo
@testable import Core
import AIChat
import AIChatTestingUtilities
import BrowserServicesKit
import Bookmarks
import Persistence
import PersistenceTestingUtils
import DDGSync
import WKAbstractions
import BrowserServicesKitTestsUtils

@MainActor
final class FireExecutorTests: XCTestCase {
    
    // MARK: - Mocks
    
    class MockFireExecutorDelegate: FireExecutorDelegate {
        private(set) var willStartBurningTabsCalled = false
        private(set) var didFinishBurningTabsCalled = false
        private(set) var willStartBurningDataCalled = false
        private(set) var didFinishBurningDataCalled = false
        private(set) var willStartBurningAIHistoryCalled = false
        private(set) var didFinishBurningAIHistoryCalled = false
        private(set) var willStartBurningCalled = false
        private(set) var willStartBurningFireRequest: FireRequest?
        private(set) var didFinishBurningCalled = false
        private(set) var didFinishBurningFireRequest: FireRequest?
        
        func willStartBurning(fireRequest: FireRequest) {
            willStartBurningCalled = true
            willStartBurningFireRequest = fireRequest
        }
        
        func willStartBurningTabs(fireRequest: FireRequest) {
            willStartBurningTabsCalled = true
        }
        
        func didFinishBurningTabs(fireRequest: FireRequest) {
            didFinishBurningTabsCalled = true
        }
        
        func willStartBurningData(fireRequest: FireRequest) {
            willStartBurningDataCalled = true
        }
        
        func didFinishBurningData(fireRequest: FireRequest) {
            didFinishBurningDataCalled = true
        }
        
        func willStartBurningAIHistory(fireRequest: FireRequest) {
            willStartBurningAIHistoryCalled = true
        }
        
        func didFinishBurningAIHistory(fireRequest: FireRequest) {
            didFinishBurningAIHistoryCalled = true
        }
        
        func didFinishBurning(fireRequest: FireRequest) {
            didFinishBurningCalled = true
            didFinishBurningFireRequest = fireRequest
        }
    }
    
    class MockHistoryCleaner: HistoryCleaning {
        var cleanAIChatHistoryResult: Result<Void, Error> = .success(())
        private(set) var cleanAIChatHistoryCallCount = 0
        
        var deleteAIChatResult: Result<Void, Error> = .success(())
        private(set) var deleteAIChatCalls: [String] = []
        
        func cleanAIChatHistory() async -> Result<Void, Error> {
            cleanAIChatHistoryCallCount += 1
            return cleanAIChatHistoryResult
        }
        
        func deleteAIChat(chatID: String) async -> Result<Void, Error> {
            deleteAIChatCalls.append(chatID)
            return deleteAIChatResult
        }
    }

    class MockBookmarkDatabaseCleaner: BookmarkDatabaseCleaning {
        private(set) var cleanUpDatabaseNowCalled = false

        func cleanUpDatabaseNow() {
            cleanUpDatabaseNowCalled = true
        }
        func scheduleRegularCleaning() {}
        func cancelCleaningSchedule() {}
    }
    
    // MARK: - Setup
    
    private var mockTabManager: MockTabManager!
    private var spyDownloadManager: SpyDownloadManager!
    private var mockWebsiteDataManager: MockWebsiteDataManager!
    private var mockDaxDialogsManager: DummyDaxDialogsManager!
    private var mockSyncService: MockDDGSyncing!
    private var mockFireproofing: MockFireproofing!
    private var mockTextZoomCoordinator: MockTextZoomCoordinator!
    private var mockHistoryManager: MockHistoryManager!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var mockPrivacyConfigurationManager: PrivacyConfigurationManagerMock!
    private var mockHistoryCleaner: MockHistoryCleaner!
    private var mockBookmarkDatabaseCleaner: MockBookmarkDatabaseCleaner!
    private var mockDelegate: MockFireExecutorDelegate!
    private var mockAppSettings: AppSettingsMock!
    private var mockAIChatSyncCleaner: MockAIChatSyncCleaning!
    
    override func setUp() {
        super.setUp()
        mockTabManager = MockTabManager()
        spyDownloadManager = SpyDownloadManager()
        mockWebsiteDataManager = MockWebsiteDataManager()
        mockDaxDialogsManager = DummyDaxDialogsManager()
        mockSyncService = MockDDGSyncing(authState: .inactive, isSyncInProgress: false)
        mockFireproofing = MockFireproofing(domains: [])
        mockTextZoomCoordinator = MockTextZoomCoordinator()
        mockHistoryManager = MockHistoryManager()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPrivacyConfigurationManager = PrivacyConfigurationManagerMock()
        mockHistoryCleaner = MockHistoryCleaner()
        mockBookmarkDatabaseCleaner = MockBookmarkDatabaseCleaner()
        mockDelegate = MockFireExecutorDelegate()
        mockAppSettings = AppSettingsMock()
        mockAppSettings.autoClearAIChatHistory = true
        mockFeatureFlagger.enabledFeatureFlags = [.enhancedDataClearingSettings]
        mockAIChatSyncCleaner = MockAIChatSyncCleaning()
    }
    
    override func tearDown() {
        mockTabManager = nil
        spyDownloadManager = nil
        mockWebsiteDataManager = nil
        mockDaxDialogsManager = nil
        mockSyncService = nil
        mockFireproofing = nil
        mockTextZoomCoordinator = nil
        mockHistoryManager = nil
        mockFeatureFlagger = nil
        mockPrivacyConfigurationManager = nil
        mockHistoryCleaner = nil
        mockBookmarkDatabaseCleaner = nil
        mockDelegate = nil
        mockAppSettings = nil
        mockAIChatSyncCleaner = nil
        super.tearDown()
    }
    
    private func makeFireExecutor(
        syncService: DDGSyncing? = nil,
        bookmarksDatabaseCleaner: (any BookmarkDatabaseCleaning)? = nil,
        fireproofing: Fireproofing? = nil
    ) -> FireExecutor {
        let executor = FireExecutor(
            tabManager: mockTabManager,
            downloadManager: spyDownloadManager,
            websiteDataManager: mockWebsiteDataManager,
            daxDialogsManager: mockDaxDialogsManager,
            syncService: syncService ?? mockSyncService,
            bookmarksDatabaseCleaner: bookmarksDatabaseCleaner ?? mockBookmarkDatabaseCleaner,
            fireproofing: fireproofing ?? mockFireproofing,
            textZoomCoordinator: mockTextZoomCoordinator,
            historyManager: mockHistoryManager,
            featureFlagger: mockFeatureFlagger,
            privacyConfigurationManager: mockPrivacyConfigurationManager,
            dataStore: MockWebsiteDataStore(),
            historyCleanerProvider: { self.mockHistoryCleaner },
            appSettings: mockAppSettings,
            aiChatSyncCleaner: mockAIChatSyncCleaner
        )
        executor.delegate = mockDelegate
        return executor
    }
    
    private func makeFireRequest(
        options: FireRequest.Options,
        trigger: FireRequest.Trigger = .manualFire,
        scope: FireRequest.Scope = .all,
        source: FireRequest.Source = .browsing
    ) -> FireRequest {
        FireRequest(options: options, trigger: trigger, scope: scope, source: source)
    }
    
    private func makeTabViewModel() -> TabViewModel {
        let tab = Tab(uid: "test-tab-uid")
        return TabViewModel(tab: tab, historyManager: mockHistoryManager)
    }
    
    private func makeAITabViewModel(chatID: String) -> TabViewModel {
        let tab = Tab(uid: "test-ai-tab-uid")
        let aiURL = URL(string: "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4&chatID=\(chatID)")!
        tab.link = Link(title: nil, url: aiURL)
        return TabViewModel(tab: tab, historyManager: mockHistoryManager)
    }
    
    private func makeTabViewModelWithContextualChat(contextualChatID: String) -> TabViewModel {
        let tab = Tab(uid: "test-tab-with-contextual-chat")
        tab.contextualChatURL = "https://duckduckgo.com/?ia=chat&duckai=4&chatID=\(contextualChatID)"
        return TabViewModel(tab: tab, historyManager: mockHistoryManager)
    }
    
    // MARK: - prepare Tests
    
    func testPrepareWithTabsOptionCallsPrepareForBurningTabs() {
        // Given
        let executor = makeFireExecutor()
        
        // When
        executor.prepare(for: makeFireRequest(options: .tabs))
        
        // Then
        XCTAssertTrue(mockTabManager.prepareAllTabsExceptCurrentCalled)
    }
    
    func testPrepareWithoutTabsOptionDoesNotCallPrepareForBurningTabs() {
        // Given
        let executor = makeFireExecutor()
        
        // When
        executor.prepare(for: makeFireRequest(options: .data))
        
        // Then
        XCTAssertFalse(mockTabManager.prepareAllTabsExceptCurrentCalled)
    }
    
    func testPrepareWithTabScopeForNonCurrentTabCallsPrepareTab() {
        // Given
        let executor = makeFireExecutor()
        let tabViewModel = makeTabViewModel()
        mockTabManager.isCurrentTabReturnValue = false
        
        // When
        executor.prepare(for: makeFireRequest(options: .tabs, scope: .tab(viewModel: tabViewModel)))
        
        // Then
        XCTAssertTrue(mockTabManager.prepareTabCalled)
        XCTAssertEqual(mockTabManager.prepareTabCalledWith, tabViewModel.tab)
        XCTAssertEqual(mockTabManager.isCurrentTabCalledWith, tabViewModel.tab)
    }
    
    func testPrepareWithTabScopeForCurrentTabDoesNotCallPrepareTab() {
        // Given
        let executor = makeFireExecutor()
        let tabViewModel = makeTabViewModel()
        mockTabManager.isCurrentTabReturnValue = true
        
        // When
        executor.prepare(for: makeFireRequest(options: .tabs, scope: .tab(viewModel: tabViewModel)))
        
        // Then
        XCTAssertFalse(mockTabManager.prepareTabCalled)
        XCTAssertEqual(mockTabManager.isCurrentTabCalledWith, tabViewModel.tab)
    }
    
    // MARK: - burn Tabs Tests
    
    func testBurnTabsCallsDelegateAndClearsTabs() async {
        // Given
        let executor = makeFireExecutor()
        executor.delegate = mockDelegate
        
        // When
        await executor.burn(request: makeFireRequest(options: .tabs), applicationState: .unknown)
        
        // Then
        XCTAssertTrue(mockDelegate.willStartBurningTabsCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningTabsCalled)
        XCTAssertTrue(mockTabManager.prepareCurrentTabCalled)
        XCTAssertTrue(mockTabManager.removeAllCalled)
        // Downloads are only cancelled when both .tabs and .data are present
        XCTAssertEqual(spyDownloadManager.cancelAllDownloadsCallCount, 0)
    }
    
    func testBurnTabsWithTabScopeForCurrentTabCallsPrepareTab() async {
        // Given
        let executor = makeFireExecutor()
        let tabViewModel = makeTabViewModel()
        mockTabManager.isCurrentTabReturnValue = true
        
        // When
        await executor.burn(request: makeFireRequest(options: .tabs, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)
        
        // Then
        XCTAssertTrue(mockTabManager.prepareTabCalled)
        XCTAssertEqual(mockTabManager.prepareTabCalledWith, tabViewModel.tab)
        XCTAssertEqual(mockTabManager.isCurrentTabCalledWith, tabViewModel.tab)
    }
    
    func testBurnTabsWithTabScopeForNonCurrentTabDoesNotCallPrepareTab() async {
        // Given
        let executor = makeFireExecutor()
        let tabViewModel = makeTabViewModel()
        mockTabManager.isCurrentTabReturnValue = false
        
        // When
        let request = makeFireRequest(options: .tabs, scope: .tab(viewModel: tabViewModel))
        executor.prepare(for: request)
        
        // Then
        XCTAssertTrue(mockTabManager.prepareTabCalled)
        
        // When
        mockTabManager.prepareTabCalled = false
        await executor.burn(request: request, applicationState: .unknown)
        
        // Then
        XCTAssertFalse(mockTabManager.prepareTabCalled)
    }
    
    func testBurnTabsWithTabScopeClosesTabAndNavigatesToHomepage() async {
        // Given
        let executor = makeFireExecutor()
        let tabViewModel = makeTabViewModel()
        
        // When
        await executor.burn(request: makeFireRequest(options: .tabs, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)
        
        // Then - Tab is closed and navigates to homepage (reusing existing or creating new)
        XCTAssertTrue(mockTabManager.closeTabAndNavigateToHomepageCalled)
        XCTAssertEqual(mockTabManager.closeTabAndNavigateToHomepageCalledWith, tabViewModel.tab)
        XCTAssertEqual(mockTabManager.closeTabAndNavigateToHomepageClearTabHistory, false)
    }
    
    func testBurnTabsWithTabScopeCleansUpTabHistoryAfterBurnCompletes() async {
        // Given
        let executor = makeFireExecutor()
        let tabViewModel = makeTabViewModel()
        
        // When
        await executor.burn(request: makeFireRequest(options: .tabs, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)
        
        // Then - Tab history should be removed after burn completes
        XCTAssertEqual(mockHistoryManager.removeTabHistoryCalls.count, 1)
        XCTAssertEqual(mockHistoryManager.removeTabHistoryCalls.first, [tabViewModel.tab.uid])
    }
    
    func testWhenBurningDataAndAIChatsWithTabScopeThenTabHistoryIsNotRemoved() async {
        // Given
        let executor = makeFireExecutor()
        let tabViewModel = makeTabViewModel()
        
        // When - Burn data and AI chats (but not tabs) for a specific tab
        await executor.burn(request: makeFireRequest(options: [.data, .aiChats], scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)
        
        // Then - Tab history should NOT be removed because the tab itself was not burned
        XCTAssertEqual(mockHistoryManager.removeTabHistoryCalls.count, 0)
    }
    
    // MARK: - burn Data Tests
    
    func testBurnDataCallsDelegateAndClearsData() async {
        // Given
        let executor = makeFireExecutor()
        executor.delegate = mockDelegate
        
        // When
        await executor.burn(request: makeFireRequest(options: .data, trigger: .autoClearOnLaunch), applicationState: .unknown)
        
        // Then
        XCTAssertTrue(mockDelegate.willStartBurningDataCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningDataCalled)
        // Downloads are only cancelled when both .tabs and .data are present
        XCTAssertEqual(spyDownloadManager.cancelAllDownloadsCallCount, 0)
    }
    
    func testBurnDataSkipsBookmarkCleanerWhenSyncActive() async {
        // Given
        let bookmarkCleaner = MockBookmarkDatabaseCleaner()
        let activeSyncService = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        let executor = makeFireExecutor(
            syncService: activeSyncService,
            bookmarksDatabaseCleaner: bookmarkCleaner
        )
        
        // When
        await executor.burn(request: makeFireRequest(options: .data), applicationState: .unknown)
        
        // Then
        XCTAssertFalse(bookmarkCleaner.cleanUpDatabaseNowCalled)
    }
    
    func testBurnDataCallsBookmarkCleanerWhenSyncInactive() async {
        // Given
        let bookmarkCleaner = MockBookmarkDatabaseCleaner()
        let executor = makeFireExecutor(
            syncService: mockSyncService,
            bookmarksDatabaseCleaner: bookmarkCleaner
        )
        
        // When
        await executor.burn(request: makeFireRequest(options: .data), applicationState: .unknown)
        
        // Then
        XCTAssertTrue(bookmarkCleaner.cleanUpDatabaseNowCalled)
    }
    
    func testBurnDataPerformsAllCleanupActions() async {
        // Given
        let fireproofedDomains = ["example.com", "test.org"]
        let fireproofing = MockFireproofing(domains: fireproofedDomains)
        let executor = makeFireExecutor(fireproofing: fireproofing)

        // When
        await executor.burn(request: makeFireRequest(options: .data), applicationState: .unknown)

        // Then - Verify delegate calls
        XCTAssertTrue(mockDelegate.willStartBurningDataCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningDataCalled)

        // Then - Verify website data is cleared
        XCTAssertEqual(mockWebsiteDataManager.clearCallCount, 1)

        // Then - Verify dax dialogs held URL data is cleared
        XCTAssertEqual(mockDaxDialogsManager.clearHeldURLDataCallCount, 1)

        // Then - Verify text zoom is reset with fireproofed domains excluded
        XCTAssertEqual(mockTextZoomCoordinator.resetTextZoomLevelsCallCount, 1)
        XCTAssertEqual(mockTextZoomCoordinator.resetTextZoomLevelsExcludingDomainsArg, fireproofedDomains)

        // Then - Verify history is removed
        XCTAssertEqual(mockHistoryManager.removeAllHistoryCallCount, 1)
    }
    
    func testBurnDataForTabScopePerformsAllCleanupActions() async {
        // Given
        let executor = makeFireExecutor()
        let tabViewModel = makeTabViewModel()
        
        mockHistoryManager.tabHistoryResult = [URL(string: "https://test.com")!]

        // When
        await executor.burn(request: makeFireRequest(options: .data, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)

        // Then - Verify delegate calls
        XCTAssertTrue(mockDelegate.willStartBurningDataCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningDataCalled)

        // Then - Verify website data is cleared
        XCTAssertEqual(mockWebsiteDataManager.clearWithDomainsCallCount, 1)
        XCTAssertEqual(mockWebsiteDataManager.clearCalledWithDomains, ["test.com"])

        // Then - Verify text zoom reset is called with visited domains and excluding domains
        XCTAssertEqual(mockTextZoomCoordinator.resetTextZoomLevelsForVisitedDomainsCallCount, 1)
        XCTAssertEqual(mockTextZoomCoordinator.resetTextZoomLevelsForVisitedDomains, ["test.com"])
        XCTAssertNotNil(mockTextZoomCoordinator.resetTextZoomLevelsForVisitedExcludingDomains)

        // Then - Verify browsing history is removed for the tab
        XCTAssertEqual(mockHistoryManager.removeBrowsingHistoryCalls.count, 1)
        XCTAssertEqual(mockHistoryManager.removeBrowsingHistoryCalls.first, tabViewModel.tab.uid)
    }

    func testBurnDataForTabScope_PassesVisitedDomainsAndExcludingDomainsToZoomCoordinator() async {
        // Given - amazon.com is fireproofed, user visited mail.amazon.com and facebook.com
        let fireproofing = MockFireproofing(domains: ["amazon.com"])
        let executor = makeFireExecutor(fireproofing: fireproofing)
        let tabViewModel = makeTabViewModel()

        mockHistoryManager.tabHistoryResult = [
            URL(string: "https://mail.amazon.com/inbox")!,
            URL(string: "https://facebook.com/feed")!
        ]

        // When
        await executor.burn(request: makeFireRequest(options: .data, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)

        // Then - Verify coordinator receives visited domains and excluding domains
        // The S3 filtering logic happens inside the coordinator/storage
        XCTAssertEqual(mockTextZoomCoordinator.resetTextZoomLevelsForVisitedDomainsCallCount, 1)
        let visitedDomains = Set(mockTextZoomCoordinator.resetTextZoomLevelsForVisitedDomains ?? [])
        XCTAssertTrue(visitedDomains.contains("mail.amazon.com"))
        XCTAssertTrue(visitedDomains.contains("facebook.com"))
        XCTAssertEqual(mockTextZoomCoordinator.resetTextZoomLevelsForVisitedExcludingDomains, ["amazon.com"])
    }
    
    
    // MARK: - Burn ongoing downloads
    
    func testBurnTabsAndDataCancelsDownloads() async {
        // Given
        let executor = makeFireExecutor()
        executor.delegate = mockDelegate
        
        // When
        await executor.burn(request: makeFireRequest(options: [.tabs, .data]), applicationState: .unknown)
        
        // Then
        XCTAssertEqual(spyDownloadManager.cancelAllDownloadsCallCount, 1)
    }
    
    func testTabScopeDoesntCancelDownloads() async {
        // Given
        let executor = makeFireExecutor()
        executor.delegate = mockDelegate
        let tabViewModel = makeTabViewModel()
        
        // When
        let request = makeFireRequest(options: [.tabs, .data], scope: .tab(viewModel: tabViewModel))
        await executor.burn(request: request, applicationState: .unknown)
        
        // Then
        XCTAssertEqual(spyDownloadManager.cancelAllDownloadsCallCount, 0)
    }
    
    // MARK: - burn AI History Tests
    
    func testBurnAIHistoryCallsDelegateOnSuccess() async {
        // Given
        let executor = makeFireExecutor()
        mockHistoryCleaner.cleanAIChatHistoryResult = .success(())
        
        // When
        await executor.burn(request: makeFireRequest(options: .aiChats), applicationState: .unknown)
        
        // Then
        XCTAssertTrue(mockDelegate.willStartBurningAIHistoryCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningAIHistoryCalled)
        XCTAssertEqual(mockHistoryCleaner.cleanAIChatHistoryCallCount, 1)
    }
    
    func testBurnAIHistoryCallsDelegateOnFailure() async {
        // Given
        let executor = makeFireExecutor()
        mockHistoryCleaner.cleanAIChatHistoryResult = .failure(NSError(domain: "test", code: 1))
        
        // When
        await executor.burn(request: makeFireRequest(options: .aiChats), applicationState: .unknown)
        
        // Then
        XCTAssertTrue(mockDelegate.willStartBurningAIHistoryCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningAIHistoryCalled)
        XCTAssertEqual(mockHistoryCleaner.cleanAIChatHistoryCallCount, 1)
    }
    
    // MARK: - burn All Options Tests
    
    func testBurnAllOptionsBurnsEverything() async {
        // Given
        let executor = makeFireExecutor()
        
        // When
        await executor.burn(request: makeFireRequest(options: .all), applicationState: .unknown)
        
        // Then
        XCTAssertTrue(mockDelegate.willStartBurningCalled)
        XCTAssertTrue(mockDelegate.willStartBurningTabsCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningTabsCalled)
        XCTAssertTrue(mockDelegate.willStartBurningDataCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningDataCalled)
        XCTAssertTrue(mockDelegate.willStartBurningAIHistoryCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningAIHistoryCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningCalled)
        XCTAssertTrue(mockTabManager.prepareCurrentTabCalled)
        XCTAssertTrue(mockTabManager.removeAllCalled)
        XCTAssertEqual(spyDownloadManager.cancelAllDownloadsCallCount, 1)
        XCTAssertEqual(mockHistoryCleaner.cleanAIChatHistoryCallCount, 1)
    }
    
    func testBurnMultipleOptionsIndividually() async {
        // Given
        let executor = makeFireExecutor()
        
        // When - Burn tabs and data separately
        await executor.burn(request: makeFireRequest(options: [.tabs, .data]), applicationState: .unknown)
        
        // Then
        XCTAssertTrue(mockDelegate.willStartBurningTabsCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningTabsCalled)
        XCTAssertTrue(mockDelegate.willStartBurningDataCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningDataCalled)
        XCTAssertFalse(mockDelegate.willStartBurningAIHistoryCalled)
        XCTAssertFalse(mockDelegate.didFinishBurningAIHistoryCalled)
    }
    
    // MARK: - Legacy AI Chats Setting Tests
    
    func testAIChatsNotClearedOnLegacyUIAndDisabledByUser() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [] // enhancedDataClearingSettings disabled
        mockAppSettings.autoClearAIChatHistory = false
        let executor = makeFireExecutor()
        
        // When
        await executor.burn(request: makeFireRequest(options: .aiChats), applicationState: .unknown)
        
        // Then - AI history should NOT be cleared because legacy setting is disabled
        XCTAssertFalse(mockDelegate.willStartBurningAIHistoryCalled)
        XCTAssertFalse(mockDelegate.didFinishBurningAIHistoryCalled)
        XCTAssertEqual(mockHistoryCleaner.cleanAIChatHistoryCallCount, 0)
    }
    
    func testWhenScopeIsTabThenAIChatsAreClearedRegardlessOfUserSetting() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [] // enhancedDataClearingSettings disabled
        mockAppSettings.autoClearAIChatHistory = false // User has disabled auto-clear
        let executor = makeFireExecutor()
        let chatID = "test-chat-id-123"
        let tabViewModel = makeAITabViewModel(chatID: chatID)
        
        // When - Burn AI chats for a specific tab
        await executor.burn(request: makeFireRequest(options: .aiChats, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)
        
        // Then - AI history should be cleared because scope is .tab (single chat burn)
        XCTAssertTrue(mockDelegate.willStartBurningAIHistoryCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningAIHistoryCalled)
        // Verify deleteAIChat was called with the correct chatID (not cleanAIChatHistory)
        XCTAssertEqual(mockHistoryCleaner.deleteAIChatCalls, [chatID])
        XCTAssertEqual(mockHistoryCleaner.cleanAIChatHistoryCallCount, 0)
        // Verify sync cleaner was notified of the chat deletion
        XCTAssertEqual(mockAIChatSyncCleaner.recordChatDeletionCalls, [chatID])
    }
    
    func testWhenScopeIsTabWithoutChatIDThenDeleteAIChatIsNotCalled() async {
        // Given
        let executor = makeFireExecutor()
        let tabViewModel = makeTabViewModel() // Regular tab without chatID
        
        // When - Burn AI chats for a tab without chatID
        await executor.burn(request: makeFireRequest(options: .aiChats, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)
        
        // Then - Delegate callbacks should still happen, but deleteAIChat should not be called
        XCTAssertTrue(mockDelegate.willStartBurningAIHistoryCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningAIHistoryCalled)
        XCTAssertTrue(mockHistoryCleaner.deleteAIChatCalls.isEmpty)
        XCTAssertEqual(mockHistoryCleaner.cleanAIChatHistoryCallCount, 0)
        XCTAssertTrue(mockAIChatSyncCleaner.recordChatDeletionCalls.isEmpty)
    }
    
    // MARK: - Contextual Chat Deletion Tests (Data Burn)
    
    func testWhenBurningDataForTabWithContextualChat_ThenContextualChatIsDeleted() async {
        // Given
        let contextualChatID = "contextual-chat-id-456"
        let tabViewModel = makeTabViewModelWithContextualChat(contextualChatID: contextualChatID)
        mockAppSettings.autoClearAIChatHistory = true
        let executor = makeFireExecutor()
        
        // When - Burn data for a tab with contextual chat
        await executor.burn(request: makeFireRequest(options: .data, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)
        
        // Then - Contextual chat should be deleted
        XCTAssertEqual(mockHistoryCleaner.deleteAIChatCalls, [contextualChatID])
        XCTAssertEqual(mockAIChatSyncCleaner.recordChatDeletionCalls, [contextualChatID])
    }
    
    func testWhenBurningDataForTabWithoutContextualChat_ThenNoContextualChatDeleted() async {
        // Given
        let tabViewModel = makeTabViewModel() // Regular tab without contextual chat
        mockAppSettings.autoClearAIChatHistory = true
        let executor = makeFireExecutor()
        
        // When - Burn data for a tab without contextual chat
        await executor.burn(request: makeFireRequest(options: .data, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)
        
        // Then - No contextual chat should be deleted
        XCTAssertTrue(mockHistoryCleaner.deleteAIChatCalls.isEmpty)
        XCTAssertTrue(mockAIChatSyncCleaner.recordChatDeletionCalls.isEmpty)
    }
    
    func testWhenAutoClearAIChatHistoryDisabled_ThenContextualChatNotDeleted() async {
        // Given
        let contextualChatID = "contextual-chat-id-789"
        let tabViewModel = makeTabViewModelWithContextualChat(contextualChatID: contextualChatID)
        mockAppSettings.autoClearAIChatHistory = false // User has disabled auto-clear
        let executor = makeFireExecutor()
        
        // When - Burn data for a tab with contextual chat but auto-clear disabled
        await executor.burn(request: makeFireRequest(options: .data, scope: .tab(viewModel: tabViewModel)), applicationState: .unknown)
        
        // Then - Contextual chat should NOT be deleted because user setting is disabled
        XCTAssertTrue(mockHistoryCleaner.deleteAIChatCalls.isEmpty)
        XCTAssertTrue(mockAIChatSyncCleaner.recordChatDeletionCalls.isEmpty)
    }
}
