//
//  DuckAiUsageResetIntervalTests.swift
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
@testable import AIChat

final class DuckAiUsageResetIntervalTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12T12:00:00Z

    func testWhenResetIsInTheFutureByDaysThenItRoundsUpToDays() {
        XCTAssertEqual(interval(afterHours: 24).shortDescription, "1d")
        XCTAssertEqual(interval(afterHours: 48).shortDescription, "2d")
        XCTAssertEqual(interval(afterHours: 72).shortDescription, "3d")
    }

    /// Both of these look wrong and aren't — they're what the web copy does. Pinned so a "fix" has to be
    /// a deliberate change rather than a drive-by.
    func testWhenIntervalSitsBetweenDayBoundariesThenTheCopyLooksOddButMatchesWeb() {
        XCTAssertEqual(interval(afterHours: 25).shortDescription, "2d", "25h ceilings to 2 days, not 1")
        XCTAssertEqual(interval(afterHours: 23.9).shortDescription, "24h", "just under a day stays in hours")
    }

    func testWhenResetIsWithinADayThenItRoundsUpToHours() {
        XCTAssertEqual(interval(afterHours: 5).shortDescription, "5h")
        XCTAssertEqual(interval(afterHours: 4.2).shortDescription, "5h")
    }

    /// Anything still in the future is at least an hour away, so the copy never says "0h" prematurely.
    func testWhenResetIsMinutesAwayThenItReportsAtLeastAnHour() {
        XCTAssertEqual(interval(afterHours: 0.1).shortDescription, "1h")
    }

    /// Only reachable if the clock moves between reading the snapshot and rendering it —
    /// `DuckAiUsageLimits.make` already drops windows that have reset.
    func testWhenResetHasPassedThenItReportsZeroHours() {
        XCTAssertEqual(interval(afterHours: -3).shortDescription, "0h")
        XCTAssertEqual(interval(afterHours: 0).shortDescription, "0h")
    }

    private func interval(afterHours hours: Double) -> DuckAiUsageResetInterval {
        .from(now: now, resetsAt: now.addingTimeInterval(hours * 3600))
    }
}
