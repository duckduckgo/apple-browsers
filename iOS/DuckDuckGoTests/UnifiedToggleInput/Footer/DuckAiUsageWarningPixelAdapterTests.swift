//
//  DuckAiUsageWarningPixelAdapterTests.swift
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
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAiUsageWarningPixelAdapterTests: XCTestCase {

    private var pixelKitMock: PixelKitMock!
    private var surface: UnifiedToggleInputPixelSurface = .duckAI
    private var sut: DuckAiUsageWarningPixelAdapter!

    private let approaching = DuckAiUsageWarningExposure(kind: .approaching, window: .weekly, percentBucket: 75)
    private let limitReached = DuckAiUsageWarningExposure(kind: .limitReached, window: .daily)
    private let notice = DuckAiUsageWarningExposure(kind: .highUsageModelNotice, modelId: "claude-opus-4-8")

    override func setUp() {
        super.setUp()
        pixelKitMock = PixelKitMock()
        surface = .duckAI
        sut = DuckAiUsageWarningPixelAdapter(firing: UTIPixelFiring(pixelKit: { [unowned self] in pixelKitMock }),
                                            surface: { [unowned self] in surface })
    }

    override func tearDown() {
        sut = nil
        pixelKitMock = nil
        super.tearDown()
    }

    // MARK: - Approaching

    func testWhenAnApproachingWarningIsShownThenItReportsTheRungAndWindow() {
        sut.fire(.shown(approaching))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_approaching_shown"])
        XCTAssertEqual(lastParameters, ["surface": "duck_ai", "window": "weekly", "percent_bucket": "75"])
    }

    func testWhenAnApproachingWarningIsDismissedThenItIsReportedUnderItsOwnName() {
        sut.fire(.dismissed(approaching))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_approaching_dismissed"])
    }

    func testWhenAnApproachingWarningLeadsToAPromptThenItIsReportedUnderItsOwnName() {
        sut.fire(.promptSubmitted(approaching))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_approaching_prompt_submitted"])
    }

    func testWhenAnApproachingWarningLeadsToAModelSwitchThenItIsReportedUnderItsOwnName() {
        sut.fire(.modelSwitched(approaching))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_approaching_model_switched"])
    }

    func testWhenAnApproachingWarningLeadsNowhereThenItIsReportedUnderItsOwnName() {
        sut.fire(.abandoned(approaching))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_approaching_abandoned"])
    }

    // MARK: - Limit reached

    /// A reached limit is not on the approaching ladder, so it reports no rung.
    func testWhenAReachedLimitIsShownThenItReportsTheWindowWithoutARung() {
        sut.fire(.shown(limitReached))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_limit_reached_shown"])
        XCTAssertEqual(lastParameters, ["surface": "duck_ai", "window": "daily"])
    }

    func testWhenAReachedLimitLeadsToAPromptThenItIsReportedUnderItsOwnName() {
        sut.fire(.promptSubmitted(limitReached))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_limit_reached_prompt_submitted"])
    }

    func testWhenAReachedLimitLeadsToAModelSwitchThenItIsReportedUnderItsOwnName() {
        sut.fire(.modelSwitched(limitReached))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_limit_reached_model_switched"])
    }

    func testWhenAReachedLimitLeadsNowhereThenItIsReportedUnderItsOwnName() {
        sut.fire(.abandoned(limitReached))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_limit_reached_abandoned"])
    }

    /// A reached limit has no close button, so there is no pixel to report — and no silent misfire
    /// under another name either.
    func testWhenAReachedLimitReportsADismissalThenNothingIsFired() {
        sut.fire(.dismissed(limitReached))

        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
    }

    // MARK: - CTAs

    func testWhenTheSwitchModelCTAIsTappedThenItIsReportedWithTheRungItWasOfferedAt() {
        sut.fire(.switchModelTapped(approaching))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_switch_model_tapped"])
        XCTAssertEqual(lastParameters, ["surface": "duck_ai", "window": "weekly", "percent_bucket": "75"])
    }

    func testWhenTheUpsellCTAIsTappedThenItIsReportedWithItsWindow() {
        sut.fire(.upsellTapped(limitReached))

        XCTAssertEqual(firedNames, ["aichat_usage_warning_upsell_tapped"])
        XCTAssertEqual(lastParameters, ["surface": "duck_ai", "window": "daily"])
    }

    // MARK: - High-usage model notice

    func testWhenTheHighUsageNoticeIsShownThenItReportsTheModelItIsAbout() {
        sut.fire(.shown(notice))

        XCTAssertEqual(firedNames, ["aichat_high_usage_model_notice_shown"])
        XCTAssertEqual(lastParameters, ["surface": "duck_ai", "model_id": "claude-opus-4-8"])
    }

    func testWhenTheHighUsageNoticeIsDismissedThenItIsReportedUnderItsOwnName() {
        sut.fire(.dismissed(notice))

        XCTAssertEqual(firedNames, ["aichat_high_usage_model_notice_dismissed"])
    }

    func testWhenTheHighUsageNoticeLeadsToAModelSwitchThenItIsReportedUnderItsOwnName() {
        sut.fire(.modelSwitched(notice))

        XCTAssertEqual(firedNames, ["aichat_high_usage_model_notice_model_switched"])
    }

    func testWhenTheHighUsageNoticeLeadsToAPromptThenItIsReportedUnderItsOwnName() {
        sut.fire(.promptSubmitted(notice))

        XCTAssertEqual(firedNames, ["aichat_high_usage_model_notice_prompt_submitted"])
    }

    func testWhenTheHighUsageNoticeLeadsNowhereThenItIsReportedUnderItsOwnName() {
        sut.fire(.abandoned(notice))

        XCTAssertEqual(firedNames, ["aichat_high_usage_model_notice_abandoned"])
    }

    // MARK: - Firing

    func testWhenAWarningPixelIsFiredThenItIsSentAsADailyAndCountPixel() {
        sut.fire(.shown(approaching))

        XCTAssertEqual(pixelKitMock.actualFireCalls.last?.frequency, .dailyAndCount)
    }

    /// One coordinator serves the address bar, the Duck.ai tab and the contextual sheet, so the
    /// surface has to be read when the pixel fires rather than when the adapter is built.
    func testWhenTheSurfaceChangesThenTheNextPixelReportsTheNewSurface() {
        sut.fire(.shown(approaching))
        surface = .contextualChat

        sut.fire(.shown(limitReached))

        XCTAssertEqual(lastParameters?["surface"], "contextual_chat")
    }

    // MARK: - Helpers

    private var firedNames: [String] {
        pixelKitMock.actualFireCalls.map(\.pixel.name)
    }

    private var lastParameters: [String: String]? {
        pixelKitMock.actualFireCalls.last?.pixel.parameters
    }
}
