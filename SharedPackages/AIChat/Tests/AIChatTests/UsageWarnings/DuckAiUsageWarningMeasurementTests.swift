//
//  DuckAiUsageWarningMeasurementTests.swift
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

final class DuckAiUsageWarningMeasurementTests: XCTestCase {

    private var firing: RecordingDuckAiUsageWarningPixelFiring!
    private var sut: DuckAiUsageWarningMeasurement!

    private let approaching = DuckAiUsageWarningExposure(kind: .approaching, window: .weekly, percentBucket: 75)
    private let limitReached = DuckAiUsageWarningExposure(kind: .limitReached, window: .weekly)
    private let notice = DuckAiUsageWarningExposure(kind: .highUsageModelNotice, modelId: "claude-opus-4-8")

    override func setUp() {
        super.setUp()
        firing = RecordingDuckAiUsageWarningPixelFiring()
        sut = DuckAiUsageWarningMeasurement(pixelFiring: firing)
    }

    override func tearDown() {
        sut = nil
        firing = nil
        super.tearDown()
    }

    // MARK: - Impressions

    func testWhenTheCardBecomesVisibleThenItIsReportedAsShown() {
        sut.cardBecameVisible(approaching)

        XCTAssertEqual(firing.events, [.shown(approaching)])
    }

    /// A refresh mid-expand can re-apply the same rung once the models land and the CTA copy fills
    /// in; that is one appearance, not two.
    func testWhenTheSameCardBecomesVisibleAgainThenItIsNotReportedTwice() {
        sut.cardBecameVisible(approaching)
        sut.cardBecameVisible(approaching)

        XCTAssertEqual(firing.events, [.shown(approaching)])
    }

    func testWhenADifferentRungBecomesVisibleThenItIsReportedAsANewImpression() {
        let ninety = DuckAiUsageWarningExposure(kind: .approaching, window: .weekly, percentBucket: 90)

        sut.cardBecameVisible(approaching)
        sut.cardBecameVisible(ninety)

        XCTAssertEqual(firing.events, [.shown(approaching), .abandoned(approaching), .shown(ninety)])
    }

    // MARK: - Terminal outcome

