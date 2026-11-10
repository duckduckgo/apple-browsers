//
//  DataBrokerProtectionDebugEmailOptOutSeederTests.swift
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

#if DEBUG
import XCTest
@testable import DataBrokerProtectionCore

final class DataBrokerProtectionDebugEmailOptOutSeederTests: XCTestCase {

    private var temporaryDatabase: TemporaryDataBrokerProtectionDatabase!

    override func setUp() async throws {
        temporaryDatabase = try TemporaryDataBrokerProtectionDatabase()
        try await temporaryDatabase.saveProfile()
    }

    override func tearDown() {
        temporaryDatabase = nil
    }

    func testSeed_storesAnOverdueRecordWithAProfileUrlThatTheDashboardListsInProgress() throws {
        let (brokerId, _) = try temporaryDatabase.saveBroker(fixture: "valid-child-broker")
        let now = Date()

        let seeded = try makeSeeder().seed(now: now)

        let queryData = try XCTUnwrap(temporaryDatabase.database.fetchBrokerProfileQueryData(forBrokerId: brokerId).first)
        let optOut = try XCTUnwrap(queryData.optOutJobData.first)
        let record = try XCTUnwrap(DBPUIScanAndOptOutMaintenanceState(from: [queryData]).inProgressOptOuts.first)
        let expectedFoundDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -15, to: now))
        XCTAssertEqual(seeded, ["fakebroker0.com"])
        XCTAssertNil(optOut.preferredRunDate)
        XCTAssertEqual(record.profileUrl, "https://fakebroker0.com/profile/debug-email-opt-out-seed")
        XCTAssertEqual(record.foundDate, expectedFoundDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertGreaterThan(try XCTUnwrap(queryData.scanJobData.preferredRunDate), now.addingTimeInterval(365 * 24 * 60 * 60))
        XCTAssertNotNil(queryData.scanJobData.lastRunDate)
    }

    func testSeed_whenRunTwice_keepsOneRecord() throws {
        let (brokerId, _) = try temporaryDatabase.saveBroker(fixture: "valid-child-broker")

        try makeSeeder().seed()
        let secondRun = try makeSeeder().seed()

        XCTAssertEqual(secondRun, [])
        XCTAssertEqual(try temporaryDatabase.database.fetchExtractedProfiles(for: brokerId).count, 1)
    }

    func testSeed_whenTheBrokerHasNoProfileQuery_failsWithANamedError() {
        XCTAssertThrowsError(try makeSeeder().seed()) { error in
            guard case DebugEmailOptOutSeedError.noProfileQuery(brokerURL: "fakebroker0.com") = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
    }

    private func makeSeeder() -> DataBrokerProtectionDebugEmailOptOutSeeder {
        DataBrokerProtectionDebugEmailOptOutSeeder(database: temporaryDatabase.database, brokerURLs: ["fakebroker0.com"])
    }
}
#endif
