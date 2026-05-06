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

}
