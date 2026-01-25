//
//  TabHistoryCoordinatorTests.swift
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

import Foundation
import XCTest
@testable import History

final class TabHistoryCoordinatorTests: XCTestCase {

    private var tabHistoryStoringMock: TabHistoryStoringMock!
    private var coordinator: TabHistoryCoordinator!

    @MainActor
    override func setUp() {
        super.setUp()
        tabHistoryStoringMock = TabHistoryStoringMock()
        coordinator = TabHistoryCoordinator(tabHistoryStoring: tabHistoryStoringMock)
    }

    override func tearDown() {
        tabHistoryStoringMock = nil
        coordinator = nil
        super.tearDown()
    }

    // MARK: - Tab History Query Tests

    @MainActor
    func testWhenTabHistoryIsCalled_ThenStoreIsQueried() async throws {
        let tabID = "query-tab-123"
        let expectedURLs = [URL(string: "https://example1.com")!, URL(string: "https://example2.com")!]
        tabHistoryStoringMock.setTabHistoryToReturn(expectedURLs)

        let result = try await coordinator.tabHistory(tabID: tabID)

        let queriedTabID = tabHistoryStoringMock.lastQueriedTabID
        let tabHistoryCalled = tabHistoryStoringMock.tabHistoryCalled

        XCTAssertTrue(tabHistoryCalled)
        XCTAssertEqual(queriedTabID, tabID)
        XCTAssertEqual(result, expectedURLs)
    }

    // MARK: - Add Visit Tests

    @MainActor
    func testWhenAddVisitWithTabID_ThenStoreInsertIsCalled() async throws {
        let tabID = "insert-tab-456"
        let url = URL(string: "https://example.com")!

        tabHistoryStoringMock.insertTabHistoryExpectation = expectation(description: "removeTabHistory called")
        coordinator.addVisit(of: url, tabID: tabID)
        await fulfillment(of: [tabHistoryStoringMock.insertTabHistoryExpectation!], timeout: 5.0)

        let insertCalled = tabHistoryStoringMock.insertTabHistoryCalled
        let insertedTabID = tabHistoryStoringMock.lastInsertedTabID
        let insertedURL = tabHistoryStoringMock.lastInsertedURL

        XCTAssertTrue(insertCalled)
        XCTAssertEqual(insertedTabID, tabID)
        XCTAssertEqual(insertedURL, url)
    }

    // MARK: - Remove Visits Tests

    @MainActor
    func testWhenRemoveVisitsIsCalled_ThenStoreBatchDeleteIsCalled() async throws {
        let tabIDs = ["tab-1", "tab-2", "tab-3"]

        try await coordinator.removeVisits(for: tabIDs)

        let removeCalled = tabHistoryStoringMock.removeTabHistoryCalled
        let removedTabIDs = tabHistoryStoringMock.lastRemovedTabIDs

        XCTAssertTrue(removeCalled)
        XCTAssertEqual(removedTabIDs, tabIDs)
    }
}

// MARK: - TabHistoryStoringMock

class TabHistoryStoringMock: TabHistoryStoring {

    var tabHistoryCalled = false
    var insertTabHistoryCalled = false
    var removeTabHistoryCalled = false
    var lastQueriedTabID: String?
    var lastInsertedTabID: String?
    var lastInsertedURL: URL?
    var lastRemovedTabIDs: [String]?
    var tabHistoryToReturn: [URL] = []

    var insertTabHistoryExpectation: XCTestExpectation?

    func setTabHistoryToReturn(_ urls: [URL]) {
        tabHistoryToReturn = urls
    }

    func tabHistory(for tabID: String) async throws -> [URL] {
        tabHistoryCalled = true
        lastQueriedTabID = tabID
        return tabHistoryToReturn
    }

    func insertTabHistory(for tabID: String, url: URL) async throws {
        insertTabHistoryCalled = true
        lastInsertedTabID = tabID
        lastInsertedURL = url
        insertTabHistoryExpectation?.fulfill()
    }

    func removeTabHistory(for tabIDs: [String]) async throws {
        removeTabHistoryCalled = true
        lastRemovedTabIDs = tabIDs
    }
}
