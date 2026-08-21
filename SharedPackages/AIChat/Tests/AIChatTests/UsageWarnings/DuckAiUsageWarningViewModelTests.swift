//
//  DuckAiUsageWarningViewModelTests.swift
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

final class DuckAiUsageWarningViewModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12T12:00:00Z
    private var resetsAt: Date { now.addingTimeInterval(5 * 3600) }
    private var limitsProvider: StubUsageLimitsProvider!
    private var dismissalStore: InMemoryDuckAiUsageWarningDismissalStore!

    override func setUp() {
        super.setUp()
        limitsProvider = StubUsageLimitsProvider()
        dismissalStore = InMemoryDuckAiUsageWarningDismissalStore()
    }

    override func tearDown() {
        limitsProvider = nil
        dismissalStore = nil
        super.tearDown()
    }

    /// An inactive feature and an active one with nothing to show both publish `nil`, but only the first
    /// must avoid touching storage at all.
    func testWhenTheFeatureIsInactiveThenNothingIsPublishedAndStorageIsNotRead() {
        let sut = makeSUT(isFeatureActive: false)

        sut.refresh()

        XCTAssertNil(sut.warning)
        XCTAssertEqual(limitsProvider.readCount, 0)
    }

    func testRefreshPublishesTheResolvedWarning() {
        limitsProvider.limits = limits(daily: 75)
        let sut = makeSUT()

        sut.refresh()

        XCTAssertEqual(sut.warning?.window, .daily)
        XCTAssertEqual(sut.warning?.severity, .warning)
    }

    func testRefreshPicksUpAChangedSnapshot() {
        limitsProvider.limits = limits(daily: 60)
        let sut = makeSUT()
        sut.refresh()
        XCTAssertEqual(sut.warning?.severity, .info)

        limitsProvider.limits = limits(daily: 95)
        sut.refresh()

        XCTAssertEqual(sut.warning?.severity, .critical)
    }

    // MARK: - Dismissal

    func testDismissHidesTheWarningAndRecordsTheThreshold() {
        limitsProvider.limits = limits(daily: 60)
        let sut = makeSUT()
        sut.refresh()

        sut.dismiss()

        XCTAssertNil(sut.warning)
        XCTAssertEqual(dismissalStore.dismissal(for: .daily)?.threshold, 50)
    }

    func testDismissDoesNothingForANonDismissibleWarning() {
        limitsProvider.limits = limits(daily: 100)
        let sut = makeSUT()
        sut.refresh()

        sut.dismiss()

        XCTAssertEqual(sut.warning?.message, .dailyLimitReached)
        XCTAssertNil(dismissalStore.dismissal(for: .daily))
    }

    /// `clear()` is teardown, not a user action — it must not silence the message for the rest of the
    /// reset period.
    func testClearDropsTheWarningWithoutRecordingADismissal() {
        limitsProvider.limits = limits(daily: 60)
        let sut = makeSUT()
        sut.refresh()

        sut.clear()

        XCTAssertNil(sut.warning)
        XCTAssertNil(dismissalStore.dismissal(for: .daily))
    }

    // MARK: - Actions

    func testApproachingCarriesTheSwitchActionAndPerformingItInvokesTheHandler() {
        limitsProvider.limits = limits(daily: 75)
        let sut = makeSUT(modelSuggester: StubModelSuggester(
            cheaper: .suggestion(DuckAiModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: "5.6 Luna"))
        ))
        var performed: [DuckAiUsageAction] = []
        sut.onAction = { performed.append($0) }
        sut.refresh()

        XCTAssertEqual(sut.warning?.action?.buttonTitle, "Switch to 5.6 Luna")
        XCTAssertTrue(sut.warning?.offersModelPicker ?? false)

        sut.performAction()

        XCTAssertEqual(performed.count, 1)
    }

    /// Internal testers on the free tier see approaching warnings, but the upsell belongs to the reached
    /// messages — and the `>` picker only ever modifies a model switch.
    func testInternalFreeTierApproachingOffersTheModelSwitchNotTheUpsell() {
        limitsProvider.limits = limits(daily: 75)
        let sut = makeSUT(tier: .free, isInternalUser: true, modelSuggester: StubModelSuggester(
            cheaper: .suggestion(DuckAiModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: "5.6 Luna"))
        ))

        sut.refresh()

        XCTAssertEqual(sut.warning?.action, .switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.6-luna",
                                                                                modelShortName: "5.6 Luna")))
        XCTAssertTrue(sut.warning?.offersModelPicker ?? false)
    }

    func testInternalFreeTierReachedStillOffersTheUpsellWithoutThePicker() {
        limitsProvider.limits = limits(daily: 100, weekly: 40)
        let sut = makeSUT(tier: .free, isInternalUser: true, isTrialEligible: true)

        sut.refresh()

        XCTAssertEqual(sut.warning?.action, .tryForFree(isTrialEligible: true))
        XCTAssertFalse(sut.warning?.offersModelPicker ?? true)
    }

    /// The free tier's only reached CTA is the upsell, and its copy follows trial eligibility.
    func testFreeTierReachedOffersTheUpsellAndCannotBeDismissed() {
        limitsProvider.limits = limits(daily: 100)
        let sut = makeSUT(tier: .free, isTrialEligible: true)

        sut.refresh()

        XCTAssertEqual(sut.warning?.action, .tryForFree(isTrialEligible: true))
        XCTAssertFalse(sut.warning?.isDismissible ?? true)
    }

    /// Only worth offering when the weekly allowance can actually absorb more.
    func testPaidDailyReachedOffersTheWeeklyLimitOnlyWhenWeeklyHasRoom() {
        limitsProvider.limits = limits(daily: 100, weekly: 40)
        let withRoom = makeSUT()
        withRoom.refresh()
        XCTAssertEqual(withRoom.warning?.action, .startUsingWeeklyLimit)

        limitsProvider.limits = limits(daily: 100)
        let withoutWeeklyData = makeSUT()
        withoutWeeklyData.refresh()
        XCTAssertNil(withoutWeeklyData.warning?.action)
    }

    /// A daily reset can't unblock a spent weekly allowance, so weekly is the one worth showing.
    func testWhenBothWindowsAreBlockedThenWeeklyIsShown() {
        limitsProvider.limits = limits(daily: 100, weekly: 100)
        let sut = makeSUT()

        sut.refresh()

        XCTAssertEqual(sut.warning?.window, .weekly)
        XCTAssertEqual(sut.warning?.message, .weeklyLimitReached)
    }

    func testReachedNeverOffersACheaperModelOrThePicker() {
        limitsProvider.limits = limits(daily: 100, weekly: 40)
        let sut = makeSUT(modelSuggester: StubModelSuggester(
            cheaper: .suggestion(DuckAiModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: "5.6 Luna"))
        ))

        sut.refresh()

        XCTAssertEqual(sut.warning?.action, .startUsingWeeklyLimit)
        XCTAssertFalse(sut.warning?.offersModelPicker ?? true)
    }

    func testPerformingAnActionDoesNothingWhenThereIsNone() {
        limitsProvider.limits = limits(daily: 75)
        let sut = makeSUT()
        var actionCount = 0
        sut.onAction = { _ in actionCount += 1 }
        sut.refresh()

        sut.performAction()

        XCTAssertEqual(actionCount, 0)
    }

    func testOpeningTheModelPickerDoesNothingWhenItIsNotOffered() {
        limitsProvider.limits = limits(daily: 75)
        let sut = makeSUT()
        var openCount = 0
        sut.onOpenModelPicker = { openCount += 1 }
        sut.refresh()

        sut.openModelPicker()

        XCTAssertEqual(openCount, 0)
    }

    // MARK: - Helpers

    /// `isFeatureActive: false` builds the view model with no provider at all, which is how the factory
    /// represents "flag off, or no storage bridge".
    private func makeSUT(isFeatureActive: Bool = true,
                         tier: AIChatUserTier = .pro,
                         isInternalUser: Bool = false,
                         modelSuggester: DuckAiModelSuggesting = NullDuckAiModelSuggester(),
                         isTrialEligible: Bool = false
    ) -> DuckAiUsageWarningViewModel {
        DuckAiUsageWarningViewModel(
            limitsProvider: isFeatureActive ? limitsProvider : nil,
            tierProvider: { tier },
            isInternalUser: { isInternalUser },
            dismissalStore: dismissalStore,
            modelSuggester: modelSuggester,
            isTrialEligible: { isTrialEligible },
            dateProvider: { self.now }
        )
    }

    private func limits(daily: Double? = nil, weekly: Double? = nil) -> DuckAiUsageLimits {
        DuckAiUsageLimits(
            daily: daily.map { DuckAiUsageLimitWindow(percentUsed: $0, resetsAt: resetsAt) },
            weekly: weekly.map { DuckAiUsageLimitWindow(percentUsed: $0, resetsAt: resetsAt) }
        )
    }
}

private final class StubUsageLimitsProvider: DuckAiUsageLimitsProviding {
    var limits: DuckAiUsageLimits = .noData
    private(set) var readCount = 0

    func currentUsageLimits() -> DuckAiUsageLimits {
        readCount += 1
        return limits
    }
}

private struct StubModelSuggester: DuckAiModelSuggesting {
    var cheaper: DuckAiModelSuggestionOutcome = .none(reason: .notApplicable)
    var free: DuckAiModelSuggestionOutcome = .none(reason: .notApplicable)
    func cheaperModel() -> DuckAiModelSuggestionOutcome { cheaper }
    func freeModel() -> DuckAiModelSuggestionOutcome { free }
}
