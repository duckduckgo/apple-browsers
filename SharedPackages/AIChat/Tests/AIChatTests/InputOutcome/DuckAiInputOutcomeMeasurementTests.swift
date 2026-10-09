//
//  DuckAiInputOutcomeMeasurementTests.swift
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

import Foundation
import Testing
@testable import AIChat

@available(iOS 16, macOS 13, *)
@Suite(.timeLimit(.minutes(1)))
struct DuckAiInputOutcomeMeasurementTests {

    private let firing = RecordingDuckAiInputOutcomePixelFiring()
    private let sut: DuckAiInputOutcomeMeasurement

    init() {
        sut = DuckAiInputOutcomeMeasurement(pixelFiring: firing)
    }

    @Test
    func whenAPromptIsSentThenItIsReportedOnceWithItsMethod() {
        sut.inputOpened(surface: .addressBar, termsState: .notAccepted, isDisclaimerShown: true)

        sut.promptSubmitted(.button)
        sut.promptSubmitted(.enter)
        sut.inputClosed()

        #expect(firing.events == [
            DuckAiInputOutcomeEvent(surface: .addressBar, isDisclaimerShown: true, termsState: .notAccepted, outcome: .promptSubmitted(.button))
        ])
    }

    @Test
    func whenTheInputClosesWithoutAnOutcomeThenItIsReportedAbandonedOnce() {
        sut.inputOpened(surface: .promptBar, termsState: .accepted, isDisclaimerShown: false)

        sut.inputClosed()
        sut.inputClosed()

        #expect(firing.events == [
            DuckAiInputOutcomeEvent(surface: .promptBar, isDisclaimerShown: false, termsState: .accepted, outcome: .abandoned)
        ])
    }

    /// Callers re-sync on every state change, so a second opening must not replace the open input's surface or state.
    @Test
    func whenTheInputIsOpenThenAnotherOpeningIsIgnored() {
        sut.inputOpened(surface: .duckAI, termsState: .notAccepted, isDisclaimerShown: false)
        sut.inputOpened(surface: .addressBar, termsState: .accepted, isDisclaimerShown: true)

        sut.voiceStarted()

        #expect(firing.events == [
            DuckAiInputOutcomeEvent(surface: .duckAI, isDisclaimerShown: false, termsState: .notAccepted, outcome: .voiceStarted)
        ])
    }

    @Test
    func whenTheDisclaimerRendersWhileOpenThenItIsReportedShown() {
        sut.inputOpened(surface: .contextualChat, termsState: .notAccepted, isDisclaimerShown: false)

        sut.disclaimerBecameVisible()
        sut.inputClosed()

        #expect(firing.events.map(\.isDisclaimerShown) == [true])
    }

    @Test
    func whenNoInputIsOpenThenNothingIsReported() {
        sut.disclaimerBecameVisible()
        sut.promptSubmitted(.button)
        sut.voiceStarted()
        sut.inputClosed()

        #expect(firing.events.isEmpty)
    }

    @Test
    func whenTheNextOpeningClosesThenItReportsItsOwnOutcome() {
        sut.inputOpened(surface: .addressBar, termsState: .notAccepted, isDisclaimerShown: true)
        sut.promptSubmitted(.button)
        sut.inputClosed()

        sut.inputOpened(surface: .addressBar, termsState: .accepted, isDisclaimerShown: false)
        sut.inputClosed()

        #expect(firing.events.map(\.outcome) == [.promptSubmitted(.button), .abandoned])
    }

    @Test
    func whenTheNativeDisclaimerIsOffThenTheTermsStateIsUnknown() {
        #expect(DuckAiInputTermsState(isNativeDisclaimerEnabled: false, hasAccepted: true) == .unknown)
        #expect(DuckAiInputTermsState(isNativeDisclaimerEnabled: true, hasAccepted: true) == .accepted)
        #expect(DuckAiInputTermsState(isNativeDisclaimerEnabled: true, hasAccepted: false) == .notAccepted)
    }

    @Test
    func whenAPromptIsReportedThenTheParametersCarryTheSubmitMethod() {
        let event = DuckAiInputOutcomeEvent(surface: .contextualChat, isDisclaimerShown: true, termsState: .notAccepted, outcome: .promptSubmitted(.other))

        #expect(event.parameters == [
            "surface": "contextual_chat",
            "disclaimer_shown": "true",
            "terms_state": "not_accepted",
            "outcome": "prompt_submitted",
            "submit_method": "other"
        ])
    }

    @Test
    func whenTheInputIsAbandonedThenTheParametersHaveNoSubmitMethod() {
        let event = DuckAiInputOutcomeEvent(surface: .promptBar, isDisclaimerShown: false, termsState: .unknown, outcome: .abandoned)

        #expect(event.parameters == [
            "surface": "promptbar",
            "disclaimer_shown": "false",
            "terms_state": "unknown",
            "outcome": "abandoned"
        ])
    }
}

private final class RecordingDuckAiInputOutcomePixelFiring: DuckAiInputOutcomePixelFiring {
    private(set) var events: [DuckAiInputOutcomeEvent] = []

    func fire(_ event: DuckAiInputOutcomeEvent) {
        events.append(event)
    }
}
