//
//  HistoryManagerTests.swift
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

import Foundation
import XCTest
import BrowserServicesKit
import Persistence
import History
@testable import Core
import Common

final class HistoryManagerTests: XCTestCase {

    @MainActor
    func testWhenURLIsDeletedThenSiteIsRemovedFromHistory() async throws {

        let model = CoreDataDatabase.loadModel(from: History.bundle, named: "BrowsingHistory")!
        let db = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: model)
        let loadStoreExpectation = expectation(description: "loadStore")
        db.loadStore { _, _ in
            loadStoreExpectation.fulfill()
        }
        await fulfillment(of: [loadStoreExpectation], timeout: 5.0)

        let historyManager = makeHistoryManager(db)
        let loadHistoryExpectation = expectation(description: "loadHistory")
        historyManager.dbCoordinator.loadHistory {
            loadHistoryExpectation.fulfill()
        }

        await fulfillment(of: [loadHistoryExpectation], timeout: 5.0)

        let ddgURL = URL(string: "https://duckduckgo.com/")!
        let netflixURL = URL(string: "https://netflix.com/")!
        let exampleURL = URL(string: "https://example.com/")!

        let urls = [ exampleURL.appending("/1"),
                     exampleURL.appending("/1"),
                     exampleURL.appending("/1"),
                     netflixURL,
                     ddgURL]
        for url in urls {
            historyManager.addVisit(of: url, tabID: "1")
            historyManager.updateTitleIfNeeded(title: url.absoluteString, url: url)
            historyManager.commitChanges(url: url)
        }

        await historyManager.deleteHistoryForURL(exampleURL.appending("/1"))

