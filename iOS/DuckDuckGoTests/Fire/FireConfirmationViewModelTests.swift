//
//  FireConfirmationViewModelTests.swift
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
import Common
import History
import AIChat
import Persistence
import PersistenceTestingUtils

// swiftlint:disable force_try

@MainActor
final class FireConfirmationViewModelTests: XCTestCase {
    
    private var mockKeyValueStore: MockKeyValueFileStore!
    
    override func setUp() {
        super.setUp()
        mockKeyValueStore = try! MockKeyValueFileStore()
    }
    
    override func tearDown() {
        mockKeyValueStore = nil
        super.tearDown()
    }
    
    private struct MockTabsModel: TabsModelProtocol {
        let count: Int
    }
    
    private class TestHistoryCoordinator: NullHistoryCoordinator {
        var testHistory: BrowsingHistory?
        
        override var history: BrowsingHistory? {
            get { testHistory }
            set { testHistory = newValue }
        }
    }
    
    private class TestFireproofing: Fireproofing {
        var fireproofedDomains: [String] = []
        var allowedDomains: [String] { fireproofedDomains }
        var loginDetectionEnabled: Bool = false
        
        func addToAllowed(domain: String) {
            fireproofedDomains.append(domain)
        }
        
        func remove(domain: String) {
            fireproofedDomains.removeAll { $0 == domain }
        }
        
        func clearAll() {
            fireproofedDomains.removeAll()
        }
        
        func isAllowed(cookieDomain: String) -> Bool {
            fireproofedDomains.contains(cookieDomain)
        }
        
        func isAllowed(fireproofDomain domain: String) -> Bool {
            fireproofedDomains.contains(domain)
        }
    }
    
    private func makeViewModel(
        tabsModel: TabsModelProtocol = MockTabsModel(count: 0),
        historyManager: HistoryManaging = MockHistoryManager(
            historyCoordinator: NullHistoryCoordinator(),
            isEnabledByUser: false,
            historyFeatureEnabled: false
        ),
        tld: TLD = TLD(),
        fireproofing: Fireproofing = TestFireproofing(),
        aiChatSettings: AIChatSettingsProvider = MockAIChatSettingsProvider(),
        settingsStore: FireConfirmationSettingsStoring? = nil
    ) -> FireConfirmationViewModel {
        return FireConfirmationViewModel(
            tabsModel: tabsModel,
            historyManager: historyManager,
            tld: tld,
            fireproofing: fireproofing,
            aiChatSettings: aiChatSettings,
            keyValueFilesStore: mockKeyValueStore,
            onConfirm: {},
            onCancel: {}
        )
    }
    
    private func makeHistoryEntry(url: URL) -> HistoryEntry {
        return HistoryEntry(
            identifier: UUID(),
            url: url,
            title: nil,
            failedToLoad: false,
            numberOfTotalVisits: 1,
            lastVisit: Date(),
            visits: [],
            numberOfTrackersBlocked: 0,
            blockedTrackingEntities: [],
            trackersFound: false
        )
    }
    
