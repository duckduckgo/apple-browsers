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
    var downloadReasonContent: OnboardingDownloadReasonContent = .mock
    var serpPersonalizationContent: OnboardingPersonalizationContent = .mock
    var aiModelPersonalizationContent: OnboardingAIModelContent = .mock
    var addressBarToggleModePersonalizationContent: OnboardingAddressBarToggleModeContent = .mock
    var aiSearchPersonalizationContent: OnboardingPersonalizationContent = .mock
    var aiChatEnabledPersonalizationContent: OnboardingDuckAIEnabledPersonalizationContent = .mock
    var youTubePersonalizationContent: OnboardingPersonalizationContent = .mock
    var setDefaultBrowserContent: OnboardingComparisonContent = .mockBrowser
    var aiIntroContent: OnboardingComparisonContent = .mockAI
    var addToDockContent: OnboardingAddToDockContent = .mock
    var appIconColorContent: OnboardingAppIconColorContent = .mock
    var addressBarPositionContent: OnboardingAddressBarPositionContent = .mock
    var searchExperienceContent: OnboardingSearchExperienceContent = .mock
    var duckAIQueryContent: OnboardingDuckAIQueryContent = .mock
}

// MARK: - Helpers

extension OnboardingLandingContent {
    static let mock = OnboardingLandingContent(
        title: "Landing",
        shouldShowDuckAIAnimation: false
    )
}

extension OnboardingDownloadReasonContent {
    static let mock = OnboardingDownloadReasonContent(
        title: "Download Reason Title",
        message: "Download Reason Message",
        options: [
            .init(reason: .browserPrivately, animation: .search, title: "Search and browse privately"),
            .init(reason: .privateAIChat, animation: .duckAIChat, title: "Chat with AI privately"),
            .init(reason: .noAI, animation: .noAI, title: "Remove AI from search results"),
            .init(reason: .blockAds, animation: .imageSweep, title: "Block ads and pop-ups")
        ],
        primaryCTA: "Download Reason Primary",
        daxAnimation: .wingBottom
    )
}

extension OnboardingPersonalizationContent {
    static let mock = OnboardingPersonalizationContent(
        title: "Personalization Title",
        message: "Personalization Message",
        items: [
            .init(type: .recentlyVisitedSites, title: "Personalization Item Title", subtitle: "Personalization Item Subtitle")
        ],
        primaryCTA: "Personalization Primary",
        daxAnimation: .wingBottom
    )
}

extension OnboardingAIModelContent {
    static let mock = OnboardingAIModelContent(
        title: "AI Model Title",
        message: "AI Model Message",
        primaryCTA: "AI Model Primary",
        daxAnimation: .wingBottom
    )
}

extension OnboardingAddressBarToggleModeContent {
    static let mock = OnboardingAddressBarToggleModeContent(
        title: "Address Bar Toggle Title",
        icon: .init(name: "", bundle: .main),
        footer: "Address Bar Toggle Footer",
        primaryCTA: "Address Bar Toggle Primary",
        secondaryCTA: "Address Bar Toggle Secondary",
        daxAnimation: nil
    )
}

extension OnboardingDuckAIEnabledPersonalizationContent {
    static let mock = OnboardingDuckAIEnabledPersonalizationContent(
        icon: .init(name: "", bundle: .main),
        title: "Duck.ai Enabled Title",
        message: "Duck.ai Enabled Message",
        primaryCTA: "Duck.ai Enabled Primary",
        secondaryCTA: "Duck.ai Enabled Secondary",
        daxAnimation: nil
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
        ),
        daxAnimation: .thumbUp
    )
}

extension OnboardingComparisonContent {
    static let mockBrowser = OnboardingComparisonContent(
        title: "Browser Comparison Title",
        subHeader: nil,
        competitor: .safari,
        features: [
            .init(type: RebrandedComparisonTableModel.Feature.BrowserFeatureType.privateSearch, competitorAvailability: .unavailable, ddgAvailability: .available)
        ],
        primaryCTA: "Browser Comparison Primary",
        secondaryCTA: "Browser Comparison Secondary",
        daxAnimation: .wingBottom
    )

    static let mockAI = OnboardingComparisonContent(
        title: "AI Comparison Title",
        subHeader: "AI Comparison SubHeader",
        competitor: .ai,
        features: [
            .init(type: RebrandedComparisonTableModel.Feature.AIFeatureType.anonymousChats, competitorAvailability: .unavailable, ddgAvailability: .available)
        ],
        primaryCTA: "AI Comparison Primary",
        secondaryCTA: nil,
        daxAnimation: .wingBottom
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
        ),
        daxAnimation: .wingRight
    )
}

extension OnboardingAppIconColorContent {
    static let mock = OnboardingAppIconColorContent(
        title: "App Icon Title",
        message: "App Icon Message",
        primaryCTA: "App Icon Primary",
        daxAnimation: .wingBottom
    )
}

extension OnboardingAddressBarPositionContent {
    static let mock = OnboardingAddressBarPositionContent(
        title: "Address Bar Title",
        topOption: .init(title: "Top Title", message: "Top Message"),
        bottomOption: .init(title: "Bottom Title", message: "Bottom Message"),
        defaultIndicator: "(default)",
        primaryCTA: "Address Bar Primary",
        daxAnimation: nil
    )
}

extension OnboardingSearchExperienceContent {
    static let mock = OnboardingSearchExperienceContent(
        title: "Search Experience Title",
        footer: AttributedString("Search Experience Footer"),
        primaryCTA: "Search Experience Primary",
        daxAnimation: .wingRight
    )
}

extension OnboardingDuckAIQueryContent {
    static let mock = OnboardingDuckAIQueryContent(
        title: "Duck.ai Query Title",
        searchPlaceholder: "Search Placeholder",
        aiPlaceholder: "AI Placeholder",
        isToggleVisible: true,
        defaultMode: .search,
        daxAnimation: nil
    )
}
