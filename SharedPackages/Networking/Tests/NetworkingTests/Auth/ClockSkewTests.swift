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

    func testMonitor_MeasuresDeviceTimeAgainstTheServerDate() {
        let now = Date()
        let monitor = ClockSkewMonitor(now: { now })

        let skew = monitor.measure(serverDate: now.addingTimeInterval(.minutes(30)))

        XCTAssertEqual(skew, .behind5MinutesTo1Hour)
        XCTAssertEqual(monitor.current, .behind5MinutesTo1Hour)
    }

    func testMonitor_KeepsTheLatestMeasurement() {
        let now = Date()
        let monitor = ClockSkewMonitor(now: { now })
        monitor.measure(serverDate: now.addingTimeInterval(-TimeInterval.days(3)))
        monitor.measure(serverDate: now)

        XCTAssertEqual(monitor.current, .within5Minutes)
    }

    func testMonitor_ReadsTheHTTPDateHeader() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-24T12:00:00Z"))
        let monitor = ClockSkewMonitor(now: { now })

        let skew = monitor.measure(makeResponse(dateHeader: "Sun, 22 Nov 2026 12:00:00 GMT"))

        XCTAssertEqual(skew, .aheadOver1Day)
        XCTAssertEqual(monitor.current, .aheadOver1Day)
    }

    func testMonitor_ResponseWithoutAValidDateHeader_KeepsThePreviousMeasurement() {
        let now = Date()
        let monitor = ClockSkewMonitor(now: { now })
        monitor.measure(serverDate: now.addingTimeInterval(.hours(2)))

        XCTAssertNil(monitor.measure(makeResponse(dateHeader: nil)))
        XCTAssertNil(monitor.measure(makeResponse(dateHeader: "yesterday")))
        XCTAssertEqual(monitor.current, .behind1HourTo1Day)
    }

    private func makeResponse(dateHeader: String?) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com")!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: dateHeader.map { ["Date": $0] })!
    }
}
