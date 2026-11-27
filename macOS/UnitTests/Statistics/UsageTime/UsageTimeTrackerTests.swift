//
//  UsageTimeTrackerTests.swift
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

final class UsageTimeTrackerTests: XCTestCase {
    // 00:00 ET, 25 November 2026.
    private let midnight = Date(timeIntervalSince1970: 1_795_582_800)

    private func reading(_ seconds: TimeInterval, uptime: TimeInterval? = nil) -> UsageTimeReading {
        UsageTimeReading(date: midnight.addingTimeInterval(seconds), uptime: uptime ?? seconds)
    }

    func testIdleDeadlineSplitsAtEasternMidnight() {
        var tracker = UsageTimeTracker()
        _ = tracker.record(.start, at: reading(-100))
        _ = tracker.record(.input, at: reading(-100))
        XCTAssertEqual(tracker.record(.checkpoint, at: reading(260)), [
            UsageTimeIncrement(start: reading(-100).date, open: 100, active: 100),
            UsageTimeIncrement(start: midnight, open: 260, active: 200)
        ])
    }

    func testResigningAndSleepingRequireFreshInput() {
        var tracker = UsageTimeTracker()
        _ = tracker.record(.start, at: reading(0))
        _ = tracker.record(.input, at: reading(0))
        XCTAssertEqual(tracker.record(.resignActive, at: reading(10)).first?.active, 10)
        XCTAssertEqual(tracker.record(.stop, at: reading(30)).first?.active, 0)
        XCTAssertTrue(tracker.record(.checkpoint, at: reading(1000, uptime: 30)).isEmpty)
        _ = tracker.record(.start, at: reading(2000, uptime: 30))
        XCTAssertEqual(tracker.record(.checkpoint, at: reading(2020, uptime: 50)), [
            UsageTimeIncrement(start: reading(2000).date, open: 20, active: 0)
        ])
    }

    func testStoppingAtMidnightLeavesNewDayToNextStart() {
        var tracker = UsageTimeTracker()
        _ = tracker.record(.start, at: reading(-10))
        XCTAssertEqual(tracker.record(.stop, at: reading(0)), [
            UsageTimeIncrement(start: reading(-10).date, open: 10, active: 0)
        ])
        XCTAssertEqual(tracker.record(.start, at: reading(500)).first?.start, reading(500).date)
    }

    func testSecondInputExtendsDeadlineFromItsOwnTimestamp() {
        var tracker = UsageTimeTracker()
        _ = tracker.record(.start, at: reading(0))
        _ = tracker.record(.input, at: reading(10))
        XCTAssertEqual(tracker.record(.input, at: reading(290)).first?.active, 280)
        XCTAssertEqual(tracker.record(.checkpoint, at: reading(650)).first?.active, 300)
    }

    func testClockJumpCreditsOnlyPrecedingDate() {
        var tracker = UsageTimeTracker()
        _ = tracker.record(.start, at: reading(-10, uptime: 10))
        let result = tracker.record(.checkpoint, at: reading(90_000, uptime: 15))
        XCTAssertEqual(result, [
            UsageTimeIncrement(start: reading(-10).date, open: 5, active: 0),
            UsageTimeIncrement(start: reading(90_000).date, open: 0, active: 0)
        ])
    }
}
