//
//  AIChatUsageWarningCopyTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

/// The card's copy mapping. The module's own `messagePreview` is debug-log-only and unlocalized,
/// so this is what a user actually reads.
final class AIChatUsageWarningCopyTests: XCTestCase {

    // MARK: - Headlines

    func testApproachingNamesTheWindowAndThePercentage() {
        XCTAssertEqual(warning(.approaching, window: .daily, percent: 75).localizedHeadline,
                       "75% of daily limit")
        XCTAssertEqual(warning(.approaching, window: .weekly, percent: 90).localizedHeadline,
                       "90% of weekly limit")
    }

    func testReachedHeadlinesMatchTheSpecifiedCopy() {
        XCTAssertEqual(warning(.dailyLimitReached, window: .daily).localizedHeadline,
                       "Daily limit reached")
        XCTAssertEqual(warning(.weeklyLimitReached, window: .weekly).localizedHeadline,
                       "Weekly usage limit reached")
        XCTAssertEqual(warning(.advancedModelsLimitReached, window: .weekly).localizedHeadline,
                       "Advanced AI models limit reached")
    }

    func testResetCopyWrapsTheShortInterval() {
        XCTAssertEqual(warning(.dailyLimitReached, window: .daily, resetsIn: .days(7)).localizedResetsIn,
                       "Resets in 7d")
        XCTAssertEqual(warning(.dailyLimitReached, window: .daily, resetsIn: .hours(12)).localizedResetsIn,
                       "Resets in 12h")
    }

    // MARK: - Action titles

    func testModelSwitchNamesTheSuggestedModel() {
        let action = DuckAiUsageAction.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                          modelShortName: "5.4 mini"))
        XCTAssertEqual(warning(.approaching, window: .daily, action: action).localizedActionTitle,
                       "Switch to 5.4 mini")
    }

    /// A suggestion can arrive without a display name, and "Switch to " with nothing after it
    /// would be worse than a generic label.
    func testModelSwitchFallsBackWhenTheModelHasNoShortName() {
        let action = DuckAiUsageAction.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                          modelShortName: nil))
        XCTAssertEqual(warning(.approaching, window: .daily, action: action).localizedActionTitle,
                       "Switch Model")
    }

    func testFreeModelSwitchUsesItsOwnCopyRatherThanTheModelName() {
        let action = DuckAiUsageAction.switchToFreeModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini",
                                                                              modelShortName: "5.4 mini"))
        XCTAssertEqual(warning(.advancedModelsLimitReached, window: .weekly, action: action).localizedActionTitle,
                       "Switch to a Free Model")
    }

    func testUpsellCopyFollowsTrialEligibility() {
        XCTAssertEqual(warning(.dailyLimitReached, window: .daily,
                               action: .tryForFree(isTrialEligible: true)).localizedActionTitle,
                       "Try for free")
        XCTAssertEqual(warning(.dailyLimitReached, window: .daily,
                               action: .tryForFree(isTrialEligible: false)).localizedActionTitle,
                       "Subscribe")
    }

    /// The resolver still produces this action so the decision stays visible in the log, but there
    /// is no native route for it yet, so the card must render no button.
    func testStartUsingWeeklyLimitOffersNoButton() {
        XCTAssertNil(warning(.dailyLimitReached, window: .daily, action: .startUsingWeeklyLimit).localizedActionTitle)
    }

    func testNoActionOffersNoButton() {
        XCTAssertNil(warning(.weeklyLimitReached, window: .weekly, action: nil).localizedActionTitle)
    }

    // MARK: - Helpers

    private func warning(_ message: DuckAiUsageMessage,
                         window: DuckAiUsageWindow,
                         percent: Int = 100,
                         resetsIn: DuckAiUsageResetInterval = .days(1),
                         action: DuckAiUsageAction? = nil) -> DuckAiUsageWarning {
        DuckAiUsageWarning(window: window,
                           message: message,
                           severity: message == .approaching ? .warning : .reached,
                           percent: percent,
                           resetsIn: resetsIn,
                           isDismissible: message == .approaching,
                           action: action,
                           offersModelPicker: action?.offersModelPickerForTesting ?? false)
    }
}

private extension DuckAiUsageAction {
    /// `offersModelPicker` is internal to the module, and the flag is only incidental here — the
    /// copy under test doesn't depend on it.
    var offersModelPickerForTesting: Bool {
        switch self {
        case .switchToModel, .switchToFreeModel: return true
        case .tryForFree, .startUsingWeeklyLimit: return false
        }
    }
}
