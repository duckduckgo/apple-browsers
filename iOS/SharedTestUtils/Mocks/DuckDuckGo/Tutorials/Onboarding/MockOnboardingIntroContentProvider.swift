//
//  MockOnboardingIntroContentProvider.swift
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
@testable import DuckDuckGo

class MockOnboardingIntroContentProvider: OnboardingIntroContentProviding {
    var landingContent: OnboardingLandingContent = .mock
    var introStepContent: OnboardingIntroStepContent = .mock
    var addToDockContent: OnboardingAddToDockContent = .mock
}

// MARK: - Helpers

extension OnboardingLandingContent {
    static let mock = OnboardingLandingContent(
        title: "Landing",
        shouldShowDuckAIAnimation: false
    )
}

extension OnboardingIntroStepContent {
    static let mock = OnboardingIntroStepContent(
        title: "Intro Title",
        message: "Intro Message",
        primaryCTA: "Intro Primary",
        secondaryCTA: "Intro Secondary",
        restorePromptStepContent: .init(
            title: "Restore Title",
            message: "Restore Message",
            primaryCTA: "Restore Primary",
            secondaryCTA: "Restore Secondary"
        ),
        skipFlowStepContent: .init(
            title: "Skip Title",
            message: "Skip Message",
            primaryCTA: "Skip Primary",
            secondaryCTA: "Skip Secondary"
        )
    )
}

extension OnboardingAddToDockContent {
    static let mock = OnboardingAddToDockContent(
        title: "Add to Dock Title",
        message: "Add to Dock Message",
        primaryCTA: "Add to Dock Primary",
        secondaryCTA: "Add to Dock Secondary",
        tutorialStepContent: .init(
            title: "Tutorial Title",
            message: "Tutorial Message",
            primaryCTA: "Tutorial Primary"
        )
    )
}
