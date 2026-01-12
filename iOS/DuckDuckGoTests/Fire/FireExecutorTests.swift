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
        private(set) var willStartBurningFireContext: FireContext?
        private(set) var didFinishBurningCalled = false
        private(set) var didFinishBurningFireContext: FireContext?
        
        func willStartBurning(fireContext: FireContext) {
            willStartBurningCalled = true
            willStartBurningFireContext = fireContext
        }
        
        func willStartBurningTabs(fireContext: FireContext) {
            willStartBurningTabsCalled = true
        }
        
        func didFinishBurningTabs(fireContext: FireContext) {
            didFinishBurningTabsCalled = true
        }
        
        func willStartBurningData(fireContext: FireContext) {
            willStartBurningDataCalled = true
        }
        
        func didFinishBurningData(fireContext: FireContext) {
            didFinishBurningDataCalled = true
        }
        
        func willStartBurningAIHistory(fireContext: FireContext) {
            willStartBurningAIHistoryCalled = true
        }
        
        func didFinishBurningAIHistory(fireContext: FireContext) {
            didFinishBurningAIHistoryCalled = true
        }
        
        func didFinishBurning(fireContext: FireContext) {
            didFinishBurningCalled = true
            didFinishBurningFireContext = fireContext
        }
    }
    
    class MockHistoryCleaner: HistoryCleaning {
        var cleanAIChatHistoryResult: Result<Void, Error> = .success(())
        private(set) var cleanAIChatHistoryCallCount = 0
        
        func cleanAIChatHistory() async -> Result<Void, Error> {
            cleanAIChatHistoryCallCount += 1
            return cleanAIChatHistoryResult
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
            aiChatHistoryCleaner: mockHistoryCleaner,
            appSettings: mockAppSettings
        )
        executor.delegate = mockDelegate
        return executor
    }
    
    // MARK: - prepare Tests
    
    func testPrepareWithTabsOptionCallsPrepareForBurningTabs() {
        // Given
        let executor = makeFireExecutor()
        
        // When
        executor.prepare(for: .tabs)
        
        // Then
        XCTAssertTrue(mockTabManager.prepareAllTabsExceptCurrentCalled)
    }
    
    func testPrepareWithoutTabsOptionDoesNotCallPrepareForBurningTabs() {
        // Given
        let executor = makeFireExecutor()
        
        // When
        executor.prepare(for: .data)
        
        // Then
        XCTAssertFalse(mockTabManager.prepareAllTabsExceptCurrentCalled)
    }
    
    // MARK: - burn Tabs Tests
    
    func testBurnTabsCallsDelegateAndClearsTabs() async {
        // Given
        let executor = makeFireExecutor()
        executor.delegate = mockDelegate
        
        // When
        await executor.burn(options: .tabs, fireContext: .manualFire)
        
        // Then
        XCTAssertTrue(mockDelegate.willStartBurningTabsCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningTabsCalled)
        XCTAssertTrue(mockTabManager.prepareCurrentTabCalled)
        XCTAssertTrue(mockTabManager.removeAllCalled)
        // Downloads are only cancelled when both .tabs and .data are present
        XCTAssertEqual(spyDownloadManager.cancelAllDownloadsCallCount, 0)
    }
    
    // MARK: - burn Data Tests
    
    func testBurnDataCallsDelegateAndClearsData() async {
        // Given
        let executor = makeFireExecutor()
        executor.delegate = mockDelegate
        
        // When
        await executor.burn(options: .data, fireContext: .autoClearOnLaunch)
        
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
        await executor.burn(options: .data, fireContext: .manualFire)
        
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
        await executor.burn(options: .data, fireContext: .manualFire)
        
        // Then
        XCTAssertTrue(bookmarkCleaner.cleanUpDatabaseNowCalled)
    }
    
    func testBurnDataPerformsAllCleanupActions() async {
        // Given
        let fireproofedDomains = ["example.com", "test.org"]
        let fireproofing = MockFireproofing(domains: fireproofedDomains)
        let executor = makeFireExecutor(fireproofing: fireproofing)

        // When
        await executor.burn(options: .data, fireContext: .manualFire)

        // Then - Verify delegate calls
        XCTAssertTrue(mockDelegate.willStartBurningDataCalled)
        XCTAssertTrue(mockDelegate.didFinishBurningDataCalled)

        // Then - Verify website data is cleared
        XCTAssertEqual(mockWebsiteDataManager.clearCallCount, 1)

        // Then - Verify dax dialogs held URL data is cleared
        XCTAssertEqual(mockDaxDialogsManager.clearHeldURLDataCallCount, 1)

        // Then - Verify text zoom is reset with fireproofed domains excluded
        XCTAssertEqual(mockTextZoomCoordinator.resetTextZoomLevelsCallCount, 1)
        XCTAssertEqual(mockTextZoomCoordinator.resetTextZoomLevelsExcludingDomains, fireproofedDomains)

        // Then - Verify history is removed
        XCTAssertEqual(mockHistoryManager.removeAllHistoryCallCount, 1)
    }
    
    // MARK: - Burn ongoing downloads
    
    func testBurnTabsAndDataCancelsDownloads() async {
        // Given
        let executor = makeFireExecutor()
        executor.delegate = mockDelegate
        
        // When
        await executor.burn(options: [.tabs, .data], fireContext: .manualFire)
        
        // Then
        XCTAssertEqual(spyDownloadManager.cancelAllDownloadsCallCount, 1)
    }
    
    // MARK: - burn AI History Tests
    
    func testBurnAIHistoryCallsDelegateOnSuccess() async {
        // Given
        let executor = makeFireExecutor()
        mockHistoryCleaner.cleanAIChatHistoryResult = .success(())
        
        // When
        await executor.burn(options: .aiChats, fireContext: .manualFire)
        
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
        await executor.burn(options: .aiChats, fireContext: .manualFire)
        
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
        await executor.burn(options: .all, fireContext: .manualFire)
        
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
        await executor.burn(options: [.tabs, .data], fireContext: .manualFire)
        
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
        await executor.burn(options: .aiChats, fireContext: .manualFire)
        
        // Then - AI history should NOT be cleared because legacy setting is disabled
        XCTAssertFalse(mockDelegate.willStartBurningAIHistoryCalled)
        XCTAssertFalse(mockDelegate.didFinishBurningAIHistoryCalled)
        XCTAssertEqual(mockHistoryCleaner.cleanAIChatHistoryCallCount, 0)
    }
}
