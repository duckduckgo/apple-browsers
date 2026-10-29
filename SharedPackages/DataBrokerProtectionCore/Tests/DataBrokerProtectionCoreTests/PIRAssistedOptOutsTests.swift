//
//  PIRAssistedOptOutsTests.swift
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

#if os(macOS) && DEBUG
import XCTest
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class PIRAssistedOptOutsTests: XCTestCase {

    private let broker = DataBroker.mock(id: 1, name: "PeopleFinders", url: "peoplefinders.com")
    private let now = Date(timeIntervalSince1970: 1_000)

    private func pending(_ optOuts: [OptOutJobData], broker: DataBroker? = nil, scan: ScanJobData = .mock) throws -> [Int64?] {
        let database = MockDatabase()
        database.brokerProfileQueryDataToReturn = [BrokerProfileQueryData(dataBroker: broker ?? self.broker, profileQuery: .mock,
                                                                          scanJobData: scan, optOutJobData: optOuts)]
        return try PIRAssistedOptOuts.pending(in: database, now: now).map(\.extractedProfileId)
    }

    private func record(_ id: Int64) -> ExtractedProfile {
        ExtractedProfile(id: id, name: "\(id)", profileUrl: "\(id)", identifier: "\(id)")
    }

    func testAStartLetsTheJobRunOnce() {
        XCTAssertFalse(PIRAssistedOptOuts.consumeStart(brokerId: 90, profileQueryId: 1, extractedProfileId: 2))

        PIRAssistedOptOuts.markStarted(brokerId: 90, profileQueryId: 1, extractedProfileId: 2)

        XCTAssertFalse(PIRAssistedOptOuts.consumeStart(brokerId: 90, profileQueryId: 1, extractedProfileId: nil))
        XCTAssertTrue(PIRAssistedOptOuts.consumeStart(brokerId: 90, profileQueryId: 1, extractedProfileId: 2))
        XCTAssertFalse(PIRAssistedOptOuts.consumeStart(brokerId: 90, profileQueryId: 1, extractedProfileId: 2))
    }

    func testWhenAnOptOutAwaitsEmailConfirmation_thenItNoLongerWaitsForTheUser() throws {
        let awaiting = OptOutJobData.mock(with: record(10),
                                          historyEvents: [.mock(type: .optOutStarted, date: Date(timeIntervalSince1970: 1)),
                                                          .mock(type: .optOutSubmittedAndAwaitingEmailConfirmation, date: Date(timeIntervalSince1970: 2))])

        XCTAssertEqual(try pending([awaiting, .mock(with: record(11))]), [11])
    }

    func testWhenASubmittedOptOutIsDueAgain_thenTheUserCanStartIt() throws {
        let due = OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: now, preferredRunDate: now.addingTimeInterval(-1),
                                historyEvents: [], attemptCount: 1, submittedSuccessfullyDate: now, extractedProfile: record(10))
        let notYet = OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: now, preferredRunDate: now.addingTimeInterval(60),
                                   historyEvents: [], attemptCount: 1, submittedSuccessfullyDate: now, extractedProfile: record(11))

        XCTAssertEqual(try pending([due, notYet]), [10])
    }

    func testWhenAHeldScanIsDueAgain_thenTheUserCanStartIt() throws {
        let spyFly = DataBroker.mock(id: 3, name: "SpyFly", url: "spyfly.com")
        let due = ScanJobData(brokerId: 3, profileQueryId: 1, preferredRunDate: now, historyEvents: [], lastRunDate: now.addingTimeInterval(-60))
        let notYet = ScanJobData(brokerId: 3, profileQueryId: 1, preferredRunDate: now.addingTimeInterval(60), historyEvents: [],
                                 lastRunDate: now.addingTimeInterval(-60))

        XCTAssertEqual(try pending([], broker: spyFly, scan: due), [nil])
        XCTAssertEqual(try pending([], broker: spyFly, scan: notYet), [])
    }
}
#endif
