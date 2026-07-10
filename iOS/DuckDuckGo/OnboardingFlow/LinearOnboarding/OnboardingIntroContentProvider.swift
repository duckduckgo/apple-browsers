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
    var browserComparisonContent: OnboardingBrowserComparisonContent { get }
    var aiComparisonContent: OnboardingAIComparisonContent { get }
    var addToDockContent: OnboardingAddToDockContent { get }
    var appIconColorContent: OnboardingAppIconColorContent { get }
    var addressBarPositionContent: OnboardingAddressBarPositionContent { get }
    var searchExperienceContent: OnboardingSearchExperienceContent { get }
    var duckAIQueryContent: OnboardingDuckAIQueryContent { get }
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
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var introStepContent: OnboardingIntroStepContent {
        let introMessage = switch flowType {
        case .default: UserText.Onboarding.Rebranding.Intro.message
        case .duckAI: UserText.Onboarding.DuckAICPP.Intro.message
        }

        let (skipMessage, skipPrimaryCTA) = switch flowType {
        case .default: (UserText.Onboarding.Skip.message, UserText.Onboarding.Skip.confirmSkipOnboardingCTA)
        case .duckAI: (UserText.Onboarding.DuckAICPP.Skip.message, UserText.Onboarding.DuckAICPP.Skip.confirmSkipOnboardingCTA)
        }

        let skipOnboardingContent = OnboardingIntroStepContent.SkipFlowStepContent(
            title: UserText.Onboarding.Skip.title,
            message: skipMessage,
            primaryCTA: skipPrimaryCTA,
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
            message: introMessage,
            primaryCTA: UserText.Onboarding.Intro.continueCTA,
            secondaryCTA: UserText.Onboarding.Intro.skipCTA,
            restorePromptStepContent: restoreOnboardingContent,
            skipFlowStepContent: skipOnboardingContent,
            daxAnimation: .thumbUp
        )
    }

}

// MARK: - Content Provider + Browser Comparison (Protections activated!)

struct OnboardingBrowserComparisonContent: Equatable {
    let title: String
    let features: [RebrandedComparisonTableModel.Feature]
    let primaryCTA: String
    let secondaryCTA: String
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var browserComparisonContent: OnboardingBrowserComparisonContent {
        let title = switch flowType {
        case .default: UserText.Onboarding.BrowsersComparison.title
        case .duckAI: UserText.Onboarding.DuckAICPP.BrowserComparison.title
        }

        return OnboardingBrowserComparisonContent(
            title: title,
            features: RebrandedComparisonTableModel.defaultBrowserFeatures,
            primaryCTA: UserText.Onboarding.BrowsersComparison.cta,
            secondaryCTA: UserText.onboardingSkip,
            daxAnimation: .wingBottom
        )
    }

}

// MARK: - Content Provider + AI Comparison (AI Protections activated!)

struct OnboardingAIComparisonContent: Equatable {
    let title: String
    let subHeader: String
    let features: [RebrandedComparisonTableModel.Feature]
    let primaryCTA: String
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var aiComparisonContent: OnboardingAIComparisonContent {
        OnboardingAIComparisonContent(
            title: UserText.Onboarding.DuckAICPP.AIComparison.title,
            subHeader: UserText.Onboarding.DuckAICPP.AIComparison.subHeader,
            features: RebrandedComparisonTableModel.defaultAIFeatures,
            primaryCTA: UserText.Onboarding.DuckAICPP.AIComparison.cta,
            daxAnimation: .wingBottom
        )
    }

}

// MARK: - Content Provider + Add to Dock (Add me to your Dock!)

struct OnboardingAddToDockContent: Equatable {
    struct TutorialStepContent: Equatable {
        let title: String
        let message: String
        let primaryCTA: String
    }

