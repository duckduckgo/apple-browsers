//
//  DBPWideEventSweeperTests.swift
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
import PixelKit
import PixelKitTestingUtilities
import BrowserServicesKit
@testable import DataBrokerProtectionCore

final class DBPWideEventSweeperTests: XCTestCase {

    func testSweepSubmissionBeyondDeadlineCompletesWithExpiredReason() async {
        let wideEvent = WideEventMock()
        let startDate = Date(timeIntervalSince1970: 0)
        let submissionInterval = WideEvent.MeasuredInterval(start: startDate, end: nil)
        let data = OptOutSubmissionWideEventData(globalData: WideEventGlobalData(),
                                                 dataBrokerURL: "example.com",
                                                 dataBrokerVersion: "1.0",
                                                 submissionInterval: submissionInterval)
        wideEvent.startFlow(data)

        let sweeper = DBPWideEventSweeper(wideEvent: wideEvent,
                                          submissionWindow: .seconds(10),
                                          confirmationWindow: .seconds(20),
                                          currentDateForTesting: { Date(timeIntervalSince1970: 20) })
        await sweeper.performSweep()

        XCTAssertEqual(wideEvent.completions.count, 1)
        guard let completion = wideEvent.completions.first else {
            return XCTFail("Expected submission completion")
        }
        XCTAssertTrue(completion.0 is OptOutSubmissionWideEventData)
        guard case .unknown(let reason) = completion.1 else {
            return XCTFail("Expected unknown status")
        }
        XCTAssertEqual(reason, OptOutSubmissionWideEventData.StatusReason.submissionWindowExpired.rawValue)
    }

    func testSweepConfirmationBeyondDeadlineCompletesWithExpiredReason() async {
        let wideEvent = WideEventMock()
        let startDate = Date(timeIntervalSince1970: 0)
        let confirmationInterval = WideEvent.MeasuredInterval(start: startDate, end: nil)
        let data = OptOutConfirmationWideEventData(globalData: WideEventGlobalData(),
                                                   dataBrokerURL: "example.com",
                                                   dataBrokerVersion: "1.0",
                                                   confirmationInterval: confirmationInterval)
        wideEvent.startFlow(data)

        let sweeper = DBPWideEventSweeper(wideEvent: wideEvent,
                                          submissionWindow: .seconds(10),
                                          confirmationWindow: .seconds(30),
                                          currentDateForTesting: { Date(timeIntervalSince1970: 40) })
        await sweeper.performSweep()

        XCTAssertEqual(wideEvent.completions.count, 1)
        guard let completion = wideEvent.completions.first else {
            return XCTFail("Expected confirmation completion")
        }
        XCTAssertTrue(completion.0 is OptOutConfirmationWideEventData)
        guard case .unknown(let reason) = completion.1 else {
            return XCTFail("Expected unknown status")
        }
        XCTAssertEqual(reason, OptOutConfirmationWideEventData.StatusReason.confirmationWindowExpired.rawValue)
    }

    func testSweepWithinDeadlineDoesNotComplete() async {
        let wideEvent = WideEventMock()
        let startDate = Date()
        let submissionInterval = WideEvent.MeasuredInterval(start: startDate, end: nil)
        let data = OptOutSubmissionWideEventData(globalData: WideEventGlobalData(),
                                                 dataBrokerURL: "example.com",
                                                 dataBrokerVersion: nil,
                                                 submissionInterval: submissionInterval)
        wideEvent.startFlow(data)

        let sweeper = DBPWideEventSweeper(wideEvent: wideEvent,
                                          submissionWindow: .days(7),
                                          confirmationWindow: .days(14),
                                          currentDateForTesting: { startDate.addingTimeInterval(TimeInterval.days(1)) })
        await sweeper.performSweep()

        XCTAssertTrue(wideEvent.completions.isEmpty)
    }
}
