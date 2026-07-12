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
            "Check intro message is correct per flow",
            arguments: zip(
                [OnboardingFlowType.default, .duckAI],
                [UserText.Onboarding.Rebranding.Intro.message, UserText.Onboarding.DuckAICPP.Intro.message]
            )
        )
        func checkIntroMessage(flow: OnboardingFlowType, expectedMessage: String) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.introStepContent

            // THEN
            #expect(result.message == expectedMessage)
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
                "Check skip flow message is correct per flow",
                arguments: zip(
                    [OnboardingFlowType.default, .duckAI],
                    [UserText.Onboarding.Skip.message, UserText.Onboarding.DuckAICPP.Skip.message]
                )
            )
            func checkSkipFlowMessage(flow: OnboardingFlowType, expectedMessage: String) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.skipFlowStepContent

                // THEN
                #expect(result.message == expectedMessage)
            }

            @Test(
                "Check skip flow primary CTA is correct per flow",
                arguments: zip(
                    [OnboardingFlowType.default, .duckAI],
                    [UserText.Onboarding.Skip.confirmSkipOnboardingCTA, UserText.Onboarding.DuckAICPP.Skip.confirmSkipOnboardingCTA]
                )
            )
            func checkSkipFlowPrimaryCTA(flow: OnboardingFlowType, expectedPrimaryCTA: String) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.skipFlowStepContent

                // THEN
                #expect(result.primaryCTA == expectedPrimaryCTA)
            }

            @Test("Check Duck.ai skip flow message contains the chat icon token")
            func duckAISkipFlowMessageContainsChatIconToken() {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: .duckAI, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.skipFlowStepContent

                // THEN
                #expect(result.message.contains(UserText.Onboarding.ContextualOnboarding.onboardingChatIconToken))
            }

            @Test("Check default skip flow message does not contain the chat icon token")
            func defaultSkipFlowMessageDoesNotContainChatIconToken() {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: .default, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.introStepContent.skipFlowStepContent

                // THEN
                #expect(!result.message.contains(UserText.Onboarding.ContextualOnboarding.onboardingChatIconToken))
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

    @Suite("Browser Comparison Content")
    struct BrowserComparisonContent {

        @Test(
            "Check browser comparison title is correct per flow",
            arguments: zip(
                [OnboardingFlowType.default, .duckAI],
                [UserText.Onboarding.BrowsersComparison.title, UserText.Onboarding.DuckAICPP.BrowserComparison.title]
            )
        )
        func checkBrowserComparisonTitle(flow: OnboardingFlowType, expectedTitle: String) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.browserComparisonContent

            // THEN
            #expect(result.title == expectedTitle)
        }

        @Test(
            "Check browser comparison primary CTA is choose your browser",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkBrowserComparisonPrimaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.browserComparisonContent

            // THEN
            #expect(result.primaryCTA == UserText.Onboarding.BrowsersComparison.cta)
        }

        @Test(
            "Check browser comparison secondary CTA is skip",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkBrowserComparisonSecondaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.browserComparisonContent

            // THEN
            #expect(result.secondaryCTA == UserText.onboardingSkip)
        }

        @Test(
            "Check browser comparison features default to the model's default list",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkBrowserComparisonFeatures(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.browserComparisonContent

            // THEN
            #expect(result.features == RebrandedComparisonTableModel.defaultBrowserFeatures)
        }

    }

    @Suite("AI Comparison Content")
    struct AIComparisonContent {

        @Test(
            "Check AI comparison title is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAIComparisonTitle(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.aiComparisonContent

            // THEN
            #expect(result.title == UserText.Onboarding.DuckAICPP.AIComparison.title)
        }

        @Test(
            "Check AI comparison sub-header is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAIComparisonSubHeader(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.aiComparisonContent

            // THEN
            #expect(result.subHeader == UserText.Onboarding.DuckAICPP.AIComparison.subHeader)
        }

        @Test(
            "Check AI comparison primary CTA is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAIComparisonPrimaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.aiComparisonContent

            // THEN
            #expect(result.primaryCTA == UserText.Onboarding.DuckAICPP.AIComparison.cta)
        }

        @Test(
            "Check AI comparison features default to the model's default AI list",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAIComparisonFeatures(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.aiComparisonContent

            // THEN
            #expect(result.features == RebrandedComparisonTableModel.defaultAIFeatures)
        }

    }

    @Suite("Add to Dock Content")
    struct AddToDockContent {

        @Test(
            "Check add to dock title is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAddToDockTitle(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.addToDockContent

            // THEN
            #expect(result.title == UserText.AddToDockOnboarding.Promo.title)
        }

        @Test(
            "Check add to dock message is correct per flow",
            arguments: zip(
                [OnboardingFlowType.default, .duckAI],
                [UserText.AddToDockOnboarding.Promo.introMessage, UserText.Onboarding.DuckAICPP.AddToDock.Promo.message]
            )
        )
        func checkAddToDockMessage(flow: OnboardingFlowType, expectedMessage: String) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.addToDockContent

            // THEN
            #expect(result.message == expectedMessage)
        }

        @Test(
            "Check add to dock primary CTA is show tutorial",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAddToDockPrimaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.addToDockContent

            // THEN
            #expect(result.primaryCTA == UserText.AddToDockOnboarding.Buttons.tutorial)
        }

        @Test(
            "Check add to dock secondary CTA is skip",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAddToDockSecondaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.addToDockContent

            // THEN
            #expect(result.secondaryCTA == UserText.AddToDockOnboarding.Buttons.skip)
        }

        @Suite("Tutorial")
        struct Tutorial {

            @Test(
                "Check tutorial title is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkTutorialTitle(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.addToDockContent.tutorialStepContent

                // THEN
                #expect(result.title == UserText.AddToDockOnboarding.Tutorial.title)
            }

            @Test(
                "Check tutorial message is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkTutorialMessage(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.addToDockContent.tutorialStepContent

                // THEN
                #expect(result.message == UserText.AddToDockOnboarding.Tutorial.message)
            }

            @Test(
                "Check tutorial primary CTA is got it",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkTutorialPrimaryCTA(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.addToDockContent.tutorialStepContent

                // THEN
                #expect(result.primaryCTA == UserText.AddToDockOnboarding.Buttons.gotIt)
            }

        }

    }

    @Suite("App Icon Color Content")
    struct AppIconColorContent {

        @Test(
            "Check app icon title is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAppIconTitle(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.appIconColorContent

            // THEN
            #expect(result.title == UserText.Onboarding.AppIconSelection.title)
        }

        @Test(
            "Check app icon message is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAppIconMessage(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.appIconColorContent

            // THEN
            #expect(result.message == UserText.Onboarding.AppIconSelection.message)
        }

        @Test(
            "Check app icon primary CTA is next",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAppIconPrimaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.appIconColorContent

            // THEN
            #expect(result.primaryCTA == UserText.Onboarding.AppIconSelection.cta)
        }

    }

    @Suite("Address Bar Position Content")
    struct AddressBarPositionContent {

        @Test(
            "Check address bar title is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAddressBarTitle(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.addressBarPositionContent

            // THEN
            #expect(result.title == UserText.Onboarding.AddressBarPosition.title)
        }

        @Test(
            "Check address bar default indicator is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAddressBarDefaultIndicator(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.addressBarPositionContent

            // THEN
            #expect(result.defaultIndicator == UserText.Onboarding.AddressBarPosition.defaultOption)
        }

        @Test(
            "Check address bar primary CTA is next",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkAddressBarPrimaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.addressBarPositionContent

            // THEN
            #expect(result.primaryCTA == UserText.Onboarding.AddressBarPosition.cta)
        }

        @Suite("Top Option")
        struct TopOption {

            @Test(
                "Check top option title is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkTopOptionTitle(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.addressBarPositionContent.topOption

                // THEN
                #expect(result.title == UserText.Onboarding.AddressBarPosition.topTitle)
            }

            @Test(
                "Check top option message is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkTopOptionMessage(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.addressBarPositionContent.topOption

                // THEN
                #expect(result.message == UserText.Onboarding.AddressBarPosition.topMessage)
            }

        }

        @Suite("Bottom Option")
        struct BottomOption {

            @Test(
                "Check bottom option title is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkBottomOptionTitle(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.addressBarPositionContent.bottomOption

                // THEN
                #expect(result.title == UserText.Onboarding.AddressBarPosition.bottomTitle)
            }

            @Test(
                "Check bottom option message is correct",
                arguments: [.default, .duckAI] as [OnboardingFlowType]
            )
            func checkBottomOptionMessage(flow: OnboardingFlowType) {
                // GIVEN
                let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

                // WHEN
                let result = sut.addressBarPositionContent.bottomOption

                // THEN
                #expect(result.message == UserText.Onboarding.AddressBarPosition.bottomMessage)
            }

        }

    }

    @Suite("Search Experience Content")
    struct SearchExperienceContent {

        @Test(
            "Check search experience title is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkSearchExperienceTitle(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.searchExperienceContent

            // THEN
            #expect(result.title == UserText.Onboarding.SearchExperience.title)
        }

        @Test(
            "Check search experience footer is the attributed footer",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkSearchExperienceFooter(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.searchExperienceContent

            // THEN
            #expect(result.footer == AttributedString(UserText.Onboarding.SearchExperience.footerAttributed()))
        }

        @Test(
            "Check search experience primary CTA is next",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkSearchExperiencePrimaryCTA(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.searchExperienceContent

            // THEN
            #expect(result.primaryCTA == UserText.Onboarding.SearchExperience.cta)
        }

    }

    @Suite("Duck.ai Query Content")
    struct DuckAIQueryContent {

        @Test(
            "Check duck.ai query title is correct per flow",
            arguments: zip(
                [OnboardingFlowType.default, .duckAI],
                [UserText.Onboarding.DuckAIQuery.title, UserText.Onboarding.DuckAICPP.DuckAIQuery.title]
            )
        )
        func checkDuckAIQueryTitle(flow: OnboardingFlowType, expectedTitle: String) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.duckAIQueryContent

            // THEN
            #expect(result.title == expectedTitle)
        }

        @Test(
            "Check duck.ai query search placeholder is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkDuckAIQuerySearchPlaceholder(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.duckAIQueryContent

            // THEN
            #expect(result.searchPlaceholder == UserText.Onboarding.DuckAIQuery.searchPlaceholder)
        }

        @Test(
            "Check duck.ai query AI placeholder is correct",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func checkDuckAIQueryAIPlaceholder(flow: OnboardingFlowType) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.duckAIQueryContent

            // THEN
            #expect(result.aiPlaceholder == UserText.Onboarding.DuckAIQuery.aiPlaceholder)
        }

        @Test(
            "Check toggle visibility is correct per flow",
            arguments: zip(
                [OnboardingFlowType.default, .duckAI],
                [true, false]
            )
        )
        func checkIsToggleVisible(flow: OnboardingFlowType, expectedVisibility: Bool) {
            // GIVEN
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())

            // WHEN
            let result = sut.duckAIQueryContent

            // THEN
            #expect(result.isToggleVisible == expectedVisibility)
        }

    }

    @Suite("Dax Animations")
    struct DaxAnimations {

        @Test(
            "Check intro step uses thumbUp animation",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func introStepDaxAnimation(flow: OnboardingFlowType) {
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())
            #expect(sut.introStepContent.daxAnimation == .thumbUp)
        }

        @Test(
            "Check browser comparison uses wingBottom animation",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func browserComparisonDaxAnimation(flow: OnboardingFlowType) {
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())
            #expect(sut.browserComparisonContent.daxAnimation == .wingBottom)
        }

        @Test(
            "Check AI comparison uses wingBottom animation",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func aiComparisonDaxAnimation(flow: OnboardingFlowType) {
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())
            #expect(sut.aiComparisonContent.daxAnimation == .wingBottom)
        }

        @Test(
            "Check add to dock uses wingLeft animation",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func addToDockDaxAnimation(flow: OnboardingFlowType) {
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())
            #expect(sut.addToDockContent.daxAnimation == .wingLeft)
        }

        @Test(
            "Check app icon color uses wingRight animation",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func appIconColorDaxAnimation(flow: OnboardingFlowType) {
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())
            #expect(sut.appIconColorContent.daxAnimation == .wingRight)
        }

        @Test(
            "Check address bar position has no overlay animation (Dax is embedded in the background)",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func addressBarPositionDaxAnimation(flow: OnboardingFlowType) {
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())
            #expect(sut.addressBarPositionContent.daxAnimation == nil)
        }

        @Test(
            "Check search experience uses wingLeft animation",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func searchExperienceDaxAnimation(flow: OnboardingFlowType) {
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())
            #expect(sut.searchExperienceContent.daxAnimation == .wingLeft)
        }

        @Test(
            "Check duck.ai query has no animation",
            arguments: [.default, .duckAI] as [OnboardingFlowType]
        )
        func duckAIQueryDaxAnimation(flow: OnboardingFlowType) {
            let sut = OnboardingIntroContentProvider(flowType: flow, featureFlagger: MockFeatureFlagger())
            #expect(sut.duckAIQueryContent.daxAnimation == nil)
        }

    }

}
