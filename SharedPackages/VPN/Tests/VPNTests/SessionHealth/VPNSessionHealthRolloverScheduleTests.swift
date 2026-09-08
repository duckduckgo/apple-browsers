//
//  VPNSessionHealthRolloverScheduleTests.swift
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
@testable import VPN

final class VPNSessionHealthRolloverScheduleTests: XCTestCase {

    private let schedule = VPNSessionHealthRolloverSchedule()

    // January 1, 2024, at midnight UTC.
    private let midnight = Date(timeIntervalSince1970: 1_704_067_200)

    func testSameHourDoesNotRollOver() {
        let start = midnight.addingTimeInterval(1_200)
        let now = midnight.addingTimeInterval(3_599)

        XCTAssertNil(schedule.rolloverDates(from: start, to: now))
    }

    func testUnchangedClockDoesNotRollOver() {
        let start = midnight.addingTimeInterval(1_200)

        XCTAssertNil(schedule.rolloverDates(from: start, to: start))
    }

    func testClockMovingBackwardsDoesNotRollOver() {
        let start = midnight.addingTimeInterval(1_200)
        let now = midnight.addingTimeInterval(600)

        XCTAssertNil(schedule.rolloverDates(from: start, to: now))
    }

    func testExactBoundaryClosesPreviousHourAndStartsNextHour() throws {
        let result = try XCTUnwrap(schedule.rolloverDates(from: midnight.addingTimeInterval(2_700), to: midnight.addingTimeInterval(3_600)))
        XCTAssertEqual(result.endedAt, midnight.addingTimeInterval(3_600))
        XCTAssertEqual(result.startedAt, result.endedAt)
    }

    func testDelayedCallbackSkipsIntermediateHours() throws {
        let result = try XCTUnwrap(schedule.rolloverDates(from: midnight.addingTimeInterval(1_200), to: midnight.addingTimeInterval(11_100)))
        XCTAssertEqual(result.endedAt, midnight.addingTimeInterval(3_600))
        XCTAssertEqual(result.startedAt, midnight.addingTimeInterval(10_800))
    }

    func testRolloverAcrossMidnight() throws {
        let result = try XCTUnwrap(schedule.rolloverDates(from: midnight.addingTimeInterval(-60), to: midnight.addingTimeInterval(60)))
        XCTAssertEqual(result.endedAt, midnight)
        XCTAssertEqual(result.startedAt, midnight)
    }
}
