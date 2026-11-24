//
//  ClockSkewTests.swift
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

import XCTest
import FoundationExtensions
@testable import Subscription
@_spi(Testing) @testable import Networking

final class ClockSkewTests: XCTestCase {

    func testBuckets() {
        XCTAssertEqual(ClockSkew(offset: 0), .within5Minutes)
        XCTAssertEqual(ClockSkew(offset: TimeInterval.minutes(5) - 1), .within5Minutes)
        XCTAssertEqual(ClockSkew(offset: -(TimeInterval.minutes(5) - 1)), .within5Minutes)
        XCTAssertEqual(ClockSkew(offset: .minutes(5)), .ahead5MinutesTo1Hour)
        XCTAssertEqual(ClockSkew(offset: -TimeInterval.minutes(5)), .behind5MinutesTo1Hour)
        XCTAssertEqual(ClockSkew(offset: .hours(1)), .ahead1HourTo1Day)
        XCTAssertEqual(ClockSkew(offset: -TimeInterval.hours(1)), .behind1HourTo1Day)
        XCTAssertEqual(ClockSkew(offset: .days(1)), .aheadOver1Day)
        XCTAssertEqual(ClockSkew(offset: -TimeInterval.days(1)), .behindOver1Day)
    }

    func testIsSkewed() {
        XCTAssertFalse(ClockSkew.within5Minutes.isSkewed)
        XCTAssertTrue(ClockSkew.allCases.filter { $0 != .within5Minutes }.allSatisfy(\.isSkewed))
    }

    func testMonitor_StartsWithNoMeasurement() {
        XCTAssertNil(ClockSkewMonitor().current)
    }

    func testMonitor_MeasuresDeviceTimeAgainstTheTokenIssueTime() {
        let now = Date()
        let monitor = ClockSkewMonitor(now: { now })
        let token = OAuthTokensFactory.makeTokenContainer(accessTokenIssuedAt: now.addingTimeInterval(.minutes(30)))

        let skew = monitor.measure(freshlyIssued: token)

        XCTAssertEqual(skew, .behind5MinutesTo1Hour)
        XCTAssertEqual(monitor.current, .behind5MinutesTo1Hour)
    }

    func testMonitor_KeepsTheLatestMeasurement() {
        let now = Date()
        let monitor = ClockSkewMonitor(now: { now })
        monitor.measure(freshlyIssued: OAuthTokensFactory.makeTokenContainer(accessTokenIssuedAt: now.addingTimeInterval(-TimeInterval.days(3))))
        monitor.measure(freshlyIssued: OAuthTokensFactory.makeTokenContainer(accessTokenIssuedAt: now))

        XCTAssertEqual(monitor.current, .within5Minutes)
    }
}