    func testWhenTabsModelIsNilThenClearTabsSubtitleReturnsZeroCount() {
        // Given
        let viewModel = makeViewModel()
        
        // When
        let subtitle = viewModel.clearTabsSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "None")
    }
    
    func testWhenTabsModelHasZeroTabsThenClearTabsSubtitleShowsNone() {
        // Given
        let tabsModel = MockTabsModel(count: 0)
        let viewModel = makeViewModel(tabsModel: tabsModel)
        
        // When
        let subtitle = viewModel.clearTabsSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "None")
    }
    
    func testWhenTabsModelHasOneTabThenClearTabsSubtitleShowsSingular() {
        // Given
        let tabsModel = MockTabsModel(count: 1)
        let viewModel = makeViewModel(tabsModel: tabsModel)
        
        // When
        let subtitle = viewModel.clearTabsSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "Close 1 tab")
    }
    
    func testWhenTabsModelHasMultipleTabsThenClearTabsSubtitleShowsPlural() {
        // Given
        let tabsModel = MockTabsModel(count: 5)
        let viewModel = makeViewModel(tabsModel: tabsModel)
        
        // When
        let subtitle = viewModel.clearTabsSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "Close all 5 tabs")
    }
    
    // MARK: - clearDataSubtitle Tests
    func testWhenHistoryIsDisabledThenClearDataSubtitleReturnsStaticText() {
        // Given
        let historyManager = MockHistoryManager(
            historyCoordinator: TestHistoryCoordinator(),
            isEnabledByUser: false,
            historyFeatureEnabled: false
        )
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: TestFireproofing())
        
        // When
        let subtitle = viewModel.clearDataSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "May sign you out of accounts")
    }
    
    func testWhenHistoryIsEnabledButEmptyThenClearDataSubtitleReturnsZeroCount() {
        // Given
        let historyCoordinator = TestHistoryCoordinator()
        historyCoordinator.testHistory = []
        
        let historyManager = MockHistoryManager(
            historyCoordinator: historyCoordinator,
            isEnabledByUser: true,
            historyFeatureEnabled: true
        )
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: TestFireproofing())
        
        // When
        let subtitle = viewModel.clearDataSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "None")
    }
    
    func testWhenHistoryHasOneSiteThenClearDataSubtitleShowsSingular() {
        // Given
        let historyCoordinator = TestHistoryCoordinator()
        historyCoordinator.testHistory = [
            makeHistoryEntry(url: URL(string: "https://example.com")!)
        ]
        
        let historyManager = MockHistoryManager(
            historyCoordinator: historyCoordinator,
            isEnabledByUser: true,
            historyFeatureEnabled: true
        )
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: TestFireproofing())
        
        // When
        let subtitle = viewModel.clearDataSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "Delete from 1 site. May sign you out of accounts.")
    }
    
    func testWhenHistoryHasMultipleSitesThenClearDataSubtitleShowsPlural() {
        // Given
        let historyCoordinator = TestHistoryCoordinator()
        historyCoordinator.testHistory = [
            makeHistoryEntry(url: URL(string: "https://example.com")!),
            makeHistoryEntry(url: URL(string: "https://duckduckgo.com")!),
            makeHistoryEntry(url: URL(string: "https://test.org")!)
        ]
        
        let historyManager = MockHistoryManager(
            historyCoordinator: historyCoordinator,
            isEnabledByUser: true,
            historyFeatureEnabled: true
        )
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: TestFireproofing())
        
        // When
        let subtitle = viewModel.clearDataSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "Delete from 3 sites. May sign you out of accounts.")
    }
    
    func testWhenHistoryHasDuplicateDomainsThenClearDataSubtitleCountsUniqueDomains() {
        // Given
        let historyCoordinator = TestHistoryCoordinator()
        historyCoordinator.testHistory = [
            makeHistoryEntry(url: URL(string: "https://example.com/page1")!),
            makeHistoryEntry(url: URL(string: "https://example.com/page2")!),
            makeHistoryEntry(url: URL(string: "https://sub.example.com/page3")!)
        ]
        
        let historyManager = MockHistoryManager(
            historyCoordinator: historyCoordinator,
            isEnabledByUser: true,
            historyFeatureEnabled: true
        )
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: TestFireproofing())
        
        // When
        let subtitle = viewModel.clearDataSubtitle()
        
        // Then - example.com and sub.example.com are separate hosts
        XCTAssertEqual(subtitle, "Delete from 2 sites. May sign you out of accounts.")
    }
    
    func testWhenSomeDomainsAreFireproofedThenClearDataSubtitleCountsOnlyNonFireproofed() {
        // Given
        let historyCoordinator = TestHistoryCoordinator()
        historyCoordinator.testHistory = [
            makeHistoryEntry(url: URL(string: "https://example.com")!),
            makeHistoryEntry(url: URL(string: "https://test.org")!),
            makeHistoryEntry(url: URL(string: "https://notfireproofed.com")!)
        ]
        
        let historyManager = MockHistoryManager(
            historyCoordinator: historyCoordinator,
            isEnabledByUser: true,
            historyFeatureEnabled: true
        )
        
        let fireproofing = TestFireproofing()
        fireproofing.fireproofedDomains = ["example.com", "test.org"]
        
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: fireproofing)
        
        // When
        let subtitle = viewModel.clearDataSubtitle()
        
        // Then - Only notfireproofed.com is counted
        XCTAssertEqual(subtitle, "Delete from 1 site. May sign you out of accounts.")
    }
    
    func testWhenSubdomainIsFireproofedThenOtherSubdomainsAreStillCounted() {
        // Given
        let historyCoordinator = TestHistoryCoordinator()
        historyCoordinator.testHistory = [
            makeHistoryEntry(url: URL(string: "https://www.example.com")!),
            makeHistoryEntry(url: URL(string: "https://mail.example.com")!)
        ]
        
        let historyManager = MockHistoryManager(
            historyCoordinator: historyCoordinator,
            isEnabledByUser: true,
            historyFeatureEnabled: true
        )
        
        let fireproofing = TestFireproofing()
        fireproofing.fireproofedDomains = ["www.example.com"]  // Only www is fireproofed
        
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: fireproofing)
        
        // When
        let subtitle = viewModel.clearDataSubtitle()
        
        // Then - Only mail.example.com is counted (www is fireproofed)
        XCTAssertEqual(subtitle, "Delete from 1 site. May sign you out of accounts.")
    }
    
    // MARK: - Persistence Tests
    
    func testWhenNoStoredValuesThenDefaultsAreUsed() {
        // Given - No stored values (clean UserDefaults)
        // Use tabs model with tabs so toggle is enabled
        let tabsModel = MockTabsModel(count: 3)
        
        // When
        let viewModel = makeViewModel(tabsModel: tabsModel)
        
        // Then
        XCTAssertTrue(viewModel.clearTabs, "clearTabs should default to true")
        XCTAssertTrue(viewModel.clearData, "clearData should default to true")
        XCTAssertFalse(viewModel.clearAIChats, "clearAIChats should default to false")
    }
    
    func testWhenConfirmCalledThenToggleValuesArePersisted() {
        // Given - Enable AI Chat so clearAIChats can be persisted and loaded
        // Use tabs model with tabs so toggle is enabled and can be persisted
        let tabsModel = MockTabsModel(count: 3)
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatEnabled: true)
        let viewModel = makeViewModel(tabsModel: tabsModel, aiChatSettings: aiChatSettings)
        viewModel.clearTabs = false
        viewModel.clearData = false
        viewModel.clearAIChats = true
        
        // When
        viewModel.confirm()
        
        // Then - Create new view model with same tabs so toggle remains enabled
        let newViewModel = makeViewModel(tabsModel: tabsModel, aiChatSettings: aiChatSettings)
        XCTAssertFalse(newViewModel.clearTabs, "clearTabs should be persisted as false")
        XCTAssertFalse(newViewModel.clearData, "clearData should be persisted as false")
        XCTAssertTrue(newViewModel.clearAIChats, "clearAIChats should be persisted as true")
    }
    
    func testWhenStoredValuesExistThenTheyAreLoadedOnInit() {
        // Given - Pre-populate storage and enable AI Chat
        try! mockKeyValueStore.set(false, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearTabs")
        try! mockKeyValueStore.set(false, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearData")
        try! mockKeyValueStore.set(true, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearAIChats")
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatEnabled: true)
        
        // When
        let viewModel = makeViewModel(aiChatSettings: aiChatSettings)
        
        // Then
        XCTAssertFalse(viewModel.clearTabs, "clearTabs should load stored value false")
        XCTAssertFalse(viewModel.clearData, "clearData should load stored value false")
        XCTAssertTrue(viewModel.clearAIChats, "clearAIChats should load stored value true when AI Chat is enabled")
    }
    
    func testWhenAIChatIsDisabledThenStoredClearAIChatsIsIgnored() {
        // Given - Pre-populate storage with clearAIChats = true, but AI Chat is disabled
        try! mockKeyValueStore.set(true, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearAIChats")
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatEnabled: false)
        
        // When
        let viewModel = makeViewModel(aiChatSettings: aiChatSettings)
        
        // Then
        XCTAssertFalse(viewModel.clearAIChats, "clearAIChats should be false when AI Chat is disabled, regardless of stored value")
        XCTAssertFalse(viewModel.showAIChatsOption, "showAIChatsOption should be false when AI Chat is disabled")
    }
    
    func testWhenAIChatIsDisabledAndClearAIChatsPersistedThenDeleteButtonRespectsVisibleTogglesOnly() {
        // Given - Pre-populate storage with clearAIChats = true, but AI Chat is disabled
        // Both visible toggles are off
        try! mockKeyValueStore.set(false, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearTabs")
        try! mockKeyValueStore.set(false, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearData")
        try! mockKeyValueStore.set(true, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearAIChats")
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatEnabled: false)
        
        // When
        let viewModel = makeViewModel(aiChatSettings: aiChatSettings)
        
        // Then - Delete button should be disabled since all visible toggles are off
        XCTAssertTrue(viewModel.isDeleteButtonDisabled, "Delete button should be disabled when AI Chat is disabled and visible toggles are off")
    }
    
    func testWhenCancelCalledThenToggleValuesAreNotPersisted() {
        // Given - Use tabs model with tabs so toggle is enabled
        let tabsModel = MockTabsModel(count: 3)
        let viewModel = makeViewModel(tabsModel: tabsModel)
        viewModel.clearTabs = false
        viewModel.clearData = false
        viewModel.clearAIChats = true
        
        // When
        viewModel.cancel()
        
        // Then - Create new view model with same tabs so toggle remains enabled
        let newViewModel = makeViewModel(tabsModel: tabsModel)
        XCTAssertTrue(newViewModel.clearTabs, "clearTabs should remain default true after cancel")
        XCTAssertTrue(newViewModel.clearData, "clearData should remain default true after cancel")
        XCTAssertFalse(newViewModel.clearAIChats, "clearAIChats should remain default false after cancel")
    }
    
    // MARK: - Toggle Disabled State Tests
    
    func testWhenTabsCountIsZeroThenTabsToggleIsDisabled() {
        // Given
        let viewModel = makeViewModel(tabsModel: MockTabsModel(count: 0))
        
        // Then
        XCTAssertTrue(viewModel.isClearTabsDisabled, "Tabs toggle should be disabled when count is 0")
    }
    
    func testWhenTabsCountIsNonZeroThenTabsToggleIsEnabled() {
        // Given
        let viewModel = makeViewModel(tabsModel: MockTabsModel(count: 5))
        
        // Then
        XCTAssertFalse(viewModel.isClearTabsDisabled, "Tabs toggle should be enabled when count is greater than 0")
    }
    
    func testWhenSitesCountIsZeroThenDataToggleIsDisabled() {
        // Given
        let historyCoordinator = TestHistoryCoordinator()
        historyCoordinator.testHistory = []
        
        let historyManager = MockHistoryManager(
            historyCoordinator: historyCoordinator,
            isEnabledByUser: true,
            historyFeatureEnabled: true
        )
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: TestFireproofing())
        
        // Then
        XCTAssertTrue(viewModel.isClearDataDisabled, "Data toggle should be disabled when sites count is 0")
    }
    
    func testWhenSitesCountIsNonZeroThenDataToggleIsEnabled() {
        // Given
        let historyCoordinator = TestHistoryCoordinator()
        historyCoordinator.testHistory = [
            makeHistoryEntry(url: URL(string: "https://example.com")!)
        ]
        
        let historyManager = MockHistoryManager(
            historyCoordinator: historyCoordinator,
            isEnabledByUser: true,
            historyFeatureEnabled: true
        )
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: TestFireproofing())
        
        // Then
        XCTAssertFalse(viewModel.isClearDataDisabled, "Data toggle should be enabled when sites count is greater than 0")
    }
    
    func testWhenHistoryIsDisabledThenDataToggleIsNotDisabled() {
        // Given
        let historyManager = MockHistoryManager(
            historyCoordinator: TestHistoryCoordinator(),
            isEnabledByUser: false,
            historyFeatureEnabled: false
        )
        let viewModel = makeViewModel(historyManager: historyManager, fireproofing: TestFireproofing())
        
        // Then
        XCTAssertFalse(viewModel.isClearDataDisabled, "Data toggle should not be disabled when history is disabled")
    }
    
    // MARK: - Delete Button Disabled Tests
    
    func testWhenAllTogglesAreOffThenDeleteButtonIsDisabled() {
        // Given
        let viewModel = makeViewModel()
        viewModel.clearTabs = false
        viewModel.clearData = false
        viewModel.clearAIChats = false
        
        // Then
        XCTAssertTrue(viewModel.isDeleteButtonDisabled, "Delete button should be disabled when all toggles are off")
    }
    
    func testWhenAtLeastOneToggleIsOnThenDeleteButtonIsEnabled() {
        // Given
        let viewModel = makeViewModel()
        
        // When - Only clearTabs is on
        viewModel.clearTabs = true
        viewModel.clearData = false
        viewModel.clearAIChats = false
        
        // Then
        XCTAssertFalse(viewModel.isDeleteButtonDisabled, "Delete button should be enabled when clearTabs is on")
        
        // When - Only clearData is on
        viewModel.clearTabs = false
        viewModel.clearData = true
        viewModel.clearAIChats = false
        
        // Then
        XCTAssertFalse(viewModel.isDeleteButtonDisabled, "Delete button should be enabled when clearData is on")
        
        // When - Only clearAIChats is on
        viewModel.clearTabs = false
        viewModel.clearData = false
        viewModel.clearAIChats = true
        
        // Then
        XCTAssertFalse(viewModel.isDeleteButtonDisabled, "Delete button should be enabled when clearAIChats is on")
    }
    
    func testWhenAllTogglesAreOnThenDeleteButtonIsEnabled() {
        // Given
        let viewModel = makeViewModel()
        viewModel.clearTabs = true
        viewModel.clearData = true
        viewModel.clearAIChats = true
        
        // Then
        XCTAssertFalse(viewModel.isDeleteButtonDisabled, "Delete button should be enabled when all toggles are on")
    }
    
    // MARK: - Disabled Toggle Behavior Tests

    func testWhenTogglePersistedTrueButDisabledThenDeleteButtonIsDisabled() throws {
        // Given - clearTabs was persisted as true, but now there are no tabs
        // Other toggles are off
        try mockKeyValueStore.set(true, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearTabs")
        try mockKeyValueStore.set(false, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearData")
        try mockKeyValueStore.set(false, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearAIChats")
        
        // When
        let viewModel = makeViewModel(tabsModel: MockTabsModel(count: 0))
        
        // Then
        XCTAssertFalse(viewModel.clearTabs, "clearTabs should be false when tabs toggle is disabled")
        XCTAssertTrue(viewModel.isClearTabsDisabled, "Tabs toggle should be disabled")
        XCTAssertTrue(viewModel.isDeleteButtonDisabled, "Delete button should be disabled when persisted toggle is disabled")
    }

    func testWhenDisabledToggleThenStoredPreferenceIsPreservedAndRestoredWhenEnabled() throws {
        // Given - User previously had clearTabs = true, now tabs are disabled
        try mockKeyValueStore.set(true, forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearTabs")
        
        // When - Open dialog with no tabs (toggle disabled, clearTabs forced to false)
        let viewModel = makeViewModel(tabsModel: MockTabsModel(count: 0))
        XCTAssertFalse(viewModel.clearTabs, "clearTabs should be false when disabled")
        
        viewModel.confirm()
        
        // Then
        let optionalStoredValue = try mockKeyValueStore.object(forKey: "com_duckduckgo_ios_fireConfirmation_toggle_clearTabs") as? Bool
        let storedValue = try XCTUnwrap(optionalStoredValue)
        XCTAssertTrue(storedValue, "Stored preference should be preserved when toggle is disabled")
        
        let newViewModel = makeViewModel(tabsModel: MockTabsModel(count: 5))
        XCTAssertTrue(newViewModel.clearTabs, "Preference should restore when toggle becomes enabled again")
    }
    
    // MARK: - showAIChatsOption Tests
    
    func testWhenAIChatIsEnabledThenShowAIChatsOptionIsTrue() {
        // Given
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatEnabled: true)
        let viewModel = makeViewModel(aiChatSettings: aiChatSettings)
        
        // Then
        XCTAssertTrue(viewModel.showAIChatsOption, "showAIChatsOption should be true when AI Chat is enabled")
    }
    
    func testWhenAIChatIsDisabledThenShowAIChatsOptionIsFalse() {
        // Given
        let aiChatSettings = MockAIChatSettingsProvider(isAIChatEnabled: false)
        let viewModel = makeViewModel(aiChatSettings: aiChatSettings)
        
        // Then
        XCTAssertFalse(viewModel.showAIChatsOption, "showAIChatsOption should be false when AI Chat is disabled")
    }
}

// swiftlint:enable force_try
