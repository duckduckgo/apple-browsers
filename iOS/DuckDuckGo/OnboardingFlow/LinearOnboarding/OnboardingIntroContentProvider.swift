//
//  OnboardingIntroContentProvider.swift
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
import PrivacyConfig

// MARK: - Provider

protocol OnboardingIntroContentProviding {
    var landingContent: OnboardingLandingContent { get }
    var introStepContent: OnboardingIntroStepContent { get }
}

struct OnboardingIntroContentProvider: OnboardingIntroContentProviding {
    private let flowType: OnboardingFlowType
    private let featureFlagger: FeatureFlagger

    init(flowType: OnboardingFlowType, featureFlagger: FeatureFlagger) {
        self.flowType = flowType
        self.featureFlagger = featureFlagger
    }
}

// MARK: - Content Provider + Landing (Welcome to DuckDuckGo!)

struct OnboardingLandingContent: Equatable {
    let title: String
    let shouldShowDuckAIAnimation: Bool
}

extension OnboardingIntroContentProvider {

    var landingContent: OnboardingLandingContent {
        OnboardingLandingContent(
            title: UserText.onboardingWelcomeHeader,
            shouldShowDuckAIAnimation: flowType == .duckAI
        )
    }

}

// MARK: - Content Provider + Intro (Ready to...)

struct OnboardingIntroStepContent: Equatable {
    struct RestorePromptStepContent: Equatable {
        let title: String
        let message: String
        let primaryCTA: String
        let secondaryCTA: String
    }

    struct SkipFlowStepContent: Equatable {
        let title: String
        let message: String
        let primaryCTA: String
        let secondaryCTA: String
    }

    let title: String
    let message: String
    let primaryCTA: String
    let secondaryCTA: String
    let restorePromptStepContent: RestorePromptStepContent
    let skipFlowStepContent: SkipFlowStepContent
}

extension OnboardingIntroContentProvider {

    var introStepContent: OnboardingIntroStepContent {
        let skipOnboardingContent = OnboardingIntroStepContent.SkipFlowStepContent(
            title: UserText.Onboarding.Skip.title,
            message:  UserText.Onboarding.Skip.message,
            primaryCTA: UserText.Onboarding.Skip.confirmSkipOnboardingCTA,
            secondaryCTA: UserText.Onboarding.Skip.resumeOnboardingCTA
        )

        let restoreOnboardingContent = OnboardingIntroStepContent.RestorePromptStepContent(
            title: UserText.Onboarding.RestorePrompt.title,
            message: UserText.Onboarding.RestorePrompt.body,
            primaryCTA: UserText.Onboarding.RestorePrompt.restoreCTA,
            secondaryCTA: UserText.Onboarding.RestorePrompt.skipCTA
        )

        return OnboardingIntroStepContent(
            title: UserText.Onboarding.Rebranding.Intro.title,
            message: UserText.Onboarding.Rebranding.Intro.message,
            primaryCTA: UserText.Onboarding.Intro.continueCTA,
            secondaryCTA: UserText.Onboarding.Intro.skipCTA,
            restorePromptStepContent: restoreOnboardingContent,
            skipFlowStepContent: skipOnboardingContent
        )
    }

}
