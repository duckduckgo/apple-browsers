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

/// The debug-log preview, which is what a decision is read off in the console. The platforms own the
/// localized copy; this pins the message-to-headline mapping in one place.
final class DuckAiUsageWarningMessagePreviewTests: XCTestCase {

    func testApproaching() {
        let preview = warning(.approaching, window: .daily, percent: 75).messagePreview

        XCTAssertEqual(preview.title, "75% of daily limit · Resets in 4d")
        XCTAssertNil(preview.button)
    }

    func testApproachingWeekly() {
        XCTAssertEqual(warning(.approaching, window: .weekly, percent: 90).messagePreview.title,
                       "90% of weekly limit · Resets in 4d")
    }

    func testApproachingWithACheaperModel() {
        let suggestion = DuckAiModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: "5.6 Luna")
        let preview = warning(.approaching, action: .switchToModel(suggestion)).messagePreview

        XCTAssertEqual(preview.button, "Switch to 5.6 Luna")
    }

    /// Better than printing an empty name into the button.
    func testSwitchFallsBackWhenTheModelHasNoShortName() {
        let suggestion = DuckAiModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: nil)

        XCTAssertEqual(warning(.approaching, action: .switchToModel(suggestion)).messagePreview.button,
                       "Switch Model")
    }

    func testDailyReached() {
        let entries = [DuckAiNativeStorageEntry(key: "duckai.a", value: "{}")]
        let preview = warning(.dailyReached, percent: 100,
                              action: .startUsingWeeklyLimit(entries: entries)).messagePreview

        XCTAssertEqual(preview.title, "Daily limit reached · Resets in 4d")
        XCTAssertEqual(preview.button, "Start using weekly limit")
    }

    /// Free users see the reached copy for whichever window ran out.
    func testFreeReachedFollowsItsWindow() {
        XCTAssertEqual(warning(.freeReached, window: .daily, percent: 100).messagePreview.title,
                       "Daily limit reached · Resets in 4d")
        XCTAssertEqual(warning(.freeReached, window: .weekly, percent: 100).messagePreview.title,
                       "Weekly usage limit reached · Resets in 4d")
    }

    func testTryForFreeCopyFollowsTrialEligibility() {
        XCTAssertEqual(warning(.freeReached, action: .tryForFree(isTrialEligible: true)).messagePreview.button,
                       "Try for free")
        XCTAssertEqual(warning(.freeReached, action: .tryForFree(isTrialEligible: false)).messagePreview.button,
                       "Subscribe")
    }

    func testWeeklyReachedHasNoCTA() {
        let preview = warning(.weeklyReached, window: .weekly, percent: 100).messagePreview

        XCTAssertEqual(preview.title, "Weekly usage limit reached · Resets in 4d")
        XCTAssertNil(preview.button)
    }

    func testWeeklyReachedDegraded() {
        let suggestion = DuckAiModelSuggestion(modelId: "mistral-small", modelShortName: "Mistral Small")
        let preview = warning(.weeklyReachedDegraded, window: .weekly, percent: 100,
                              action: .switchToFreeModel(suggestion)).messagePreview

        XCTAssertEqual(preview.title, "Advanced AI models limit reached · Resets in 4d")
        XCTAssertEqual(preview.button, "Switch to a Free Model")
    }

    /// iOS and macOS deliberately drop web's "Reduce usage with a more efficient model" subtitle.
    func testThereIsNoSubtitle() {
        let preview = warning(.approaching).messagePreview

        XCTAssertFalse(preview.title.contains("Reduce usage"))
    }

    // MARK: - Helpers

    private func warning(_ message: DuckAiUsageMessage,
                         window: DuckAiUsageWindow = .daily,
                         percent: Int = 75,
                         action: DuckAiUsageAction? = nil) -> DuckAiUsageWarning {
        DuckAiUsageWarning(window: window,
                           message: message,
                           percent: percent,
                           resetsIn: .days(4),
                           isDismissible: message == .approaching,
                           action: action,
                           offersModelPicker: action?.offersModelPicker ?? false)
    }
}
