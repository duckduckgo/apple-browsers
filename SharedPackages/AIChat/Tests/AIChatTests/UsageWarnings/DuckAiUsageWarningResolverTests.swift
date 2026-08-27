//
//  DuckAiUsageWarningResolverTests.swift
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

final class DuckAiUsageWarningResolverTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12T12:00:00Z
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

    // MARK: - Visibility

    func testWhenThereIsNoDataThenNothingIsShown() {
        XCTAssertNil(resolve(.noData))
    }

    /// Gated on the raw percentage, not the rounded one, so a 49.6% window never renders as "50%".
    func testWhenUsageIsJustBelowTheFloorThenNothingIsShown() {
        XCTAssertNil(resolve(limits(daily: 49.6)))
    }

    func testWhenUsageIsJustAboveTheFloorThenTheRoundedPercentageIsShown() {
        XCTAssertEqual(resolve(limits(daily: 50.4))?.percent, 50)
    }

    // MARK: - Severity

    /// Whole numbers, so this pins the ladder itself; rounding is covered separately below.
    func testSeverityLaddersOnTheDocumentedBoundaries() {
        XCTAssertEqual(resolve(limits(daily: 50))?.severity, .info)
        XCTAssertEqual(resolve(limits(daily: 74))?.severity, .info)
        XCTAssertEqual(resolve(limits(daily: 75))?.severity, .warning)
        XCTAssertEqual(resolve(limits(daily: 89))?.severity, .warning)
        XCTAssertEqual(resolve(limits(daily: 90))?.severity, .critical)
        XCTAssertEqual(resolve(limits(daily: 100))?.severity, .reached)
    }

    /// The ring and the headline are read together, so a percentage that rounds up to a threshold must
    /// take that threshold's severity with it.
    func testSeverityFollowsTheDisplayedPercentageNotTheRawOne() {
        XCTAssertEqual(resolve(limits(daily: 74.6))?.percent, 75)
        XCTAssertEqual(resolve(limits(daily: 74.6))?.severity, .warning)
        XCTAssertEqual(resolve(limits(daily: 89.6))?.percent, 90)
        XCTAssertEqual(resolve(limits(daily: 89.6))?.severity, .critical)
    }

    /// Rounding down must not promote severity either.
    func testSeverityStaysDownWhenThePercentageRoundsDown() {
        XCTAssertEqual(resolve(limits(daily: 74.4))?.percent, 74)
        XCTAssertEqual(resolve(limits(daily: 74.4))?.severity, .info)
    }

    // MARK: - Percentage

    /// The percentage is capped at 99 until the window is actually blocked, so "100%" only ever appears
    /// alongside the reached message.
    func testWhenUsageWouldRoundToOneHundredThenItIsCappedAtNinetyNine() {
        XCTAssertEqual(resolve(limits(daily: 99.6))?.percent, 99)
        XCTAssertEqual(resolve(limits(daily: 99.9))?.percent, 99)
    }

    func testWhenBlockedThenPercentageIsOneHundred() {
        let warning = resolve(limits(daily: 100))
        XCTAssertEqual(warning?.percent, 100)
        XCTAssertEqual(warning?.message.isReached, true)
    }

    // MARK: - Audience

    func testWhenTierIsPaidOrInternalThenApproachingIsShown() {
        for tier in [AIChatUserTier.plus, .pro] {
            XCTAssertEqual(resolve(limits(daily: 75), tier: tier)?.message, .approaching, "\(tier)")
        }
        XCTAssertEqual(resolve(limits(daily: 75), tier: .free, isInternalUser: true)?.message, .approaching)
    }

    func testWhenTierIsFreeThenApproachingIsHidden() {
        XCTAssertNil(resolve(limits(daily: 75), tier: .free))
        XCTAssertNil(resolve(limits(daily: 99), tier: .free))
    }

    /// The reached message is the one thing every tier sees.
    func testWhenTierIsFreeThenReachedIsStillShownAndCannotBeDismissed() {
        let warning = resolve(limits(daily: 100), tier: .free)
        XCTAssertEqual(warning?.message.isReached, true)
        XCTAssertFalse(warning?.isDismissible ?? true)
    }

    func testReachedIsNeverDismissibleEvenForPaidTiers() {
        XCTAssertFalse(resolve(limits(daily: 100), tier: .pro)?.isDismissible ?? true)
    }

    func testApproachingIsDismissibleForPaidTiers() {
        XCTAssertTrue(resolve(limits(daily: 60), tier: .pro)?.isDismissible ?? false)
    }

    // MARK: - Window precedence

    func testWhenBothWindowsQualifyThenTheMoreSevereWins() {
        let warning = resolve(limits(daily: 60, weekly: 92))
        XCTAssertEqual(warning?.window, .weekly)
        XCTAssertEqual(warning?.severity, .critical)
    }

    func testWhenSeveritiesMatchThenTheHigherPercentageWins() {
        XCTAssertEqual(resolve(limits(daily: 76, weekly: 88))?.window, .weekly)
        XCTAssertEqual(resolve(limits(daily: 88, weekly: 76))?.window, .daily)
    }

    func testWhenSeverityAndPercentageMatchThenDailyWins() {
        XCTAssertEqual(resolve(limits(daily: 80, weekly: 80))?.window, .daily)
    }

    func testWhenOneWindowIsBlockedThenItOutranksAnApproachingOne() {
        let warning = resolve(limits(daily: 60, weekly: 100))
        XCTAssertEqual(warning?.window, .weekly)
        XCTAssertEqual(warning?.message.isReached, true)
    }

    // MARK: - Advanced-models weekly variant

    /// The discriminator isn't in the payload yet, so weekly-blocked defaults to the plain copy.
    func testWeeklyBlockedDefaultsToPlainWeeklyCopy() {
        XCTAssertEqual(resolve(limits(weekly: 100))?.message, .weeklyLimitReached)
    }

    func testWeeklyBlockedUsesAdvancedCopyWhenTheWindowIsNamed() {
        let outcome = sut.resolve(limits: limits(weekly: 100),
                                  tier: .pro,
                                  isInternalUser: false,
                                  isTrialEligible: false,
                                  advancedModelsWindow: .weekly,
                                  now: now)
        guard case .warning(let warning, _) = outcome else { return XCTFail("expected a warning") }

        XCTAssertEqual(warning.message, .advancedModelsLimitReached)
    }

    /// The free-model CTA is still a model switch, so it carries the `>` into the native picker.
    func testAdvancedModelsReachedOffersTheFreeModelSwitchAndThePicker() {
        let resolver = DuckAiUsageWarningResolver(
            dismissalStore: dismissalStore,
            modelSuggester: StubFreeModelSuggester(
                free: .suggestion(DuckAiModelSuggestion(modelId: "gpt-5.4-mini", modelShortName: "5.4 mini"))
            )
        )
        let outcome = resolver.resolve(limits: limits(weekly: 100),
                                       tier: .pro,
                                       isInternalUser: false,
                                       isTrialEligible: false,
                                       advancedModelsWindow: .weekly,
                                       now: now)
        guard case .warning(let warning, _) = outcome else { return XCTFail("expected a warning") }

        XCTAssertEqual(warning.action, .switchToFreeModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                               modelShortName: "5.4 mini")))
        XCTAssertTrue(warning.offersModelPicker)
    }

    // MARK: - Reset copy

    func testResetCopyComesFromTheWinningWindow() {
        let limits = DuckAiUsageLimits(
            daily: DuckAiUsageLimitWindow(percentUsed: 60, resetsAt: now.addingTimeInterval(5 * 3600)),
            weekly: DuckAiUsageLimitWindow(percentUsed: 95, resetsAt: now.addingTimeInterval(3 * 86400))
        )
        let warning = resolve(limits)
        XCTAssertEqual(warning?.window, .weekly)
        XCTAssertEqual(warning?.resetsIn.shortDescription, "3d")
    }

    // MARK: - Helpers

    private func resolve(_ limits: DuckAiUsageLimits,
                         tier: AIChatUserTier = .pro,
                         isInternalUser: Bool = false) -> DuckAiUsageWarning? {
        guard case .warning(let warning, _) = sut.resolve(limits: limits,
                                                          tier: tier,
                                                          isInternalUser: isInternalUser,
                                                          isTrialEligible: false,
                                                          now: now) else { return nil }
        return warning
    }

    private func limits(daily: Double? = nil, weekly: Double? = nil) -> DuckAiUsageLimits {
        let resetsAt = now.addingTimeInterval(5 * 3600)
        return DuckAiUsageLimits(
            daily: daily.map { DuckAiUsageLimitWindow(percentUsed: $0, resetsAt: resetsAt) },
            weekly: weekly.map { DuckAiUsageLimitWindow(percentUsed: $0, resetsAt: resetsAt) }
        )
    }
}

private struct StubFreeModelSuggester: DuckAiModelSuggesting {
    let free: DuckAiModelSuggestionOutcome

    func cheaperModel() -> DuckAiModelSuggestionOutcome { .none(reason: .notApplicable) }
    func freeModel() -> DuckAiModelSuggestionOutcome { free }
}
