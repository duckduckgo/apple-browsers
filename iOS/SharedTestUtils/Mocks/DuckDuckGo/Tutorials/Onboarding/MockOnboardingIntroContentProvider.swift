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
    var browserComparisonContent: OnboardingBrowserComparisonContent = .mock
    var addToDockContent: OnboardingAddToDockContent = .mock
    var appIconColorContent: OnboardingAppIconColorContent = .mock
    var addressBarPositionContent: OnboardingAddressBarPositionContent = .mock
    var searchExperienceContent: OnboardingSearchExperienceContent = .mock
    var duckAIQueryExperimentContent: OnboardingDuckAIQueryExperimentContent = .mock
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

extension OnboardingBrowserComparisonContent {
    static let mock = OnboardingBrowserComparisonContent(
        title: "Browser Comparison Title",
        features: [
            .init(type: .privateSearch, safariAvailability: .unavailable, ddgAvailability: .available)
        ],
        primaryCTA: "Browser Comparison Primary",
        secondaryCTA: "Browser Comparison Secondary"
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

extension OnboardingAppIconColorContent {
    static let mock = OnboardingAppIconColorContent(
        title: "App Icon Title",
        message: "App Icon Message",
        primaryCTA: "App Icon Primary"
    )
}

extension OnboardingAddressBarPositionContent {
    static let mock = OnboardingAddressBarPositionContent(
        title: "Address Bar Title",
        topOption: .init(title: "Top Title", message: "Top Message"),
        bottomOption: .init(title: "Bottom Title", message: "Bottom Message"),
        defaultIndicator: "(default)",
        primaryCTA: "Address Bar Primary"
    )
}

extension OnboardingSearchExperienceContent {
    static let mock = OnboardingSearchExperienceContent(
        title: "Search Experience Title",
        footer: AttributedString("Search Experience Footer"),
        primaryCTA: "Search Experience Primary"
    )
}

extension OnboardingDuckAIQueryExperimentContent {
    static let mock = OnboardingDuckAIQueryExperimentContent(
        title: "Duck.ai Query Experiment Title",
        searchPlaceholder: "Search Placeholder",
        aiPlaceholder: "AI Placeholder"
    )
}