    func testWhenTheInputSessionEndsWithNoFollowUpThenTheExposureIsReportedAsAbandoned() {
        sut.cardBecameVisible(limitReached)

        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.shown(limitReached), .abandoned(limitReached)])
    }

    func testWhenTheInputSessionEndsTwiceThenAbandonedIsReportedOnce() {
        sut.cardBecameVisible(limitReached)

        sut.inputSessionEnded()
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.shown(limitReached), .abandoned(limitReached)])
    }

    func testWhenAPromptIsSubmittedThenTheExposureIsNotReportedAsAbandoned() {
        sut.cardBecameVisible(approaching)

        sut.promptSubmitted()
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.shown(approaching), .promptSubmitted(approaching)])
    }

    func testWhenTwoPromptsAreSubmittedInOneSessionThenOnlyTheFirstIsReported() {
        sut.cardBecameVisible(approaching)

        sut.promptSubmitted()
        sut.promptSubmitted()

        XCTAssertEqual(firing.events, [.shown(approaching), .promptSubmitted(approaching)])
    }

    func testWhenTheUserSwitchesModelThenTheExposureIsReportedAsAModelSwitch() {
        sut.cardBecameVisible(notice)

        sut.modelSwitched()
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.shown(notice), .modelSwitched(notice)])
    }

    func testWhenTheUserBothSwitchesModelAndPromptsThenBothAreReported() {
        sut.cardBecameVisible(approaching)

        sut.modelSwitched()
        sut.promptSubmitted()
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.shown(approaching), .modelSwitched(approaching), .promptSubmitted(approaching)])
    }

    func testWhenNothingHasBeenShownThenAFollowUpReportsNothing() {
        sut.promptSubmitted()
        sut.modelSwitched()
        sut.warningDismissed()
        sut.inputSessionEnded()

        XCTAssertTrue(firing.events.isEmpty)
    }

    // MARK: - Dismissal

    func testWhenTheCardIsDismissedThenItIsReportedAsDismissed() {
        sut.cardBecameVisible(approaching)

        sut.warningDismissed()

        XCTAssertEqual(firing.events, [.shown(approaching), .dismissed(approaching)])
    }

    /// Dismissal is not a terminal outcome: the input session carries on, and a prompt that follows
    /// still belongs to the warning the user saw.
    func testWhenTheCardIsDismissedAndAPromptFollowsThenBothAreReported() {
        sut.cardBecameVisible(approaching)

        sut.warningDismissed()
        sut.promptSubmitted()
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.shown(approaching), .dismissed(approaching), .promptSubmitted(approaching)])
    }

    func testWhenTheCardIsDismissedAndNothingFollowsThenTheExposureIsReportedAsAbandoned() {
        sut.cardBecameVisible(approaching)

        sut.warningDismissed()
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.shown(approaching), .dismissed(approaching), .abandoned(approaching)])
    }

    // MARK: - CTAs

    func testWhenTheSwitchModelCTAIsTappedThenItIsReported() {
        sut.cardBecameVisible(approaching)

        sut.ctaTapped(.switchModel)

        XCTAssertEqual(firing.events, [.shown(approaching), .switchModelTapped(approaching)])
    }

    func testWhenTheUpsellCTAIsTappedThenItIsReported() {
        sut.cardBecameVisible(limitReached)

        sut.ctaTapped(.upsell)

        XCTAssertEqual(firing.events, [.shown(limitReached), .upsellTapped(limitReached)])
    }

    /// The switch the CTA performs is already reported as a CTA tap; reporting it again as a
    /// self-initiated switch would double-count it.
    func testWhenTheSwitchFollowsTheCardsOwnCTAThenItIsNotAlsoReportedAsAModelSwitch() {
        sut.cardBecameVisible(approaching)

        sut.ctaTapped(.switchModel)
        sut.modelSwitched()
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.shown(approaching), .switchModelTapped(approaching)])
    }

    func testWhenACTAIsTappedThenTheExposureIsNotReportedAsAbandoned() {
        sut.cardBecameVisible(limitReached)

        sut.ctaTapped(.upsell)
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.shown(limitReached), .upsellTapped(limitReached)])
    }

    // MARK: - Exposure from the resolved message

    func testWhenTheWarningIsApproachingThenTheExposureCarriesTheRungItIsShownAt() {
        XCTAssertEqual(DuckAiUsageWarningExposure(warning: warning(message: .approaching, percent: 75)).percentBucket, 75)
        XCTAssertEqual(DuckAiUsageWarningExposure(warning: warning(message: .approaching, percent: 99)).percentBucket, 90)
        XCTAssertEqual(DuckAiUsageWarningExposure(warning: warning(message: .approaching, percent: 50)).percentBucket, 50)
    }

    func testWhenTheWarningIsApproachingThenTheExposureCarriesItsWindow() {
        let exposure = DuckAiUsageWarningExposure(warning: warning(message: .approaching, percent: 75, window: .daily))

        XCTAssertEqual(exposure.kind, .approaching)
        XCTAssertEqual(exposure.window, .daily)
    }

    /// A reached limit has no rung: it is not on the approaching ladder.
    func testWhenTheLimitIsReachedThenTheExposureCarriesNoRung() {
        let exposure = DuckAiUsageWarningExposure(warning: warning(message: .weeklyReached, percent: 100))

        XCTAssertEqual(exposure.kind, .limitReached)
        XCTAssertEqual(exposure.window, .weekly)
        XCTAssertNil(exposure.percentBucket)
    }

    func testWhenTheNoticeIsForAHighUsageModelThenTheExposureCarriesTheModelId() {
        let exposure = DuckAiUsageWarningExposure(notice: DuckAiHighUsageModelNotice(modelId: "claude-opus-4-8",
                                                                                     modelShortName: "Opus 4.8"))

        XCTAssertEqual(exposure.kind, .highUsageModelNotice)
        XCTAssertEqual(exposure.modelId, "claude-opus-4-8")
        XCTAssertNil(exposure.window)
        XCTAssertNil(exposure.percentBucket)
    }

    // MARK: - Helpers

    private func warning(message: DuckAiUsageMessage,
                         percent: Int,
                         window: DuckAiUsageWindow = .weekly) -> DuckAiUsageWarning {
        DuckAiUsageWarning(window: window,
                           message: message,
                           severity: message == .approaching ? .warning : .reached,
                           percent: percent,
                           resetsIn: .days(2),
                           isDismissible: message == .approaching)
    }
}

// MARK: - Test doubles

private final class RecordingDuckAiUsageWarningPixelFiring: DuckAiUsageWarningPixelFiring {

    private(set) var events: [DuckAiUsageWarningMeasurementEvent] = []

    func fire(_ event: DuckAiUsageWarningMeasurementEvent) {
        events.append(event)
    }
}
