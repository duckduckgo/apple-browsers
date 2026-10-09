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

    /// Re-entering the open input (Plus → New Chat) must not count a second session.
    func testWhenTheDisclaimerIsOffThenTheSessionIsNotShownOnceAtStart() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)

        XCTAssertEqual(firing.events, [.sessionStarted(.notShown)])
    }

    func testWhenTheDisclaimerIsOnThenTheSessionIsShownOnceItRenders() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: true, isInputBlocked: false)
        XCTAssertEqual(firing.events, [])

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

    func testWhenSeveralPromptsAreSentThenOnlyTheFirstIsReportedAndTheSessionIsNotAbandoned() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: false, isInputBlocked: false)

        sut.promptSubmitted(.return)
        sut.promptSubmitted(.voice)
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.sessionStarted(.notShown), .promptSubmitted(.notShown, .return)])
    }

    func testWhenTheSessionEndsWithoutAPromptThenItIsAbandonedOnce() {
        sut.inputSessionStarted(hasAccepted: false, isDisclaimerEnabled: true, isInputBlocked: false)
        sut.disclaimerBecameVisible()

        sut.inputSessionEnded()
        sut.inputSessionEnded()

        XCTAssertEqual(firing.events, [.sessionStarted(.shown), .abandoned(.shown)])
    }

    func testEachEventHasItsDefinedPixelNameAndParameters() {
        let expected: [(DuckAiTermsOfServiceMeasurementEvent, String, [String: String])] = [
            (.sessionStarted(.shown), "aichat_terms_of_service_shown", ["surface": "s"]),
            (.sessionStarted(.notShown), "aichat_terms_of_service_not_shown", ["surface": "s"]),
            (.promptSubmitted(.shown, .ask), "aichat_terms_of_service_shown_prompt_submitted", ["surface": "s", "send_method": "ask"]),
            (.promptSubmitted(.notShown, .quickAction), "aichat_terms_of_service_not_shown_prompt_submitted",
             ["surface": "s", "send_method": "quick_action"]),
            (.abandoned(.shown), "aichat_terms_of_service_shown_abandoned", ["surface": "s"]),
            (.abandoned(.notShown), "aichat_terms_of_service_not_shown_abandoned", ["surface": "s"]),
            (.linkTapped, "aichat_terms_of_service_link_tapped", ["surface": "s"]),
            (.accepted(.nativeInput, isNativeDisclaimerEnabled: true), "aichat_terms_of_service_accepted",
             ["surface": "s", "source": "native_input", "native_disclaimer": "enabled"])
        ]
        for (event, name, parameters) in expected {
            XCTAssertEqual(event.pixelName, name)
            XCTAssertEqual(event.pixelParameters(surface: "s"), parameters, name)
        }
        XCTAssertEqual(DuckAiTermsOfServiceMeasurementEvent.accepted(.web, isNativeDisclaimerEnabled: false).pixelParameters(surface: nil),
                       ["source": "web", "native_disclaimer": "disabled"])
    }
}

private final class RecordingDuckAiTermsOfServicePixelFiring: DuckAiTermsOfServicePixelFiring {
    private(set) var events: [DuckAiTermsOfServiceMeasurementEvent] = []

    func fire(_ event: DuckAiTermsOfServiceMeasurementEvent) {
        events.append(event)
    }
}
