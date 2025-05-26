//
//  SyncDailyStatsTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import PersistenceTestingUtils
@testable import DDGSync

class SyncDailyStatsTests: XCTestCase {

    static let featureA = Feature(name: "featureA")
    static let featureB = Feature(name: "featureB")

    static let error1 = SyncError.unexpectedStatusCode(400)
    static let error2 = SyncError.unexpectedStatusCode(413)

    let store = MockKeyValueStore()
    var stats: SyncDailyStats!

    var statusDict: [String: Int]? {
        store.object(forKey: SyncDailyStats.Constants.dailyStatsDictKey) as? [String: Int]
    }

    override func setUp() {
        super.setUp()

        stats = SyncDailyStats(store: store)

        XCTAssertNil(store.object(forKey: SyncDailyStats.Constants.lastSentDate))
        XCTAssertNil(store.object(forKey: SyncDailyStats.Constants.syncCountParam))
    }

    func testWhenSyncIsFinishedThenCountIncreases() {
        stats.onSyncFinished(with: nil)

        XCTAssertEqual(statusDict?[SyncDailyStats.Constants.syncCountParam], 1)

        stats.onSyncFinished(with: nil)

        XCTAssertEqual(statusDict?[SyncDailyStats.Constants.syncCountParam], 2)
    }

    func testWhenErrorIsFoundThenCountsIncrease() {
        stats.onSyncFinished(with: SyncOperationError(featureErrors: [.init(feature: Self.featureA,
                                                                            underlyingError: Self.error1)]))

        XCTAssertEqual(statusDict?[SyncDailyStats.Constants.syncCountParam], 1)
        XCTAssertEqual(statusDict?[SyncDailyStats.ErrorType(syncError: Self.error1)?.key(for: Self.featureA) ?? ""], 1)

        stats.onSyncFinished(with: SyncOperationError(featureErrors: [.init(feature: Self.featureA,
                                                                            underlyingError: Self.error1),
                                                                      .init(feature: Self.featureB,
                                                                            underlyingError: Self.error2)]))

        XCTAssertEqual(statusDict?[SyncDailyStats.Constants.syncCountParam], 2)
        XCTAssertEqual(statusDict?[SyncDailyStats.ErrorType(syncError: Self.error1)?.key(for: Self.featureA) ?? ""], 2)
        XCTAssertEqual(statusDict?[SyncDailyStats.ErrorType(syncError: Self.error2)?.key(for: Self.featureB) ?? ""], 1)
    }

    func testWhenNewInstallThenSendNothing() {

        stats.sendStatsIfNeeded { _ in
            XCTFail("Should not execute")
        }

        XCTAssertNotNil(store.object(forKey: SyncDailyStats.Constants.lastSentDate))
    }

    func testWhenSameDayThenSendNothing() {
        stats.sendStatsIfNeeded { _ in
            XCTFail("Should not execute")
        }

        let firstStoredDate = store.object(forKey: SyncDailyStats.Constants.lastSentDate) as? Date
        XCTAssertNotNil(firstStoredDate)

        Thread.sleep(forTimeInterval: 0.1)

        stats.sendStatsIfNeeded { _ in
            XCTFail("Should not execute")
        }

        XCTAssertNotNil(store.object(forKey: SyncDailyStats.Constants.lastSentDate))
        XCTAssertEqual(store.object(forKey: SyncDailyStats.Constants.lastSentDate) as? Date, firstStoredDate)
    }

    func testWhenNextDayThenSendData() {
        let currentDate = Date()
        guard let yesterday = Calendar.current.date(byAdding: DateComponents(day: -1), to: currentDate) else {
            XCTFail("Could not create date")
            return
        }

        XCTAssertFalse(Calendar.current.isDate(currentDate, inSameDayAs: yesterday))
        XCTAssertFalse(Calendar.current.isDateInToday(yesterday))

        stats.sendStatsIfNeeded(currentDate: yesterday)  { _ in
            XCTFail("Should not execute")
        }

        XCTAssertEqual(store.object(forKey: SyncDailyStats.Constants.lastSentDate) as? Date, yesterday)

        let exp = expectation(description: "Should send data")

        stats.onSyncFinished(with: nil)
        stats.sendStatsIfNeeded(currentDate: currentDate) { data in
            XCTAssertEqual(data[SyncDailyStats.Constants.syncCountParam], "1")
            exp.fulfill()
        }

        XCTAssertEqual(store.object(forKey: SyncDailyStats.Constants.lastSentDate) as? Date, currentDate)

        wait(for: [exp], timeout: 1)
    }

    func testWhenNextDayButNoDataThenDontSendData() {
        let currentDate = Date()
        guard let yesterday = Calendar.current.date(byAdding: DateComponents(day: -1), to: currentDate) else {
            XCTFail("Could not create date")
            return
        }

        XCTAssertFalse(Calendar.current.isDate(currentDate, inSameDayAs: yesterday))
        XCTAssertFalse(Calendar.current.isDateInToday(yesterday))

        stats.sendStatsIfNeeded(currentDate: yesterday)  { _ in
            XCTFail("Should not execute")
        }

        XCTAssertEqual(store.object(forKey: SyncDailyStats.Constants.lastSentDate) as? Date, yesterday)

        stats.sendStatsIfNeeded(currentDate: currentDate) { _ in
            XCTFail("Should not execute - no data")
        }

        XCTAssertEqual(store.object(forKey: SyncDailyStats.Constants.lastSentDate) as? Date, currentDate)
    }

}
