//
//  OnboardingIntroContentProviderTests.swift
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

import Foundation
import Onboarding
import Testing
@testable import DuckDuckGo

@Suite("Onboarding - Content Provider")
struct OnboardingIntroContentProviderTests {

    @Suite("Landing Content")
    struct LandingContent {

        @Test(
            "Check landing title is the welcome header",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkLandingTitleIsCorrect(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.landingContent

            // THEN
            #expect(result.title == UserText.onboardingWelcomeHeader)
        }

        @Test("Check Duck.ai animation is hidden for default flow")
        func shouldShowDuckAIAnimation_isFalseForDefaultFlow() {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: .default, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.landingContent

            // THEN
            #expect(!result.shouldShowDuckAIAnimation)
        }

        @Test("Check Duck.ai animation is shown for Duck.ai flow")
        func shouldShowDuckAIAnimation_isTrueForDuckAIFlow() {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: .duckAI, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.landingContent

            // THEN
            #expect(result.shouldShowDuckAIAnimation)
        }

    }

    @Suite("Intro Step Content")
    struct IntroStepContent {

        @Test(
            "Check intro title is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkIntroTitleIsCorrect(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.introStepContent

            // THEN
            #expect(result.title == UserText.Onboarding.Rebranding.Intro.title)
        }

        @Test(
            "Check intro message is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkIntroMessage(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.introStepContent

            // THEN
            #expect(result.message == UserText.Onboarding.Rebranding.Intro.message)
        }

        @Test(
            "Check intro primary CTA is continue",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkIntroPrimaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.introStepContent

            // THEN
            #expect(result.primaryCTA == UserText.Onboarding.Intro.continueCTA)
        }

        @Test(
            "Check intro secondary CTA is skip",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkIntroSecondaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.introStepContent

            // THEN
            #expect(result.secondaryCTA == UserText.Onboarding.Intro.skipCTA)
        }

        @Suite("Restore Prompt")
        struct RestorePrompt {

            @Test(
                "Check restore prompt title is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkRestorePromptTitle(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.restorePromptStepContent

                // THEN
                #expect(result.title == UserText.Onboarding.RestorePrompt.title)
            }

            @Test(
                "Check restore prompt message is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkRestorePromptMessage(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.restorePromptStepContent

                // THEN
                #expect(result.message == UserText.Onboarding.RestorePrompt.body)
            }

            @Test(
                "Check restore prompt primary CTA is restore",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkRestorePromptPrimaryCTA(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.restorePromptStepContent

                // THEN
                #expect(result.primaryCTA == UserText.Onboarding.RestorePrompt.restoreCTA)
            }

            @Test(
                "Check restore prompt secondary CTA is skip",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkRestorePromptSecondaryCTA(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.restorePromptStepContent

                // THEN
                #expect(result.secondaryCTA == UserText.Onboarding.RestorePrompt.skipCTA)
            }

        }

        @Suite("Skip Flow")
        struct SkipFlow {

            @Test(
                "Check skip flow title is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkSkipFlowTitle(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.skipFlowStepContent

                // THEN
                #expect(result.title == UserText.Onboarding.Skip.title)
            }

            @Test(
                "Check skip flow message is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkSkipFlowMessage(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.skipFlowStepContent

                // THEN
                #expect(result.message == UserText.Onboarding.Skip.message)
            }

            @Test(
                "Check skip flow primary CTA is start browsing",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkSkipFlowPrimaryCTA(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.skipFlowStepContent

                // THEN
                #expect(result.primaryCTA == UserText.Onboarding.Skip.confirmSkipOnboardingCTA)
            }

            @Test(
                "Check skip flow secondary CTA is show tutorial",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkSkipFlowSecondaryCTA(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.skipFlowStepContent

                // THEN
                #expect(result.secondaryCTA == UserText.Onboarding.Skip.resumeOnboardingCTA)
            }

        }

    }

}
