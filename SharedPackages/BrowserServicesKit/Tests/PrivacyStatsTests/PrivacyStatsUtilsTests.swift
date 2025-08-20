//
//  PrivacyStatsUtilsTests.swift
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

import Persistence
import XCTest
@testable import PrivacyStats

final class PrivacyStatsUtilsTests: XCTestCase {
    var databaseProvider: TestPrivacyStatsDatabaseProvider!
    var database: CoreDataDatabase!

    override func setUp() async throws {
        databaseProvider = TestPrivacyStatsDatabaseProvider(databaseName: type(of: self).description())
        databaseProvider.initializeDatabase()
        database = databaseProvider.database
    }

    override func tearDown() async throws {
        databaseProvider.tearDownDatabase()
    }

    // MARK: - fetchOrInsertCurrentStats

    func testWhenThereAreNoObjectsForCompaniesThenFetchOrInsertCurrentStatsInsertsNewObjects() {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            let currentPackTimestamp = Date.currentPrivacyStatsPackTimestamp
            let companyNames: Set<String> = ["A", "B", "C", "D"]

            var returnedEntities: [DailyBlockedTrackersEntity] = []
            do {
                returnedEntities = try PrivacyStatsUtils.fetchOrInsertCurrentStats(for: companyNames, in: context)
            } catch {
                XCTFail("Should not throw")
            }

            let insertedEntities = context.insertedObjects.compactMap { $0 as? DailyBlockedTrackersEntity }

            XCTAssertEqual(returnedEntities.count, 4)
            XCTAssertEqual(insertedEntities.count, 4)
            XCTAssertEqual(Set(insertedEntities.map(\.companyName)), companyNames)
            XCTAssertEqual(Set(insertedEntities.map(\.companyName)), Set(returnedEntities.map(\.companyName)))

            // All inserted entries have the same timestamp
            XCTAssertEqual(Set(insertedEntities.map(\.timestamp)), [currentPackTimestamp])

            // All inserted entries have the count of 0
            XCTAssertEqual(Set(insertedEntities.map(\.count)), [0])
        }
    }

    func testWhenThereAreExistingObjectsForCompaniesThenFetchOrInsertCurrentStatsReturnsThem() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 123, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "B", count: 4567, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            let companyNames: Set<String> = ["A", "B", "C", "D"]

            var returnedEntities: [DailyBlockedTrackersEntity] = []
            do {
                returnedEntities = try PrivacyStatsUtils.fetchOrInsertCurrentStats(for: companyNames, in: context)
            } catch {
                XCTFail("Should not throw")
            }

            let insertedEntities = context.insertedObjects.compactMap { $0 as? DailyBlockedTrackersEntity }

            XCTAssertEqual(returnedEntities.count, 4)
            XCTAssertEqual(insertedEntities.count, 2)
            XCTAssertEqual(Set(returnedEntities.map(\.companyName)), companyNames)
            XCTAssertEqual(Set(insertedEntities.map(\.companyName)), ["C", "D"])

            do {
                let companyA = try XCTUnwrap(returnedEntities.first { $0.companyName == "A" })
                let companyB = try XCTUnwrap(returnedEntities.first { $0.companyName == "B" })

                XCTAssertEqual(companyA.count, 123)
                XCTAssertEqual(companyB.count, 4567)
            } catch {
                XCTFail("Should find companies A and B")
            }
        }
    }

    // MARK: - loadCurrentDayStats

    func testWhenThereAreNoObjectsInDatabaseThenLoadCurrentDayStatsIsEmpty() throws {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let currentDayStats = try PrivacyStatsUtils.loadCurrentDayStats(in: context)
                XCTAssertTrue(currentDayStats.isEmpty)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testWhenThereAreObjectsInDatabaseForPreviousDaysThenLoadCurrentDayStatsIsEmpty() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(1), companyName: "A", count: 123, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(2), companyName: "B", count: 4567, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(5), companyName: "C", count: 890, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let currentDayStats = try PrivacyStatsUtils.loadCurrentDayStats(in: context)
                XCTAssertTrue(currentDayStats.isEmpty)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testThatObjectsWithZeroCountAreNotReportedByLoadCurrentDayStats() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 0, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "B", count: 0, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "C", count: 0, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let currentDayStats = try PrivacyStatsUtils.loadCurrentDayStats(in: context)
                XCTAssertTrue(currentDayStats.isEmpty)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testThatObjectsWithNonZeroCountAreReportedByLoadCurrentDayStats() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 150, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "B", count: 400, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "C", count: 84, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "D", count: 5, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let currentDayStats = try PrivacyStatsUtils.loadCurrentDayStats(in: context)
                XCTAssertEqual(currentDayStats, ["A": 150, "B": 400, "C": 84, "D": 5])
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    // MARK: - load7DayStats

    func testWhenThereAreNoObjectsInDatabaseThenLoad7DayStatsIsEmpty() throws {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let stats = try PrivacyStatsUtils.load7DayStats(in: context)
                XCTAssertTrue(stats.isEmpty)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testWhenThereAreObjectsInDatabaseFrom7DaysAgoOrMoreThenLoad7DayStatsIsEmpty() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(10), companyName: "A", count: 123, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(20), companyName: "B", count: 4567, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(7), companyName: "C", count: 890, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let stats = try PrivacyStatsUtils.load7DayStats(in: context)
                XCTAssertTrue(stats.isEmpty)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testThatObjectsWithZeroCountAreNotReportedByLoad7DayStats() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 0, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(4), companyName: "B", count: 0, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(6), companyName: "C", count: 0, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let stats = try PrivacyStatsUtils.load7DayStats(in: context)
                XCTAssertTrue(stats.isEmpty)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testThatObjectsWithNonZeroCountAreReportedByLoad7DayStats() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 150, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(1), companyName: "B", count: 400, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(2), companyName: "C", count: 84, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(6), companyName: "D", count: 5, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let stats = try PrivacyStatsUtils.load7DayStats(in: context)
                XCTAssertEqual(stats, ["A": 150, "B": 400, "C": 84, "D": 5])
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    // MARK: - load7DaysTotalBlockedTrackersCount

    func testWhenThereAreNoObjectsInDatabaseThenLoad7DaysTotalBlockedTrackersCountIsZero() throws {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let count = try PrivacyStatsUtils.load7DaysTotalBlockedTrackersCount(in: context)
                XCTAssertEqual(count, 0)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testWhenThereAreObjectsInDatabaseFrom7DaysAgoOrMoreTheLoad7DaysTotalBlockedTrackersCountIsZero() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(10), companyName: "A", count: 123, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(20), companyName: "B", count: 4567, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(7), companyName: "C", count: 890, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let count = try PrivacyStatsUtils.load7DaysTotalBlockedTrackersCount(in: context)
                XCTAssertEqual(count, 0)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testThatObjectsWithZeroCountAreNotReportedByLoad7DaysTotalBlockedTrackersCount() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 0, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(4), companyName: "B", count: 0, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(6), companyName: "C", count: 0, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let count = try PrivacyStatsUtils.load7DaysTotalBlockedTrackersCount(in: context)
                XCTAssertEqual(count, 0)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testThatObjectsWithNonZeroCountAreReportedByLoad7DaysTotalBlockedTrackersCount() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "A", count: 150, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(1), companyName: "B", count: 400, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(2), companyName: "C", count: 84, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(6), companyName: "D", count: 5, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                let count = try PrivacyStatsUtils.load7DaysTotalBlockedTrackersCount(in: context)
                XCTAssertEqual(count, 639)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    // MARK: - deleteOutdatedPacks

    func testWhenDeleteOutdatedPacksIsCalledThenObjectsFrom7DaysAgoOrMoreAreDeleted() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "C", count: 1, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(4), companyName: "C", count: 2, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(6), companyName: "C", count: 3, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(7), companyName: "C", count: 4, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(8), companyName: "C", count: 5, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(100), companyName: "C", count: 6, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                try PrivacyStatsUtils.deleteOutdatedPacks(in: context)

                let allObjects = try context.fetch(DailyBlockedTrackersEntity.fetchRequest())
                XCTAssertEqual(Set(allObjects.map(\.count)), [1, 2, 3])
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    func testWhenObjectsFrom7DaysAgoOrMoreAreNotPresentThenDeleteOutdatedPacksHasNoEffect() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "C", count: 1, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(4), companyName: "C", count: 2, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(6), companyName: "C", count: 3, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                try PrivacyStatsUtils.deleteOutdatedPacks(in: context)

                let allObjects = try context.fetch(DailyBlockedTrackersEntity.fetchRequest())
                XCTAssertEqual(allObjects.count, 3)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }

    // MARK: - deleteAllStats

    func testThatDeleteAllStatsRemovesAllDatabaseObjects() throws {
        let date = Date()

        try databaseProvider.addObjects { context in
            return [
                DailyBlockedTrackersEntity.make(timestamp: date, companyName: "C", count: 1, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(4), companyName: "C", count: 2, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(6), companyName: "C", count: 3, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(60), companyName: "C", count: 3, context: context),
                DailyBlockedTrackersEntity.make(timestamp: date.daysAgo(600), companyName: "C", count: 3, context: context)
            ]
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            do {
                try PrivacyStatsUtils.deleteAllStats(in: context)

                let allObjects = try context.fetch(DailyBlockedTrackersEntity.fetchRequest())
                XCTAssertTrue(allObjects.isEmpty)
            } catch {
                XCTFail("Should not throw")
            }
        }
    }
}
