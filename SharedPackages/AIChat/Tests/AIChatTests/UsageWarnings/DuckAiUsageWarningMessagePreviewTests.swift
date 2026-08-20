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

/// The preview is what the debug log is read from while there is no UI, so its wording is pinned against
/// the web banner it has to be comparable with.
final class DuckAiUsageWarningMessagePreviewTests: XCTestCase {

    func testApproachingMatchesTheWebBannerWording() {
        let preview = warning(kind: .approaching, window: .weekly, percent: 75).messagePreview

        XCTAssertEqual(preview.title, "75% of weekly limit · Resets in 4d")
        XCTAssertNil(preview.button)
    }

    func testApproachingWithACheaperModelCarriesTheButton() {
        let preview = warning(
            kind: .approaching,
            window: .weekly,
            percent: 75,
            suggestion: DuckAiCheaperModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: "5.6 Luna")
        ).messagePreview

        XCTAssertEqual(preview.title, "75% of weekly limit · Resets in 4d")
        XCTAssertEqual(preview.button, "Switch to 5.6 Luna")
    }

    /// Web pairs the CTA with a "Reduce usage with a more efficient model" subtitle. iOS and macOS
    /// deliberately don't, so the preview is title plus button and nothing else.
    func testThereIsNoSubtitleAlongsideTheCTA() {
        let preview = warning(
            kind: .approaching,
            window: .weekly,
            percent: 75,
            suggestion: DuckAiCheaperModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: "5.6 Luna")
        ).messagePreview

        XCTAssertFalse(preview.title.localizedCaseInsensitiveContains("efficient model"))
    }

    func testButtonFallsBackWhenTheModelHasNoShortName() {
        let preview = warning(
            kind: .approaching,
            window: .daily,
            percent: 60,
            suggestion: DuckAiCheaperModelSuggestion(modelId: "gpt-5.6-luna", modelShortName: nil)
        ).messagePreview

        XCTAssertEqual(preview.button, "Switch Model")
    }

    /// Reached is sticky and has nothing left to head off, so it carries neither reset copy nor a CTA.
    func testReachedIsJustTheHeadline() {
        let preview = warning(kind: .reached, window: .daily, percent: 100).messagePreview

        XCTAssertEqual(preview.title, "Daily limit reached")
        XCTAssertNil(preview.button)
    }

    private func warning(kind: DuckAiUsageWarning.Kind,
                         window: DuckAiUsageWindow,
                         percent: Int,
                         suggestion: DuckAiCheaperModelSuggestion? = nil) -> DuckAiUsageWarning {
        DuckAiUsageWarning(
            window: window,
            kind: kind,
            severity: kind == .reached ? .reached : .warning,
            percent: percent,
            resetsIn: .days(4),
            isDismissible: kind == .approaching,
            cheaperModelSuggestion: suggestion
        )
    }
}
