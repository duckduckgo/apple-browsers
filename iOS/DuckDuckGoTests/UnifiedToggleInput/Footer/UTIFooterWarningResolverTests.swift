//
//  UTIFooterWarningResolverTests.swift
//  DuckDuckGo
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

import AIChat
import XCTest
@testable import DuckDuckGo

final class UTIFooterWarningResolverTests: XCTestCase {

    private let sut = UTIFooterWarningResolver()
    private let weeklyReset = Date(timeIntervalSince1970: 1_800_000_000)
    private let dailyReset = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Nothing to warn about

    func test_resolve_returnsNilWhenThereIsNoData() {
        XCTAssertNil(sut.resolve(limits: .noData))
    }

    func test_resolve_returnsNilBelowTheFirstThreshold() {
        XCTAssertNil(sut.resolve(limits: makeLimits(weekly: 49.9)))
    }

    // MARK: - Thresholds

    func test_resolve_returnsFiftyThresholdAtTheExactBoundary() {
        XCTAssertEqual(sut.resolve(limits: makeLimits(weekly: 50)),
                       .usageThreshold(window: .weekly, threshold: .fifty, resetsAt: weeklyReset))
    }

    func test_resolve_bucketsDownToTheHighestCrossedThreshold() {
        XCTAssertEqual(sut.resolve(limits: makeLimits(weekly: 76)),
                       .usageThreshold(window: .weekly, threshold: .seventyFive, resetsAt: weeklyReset))
    }

    func test_resolve_returnsNinetyThresholdBelowTheLimit() {
        XCTAssertEqual(sut.resolve(limits: makeLimits(weekly: 99.9)),
                       .usageThreshold(window: .weekly, threshold: .ninety, resetsAt: weeklyReset))
    }

    func test_resolve_returnsLimitReachedAtFullUsage() {
        XCTAssertEqual(sut.resolve(limits: makeLimits(weekly: 100)),
                       .limitReached(window: .weekly, resetsAt: weeklyReset))
    }

    // MARK: - Choosing between windows

    func test_resolve_picksTheWindowWithTheHigherThreshold() {
        XCTAssertEqual(sut.resolve(limits: makeLimits(daily: 92, weekly: 55)),
                       .usageThreshold(window: .daily, threshold: .ninety, resetsAt: dailyReset))
    }

    func test_resolve_picksTheBlockedWindowOverAThresholdInTheOther() {
        XCTAssertEqual(sut.resolve(limits: makeLimits(daily: 100, weekly: 90)),
                       .limitReached(window: .daily, resetsAt: dailyReset))
    }

    func test_resolve_prefersWeeklyWhenBothWindowsRankTheSame() {
        XCTAssertEqual(sut.resolve(limits: makeLimits(daily: 55, weekly: 51)),
                       .usageThreshold(window: .weekly, threshold: .fifty, resetsAt: weeklyReset))
    }

    func test_resolve_ignoresAWindowThatHasNotCrossedAThreshold() {
        XCTAssertEqual(sut.resolve(limits: makeLimits(daily: 10, weekly: 80)),
                       .usageThreshold(window: .weekly, threshold: .seventyFive, resetsAt: weeklyReset))
    }

    // MARK: - Helpers

    private func makeLimits(daily: Double? = nil, weekly: Double? = nil) -> DuckAiUsageLimits {
        DuckAiUsageLimits(
            daily: daily.map { DuckAiUsageLimitWindow(percentUsed: $0, resetsAt: dailyReset) },
            weekly: weekly.map { DuckAiUsageLimitWindow(percentUsed: $0, resetsAt: weeklyReset) }
        )
    }
}
