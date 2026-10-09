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

struct DuckAiInputOutcomeMeasurementTests {

    private let firing = RecordingDuckAiInputOutcomePixelFiring()
    private let sut: DuckAiInputOutcomeMeasurement

    init() {
        sut = DuckAiInputOutcomeMeasurement(pixelFiring: firing)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenAPromptIsSentThenItIsReportedOnceWithItsMethod() {
        sut.inputOpened(surface: .addressBar, isTermsOfServiceDisclaimerShown: true)

        sut.record(.promptSubmitted(.button))
        sut.record(.promptSubmitted(.enter))
        sut.inputClosed()

        #expect(firing.events == [
            DuckAiInputOutcomeEvent(surface: .addressBar, isTermsOfServiceDisclaimerShown: true, outcome: .promptSubmitted(.button))
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenTheInputClosesWithoutAnOutcomeThenItIsReportedAbandonedOnce() {
        sut.inputOpened(surface: .promptBar, isTermsOfServiceDisclaimerShown: false)

        sut.inputClosed()
        sut.inputClosed()

        #expect(firing.events == [
            DuckAiInputOutcomeEvent(surface: .promptBar, isTermsOfServiceDisclaimerShown: false, outcome: .abandoned)
        ])
    }

    /// Callers re-sync on every state change, so a second opening must not replace the open input's surface or disclaimer state.
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenTheInputIsOpenThenAnotherOpeningIsIgnored() {
        sut.inputOpened(surface: .duckAI, isTermsOfServiceDisclaimerShown: false)
        sut.inputOpened(surface: .addressBar, isTermsOfServiceDisclaimerShown: true)

        sut.record(.voiceStarted)

        #expect(firing.events == [
            DuckAiInputOutcomeEvent(surface: .duckAI, isTermsOfServiceDisclaimerShown: false, outcome: .voiceStarted)
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenTheDisclaimerRendersWhileOpenThenItIsReportedShown() {
        sut.inputOpened(surface: .contextualChat, isTermsOfServiceDisclaimerShown: false)

        sut.termsOfServiceDisclaimerBecameVisible()
        sut.inputClosed()

        #expect(firing.events.map(\.isTermsOfServiceDisclaimerShown) == [true])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenNoInputIsOpenThenNothingIsReported() {
        sut.termsOfServiceDisclaimerBecameVisible()
        sut.record(.promptSubmitted(.button))
        sut.record(.voiceStarted)
        sut.inputClosed()

        #expect(firing.events.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenTheNextOpeningClosesThenItReportsItsOwnOutcome() {
        sut.inputOpened(surface: .addressBar, isTermsOfServiceDisclaimerShown: true)
        sut.record(.promptSubmitted(.button))
        sut.inputClosed()

        sut.inputOpened(surface: .addressBar, isTermsOfServiceDisclaimerShown: false)
        sut.inputClosed()

        #expect(firing.events.map(\.outcome) == [.promptSubmitted(.button), .abandoned])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenAPromptIsReportedThenTheParametersCarryTheSubmitMethod() {
        let event = DuckAiInputOutcomeEvent(surface: .contextualChat, isTermsOfServiceDisclaimerShown: true, outcome: .promptSubmitted(.other))

        #expect(event.parameters == [
            "surface": "contextual_chat",
            "tos_disclaimer_shown": "true",
            "outcome": "prompt_submitted",
            "submit_method": "other"
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenASuggestedPromptIsReportedThenTheParametersHaveNoSubmitMethod() {
        let event = DuckAiInputOutcomeEvent(surface: .contextualChat, isTermsOfServiceDisclaimerShown: true, outcome: .suggestedPrompt)

        #expect(event.parameters == [
            "surface": "contextual_chat",
            "tos_disclaimer_shown": "true",
            "outcome": "suggested_prompt"
        ])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func whenTheInputIsAbandonedThenTheParametersHaveNoSubmitMethod() {
        let event = DuckAiInputOutcomeEvent(surface: .promptBar, isTermsOfServiceDisclaimerShown: false, outcome: .abandoned)

        #expect(event.parameters == [
            "surface": "promptbar",
            "tos_disclaimer_shown": "false",
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
