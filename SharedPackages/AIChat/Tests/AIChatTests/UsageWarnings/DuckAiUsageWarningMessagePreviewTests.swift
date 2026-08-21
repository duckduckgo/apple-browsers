//
//  DuckAiUsageWarningMessagePreviewTests.swift
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

/// The preview is what the debug log is read from while there is no UI, so the wording of all five
/// specified messages is pinned here.
final class DuckAiUsageWarningMessagePreviewTests: XCTestCase {

    private let suggestion = DuckAiModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: "5.6 Luna")

    func testApproaching() {
        let preview = warning(.approaching, window: .weekly, percent: 75).messagePreview

        XCTAssertEqual(preview.title, "75% of weekly limit · Resets in 4d")
        XCTAssertNil(preview.button)
    }

    func testApproachingWithACheaperModel() {
        let preview = warning(.approaching, window: .weekly, percent: 75,
                              action: .switchToModel(suggestion)).messagePreview

        XCTAssertEqual(preview.title, "75% of weekly limit · Resets in 4d")
        XCTAssertEqual(preview.button, "Switch to 5.6 Luna")
    }

    func testButtonFallsBackWhenTheModelHasNoShortName() {
        let unnamed = DuckAiModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: nil)
        let preview = warning(.approaching, window: .daily, percent: 60,
                              action: .switchToModel(unnamed)).messagePreview

        XCTAssertEqual(preview.button, "Switch Model")
    }

    /// Every reached message shows reset copy, unlike the earlier spec where it was headline-only.
    func testDailyLimitReached() {
        let preview = warning(.dailyLimitReached, window: .daily, percent: 100,
                              action: .startUsingWeeklyLimit).messagePreview

        XCTAssertEqual(preview.title, "Daily limit reached · Resets in 4d")
        XCTAssertEqual(preview.button, "Start using weekly limit")
    }

    func testWeeklyLimitReachedCarriesNoCTA() {
        let preview = warning(.weeklyLimitReached, window: .weekly, percent: 100).messagePreview

        XCTAssertEqual(preview.title, "Weekly usage limit reached · Resets in 4d")
        XCTAssertNil(preview.button)
    }

    func testAdvancedModelsLimitReached() {
        let preview = warning(.advancedModelsLimitReached, window: .weekly, percent: 100,
                              action: .switchToFreeModel(suggestion)).messagePreview

        XCTAssertEqual(preview.title, "Advanced AI models limit reached · Resets in 4d")
        XCTAssertEqual(preview.button, "Switch to a Free Model")
    }

    func testTryForFreeCopyFollowsTrialEligibility() {
        XCTAssertEqual(warning(.dailyLimitReached, window: .daily, percent: 100,
                               action: .tryForFree(isTrialEligible: true)).messagePreview.button,
                       "Try for free")
        XCTAssertEqual(warning(.dailyLimitReached, window: .daily, percent: 100,
                               action: .tryForFree(isTrialEligible: false)).messagePreview.button,
                       "Subscribe")
    }

    /// Web pairs the CTA with a "Reduce usage with a more efficient model" subtitle; native doesn't.
    func testThereIsNoSubtitle() {
        let preview = warning(.approaching, window: .weekly, percent: 75,
                              action: .switchToModel(suggestion)).messagePreview

        XCTAssertFalse(preview.title.localizedCaseInsensitiveContains("efficient model"))
    }

    private func warning(_ message: DuckAiUsageMessage,
                         window: DuckAiUsageWindow,
                         percent: Int,
                         action: DuckAiUsageAction? = nil) -> DuckAiUsageWarning {
        DuckAiUsageWarning(
            window: window,
            message: message,
            severity: message.isReached ? .reached : .warning,
            percent: percent,
            resetsIn: .days(4),
            isDismissible: !message.isReached,
            action: action
        )
    }
}
