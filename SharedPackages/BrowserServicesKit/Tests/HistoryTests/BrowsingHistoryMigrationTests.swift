//
//  BrowsingHistoryMigrationTests.swift
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

import BookmarksTestsUtils
import XCTest
import Persistence
import CoreData
@testable import History
import Foundation

class BrowsingHistoryMigrationTests: XCTestCase {

    var location: URL!
    var resourceURLDir: URL!

    override func setUp() {
        super.setUp()

        ModelAccessHelper.compileModel(from: Bundle(for: BrowsingHistoryMigrationTests.self), named: "BrowsingHistory")

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        guard let location = Bundle(for: BrowsingHistoryMigrationTests.self).resourceURL else {
            XCTFail("Failed to find bundle URL")
            return
        }

        let resourcesLocation = location.appendingPathComponent("BrowserServicesKit_HistoryTests.bundle/Contents/Resources/")
        if FileManager.default.fileExists(atPath: resourcesLocation.path) == false {
            resourceURLDir = Bundle.module.resourceURL
        } else {
            resourceURLDir = resourcesLocation
        }
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: location)
    }

    func copyDatabase(name: String, fromDirectory: URL, toDirectory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: toDirectory, withIntermediateDirectories: false)
        for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {
            let sourceFile = fromDirectory.appendingPathComponent("\(name).\(ext)")
            let destFile = toDirectory.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: sourceFile.path) {
                try fileManager.copyItem(at: sourceFile, to: destFile)
            }
        }
    }

    func loadDatabase(name: String) -> CoreDataDatabase? {
        let bundle = History.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BrowsingHistory") else {
            return nil
        }
        let historyDatabase = CoreDataDatabase(name: name, containerLocation: location, model: model)
        historyDatabase.loadStore()
        return historyDatabase
    }

    func testWhenMigratingFromV1ThenDataIsPreservedAndNewAttributeHasDefaultValue() throws {
        try commonMigrationTestForDatabase(name: "BrowsingHistory_V1")
    }

    // swiftlint:disable large_tuple
    func commonMigrationTestForDatabase(name: String) throws {
        // Copy V1 database to temp location
        try copyDatabase(name: name, fromDirectory: resourceURLDir, toDirectory: location)

        // Load database with latest model (V2) - this triggers Core Data migration
        guard let migratedDatabase = loadDatabase(name: name) else {
            XCTFail("Could not initialize migrated database")
            return
        }

        let context = migratedDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            // Verify migration succeeded
            let fetchRequest = NSFetchRequest<BrowsingHistoryEntryManagedObject>(
                entityName: "BrowsingHistoryEntryManagedObject"
            )
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "lastVisit", ascending: true)]

            guard let entries = try? context.fetch(fetchRequest) else {
                XCTFail("Failed to fetch history entries after migration")
                return
            }

            // Verify expected number of entries
            XCTAssertEqual(entries.count, 5, "Expected 5 history entries after migration")

            // Expected data from HistoryTestDBBuilder
            // Note: visitCount represents actual visit objects count (visits.count)
            // Entry 5 has numberOfTotalVisits=1 but visits=[] (handled separately)
            let expectedEntries: [(uuid: UUID, url: String, title: String?, lastVisit: TimeInterval, visitCount: Int, trackersFound: Bool, trackersBlocked: Int64, blockedEntities: String?, failedToLoad: Bool)] = [
                (UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, "https://example.com", "Example Domain", 1000, 1, false, 0, nil, false),
                (UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, "https://duckduckgo.com", "DuckDuckGo", 2200, 3, false, 0, nil, false),
                (UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, "https://tracking-site.com", "Tracking Site", 3100, 2, true, 3, "tracker1.com|tracker2.com|tracker3.com", false),
                (UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, "https://notitle.com/page", nil, 4000, 1, false, 0, nil, false),
                (UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, "https://failed-load.com", nil, 5000, 0, false, 0, nil, true)
            ]

            // Verify each entry matches expected data
            for (index, expected) in expectedEntries.enumerated() {
                guard index < entries.count else {
                    XCTFail("Missing entry at index \(index)")
                    continue
                }

                let entry = entries[index]

                // Verify identifier
                XCTAssertEqual(entry.identifier, expected.uuid,
                               "Entry \(index): Identifier mismatch")

                // Verify URL
                XCTAssertEqual(entry.url?.absoluteString, expected.url,
                               "Entry \(index): URL mismatch")

                // Verify title (can be nil)
                XCTAssertEqual(entry.title, expected.title,
                               "Entry \(index): Title mismatch")

                // Verify lastVisit (with small tolerance for date comparison)
                if let lastVisit = entry.lastVisit {
                    let timeInterval = lastVisit.timeIntervalSince1970
                    XCTAssertEqual(timeInterval, expected.lastVisit, accuracy: 1.0,
                                   "Entry \(index): Last visit date mismatch")
                } else {
                    XCTFail("Entry \(index): Last visit is nil")
                }

                // Verify numberOfTotalVisits
                // Note: Entry 5 has numberOfTotalVisits=1 but visits=[] (handled separately)
                let expectedNumberOfTotalVisits: Int64
                switch expected.uuid.uuidString {
                case "55555555-5555-5555-5555-555555555555":
                    expectedNumberOfTotalVisits = 1
                default:
                    expectedNumberOfTotalVisits = Int64(expected.visitCount)
                }
                XCTAssertEqual(entry.numberOfTotalVisits, expectedNumberOfTotalVisits,
                               "Entry \(index): Number of total visits mismatch")

                // Verify tracker-related attributes
                XCTAssertEqual(entry.trackersFound, expected.trackersFound,
                               "Entry \(index): trackersFound mismatch")
                XCTAssertEqual(entry.numberOfTrackersBlocked, expected.trackersBlocked,
                               "Entry \(index): numberOfTrackersBlocked mismatch")
                XCTAssertEqual(entry.blockedTrackingEntities, expected.blockedEntities,
                               "Entry \(index): blockedTrackingEntities mismatch")

                // Verify failedToLoad
                XCTAssertEqual(entry.failedToLoad, expected.failedToLoad,
                               "Entry \(index): failedToLoad mismatch")

                // Verify new attribute exists and has default value
                XCTAssertFalse(entry.cookiePopupBlocked,
                               "Entry \(index): cookiePopupBlocked should default to false for migrated entries")

                // Verify visits relationship for entries that should have visits
                let entryVisits = (entry.visits as? Set<PageVisitManagedObject>) ?? []
                XCTAssertEqual(entryVisits.count, expected.visitCount,
                               "Entry \(index): Visit count mismatch")

                // Verify visit dates for entries with visits
                if expected.visitCount > 0 {
                    let sortedVisits = entryVisits.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
                    let expectedVisitDates: [TimeInterval]
                    switch expected.uuid.uuidString {
                    case "11111111-1111-1111-1111-111111111111":
                        expectedVisitDates = [1000]
                    case "22222222-2222-2222-2222-222222222222":
                        expectedVisitDates = [2000, 2100, 2200]
                    case "33333333-3333-3333-3333-333333333333":
                        expectedVisitDates = [3000, 3100]
                    case "44444444-4444-4444-4444-444444444444":
                        expectedVisitDates = [4000]
                    default:
                        expectedVisitDates = []
                    }

                    XCTAssertEqual(sortedVisits.count, expectedVisitDates.count,
                                   "Entry \(index): Visit count mismatch")
                    for (visitIndex, visit) in sortedVisits.enumerated() {
                        if let visitDate = visit.date {
                            let visitTimeInterval = visitDate.timeIntervalSince1970
                            XCTAssertEqual(visitTimeInterval, expectedVisitDates[visitIndex], accuracy: 1.0,
                                           "Entry \(index), Visit \(visitIndex): Date mismatch")
                        } else {
                            XCTFail("Entry \(index), Visit \(visitIndex): Date is nil")
                        }
                        XCTAssertEqual(visit.historyEntry?.identifier, expected.uuid,
                                       "Entry \(index), Visit \(visitIndex): Relationship mismatch")
                    }
                }
            }

            // Verify all visits are properly linked
            let visitsFetchRequest = NSFetchRequest<PageVisitManagedObject>(
                entityName: "PageVisitManagedObject"
            )
            if let allVisits = try? context.fetch(visitsFetchRequest) {
                XCTAssertEqual(allVisits.count, 7, "Expected 7 total visits (1 + 3 + 2 + 1)")
                for visit in allVisits {
                    XCTAssertNotNil(visit.historyEntry, "All visits should have a history entry")
                    XCTAssertNotNil(visit.date, "All visits should have a date")
                }
            }
        }

        try? migratedDatabase.tearDown(deleteStores: true)
    }
    // swiftlint:enable large_tuple
}
