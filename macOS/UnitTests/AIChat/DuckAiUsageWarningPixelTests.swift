//
//  DuckAiUsageWarningPixelTests.swift
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
import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

/// The event → pixel mapping. Each state has to land on its own series, and the combinations a state
/// cannot produce must report nothing rather than another state's.
final class DuckAiUsageWarningPixelTests: XCTestCase {

    private var pixelFiring: CapturingPixelFiring!
    private var sut: DuckAiUsageWarningPixelAdapter!

    override func setUp() {
        super.setUp()
        pixelFiring = CapturingPixelFiring()
        sut = DuckAiUsageWarningPixelAdapter(surface: .addressBar, pixelFiring: pixelFiring)
    }

    override func tearDown() {
        pixelFiring = nil
        sut = nil
        super.tearDown()
    }

    private var fired: [PixelKit.Event] { pixelFiring.firedPixels }

    func testAnApproachingCardReportsItsRungAndWindow() {
        sut.fire(.shown(approaching))

        XCTAssertEqual(fired.map(\.name), ["aichat_usage_warning_approaching_shown"])
        XCTAssertEqual(fired.first?.parameters?["window"], "weekly")
        XCTAssertEqual(fired.first?.parameters?["percent_bucket"], "75")
    }

    func testAReachedCardReportsItsWindowWithoutARung() {
        sut.fire(.shown(reached))

        XCTAssertEqual(fired.map(\.name), ["aichat_usage_warning_limit_reached_shown"])
        XCTAssertEqual(fired.first?.parameters?["window"], "daily")
        XCTAssertNil(fired.first?.parameters?["percent_bucket"])
    }

    /// The reached card carries no close button, so there is no series for this to land on.
    func testAReachedCardReportsNoDismissal() {
        sut.fire(.dismissed(reached))

        XCTAssertTrue(fired.isEmpty)
    }

    func testEachStateReportsItsFollowThroughUnderItsOwnName() {
        sut.fire(.promptSubmitted(approaching))
        sut.fire(.promptSubmitted(reached))
        sut.fire(.promptSubmitted(notice))
        sut.fire(.abandoned(approaching))
        sut.fire(.modelSwitched(reached))

        XCTAssertEqual(fired.map(\.name), [
            "aichat_usage_warning_approaching_prompt_submitted",
            "aichat_usage_warning_limit_reached_prompt_submitted",
            "aichat_high_usage_model_notice_prompt_submitted",
            "aichat_usage_warning_approaching_abandoned",
            "aichat_usage_warning_limit_reached_model_switched"
        ])
    }

    /// One series each: the CTA names itself, so the state it was offered from is a parameter.
    func testTheCTAsAreOneSeriesAcrossTheStatesOfferingThem() {
        sut.fire(.switchModelTapped(approaching))
        sut.fire(.upsellTapped(reached))

        XCTAssertEqual(fired.map(\.name), [
            "aichat_usage_warning_switch_model_tapped",
            "aichat_usage_warning_upsell_tapped"
        ])
        XCTAssertEqual(fired.first?.parameters?["percent_bucket"], "75")
    }

    func testTheHighUsageNoticeReportsTheModelItIsAbout() {
        sut.fire(.shown(notice))

        XCTAssertEqual(fired.map(\.name), ["aichat_high_usage_model_notice_shown"])
        XCTAssertEqual(fired.first?.parameters?["model_id"], "claude-opus-4-8")
        XCTAssertNil(fired.first?.parameters?["window"])
    }

    func testEveryPixelSaysWhichInputReportedIt() {
        let promptBar = DuckAiUsageWarningPixelAdapter(surface: .promptBar, pixelFiring: pixelFiring)

        sut.fire(.shown(approaching))
        promptBar.fire(.shown(approaching))

        XCTAssertEqual(fired.compactMap { $0.parameters?["surface"] }, ["address_bar", "prompt_bar"])
    }

    /// The definitions declare `first_daily_count`, which is this frequency.
    func testPixelsAreFiredDailyAndCount() {
        sut.fire(.shown(approaching))

        XCTAssertEqual(pixelFiring.firedFrequencies, [.dailyAndCount])
    }

    private var approaching: DuckAiUsageWarningExposure {
        DuckAiUsageWarningExposure(kind: .approaching, window: .weekly, percentBucket: 75)
    }

    private var reached: DuckAiUsageWarningExposure {
        DuckAiUsageWarningExposure(kind: .limitReached, window: .daily)
    }

    private var notice: DuckAiUsageWarningExposure {
        DuckAiUsageWarningExposure(kind: .highUsageModelNotice, modelId: "claude-opus-4-8")
    }
}

private final class CapturingPixelFiring: PixelFiring {

    private(set) var firedPixels: [PixelKit.Event] = []
    private(set) var firedFrequencies: [PixelKit.Frequency] = []

    func fire(event: PixelKit.Event,
              frequency: PixelKit.Frequency,
              options: PixelKit.Options,
              onComplete: @escaping PixelKit.CompletionBlock) {
        firedPixels.append(event)
        firedFrequencies.append(frequency)
        onComplete(true, nil)
    }
}
