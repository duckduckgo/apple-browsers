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

import AIChat
import XCTest
@testable import DuckDuckGo

/// The card's copy mapping. The module's own `messagePreview` is debug-log-only and unlocalized,
/// so this is what a user actually reads.
final class UTIFooterMessageMapperTests: XCTestCase {

    private let sut = UTIFooterMessageMapper(resetDescriber: UTIFooterResetDescriber(locale: Locale(identifier: "en_US")))

    // MARK: - Headlines

    func test_message_approachingNamesTheWindowAndThePercentage() {
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .daily, percent: 75)).title,
                       "75% of daily limit")
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 90)).title,
                       "90% of weekly limit")
    }

    func test_message_reachedHeadlinesMatchTheSpecifiedCopy() {
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily)).title,
                       "Daily limit reached")
        XCTAssertEqual(sut.message(for: warning(.weeklyLimitReached, window: .weekly)).title,
                       "Weekly usage limit reached")
        XCTAssertEqual(sut.message(for: warning(.advancedModelsLimitReached, window: .weekly)).title,
                       "Advanced AI models limit reached")
    }

    // MARK: - Icon

    /// The ring tracks the real percentage, not the threshold rung it crossed.
    func test_message_approachingFillsTheRingToTheReportedPercentage() {
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 76)).icon,
                       .usageRing(progress: 0.76, severity: .warning))
    }

    /// The ring is colour-coded by rung — neutral, amber, then red — so the severity has to reach it.
    func test_message_ringCarriesTheSeverityThatColoursIt() {
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 50, severity: .info)).icon,
                       .usageRing(progress: 0.5, severity: .info))
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 75, severity: .warning)).icon,
                       .usageRing(progress: 0.75, severity: .warning))
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .weekly, percent: 90, severity: .critical)).icon,
                       .usageRing(progress: 0.9, severity: .critical))
    }

    func test_message_reachedShowsTheAlertIcon() {
        XCTAssertEqual(sut.message(for: warning(.weeklyLimitReached, window: .weekly)).icon, .alert)
        XCTAssertEqual(sut.message(for: warning(.advancedModelsLimitReached, window: .weekly)).icon, .alert)
    }

    // MARK: - Reset copy

    func test_message_subtitleLocalizesWholeDays() {
        XCTAssertEqual(sut.message(for: warning(.weeklyLimitReached, window: .weekly, resetsIn: .days(2))).subtitle,
                       "Resets in 2 days")
    }

    func test_message_subtitleUsesTheSingularDay() {
        XCTAssertEqual(sut.message(for: warning(.weeklyLimitReached, window: .weekly, resetsIn: .days(1))).subtitle,
                       "Resets in 1 day")
    }

    func test_message_subtitleFallsBackToHoursWithinADay() {
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily, resetsIn: .hours(12))).subtitle,
                       "Resets in 12 hours")
    }

    /// Only reachable if the clock moves between read and render, and "Resets in 0 hours" would read
    /// as broken.
    func test_message_subtitleNeverCountsDownToZero() {
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily, resetsIn: .hours(0))).subtitle,
                       "Resets in 1 hour")
    }

    // MARK: - Action titles

    /// Every model switch reads the same one word, whether or not the suggestion carries a name and
    /// whether it steps down a tier or across to a free model.
    func test_message_everyModelSwitchReadsSwitch() {
        let named = DuckAiUsageAction.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                         modelShortName: "5.4 mini"))
        let unnamed = DuckAiUsageAction.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                           modelShortName: nil))
        let free = DuckAiUsageAction.switchToFreeModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                            modelShortName: "5.4 mini"))

        XCTAssertEqual(sut.message(for: warning(.approaching, window: .daily, action: named)).primaryAction?.title,
                       "Switch")
        XCTAssertEqual(sut.message(for: warning(.approaching, window: .daily, action: unnamed)).primaryAction?.title,
                       "Switch")
        XCTAssertEqual(sut.message(for: warning(.advancedModelsLimitReached, window: .weekly, action: free)).primaryAction?.title,
                       "Switch")
    }

    func test_message_upsellCopyFollowsTrialEligibility() {
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily,
                                                action: .tryForFree(isTrialEligible: true))).primaryAction?.title,
                       "Try for free")
        XCTAssertEqual(sut.message(for: warning(.dailyLimitReached, window: .daily,
                                                action: .tryForFree(isTrialEligible: false))).primaryAction?.title,
                       "Subscribe")
    }

    /// The resolver still produces this action so the decision stays visible in the log, but there is
    /// no native route for it yet, so the card must render no button.
    func test_message_startUsingWeeklyLimitOffersNoButton() {
        XCTAssertNil(sut.message(for: warning(.dailyLimitReached, window: .daily,
                                              action: .startUsingWeeklyLimit)).primaryAction)
    }

    func test_message_noActionOffersNoButton() {
        XCTAssertNil(sut.message(for: warning(.weeklyLimitReached, window: .weekly, action: nil)).primaryAction)
    }

    // MARK: - Dismissal

    func test_message_dismissibilityComesFromTheWarning() {
        XCTAssertTrue(sut.message(for: warning(.approaching, window: .weekly, isDismissible: true)).isDismissible)
        XCTAssertFalse(sut.message(for: warning(.weeklyLimitReached, window: .weekly, isDismissible: false)).isDismissible)
    }

    // MARK: - High-usage model notice

    func test_message_highUsageNoticeNamesTheModel() {
        XCTAssertEqual(sut.message(for: notice).title,
                       "Opus 4.8 uses limits up to 2-5x faster than basic models.")
    }

    /// Keyed off the selected model, not the allowance, so there is no percentage and no reset line.
    func test_message_highUsageNoticeShowsNoIconAndNoResetLine() {
        XCTAssertEqual(sut.message(for: notice).icon, UTIFooterMessage.Icon.none)
        XCTAssertNil(sut.message(for: notice).subtitle)
    }

    func test_message_highUsageNoticeOffersNoButton() {
        XCTAssertNil(sut.message(for: notice).primaryAction)
    }

    /// Copy only: the notice explains the cost and offers nothing to tap but the close button.
    func test_message_highUsageNoticeCarriesNothingButItsCopy() {
        let message = sut.message(for: notice)
        XCTAssertNil(message.primaryAction)
        XCTAssertNil(message.subtitle)
        XCTAssertEqual(message.icon, UTIFooterMessage.Icon.none)
    }

    func test_message_highUsageNoticeIsDismissible() {
        XCTAssertTrue(sut.message(for: notice).isDismissible)
    }

    // MARK: - Helpers

    private let notice = DuckAiHighUsageModelNotice(modelId: "claude-opus-4-8", modelShortName: "Opus 4.8")

    private func warning(_ message: DuckAiUsageMessage,
                         window: DuckAiUsageWindow,
                         percent: Int = 100,
                         severity: DuckAiUsageSeverity? = nil,
                         resetsIn: DuckAiUsageResetInterval = .days(1),
                         isDismissible: Bool = true,
                         action: DuckAiUsageAction? = nil) -> DuckAiUsageWarning {
        DuckAiUsageWarning(window: window,
                           message: message,
                           severity: severity ?? (message == .approaching ? .warning : .reached),
                           percent: percent,
                           resetsIn: resetsIn,
                           isDismissible: isDismissible,
                           action: action)
    }
}
