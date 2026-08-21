//
//  DuckAiUsageWarningDismissalTests.swift
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

/// The redisplay ladders are per-window and deliberately differ from the severity ladder, which is the
/// easiest part of this feature to get wrong. These pin the documented behaviour.
final class DuckAiUsageWarningDismissalTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12T12:00:00Z
    private var resetsAt: Date { now.addingTimeInterval(5 * 3600) }
    private var dismissalStore: InMemoryDuckAiUsageWarningDismissalStore!
    private var sut: DuckAiUsageWarningResolver!

    override func setUp() {
        super.setUp()
        dismissalStore = InMemoryDuckAiUsageWarningDismissalStore()
        sut = DuckAiUsageWarningResolver(dismissalStore: dismissalStore)
    }

    override func tearDown() {
        dismissalStore = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Daily ladder: 50 → 90 → 100

    /// Daily skips 75: the message goes to `.warning` there but stays hidden, because 75 isn't one of the
    /// daily redisplay thresholds.
    func testWhenDailyIsDismissedAtFiftyThenItStaysHiddenThroughSeventyFive() {
        dismiss(.daily, atThreshold: 50)

        XCTAssertNil(resolve(daily: 60))
        XCTAssertNil(resolve(daily: 75))
        XCTAssertNil(resolve(daily: 89))
    }

    func testWhenDailyIsDismissedAtFiftyThenItReturnsAtNinety() {
        dismiss(.daily, atThreshold: 50)

        XCTAssertEqual(resolve(daily: 90)?.severity, .critical)
    }

    func testWhenDailyIsDismissedAtNinetyThenOnlyBeingBlockedBringsItBack() {
        dismiss(.daily, atThreshold: 90)

        XCTAssertNil(resolve(daily: 95))
        XCTAssertEqual(resolve(daily: 100)?.message.isReached, true)
    }

    // MARK: - Weekly ladder: 50 → 75 → 90 → 100

    func testWhenWeeklyIsDismissedAtFiftyThenItReturnsAtSeventyFive() {
        dismiss(.weekly, atThreshold: 50)

        XCTAssertNil(resolve(weekly: 60))
        XCTAssertEqual(resolve(weekly: 75)?.severity, .warning)
    }

    func testWhenWeeklyIsDismissedAtSeventyFiveThenItReturnsAtNinety() {
        dismiss(.weekly, atThreshold: 75)

        XCTAssertNil(resolve(weekly: 80))
        XCTAssertEqual(resolve(weekly: 90)?.severity, .critical)
    }

    // MARK: - Expiry and scope

    func testWhenTheWindowHasResetThenAnOldDismissalIsIgnored() {
        dismiss(.daily, atThreshold: 50, resetsAt: resetsAt)

        let nextPeriod = DuckAiUsageLimits(
            daily: DuckAiUsageLimitWindow(percentUsed: 60, resetsAt: resetsAt.addingTimeInterval(86400)),
            weekly: nil
        )
        XCTAssertNotNil(warning(in: nextPeriod))
    }

    /// Dismissal is per window, and filtering happens before the winner is picked — so silencing daily
    /// must not silence a weekly that still has something to say.
    func testWhenDailyIsDismissedThenAQualifyingWeeklyStillShows() {
        dismiss(.daily, atThreshold: 50)

        let warning = resolve(daily: 60, weekly: 60)
        XCTAssertEqual(warning?.window, .weekly)
    }

    /// A reached message is never dismissible, so a prior dismissal at 50 can't suppress it.
    func testWhenBlockedThenAnEarlierDismissalDoesNotSuppressIt() {
        dismiss(.daily, atThreshold: 50)

        XCTAssertEqual(resolve(daily: 100)?.message.isReached, true)
    }

    // MARK: - Helpers

    private func dismiss(_ window: DuckAiUsageWindow, atThreshold threshold: Int, resetsAt: Date? = nil) {
        dismissalStore.setDismissal(
            DuckAiUsageWarningDismissal(resetsAt: resetsAt ?? self.resetsAt, threshold: threshold),
            for: window
        )
    }

    private func resolve(daily: Double? = nil, weekly: Double? = nil) -> DuckAiUsageWarning? {
        warning(in: DuckAiUsageLimits(
            daily: daily.map { DuckAiUsageLimitWindow(percentUsed: $0, resetsAt: resetsAt) },
            weekly: weekly.map { DuckAiUsageLimitWindow(percentUsed: $0, resetsAt: resetsAt) }
        ))
    }

    private func warning(in limits: DuckAiUsageLimits) -> DuckAiUsageWarning? {
        guard case .warning(let warning, _) = sut.resolve(limits: limits,
                                                          tier: .pro,
                                                          isInternalUser: false,
                                                          isTrialEligible: false,
                                                          now: now) else { return nil }
        return warning
    }
}
