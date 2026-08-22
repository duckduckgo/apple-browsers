//
//  UTIFooterMessageMapperTests.swift
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

import XCTest
@testable import DuckDuckGo

final class UTIFooterMessageMapperTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private lazy var sut = UTIFooterMessageMapper(resetDescriber: UTIFooterResetDescriber(locale: Locale(identifier: "en_US")))

    // MARK: - Usage threshold

    func test_message_usageThresholdShowsTheRingFilledToTheThreshold() {
        let message = sut.message(for: .usageThreshold(window: .weekly, threshold: .seventyFive, resetsAt: now.addingTimeInterval(.days(2))), now: now)

        XCTAssertEqual(message.icon, .usageRing(progress: 0.75))
    }

    func test_message_usageThresholdTitleCarriesThePercentageAndWindow() {
        let message = sut.message(for: .usageThreshold(window: .weekly, threshold: .fifty, resetsAt: now.addingTimeInterval(.days(2))), now: now)

        XCTAssertTrue(message.title.contains("50%"), message.title)
        XCTAssertTrue(message.title.lowercased().contains("weekly"), message.title)
    }

    func test_message_usageThresholdOffersReduceUsage() {
        let message = sut.message(for: .usageThreshold(window: .daily, threshold: .ninety, resetsAt: now.addingTimeInterval(.days(2))), now: now)

        XCTAssertEqual(message.primaryAction?.action, .reduceUsage)
        XCTAssertFalse(message.primaryAction?.title.isEmpty ?? true)
    }

    // MARK: - Limit reached

    func test_message_limitReachedShowsTheAlertIcon() {
        let message = sut.message(for: .limitReached(window: .weekly, resetsAt: now.addingTimeInterval(.days(7))), now: now)

        XCTAssertEqual(message.icon, .alert)
    }

    func test_message_limitReachedOffersSwitch() {
        let message = sut.message(for: .limitReached(window: .weekly, resetsAt: now.addingTimeInterval(.days(7))), now: now)

        XCTAssertEqual(message.primaryAction?.action, .switchModel)
    }

    func test_message_everyStateIsDismissible() {
        let threshold = sut.message(for: .usageThreshold(window: .weekly, threshold: .fifty, resetsAt: now), now: now)
        let reached = sut.message(for: .limitReached(window: .weekly, resetsAt: now), now: now)

        XCTAssertTrue(threshold.isDismissible)
        XCTAssertTrue(reached.isDismissible)
    }

    // MARK: - Reset description

    func test_message_subtitleDescribesWholeDaysUntilReset() {
        let message = sut.message(for: .usageThreshold(window: .weekly, threshold: .fifty, resetsAt: now.addingTimeInterval(.days(2) + .hours(3))), now: now)

        XCTAssertTrue(message.subtitle?.contains("2 days") ?? false, message.subtitle ?? "nil")
    }

    func test_message_subtitleUsesTheSingularDay() {
        let message = sut.message(for: .usageThreshold(window: .weekly, threshold: .fifty, resetsAt: now.addingTimeInterval(.days(1) + .hours(1))), now: now)

        XCTAssertTrue(message.subtitle?.contains("1 day") ?? false, message.subtitle ?? "nil")
    }

    func test_message_subtitleFallsBackToHoursWithinADay() {
        let message = sut.message(for: .usageThreshold(window: .daily, threshold: .fifty, resetsAt: now.addingTimeInterval(.hours(5))), now: now)

        XCTAssertTrue(message.subtitle?.contains("5 hours") ?? false, message.subtitle ?? "nil")
    }

    func test_message_subtitleFallsBackToMinutesWithinAnHour() {
        let message = sut.message(for: .usageThreshold(window: .daily, threshold: .fifty, resetsAt: now.addingTimeInterval(12 * 60)), now: now)

        XCTAssertTrue(message.subtitle?.contains("12 minutes") ?? false, message.subtitle ?? "nil")
    }

    func test_message_subtitleHandlesAResetThatHasAlreadyPassed() {
        let message = sut.message(for: .usageThreshold(window: .daily, threshold: .fifty, resetsAt: now.addingTimeInterval(-60)), now: now)

        XCTAssertNotNil(message.subtitle)
    }
}

private extension TimeInterval {
    static func days(_ count: Double) -> TimeInterval { count * 24 * 60 * 60 }
    static func hours(_ count: Double) -> TimeInterval { count * 60 * 60 }
}