        XCTAssertEqual(2, historyManager.history?.count)
        XCTAssertTrue(historyManager.history?.contains(where: { $0.url == ddgURL }) ?? false)
        XCTAssertTrue(historyManager.history?.contains(where: { $0.url == netflixURL }) ?? false)
    }

    @MainActor
    func testWhenEnabledInPrivacyConfig_ThenFeatureIsEnabled() {
        let historyManager = makeHistoryManagerWithHistory()

        XCTAssertNotNil(historyManager.history)
    }

    @MainActor
    func test_WhenUserHasDisabledAutocompleteSitesSetting_ThenDontStoreOrLoadHistory() {
        autocompleteEnabledByUser = false

        let historyManager = makeHistoryManagerWithHistory()

        XCTAssertNil(historyManager.history)
    }

    @MainActor
    func test_WhenUserHasDisabledRecentlyVisitedSitesSetting_ThenDontStoreOrLoadHistory() {
        recentlyVisitedSitesEnabledByUser = false

        let historyManager = makeHistoryManagerWithHistory()

        XCTAssertNil(historyManager.history)
    }

    // MARK: - Delegation Tests
    
    @MainActor
    func testWhenHistoryEnabled_ThenAddVisitUsesHistoryCoordinator() async throws {
        let spyHistoryCoordinator = SpyHistoryCoordinator()
        let mockTabHistoryCoordinator = MockTabHistoryCoordinating()
        let historyManager = HistoryManager(dbCoordinator: spyHistoryCoordinator,
                                            tld: TLD(),
                                            tabHistoryCoordinator: mockTabHistoryCoordinator,
                                            isAutocompleteEnabledByUser: true,
                                            isRecentlyVisitedSitesEnabledByUser: true)
        
        let testURL = URL(string: "https://example.com")!
        historyManager.addVisit(of: testURL, tabID: "tab-1")
        
        XCTAssertEqual(spyHistoryCoordinator.addVisitCalls.count, 1)
        XCTAssertEqual(spyHistoryCoordinator.addVisitCalls.first?.url, testURL)
        XCTAssertEqual(spyHistoryCoordinator.addVisitCalls.first?.tabID, "tab-1")
        XCTAssertTrue(mockTabHistoryCoordinator.addVisitCalls.isEmpty)
    }
    
    @MainActor
    func testWhenHistoryDisabled_ThenAddVisitUsesTabHistoryCoordinator() async throws {
        let spyHistoryCoordinator = SpyHistoryCoordinator()
        let mockTabHistoryCoordinator = MockTabHistoryCoordinating()
        let historyManager = HistoryManager(dbCoordinator: spyHistoryCoordinator,
                                            tld: TLD(),
                                            tabHistoryCoordinator: mockTabHistoryCoordinator,
                                            isAutocompleteEnabledByUser: false,
                                            isRecentlyVisitedSitesEnabledByUser: true)
        
        let testURL = URL(string: "https://example.com")!
        historyManager.addVisit(of: testURL, tabID: "tab-1")
        
        XCTAssertTrue(spyHistoryCoordinator.addVisitCalls.isEmpty)
        XCTAssertEqual(mockTabHistoryCoordinator.addVisitCalls.count, 1)
        XCTAssertEqual(mockTabHistoryCoordinator.addVisitCalls.first?.url, testURL)
        XCTAssertEqual(mockTabHistoryCoordinator.addVisitCalls.first?.tabID, "tab-1")
    }
    
    @MainActor
    func testWhenTabHistoryCalled_ThenDelegatesToTabHistoryCoordinator() async throws {
        let mockTabHistoryCoordinator = MockTabHistoryCoordinating()
        let expectedURLs = [URL(string: "https://example.com")!, URL(string: "https://duckduckgo.com")!]
        mockTabHistoryCoordinator.tabHistoryResult = expectedURLs
        
        let historyManager = HistoryManager(dbCoordinator: NullHistoryCoordinator(),
                                            tld: TLD(),
                                            tabHistoryCoordinator: mockTabHistoryCoordinator,
                                            isAutocompleteEnabledByUser: true,
                                            isRecentlyVisitedSitesEnabledByUser: true)
        
        let result = try await historyManager.tabHistory(tabID: "test-tab")
        
        XCTAssertEqual(mockTabHistoryCoordinator.tabHistoryCalls, ["test-tab"])
        XCTAssertEqual(result, expectedURLs)
    }
    
    @MainActor
    func testWhenRemoveTabHistoryCalled_ThenDelegatesToTabHistoryCoordinator() async {
        let mockTabHistoryCoordinator = MockTabHistoryCoordinating()
        let historyManager = HistoryManager(dbCoordinator: NullHistoryCoordinator(),
                                            tld: TLD(),
                                            tabHistoryCoordinator: mockTabHistoryCoordinator,
                                            isAutocompleteEnabledByUser: true,
                                            isRecentlyVisitedSitesEnabledByUser: true)
        
        await historyManager.removeTabHistory(for: ["tab-1", "tab-2"])
        
        XCTAssertEqual(mockTabHistoryCoordinator.removeVisitsCalls.count, 1)
        XCTAssertEqual(mockTabHistoryCoordinator.removeVisitsCalls.first, ["tab-1", "tab-2"])
    }

    private func makeHistoryManager(_ db: CoreDataDatabase) -> HistoryManager {
        let eventMapper = HistoryStoreEventMapper()
        let context = db.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let store = HistoryStore(context: context, eventMapper: eventMapper)
        let tabHistoryStore = TabHistoryStore(context: context, eventMapper: eventMapper)
        let dbCoordinator = HistoryCoordinator(historyStoring: store)
        let tabHistoryCoordinator = TabHistoryCoordinator(tabHistoryStoring: tabHistoryStore)

        return HistoryManager(dbCoordinator: dbCoordinator,
                              tld: TLD(),
                              tabHistoryCoordinator: tabHistoryCoordinator,
                              isAutocompleteEnabledByUser: self.autocompleteEnabledByUser,
                              isRecentlyVisitedSitesEnabledByUser: self.recentlyVisitedSitesEnabledByUser)
    }
    
    @MainActor
    private func makeHistoryManagerWithHistory() -> HistoryManager {
        let historyCoordinator = NullHistoryCoordinator()
        historyCoordinator.history = [
            makeHistoryEntry(url: URL(string: "https://example.com")!)
        ]
        return HistoryManager(dbCoordinator: historyCoordinator,
                              tld: TLD(),
                              tabHistoryCoordinator: MockTabHistoryCoordinating(),
                              isAutocompleteEnabledByUser: self.autocompleteEnabledByUser,
                              isRecentlyVisitedSitesEnabledByUser: self.recentlyVisitedSitesEnabledByUser)
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

    var autocompleteEnabledByUser = true
    var recentlyVisitedSitesEnabledByUser = true

}
