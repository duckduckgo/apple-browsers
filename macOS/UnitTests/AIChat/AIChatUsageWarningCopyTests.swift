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
        XCTAssertEqual(warning(.dailyReached, window: .daily).localizedHeadline,
                       "Daily limit reached")
        XCTAssertEqual(warning(.weeklyReached, window: .weekly).localizedHeadline,
                       "Weekly usage limit reached")
        XCTAssertEqual(warning(.weeklyReachedDegraded, window: .weekly).localizedHeadline,
                       "Advanced AI models limit reached")
    }

    /// Web sends one id for a free user whichever window ran out, so the window picks the noun.
    func testFreeReachedFollowsItsWindow() {
        XCTAssertEqual(warning(.freeReached, window: .daily).localizedHeadline,
                       "Daily limit reached")
        XCTAssertEqual(warning(.freeReached, window: .weekly).localizedHeadline,
                       "Weekly usage limit reached")
    }

    func testResetCopyWrapsTheShortInterval() {
        XCTAssertEqual(warning(.dailyReached, window: .daily, resetsIn: .days(7)).localizedResetsIn,
                       "Resets in 7d")
        XCTAssertEqual(warning(.dailyReached, window: .daily, resetsIn: .hours(12)).localizedResetsIn,
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
        XCTAssertEqual(warning(.weeklyReachedDegraded, window: .weekly, action: action).localizedActionTitle,
                       "Switch to a Free Model")
    }

    func testUpsellCopyFollowsTrialEligibility() {
        XCTAssertEqual(warning(.freeReached, window: .daily,
                               action: .tryForFree(isTrialEligible: true)).localizedActionTitle,
                       "Try Subscription for Free")
        XCTAssertEqual(warning(.freeReached, window: .daily,
                               action: .tryForFree(isTrialEligible: false)).localizedActionTitle,
                       "Subscribe")
    }

    func testStartUsingWeeklyLimitNamesTheHandOff() {
        let entries = [DuckAiNativeStorageEntry(key: "duckai.fixedCostWindowBypassResetAtById", value: "{}")]

        XCTAssertEqual(warning(.dailyReached, window: .daily,
                               action: .startUsingWeeklyLimit(entries: entries)).localizedActionTitle,
                       "Start Using Weekly Limit")
    }

    /// How a switch with nothing usable to switch to renders, as well as a notice web sent no cta for.
    func testNoActionOffersNoButton() {
        XCTAssertNil(warning(.weeklyReached, window: .weekly, action: nil).localizedActionTitle)
    }

    // MARK: - High-usage model notice

    /// The web app's and Windows' sentence, with the model named. iOS words it differently for now.
    func testHighUsageNoticeNamesTheModel() {
        let notice = DuckAiHighUsageModelNotice(modelId: "claude-opus-4-8", modelShortName: "Opus 4.8")

        XCTAssertEqual(UserText.aiChatUsageWarningsHighUsageModel(notice.modelShortName),
                       "Opus 4.8 reaches usage limits 2-5x sooner than basic models.")
    }

    /// Only the model the web app calls high-usage, since the models payload carries no such field.
    func testOnlyOpusCountsAsHighUsage() {
        XCTAssertTrue(DuckAiHighUsageModels.includes("claude-opus-4-8"))
        XCTAssertFalse(DuckAiHighUsageModels.includes("claude-sonnet-4-6"))
        XCTAssertFalse(DuckAiHighUsageModels.includes(nil))
    }

    // MARK: - Create Image model switch notice

    func testWhenCreateImageSwitchesModels_ThenCopyNamesBothModels() {
        XCTAssertEqual(UserText.aiChatCreateImageModelSwitchTitle("GPT-5.4 mini"),
                       "Now using GPT-5.4 mini")
        XCTAssertEqual(UserText.aiChatCreateImageModelSwitchSubtitle("Mistral Small"),
                       "Mistral Small doesn't support image creation.")
    }

    func testWhenCreateImageSwitchesFromOSSModel_ThenCopyExplainsPrivacyChange() {
        XCTAssertEqual(UserText.aiChatCreateImageModelSwitchPrivacySubtitle("GPT-OSS"),
                       "GPT-OSS can't create images. Its extra privacy protections won't apply until you switch back.")
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
