//
//  ScopedFireConfirmationViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Persistence
@testable import DuckDuckGo

@MainActor
final class ScopedFireConfirmationViewModelTests: XCTestCase {
    
    private var mockDownloadManager: SpyDownloadManager!
    private var mockKeyValueStore: MockKeyValueStore!
    private var mockHistoryManager: MockHistoryManager!
    private var mockAppSettings: AppSettingsMock!

    override func setUp() {
        super.setUp()
        mockDownloadManager = SpyDownloadManager()
        mockKeyValueStore = MockKeyValueStore()
        mockHistoryManager = MockHistoryManager()
        mockAppSettings = AppSettingsMock()
    }
    
    override func tearDown() {
        mockDownloadManager = nil
        mockKeyValueStore = nil
        mockHistoryManager = nil
        mockAppSettings = nil
        super.tearDown()
    }
    
    // MARK: - burnAllTabs Tests
    
    func testWhenBurnAllTabsCalledThenOnConfirmIsCalledWithCorrectRequest() {
        // Given
        var capturedRequest: FireRequest?
        let sut = makeSUT(tabViewModel: nil, onConfirm: { request in
            capturedRequest = request
        })
        
        // When
        sut.burnAllTabs()
        
        // Then
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.options, .all)
        XCTAssertEqual(capturedRequest?.trigger, .manualFire)
        if case .all = capturedRequest?.scope {
            // Expected scope
        } else {
            XCTFail("Expected scope to be .all")
        }
    }
    
    // MARK: - burnThisTab Tests
    
    func testWhenBurnThisTabCalledWithTabViewModelThenOnConfirmIsCalledWithCorrectRequest() {
        // Given
        var capturedRequest: FireRequest?
        let tabViewModel = createTabViewModel()
        let sut = makeSUT(tabViewModel: tabViewModel, onConfirm: { request in
            capturedRequest = request
        })
        
        // When
        sut.burnThisTab()
        
        // Then
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.options, .all)
        XCTAssertEqual(capturedRequest?.trigger, .manualFire)
        if case .tab(let vm) = capturedRequest?.scope {
            XCTAssertTrue(vm.tab == tabViewModel.tab)
        } else {
            XCTFail("Expected scope to be .tab with the correct view model")
        }
    }
    
    // MARK: - cancel Tests
    
    func testWhenCancelCalledThenOnCancelIsCalled() {
        // Given
        var cancelCalled = false
        let sut = makeSUT(tabViewModel: nil, onCancel: {
            cancelCalled = true
        })
        
        // When
        sut.cancel()
        
        // Then
        XCTAssertTrue(cancelCalled)
    }
    
    // MARK: - canBurnSingleTab Tests
    
    func testWhenTabViewModelIsNilThenCanBurnSingleTabReturnsFalse() {
        // Given
        let sut = makeSUT(tabViewModel: nil)
        
        // Then
        XCTAssertFalse(sut.canBurnSingleTab)
    }
    
    func testWhenTabSupportsTabHistoryThenCanBurnSingleTabReturnsTrue() {
        // Given
        let sut = makeSUT(tabViewModel: createTabViewModel())
        
        // Then
        XCTAssertTrue(sut.canBurnSingleTab)
    }
    
    func testWhenTabDoesNotSupportTabHistoryThenCanBurnSingleTabReturnsFalse() {
        // Given
        let legacyTab = Tab(supportsTabHistory: false)
        let tabViewModel = TabViewModel(tab: legacyTab, historyManager: mockHistoryManager)
        let sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then
        XCTAssertFalse(sut.canBurnSingleTab)
    }
    
    // MARK: - subtitle Tests - Ongoing Downloads
    
    func testWhenOngoingDownloadsExistThenSubtitleIsDownloadsWarning() {
        // Given
        let runningDownload = createRunningDownload()
        mockDownloadManager.downloadList = [runningDownload]
        
        // When
        let sut = makeSUT(tabViewModel: createTabViewModel())
        
        // Then
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationDownloadsWarning)
    }
    
    // MARK: - subtitle Tests - No Tab View Model
    
    func testWhenNoTabViewModelThenSubtitleIsNil() {
        // Given/When
        let sut = makeSUT(tabViewModel: nil)
        
        // Then
        XCTAssertNil(sut.subtitle)
    }
    
    // MARK: - subtitle Tests - Tab Without History Support
    
    func testWhenTabDoesNotSupportTabHistoryThenSubtitleIsNewTabsInfo() {
        // Given
        let legacyTab = Tab(supportsTabHistory: false)
        let tabViewModel = TabViewModel(tab: legacyTab, historyManager: mockHistoryManager)
        
        // When
        let sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationNewTabsInfo)
    }
    
    // MARK: - subtitle Tests - AI Tab
    
    func testAITabSubtitle() {
        // Given
        let aiTab = createAITab()
        let tabViewModel = TabViewModel(tab: aiTab, historyManager: mockHistoryManager)
        
        // When ai clearing enabled
        mockAppSettings.autoClearAIChatHistory = true
        var sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then don't show subtitle
        XCTAssertNil(sut.subtitle)

        // When ai clearing disabled
        mockAppSettings.autoClearAIChatHistory = false
        sut = makeSUT(tabViewModel: tabViewModel)

        // Then show subtitle
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationDeleteThisChatDescription)
    }
    
    // MARK: - subtitle Tests - Web Tab
    
    func testWhenWebTabFirstTimeThenSubtitleIsSignOutWarning() {
        // Given
        let tabViewModel = createTabViewModel()
        
        // When first time
        var sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then show subtitle
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationSignOutWarning)
        
        // When second time
        sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then show subtitle
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationSignOutWarning)
        
        // When more than two times
        sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then don't show subtitle
        XCTAssertNil(sut.subtitle)
    }
    
    // MARK: - subtitle Tests - Dax Dialogs (Onboarding)
    
    func testWhenDaxDialogsIsShowingFireDialogThenSubtitleIsNil() {
        // Given
        let mockDaxDialogsManager = DummyDaxDialogsManager()
        mockDaxDialogsManager.isShowingFireDialog = true
        let tabViewModel = createTabViewModel()
        
        // When
        let sut = makeSUT(tabViewModel: tabViewModel, daxDialogsManager: mockDaxDialogsManager)
        
        // Then - subtitle is nil even though it would normally show sign out warning
        XCTAssertNil(sut.subtitle)
    }
    
    // MARK: - subtitle Tests - Priority
    
    func testWhenOngoingDownloadsExistEvenForAITabThenSubtitleIsDownloadsWarning() {
        // Given
        let runningDownload = createRunningDownload()
        mockDownloadManager.downloadList = [runningDownload]
        let aiTab = createAITab()
        let tabViewModel = TabViewModel(tab: aiTab, historyManager: mockHistoryManager)
        
        // When
        let sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then - downloads warning takes priority over AI description
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationDownloadsWarning)
    }
    
    func testWhenLegacyTabWithOngoingDownloadsThenSubtitleIsDownloadsWarning() {
        // Given
        let runningDownload = createRunningDownload()
        mockDownloadManager.downloadList = [runningDownload]
        let legacyTab = Tab(supportsTabHistory: false)
        let tabViewModel = TabViewModel(tab: legacyTab, historyManager: mockHistoryManager)
        
        // When
        let sut = makeSUT(tabViewModel: tabViewModel)
        
        // Then - downloads warning takes priority
        XCTAssertEqual(sut.subtitle, UserText.scopedFireConfirmationDownloadsWarning)
    }
    
    // MARK: - Helpers
    
    private func makeSUT(tabViewModel: TabViewModel?,
                         source: FireRequest.Source = .browsing,
                         daxDialogsManager: DaxDialogsManaging = DummyDaxDialogsManager(),
                         onConfirm: @escaping (FireRequest) -> Void = { _ in },
                         onCancel: @escaping () -> Void = { }) -> ScopedFireConfirmationViewModel {
        return ScopedFireConfirmationViewModel(tabViewModel: tabViewModel,
                                               source: source,
                                               downloadManager: mockDownloadManager,
                                               keyValueStore: mockKeyValueStore,
                                               appSettings: mockAppSettings,
                                               daxDialogsManager: daxDialogsManager,
                                               onConfirm: onConfirm,
                                               onCancel: onCancel)
    }
    
    private func createTabViewModel() -> TabViewModel {
        let tab = Tab()
        return TabViewModel(tab: tab, historyManager: mockHistoryManager)
    }
    
    private func createAITab() -> Tab {
        let aiChatURL = URL(string: "https://duckduckgo.com/?ia=chat")!
        let link = Link(title: "AI Chat", url: aiChatURL)
        return Tab(link: link)
    }
    
    private func createRunningDownload(temporary: Bool = false) -> Download {
        let mockSession = MockDownloadSession()
        mockSession.isRunning = true
        return Download(url: URL(string: "https://example.com/file.zip")!,
                        filename: "file.zip",
                        mimeType: .unknown,
                        temporary: temporary,
                        downloadSession: mockSession)
    }
}

// MARK: - MockKeyValueStore

private class MockKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]
    
    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }
    
    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
    
    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}
