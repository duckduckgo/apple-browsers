//
//  ContextualOnboardingContentProviderTests.swift
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
@Suite("Onboarding - Contextual Content Provider")
struct ContextualOnboardingContentProviderTests {

    private func makeSUT(
        tryAIContent: OnboardingEndOfJourneyTryAIContent? = nil,
        reason: OnboardingDownloadReason? = nil,
        didStartAIChat: Bool = false
    ) -> ContextualOnboardingContentProvider {
        let manager = OnboardingManagerMock()
        manager.currentDownloadReason = reason
        let searchExperience = MockOnboardingSearchExperienceProvider()
        searchExperience.didStartAIChatDuringOnboarding = didStartAIChat
        return ContextualOnboardingContentProvider(
            tryAIContentProvider: StubTryAIContentProvider(dialogContent: tryAIContent),
            downloadReasonProvider: manager,
            searchExperienceProvider: searchExperience
        )
    }

    @Test("Try-AI content present returns the Try-AI variant")
    func tryAIContentPresentReturnsTryAIVariant() {
        // GIVEN
        let tryAIContent = OnboardingEndOfJourneyTryAIContent(title: "Title", message: "Message", primaryCTA: "Primary", secondaryCTA: "Secondary")
        let sut = makeSUT(tryAIContent: tryAIContent, reason: .browserPrivately)

        // WHEN
        let content = sut.endOfJourneyContent

        // THEN
        #expect(content.icon == .duckAI)
        #expect(content.title == "Title")
        #expect(content.message == "Message")
        #expect(content.primaryCTA == "Primary")
        #expect(content.primaryAction == .tryDuckAI)
        #expect(content.secondaryCTA == "Secondary")
        #expect(content.secondaryAction == .skip)
        #expect(content.isManuallyDismissable == false)
    }

    @Test("privateAIChat reason returns the AI-flavored completion")
    func privateAIChatReasonReturnsAIMessage() {
        // GIVEN
        let sut = makeSUT(reason: .privateAIChat, didStartAIChat: false)

        // WHEN
        let content = sut.endOfJourneyContent

        // THEN
        #expect(content.icon == nil)
        #expect(content.message == UserText.Onboarding.ContextualOnboarding.EndOfJourney.aiMessage)
        #expect(content.primaryAction == .completeAndActivateSearch)
        #expect(content.isManuallyDismissable == true)
    }

    @Test("Experiment users who started an AI chat get the experiment AI copy", arguments: [OnboardingDownloadReason.browserPrivately, .noAI, .blockAds])
    func experimentUserDidStartAIChatReturnsAIMessage(_ reason: OnboardingDownloadReason) {
        // GIVEN — a download reason means the user is in the download-reason experiment.
        let sut = makeSUT(reason: reason, didStartAIChat: true)

        // WHEN
        let content = sut.endOfJourneyContent

        // THEN
        #expect(content.message == UserText.Onboarding.ContextualOnboarding.EndOfJourney.aiMessage)
    }

    @Test("Non-experiment users who started an AI chat get the localized Duck.ai completion copy")
    func nonExperimentUserDidStartAIChatReturnsLocalizedCompletion() {
        // GIVEN — no download reason means the user is not in the download-reason experiment.
        let sut = makeSUT(reason: nil, didStartAIChat: true)

        // WHEN
        let content = sut.endOfJourneyContent

        // THEN
        #expect(content.message == UserText.Onboarding.DuckAIQuery.completionOnboardingMessage)
    }

    @Test("Non-experiment users who did not start an AI chat get the standard completion")
    func nonExperimentUserNoChatReturnsStandardMessage() {
        // GIVEN
        let sut = makeSUT(reason: nil, didStartAIChat: false)

        // WHEN
        let content = sut.endOfJourneyContent

        // THEN
        #expect(content.message == UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenMessage)
    }

    @Test("No Try-AI, no privateAIChat, no AI chat returns the standard completion")
    func noAISignalsReturnsStandardMessage() {
        // GIVEN
        let sut = makeSUT(reason: .browserPrivately, didStartAIChat: false)

        // WHEN
        let content = sut.endOfJourneyContent

        // THEN
        #expect(content.icon == nil)
        #expect(content.message == UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenMessage)
        #expect(content.primaryAction == .completeAndActivateSearch)
        #expect(content.isManuallyDismissable == true)
    }

}

private struct StubTryAIContentProvider: OnboardingEndOfJourneyTryAIContentProviding {
    let dialogContent: OnboardingEndOfJourneyTryAIContent?
}
