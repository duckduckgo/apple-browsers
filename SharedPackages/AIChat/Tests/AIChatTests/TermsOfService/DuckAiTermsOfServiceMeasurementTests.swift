//
//  DuckAiTermsOfServiceMeasurementTests.swift
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

final class DuckAiTermsOfServiceMeasurementTests: XCTestCase {

    private var firing: RecordingDuckAiTermsOfServicePixelFiring!
    private var sut: DuckAiTermsOfServiceMeasurement!

    override func setUp() {
        super.setUp()
        firing = RecordingDuckAiTermsOfServicePixelFiring()
        sut = DuckAiTermsOfServiceMeasurement(pixelFiring: firing)
    }

    override func tearDown() {
        sut = nil
        firing = nil
        super.tearDown()
    }

    // MARK: - Groups

    func testWhenTheDisclaimerIsOffThenTheSessionIsReportedAsNotShownAtStart() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)

        XCTAssertEqual(firing.events, [.sessionStarted(.notShown)])
    }

    func testWhenTheDisclaimerIsOnThenNothingIsReportedUntilItRenders() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: true, isInputBlocked: false)
        XCTAssertEqual(firing.events, [])

        sut.disclaimerBecameVisible()

        XCTAssertEqual(firing.events, [.sessionStarted(.shown)])
    }

    func testWhenTheDisclaimerRendersAgainInTheSameSessionThenShownIsReportedOnce() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: true, isInputBlocked: false)

        sut.disclaimerBecameVisible()
        sut.disclaimerBecameVisible()

        XCTAssertEqual(firing.events, [.sessionStarted(.shown)])
    }

    func testWhenTheUserHasAcceptedThenNoSessionIsMeasured() {
        sut.inputSessionStarted(hasAccepted: true, isDisclaimerEnabled: false, isInputBlocked: false)
        sut.promptSubmitted(.ask)
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [])
    }

    /// The disclaimer never shows over a blocked input, so the control group leaves those sessions out too.
    func testWhenTheInputIsBlockedWithTheDisclaimerOffThenNoSessionIsMeasured() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: true)
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [])
    }

    func testWhenTheDisclaimerNeverRendersThenTheSessionEndsSilently() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: true, isInputBlocked: true)
        sut.promptSubmitted(.ask)
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [])
    }

    func testWhenTheDisclaimerRendersOutsideASessionThenNothingIsReported() {
        sut.disclaimerBecameVisible()

        XCTAssertEqual(firing.events, [])
    }

    func testWhenASessionStartsWhileOneIsOpenThenTheOpenOneIsKept() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)

        XCTAssertEqual(firing.events, [.sessionStarted(.notShown)])
    }

    // MARK: - Outcomes

    func testWhenAPromptIsSentThenItIsReportedWithTheSessionsGroupAndSendMethod() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: true, isInputBlocked: false)
        sut.disclaimerBecameVisible()

        sut.promptSubmitted(.ask)
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.sessionStarted(.shown), .promptSubmitted(.shown, .ask)])
    }

    func testWhenSeveralPromptsAreSentThenOnlyTheFirstIsReported() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)

        sut.promptSubmitted(.return)
        sut.promptSubmitted(.voice)

        XCTAssertEqual(firing.events, [.sessionStarted(.notShown), .promptSubmitted(.notShown, .return)])
    }

    func testWhenTheSessionEndsWithoutAPromptThenItIsReportedAsAbandoned() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)

        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.sessionStarted(.notShown), .abandoned(.notShown)])
    }

    func testWhenTheSessionEndsTwiceThenAbandonedIsReportedOnce() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: true, isInputBlocked: false)
        sut.disclaimerBecameVisible()

        sut.inputSessionEnded()
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.sessionStarted(.shown), .abandoned(.shown)])
    }

    func testWhenANewSessionStartsAfterOneEndsThenItIsMeasuredAgain() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)
        sut.inputSessionEnded()

        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)
        sut.promptSubmitted(.quickAction)

        XCTAssertEqual(firing.events, [.sessionStarted(.notShown), .abandoned(.notShown),
                                       .sessionStarted(.notShown), .promptSubmitted(.notShown, .quickAction)])
    }

    // MARK: - Link and acceptance

    func testWhenTheLinkIsTappedThenItIsReported() {
        sut.linkTapped()

        XCTAssertEqual(firing.events, [.linkTapped])
    }

    func testWhenAcceptedInTheNativeInputThenItIsReportedWithTheDisclaimerEnabled() {
        sut.acceptedInNativeInput()

        XCTAssertEqual(firing.events, [.accepted(.nativeInput, isNativeDisclaimerEnabled: true)])
    }
}

private final class RecordingDuckAiTermsOfServicePixelFiring: DuckAiTermsOfServicePixelFiring {
    private(set) var events: [DuckAiTermsOfServiceMeasurementEvent] = []

    func fire(_ event: DuckAiTermsOfServiceMeasurementEvent) {
        events.append(event)
    }
}