    let title: String
    let message: String
    let primaryCTA: String
    let secondaryCTA: String
    let tutorialStepContent: TutorialStepContent
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var addToDockContent: OnboardingAddToDockContent {
        let promoMessage = switch flowType {
        case .default: UserText.AddToDockOnboarding.Promo.introMessage
        case .duckAI: UserText.Onboarding.DuckAICPP.AddToDock.Promo.message
        }

        let tutorial = OnboardingAddToDockContent.TutorialStepContent(
            title: UserText.AddToDockOnboarding.Tutorial.title,
            message: UserText.AddToDockOnboarding.Tutorial.message,
            primaryCTA: UserText.AddToDockOnboarding.Buttons.gotIt
        )

        return OnboardingAddToDockContent(
            title: UserText.AddToDockOnboarding.Promo.title,
            message: promoMessage,
            primaryCTA: UserText.AddToDockOnboarding.Buttons.tutorial,
            secondaryCTA: UserText.AddToDockOnboarding.Buttons.skip,
            tutorialStepContent: tutorial,
            daxAnimation: .wingLeft
        )
    }

}

// MARK: - Content Provider + App Icon Color (Which color looks best on me?)

struct OnboardingAppIconColorContent: Equatable {
    let title: String
    let message: String
    let primaryCTA: String
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var appIconColorContent: OnboardingAppIconColorContent {
        OnboardingAppIconColorContent(
            title: UserText.Onboarding.AppIconSelection.title,
            message: UserText.Onboarding.AppIconSelection.message,
            primaryCTA: UserText.Onboarding.AppIconSelection.cta,
            daxAnimation: .wingRight
        )
    }

}

// MARK: - Content Provider + Address Bar Position (Where should I put your address bar?)

struct OnboardingAddressBarPositionContent: Equatable {
    struct OptionContent: Equatable {
        let title: String
        let message: String
    }

    let title: String
    let topOption: OptionContent
    let bottomOption: OptionContent
    let defaultIndicator: String
    let primaryCTA: String
    let daxAnimation: DaxAnimation?
}

extension OnboardingIntroContentProvider {

    var addressBarPositionContent: OnboardingAddressBarPositionContent {
        OnboardingAddressBarPositionContent(
            title: UserText.Onboarding.AddressBarPosition.title,
            topOption: .init(
                title: UserText.Onboarding.AddressBarPosition.topTitle,
                message: UserText.Onboarding.AddressBarPosition.topMessage
            ),
            bottomOption: .init(
                title: UserText.Onboarding.AddressBarPosition.bottomTitle,
                message: UserText.Onboarding.AddressBarPosition.bottomMessage
            ),
            defaultIndicator: UserText.Onboarding.AddressBarPosition.defaultOption,
            primaryCTA: UserText.Onboarding.AddressBarPosition.cta,
            daxAnimation: nil // Dax-Floating is embedded in ScrollableOnboardingBackground
        )
    }

}

// MARK: - Content Provider + Search Experience (Want easy access to private AI chat in the address bar?)

struct OnboardingSearchExperienceContent: Equatable {
    let title: String
    let footer: AttributedString
    let primaryCTA: String
    let daxAnimation: DaxAnimation
}

extension OnboardingIntroContentProvider {

    var searchExperienceContent: OnboardingSearchExperienceContent {
        OnboardingSearchExperienceContent(
            title: UserText.Onboarding.SearchExperience.title,
            footer: AttributedString(UserText.Onboarding.SearchExperience.footerAttributed()),
            primaryCTA: UserText.Onboarding.SearchExperience.cta,
            daxAnimation: .wingLeft
        )
    }

}

// MARK: - Content Provider + Duck.ai Query Selection (Ready to get started?)

struct OnboardingDuckAIQueryContent: Equatable {
    let title: String
    let searchPlaceholder: String
    let aiPlaceholder: String
    let isToggleVisible: Bool
    let daxAnimation: DaxAnimation?
}

extension OnboardingIntroContentProvider {

    var duckAIQueryContent: OnboardingDuckAIQueryContent {
        let (title, isToggleVisible) = switch flowType {
        case .default:
            (UserText.Onboarding.DuckAIQuery.title, true)
        case .duckAI:
            (UserText.Onboarding.DuckAICPP.DuckAIQuery.title, false)
        }

        return OnboardingDuckAIQueryContent(
            title: title,
            searchPlaceholder: UserText.Onboarding.DuckAIQuery.searchPlaceholder,
            aiPlaceholder: UserText.Onboarding.DuckAIQuery.aiPlaceholder,
            isToggleVisible: isToggleVisible,
            daxAnimation: nil
        )
    }

}
