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

        XCTAssertEqual(sut.warning?.kind, .reached)
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

    // MARK: - Cheaper-model CTA

    func testApproachingWarningCarriesTheSuggestionAndSwitchingInvokesTheHandler() {
        limitsProvider.limits = limits(daily: 75)
        let sut = makeSUT(cheaperModelSuggester: StubCheaperModelSuggester(
            outcome: .suggestion(DuckAiCheaperModelSuggestion(modelId: "claude-sonnet-4.6", modelShortName: "Sonnet 4.6"))
        ))
        var switched: [String] = []
        sut.onSwitchToSuggestedModel = { switched.append($0.modelId) }
        sut.refresh()

        XCTAssertEqual(sut.warning?.cheaperModelSuggestion?.modelShortName, "Sonnet 4.6")

        sut.switchToSuggestedModel()

        XCTAssertEqual(switched, ["claude-sonnet-4.6"])
    }

    /// A reached message has nothing left to head off, so it never carries a CTA.
    func testReachedWarningCarriesNoSuggestion() {
        limitsProvider.limits = limits(daily: 100)
        let sut = makeSUT(cheaperModelSuggester: StubCheaperModelSuggester(
            outcome: .suggestion(DuckAiCheaperModelSuggestion(modelId: "claude-sonnet-4.6", modelShortName: "Sonnet 4.6"))
        ))
        sut.refresh()

        XCTAssertNil(sut.warning?.cheaperModelSuggestion)
    }

    func testSwitchingDoesNothingWhenThereIsNoSuggestion() {
        limitsProvider.limits = limits(daily: 75)
        let sut = makeSUT()
        var switchCount = 0
        sut.onSwitchToSuggestedModel = { _ in switchCount += 1 }
        sut.refresh()

        sut.switchToSuggestedModel()

        XCTAssertEqual(switchCount, 0)
    }

    // MARK: - Helpers

    /// `isFeatureActive: false` builds the view model with no provider at all, which is how the factory
    /// represents "flag off, or no storage bridge".
    private func makeSUT(isFeatureActive: Bool = true,
                         tier: AIChatUserTier = .pro,
                         cheaperModelSuggester: DuckAiCheaperModelSuggesting = NullDuckAiCheaperModelSuggester()
    ) -> DuckAiUsageWarningViewModel {
        DuckAiUsageWarningViewModel(
            limitsProvider: isFeatureActive ? limitsProvider : nil,
            tierProvider: { tier },
            isInternalUser: { false },
            dismissalStore: dismissalStore,
            cheaperModelSuggester: cheaperModelSuggester,
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

private struct StubCheaperModelSuggester: DuckAiCheaperModelSuggesting {
    let outcome: DuckAiCheaperModelOutcome
    func suggestion() -> DuckAiCheaperModelOutcome { outcome }
}
