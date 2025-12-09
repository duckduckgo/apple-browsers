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

final class FireConfirmationViewModelTests: XCTestCase {
    
    private let testGroupName = "FireConfirmationViewModelTests"
    private var customSuite: UserDefaults!
    
    override func setUp() {
        super.setUp()
        customSuite = UserDefaults(suiteName: testGroupName)
        customSuite.removePersistentDomain(forName: testGroupName)
        UserDefaults.app = customSuite
    }
    
    override func tearDown() {
        UserDefaults.app = .standard
        customSuite = nil
        super.tearDown()
    }
    
    private struct MockTabsModel: TabsModeling {
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
    
    private func makeViewModel(tabsModel: TabsModeling?) -> FireConfirmationViewModel {
        return FireConfirmationViewModel(
            tabsModel: tabsModel,
            historyManager: nil,
            fireproofing: nil,
            onConfirm: {},
            onCancel: {}
        )
    }
    
    private func makeViewModel(
        tabsModel: TabsModeling? = nil,
        historyManager: HistoryManaging?,
        tld: TLD = TLD(),
        fireproofing: Fireproofing?
    ) -> FireConfirmationViewModel {
        return FireConfirmationViewModel(
            tabsModel: tabsModel,
            historyManager: historyManager,
            tld: tld,
            fireproofing: fireproofing,
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
        let viewModel = makeViewModel(tabsModel: nil)
        
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
    
    @MainActor
    func testWhenHistoryManagerIsNilThenClearDataSubtitleReturnsZeroCount() {
        // Given
        let viewModel = makeViewModel(historyManager: nil, fireproofing: nil)
        
        // When
        let subtitle = viewModel.clearDataSubtitle()
        
        // Then
        XCTAssertEqual(subtitle, "None")
    }
    
    @MainActor
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
    
    @MainActor
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
    
    @MainActor
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
    
    @MainActor
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
    
    @MainActor
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
        
        // Then - All URLs resolve to example.com (eTLD+1)
        XCTAssertEqual(subtitle, "Delete from 1 site. May sign you out of accounts.")
    }
    
    @MainActor
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
    
    // MARK: - Persistence Tests
    
    func testWhenNoStoredValuesThenDefaultsAreUsed() {
        // Given - No stored values (clean UserDefaults)
        
        // When
        let viewModel = makeViewModel(tabsModel: nil)
        
        // Then
        XCTAssertTrue(viewModel.clearTabs, "clearTabs should default to true")
        XCTAssertTrue(viewModel.clearData, "clearData should default to true")
        XCTAssertFalse(viewModel.clearAIChats, "clearAIChats should default to false")
    }
    
    func testWhenConfirmCalledThenToggleValuesArePersisted() {
        // Given
        let viewModel = makeViewModel(tabsModel: nil)
        viewModel.clearTabs = false
        viewModel.clearData = false
        viewModel.clearAIChats = true
        
        // When
        viewModel.confirm()
        
        // Then
        let newViewModel = makeViewModel(tabsModel: nil)
        XCTAssertFalse(newViewModel.clearTabs, "clearTabs should be persisted as false")
        XCTAssertFalse(newViewModel.clearData, "clearData should be persisted as false")
        XCTAssertTrue(newViewModel.clearAIChats, "clearAIChats should be persisted as true")
    }
    
    func testWhenStoredValuesExistThenTheyAreLoadedOnInit() {
        // Given - Pre-populate storage
        customSuite.set(false, forKey: "com.duckduckgo.ios.fireConfirmation.toggle.clearTabs")
        customSuite.set(false, forKey: "com.duckduckgo.ios.fireConfirmation.toggle.clearData")
        customSuite.set(true, forKey: "com.duckduckgo.ios.fireConfirmation.toggle.clearAIChats")
        
        // When
        let viewModel = makeViewModel(tabsModel: nil)
        
        // Then
        XCTAssertFalse(viewModel.clearTabs, "clearTabs should load stored value true")
        XCTAssertFalse(viewModel.clearData, "clearData should load stored value false")
        XCTAssertTrue(viewModel.clearAIChats, "clearAIChats should load stored value true")
    }
    
    func testWhenCancelCalledThenToggleValuesAreNotPersisted() {
        // Given
        let viewModel = makeViewModel(tabsModel: nil)
        viewModel.clearTabs = false
        viewModel.clearData = false
        viewModel.clearAIChats = true
        
        // When
        viewModel.cancel()
        
        // Then
        let newViewModel = makeViewModel(tabsModel: nil)
        XCTAssertTrue(newViewModel.clearTabs, "clearTabs should remain default true after cancel")
        XCTAssertTrue(newViewModel.clearData, "clearData should remain default true after cancel")
        XCTAssertFalse(newViewModel.clearAIChats, "clearAIChats should remain default false after cancel")
    }
    
    // MARK: - Delete Button Disabled Tests
    
    func testWhenAllTogglesAreOffThenDeleteButtonIsDisabled() {
        // Given
        let viewModel = makeViewModel(tabsModel: nil)
        viewModel.clearTabs = false
        viewModel.clearData = false
        viewModel.clearAIChats = false
        
        // Then
        XCTAssertTrue(viewModel.isDeleteButtonDisabled, "Delete button should be disabled when all toggles are off")
    }
    
    func testWhenAtLeastOneToggleIsOnThenDeleteButtonIsEnabled() {
        // Given
        let viewModel = makeViewModel(tabsModel: nil)
        
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
        let viewModel = makeViewModel(tabsModel: nil)
        viewModel.clearTabs = true
        viewModel.clearData = true
        viewModel.clearAIChats = true
        
        // Then
        XCTAssertFalse(viewModel.isDeleteButtonDisabled, "Delete button should be enabled when all toggles are on")
    }
}
