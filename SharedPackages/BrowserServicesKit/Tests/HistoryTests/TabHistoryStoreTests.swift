//
//  TabHistoryStoreTests.swift
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
import class Persistence.CoreDataDatabase
@testable import History
import Common
import CoreData

final class TabHistoryStoreTests: XCTestCase {

    private var context: NSManagedObjectContext!
    private var tabHistoryStore: TabHistoryStore!
    private var location: URL!

    override func setUp() {
        super.setUp()
        let model = CoreDataDatabase.loadModel(from: bundle, named: "BrowsingHistory")!
        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = CoreDataDatabase(name: className, containerLocation: location, model: model)
        database.loadStore { _, error in
            if let e = error {
                XCTFail("Could not load store: \(e.localizedDescription)")
            }
        }
        context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        tabHistoryStore = TabHistoryStore(context: context, eventMapper: MockHistoryStoreEventMapper())
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: location)
        context = nil
        tabHistoryStore = nil
        try super.tearDownWithError()
    }

    // MARK: - Insert Tab History Tests

    func testWhenInsertTabHistoryIsCalled_ThenRecordIsCreated() async throws {
        let tabID = "test-tab-123"
        let url = URL(string: "https://example.com")!

        try await tabHistoryStore.insertTabHistory(for: tabID, url: url)

        let fetchedRecords = fetchAllTabHistory()
        XCTAssertEqual(fetchedRecords.count, 1)
        XCTAssertEqual(fetchedRecords.first?.tabID, tabID)
        XCTAssertEqual(fetchedRecords.first?.url, url)
        XCTAssertNil(fetchedRecords.first?.visit, "Orphaned record should have nil visit")
    }

    // MARK: - Fetch Tab History Tests

    func testWhenTabHistoryIsFetched_ThenCorrectURLsAreReturned() async throws {
        let tabID = "test-tab-456"
        let url1 = URL(string: "https://example1.com")!
        let url2 = URL(string: "https://example2.com")!

        try await tabHistoryStore.insertTabHistory(for: tabID, url: url1)
        try await tabHistoryStore.insertTabHistory(for: tabID, url: url2)

        let fetchedURLs = try await tabHistoryStore.tabHistory(for: tabID)

        XCTAssertEqual(fetchedURLs.count, 2)
        XCTAssertTrue(fetchedURLs.contains(url1))
        XCTAssertTrue(fetchedURLs.contains(url2))
    }

    func testWhenTabHistoryIsFetchedForNonExistentTab_ThenEmptyArrayReturned() async throws {
        let nonExistentTabID = "non-existent-tab"

        let fetchedURLs = try await tabHistoryStore.tabHistory(for: nonExistentTabID)

        XCTAssertTrue(fetchedURLs.isEmpty)
    }

    // MARK: - Remove Tab History Tests

    func testWhenRemoveTabHistoryIsCalled_ThenRecordsAreDeleted() async throws {
        let tabID1 = "tab-to-remove-1"
        let tabID2 = "tab-to-remove-2"
        let tabID3 = "tab-to-keep"
        let url = URL(string: "https://example.com")!

        try await tabHistoryStore.insertTabHistory(for: tabID1, url: url)
        try await tabHistoryStore.insertTabHistory(for: tabID2, url: url)
        try await tabHistoryStore.insertTabHistory(for: tabID3, url: url)

        XCTAssertEqual(fetchAllTabHistory().count, 3)

        try await tabHistoryStore.removeTabHistory(for: [tabID1, tabID2])

        let remainingRecords = fetchAllTabHistory()
        XCTAssertEqual(remainingRecords.count, 1)
        XCTAssertEqual(remainingRecords.first?.tabID, tabID3)
    }

    // MARK: - Create Tab History Record with Linked Visit Tests

    func testWhenCreateTabHistoryRecordWithLinkedVisit_ThenRelationshipIsSet() {
        let tabID = "linked-tab-123"
        let url = URL(string: "https://linked-example.com")!

        context.performAndWait {
            // Create a PageVisitManagedObject first
            guard let visitMO = NSEntityDescription.insertNewObject(
                forEntityName: PageVisitManagedObject.entityName,
                into: context
            ) as? PageVisitManagedObject else {
                XCTFail("Failed to create PageVisitManagedObject")
                return
            }
            visitMO.date = Date()

            // Create TabHistory with linked visit
            let tabHistoryMO = tabHistoryStore.createTabHistoryRecord(
                tabID: tabID,
                url: url,
                linkedVisit: visitMO,
                in: context
            )

            XCTAssertNotNil(tabHistoryMO)
            XCTAssertEqual(tabHistoryMO?.tabID, tabID)
            XCTAssertEqual(tabHistoryMO?.url, url)
            XCTAssertNotNil(tabHistoryMO?.visit, "Visit relationship should be set")
            XCTAssertEqual(tabHistoryMO?.visit, visitMO)
        }
    }

    // MARK: - Helpers

    private func fetchAllTabHistory() -> [TabHistoryManagedObject] {
        var results: [TabHistoryManagedObject] = []
        context.performAndWait {
            let request = TabHistoryManagedObject.fetchRequest()
            results = (try? context.fetch(request)) ?? []
        }
        return results
    }
}
