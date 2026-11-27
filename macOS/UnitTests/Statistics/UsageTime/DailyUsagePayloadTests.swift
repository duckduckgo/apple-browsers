//
//  DailyUsagePayloadTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class DailyUsagePayloadTests: XCTestCase {
    private func date(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
    }

    func testLateReportUsesOriginalEasternDate() throws {
        let first = try date("2026-11-25T04:30:00Z")
        let record = UsageDayRecord(firstSignal: first)
        XCTAssertNil(record.reportIfEligible(asOf: first.addingTimeInterval(86_399)))
        XCTAssertEqual(record.reportIfEligible(asOf: first.addingTimeInterval(86_400))?.payload.daysAgo, 1)
        let payload = try XCTUnwrap(record.reportIfEligible(asOf: date("2026-11-26T15:00:00Z"))?.payload)
        XCTAssertEqual(payload.usageDate, "2026-11-24")
        XCTAssertEqual(payload.daysAgo, 2)
        XCTAssertNotNil(record.reportIfEligible(asOf: first.addingTimeInterval(7 * 86_400)))
        XCTAssertNil(record.reportIfEligible(asOf: first.addingTimeInterval(8 * 86_400)))
    }

    func testBothDayEndAndElapsedTimeAreRequiredAcrossDST() throws {
        let spring = UsageDayRecord(firstSignal: try date("2026-03-08T05:00:00Z"))
        XCTAssertNil(spring.reportIfEligible(asOf: try date("2026-03-09T04:00:00Z")))
        XCTAssertNotNil(spring.reportIfEligible(asOf: try date("2026-03-09T05:00:00Z")))
        let fall = UsageDayRecord(firstSignal: try date("2026-11-01T04:00:00Z"))
        XCTAssertNil(fall.reportIfEligible(asOf: try date("2026-11-02T04:00:00Z")))
        XCTAssertNotNil(fall.reportIfEligible(asOf: try date("2026-11-02T05:00:00Z")))
    }

    func testBucketsUseExactSecondsAtBoundaries() {
        XCTAssertEqual(DailyUsagePayload.bucket(seconds: 0), "0")
        XCTAssertEqual(DailyUsagePayload.bucket(seconds: 1799.9), "(0,30)")
        XCTAssertEqual(DailyUsagePayload.bucket(seconds: 1800), "[30,60)")
        XCTAssertEqual(DailyUsagePayload.bucket(seconds: 3600), "[60,120)")
        XCTAssertEqual(DailyUsagePayload.bucket(seconds: 120 * 60), "[120,180)")
        XCTAssertEqual(DailyUsagePayload.bucket(seconds: 180 * 60), "[180,300)")
        XCTAssertEqual(DailyUsagePayload.bucket(seconds: 300 * 60), "[300,420)")
        XCTAssertEqual(DailyUsagePayload.bucket(seconds: 420 * 60), "[420,600)")
        XCTAssertEqual(DailyUsagePayload.bucket(seconds: 36_000), "[600,+∞)")
    }
}
