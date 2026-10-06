//
//  OnboardingEndOfJourneyTryAIProviderTests.swift
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

import Testing
import Onboarding
@testable import DuckDuckGo

@MainActor
@Suite("Onboarding -  Search Flow Completion Provider")
struct OnboardingEndOfJourneyTryAIProviderTests {

    private func makeSUT(
        flow: OnboardingFlowType = .default,
        reason: OnboardingDownloadReason? = .browserPrivately,
        toggleEnabled: Bool = true,
        didStartAIChat: Bool = false
    ) -> OnboardingEndOfJourneyTryAIProvider {
        let manager = OnboardingManagerMock()
        manager.currentOnboardingFlow = flow
        manager.currentDownloadReason = reason
        let searchExperience = MockOnboardingSearchExperienceProvider()
        searchExperience.didEnableAIChatSearchInputDuringOnboarding = toggleEnabled
        searchExperience.didStartAIChatDuringOnboarding = didStartAIChat
        return OnboardingEndOfJourneyTryAIProvider(
            onboardingManager: manager,
            searchExperienceProvider: searchExperience
        )
    }

    @Test("Search-path reasons with the toggle on and Search return the chat completion content", arguments: [OnboardingDownloadReason.browserPrivately, .noAI, .blockAds])
    func qualifyingReasonsReturnContent(_ reason: OnboardingDownloadReason) {
        // GIVEN
        let sut = makeSUT(reason: reason, toggleEnabled: true)

        // WHEN
        let result = sut.dialogContent

        // THEN
        #expect(result == OnboardingEndOfJourneyTryAIContent(
            title: UserText.Onboarding.ContextualOnboarding.EndOfJourneyTryAI.title,
            message: UserText.Onboarding.ContextualOnboarding.EndOfJourneyTryAI.message,
            primaryCTA: UserText.Onboarding.ContextualOnboarding.EndOfJourneyTryAI.primaryButton,
            secondaryCTA: UserText.Onboarding.ContextualOnboarding.EndOfJourneyTryAI.secondaryButton
        ))
    }

    @Test("Returns nil when the user already started an AI chat during onboarding", arguments: [OnboardingDownloadReason.browserPrivately, .noAI, .blockAds])
    func alreadyTriedAIReturnsNil(_ reason: OnboardingDownloadReason) {
        // GIVEN
        let sut = makeSUT(reason: reason, toggleEnabled: true, didStartAIChat: true)

        // WHEN
        let result = sut.dialogContent

        // THEN
        #expect(result == nil)
    }

    @Test("shouldPresentTryAIDialog tracks the content gate", arguments: zip([OnboardingDownloadReason.browserPrivately, .privateAIChat], [true, false]))
    func shouldPresentTryAIDialogTracksContentGate(_ reason: OnboardingDownloadReason, expectedShouldPresentTryDialog: Bool) {
        // GIVEN
        let sut = makeSUT(reason: reason, toggleEnabled: true)

        // WHEN
        let result = sut.shouldPresentTryAIDialog

        // THEN
        #expect(result == expectedShouldPresentTryDialog)
    }

    @Test("Toggle off returns nil", arguments: [OnboardingDownloadReason.browserPrivately, .noAI, .blockAds])
    func toggleOffReturnsNil(_ reason: OnboardingDownloadReason) {
        // GIVEN
        let sut = makeSUT(reason: reason, toggleEnabled: false)

        // WHEN
        let result = sut.dialogContent

        // THEN
        #expect(result == nil)
    }

    @Test("privateAIChat reason returns nil (AI Chat path keeps its own completion)")
    func privateAIChatReturnsNil() {
        // GIVEN
        let sut = makeSUT(reason: .privateAIChat, toggleEnabled: true)

        // WHEN
        let result = sut.dialogContent

        // THEN
        #expect(result == nil)
    }

    @Test("No download reason returns nil (control arm / not enrolled)")
    func noReasonReturnsNil() {
        // GIVEN
        let sut = makeSUT(reason: nil, toggleEnabled: true)

        // WHEN
        let result = sut.dialogContent

        // THEN
        #expect(result == nil)
    }

    @Test("Duck.ai CPP flow returns nil even for a search-path reason with the toggle on")
    func duckAIFlowReturnsNil() {
        // GIVEN
        let sut = makeSUT(flow: .duckAI, reason: .browserPrivately, toggleEnabled: true)

        // WHEN
        let result = sut.dialogContent

        // THEN
        #expect(result == nil)
    }
}
