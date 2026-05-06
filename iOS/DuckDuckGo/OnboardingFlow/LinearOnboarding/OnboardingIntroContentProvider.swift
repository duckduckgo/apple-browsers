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

// MARK: - Onboarding Step Content

struct OnboardingLandingContent: Equatable {
    let title: String
    let shouldShowDuckAIAnimation: Bool
}


// MARK: - Provider

protocol LinearOnboardingContentProviding {
    var landingContent: OnboardingLandingContent { get }
}

struct LinearOnboardingContentProvider: LinearOnboardingContentProviding {
    private let flowType: OnboardingFlowType
    private let featureFlagger: FeatureFlagger

    init(flowType: OnboardingFlowType, featureFlagger: FeatureFlagger) {
        self.flowType = flowType
        self.featureFlagger = featureFlagger
    }
}

// MARK: - Content Provider + Landing (Welcome to DuckDuckGo!)

extension LinearOnboardingContentProvider {

    var landingContent: OnboardingLandingContent {
        OnboardingLandingContent(
            title: UserText.onboardingWelcomeHeader,
            shouldShowDuckAIAnimation: flowType == .duckAI
        )
    }

}
