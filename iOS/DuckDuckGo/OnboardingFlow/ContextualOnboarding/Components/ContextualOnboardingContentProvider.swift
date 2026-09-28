//
//  ContextualOnboardingContentProvider.swift
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


protocol ContextualOnboardingContentProviding {
    var endOfJourneyContent: OnboardingEndOfJourneyContent { get }
}

struct ContextualOnboardingContentProvider: ContextualOnboardingContentProviding {
    private let tryAIContentProvider: OnboardingEndOfJourneyTryAIContentProviding
    private let downloadReasonProvider: OnboardingDownloadReasonHandling
    private let searchExperienceProvider: OnboardingSearchExperienceProvider

    init(
        tryAIContentProvider: OnboardingEndOfJourneyTryAIContentProviding = OnboardingEndOfJourneyTryAIProvider(),
        downloadReasonProvider: OnboardingDownloadReasonHandling = OnboardingManager(),
        searchExperienceProvider: OnboardingSearchExperienceProvider = OnboardingSearchExperience()
    ) {
        self.tryAIContentProvider = tryAIContentProvider
        self.downloadReasonProvider = downloadReasonProvider
        self.searchExperienceProvider = searchExperienceProvider
    }
}

// MARK: - End Of Journey Dialog

struct OnboardingEndOfJourneyContent: Equatable {
    let icon: OnboardingEndOfJourneyIcon?
    let title: String
    let message: String
    let primaryCTA: String
    let primaryAction: OnboardingEndOfJourneyAction
    let secondaryCTA: String?
    let secondaryAction: OnboardingEndOfJourneyAction?
    let daxAnimation: DaxAnimation?
    let isManuallyDismissable: Bool
}

/// The icon shown at the top of an end-of-journey dialog. The view maps each case to its image.
enum OnboardingEndOfJourneyIcon: Equatable {
    case duckAI
}

/// Actions a rendered end-of-journey dialog can dispatch.
enum OnboardingEndOfJourneyAction: Equatable {
    case completeAndActivateSearch
    case tryDuckAI
    case skip
    case manualDismiss
}

extension ContextualOnboardingContentProvider {

    var endOfJourneyContent: OnboardingEndOfJourneyContent {
        // The Try-AI nudge takes precedence; it only ever qualifies within the download-reason experiment.
        if let tryAI = tryAIContentProvider.dialogContent {
            return tryAIVariantContent(tryAI)
        }
        if let reason = downloadReasonProvider.currentDownloadReason {
            return endOfJourneyForDownloadReasonFlow(reason: reason)
        }
        return endOfJourneyForStandardFlow()
    }

    /// Download-reason experiment (treatment). Its AI copy is a non-localized string, so it's used only for
    /// these enrolled users — shown when they came for private AI chat, or already started an AI chat.
    private func endOfJourneyForDownloadReasonFlow(reason: OnboardingDownloadReason) -> OnboardingEndOfJourneyContent {
        if reason == .privateAIChat || searchExperienceProvider.didStartAIChatDuringOnboarding {
            return standardContent(message: UserText.Onboarding.ContextualOnboarding.EndOfJourney.aiMessage)
        }
        return standardContent()
    }

    /// Non-experiment users. When they started an AI chat, use the existing localized Duck.ai completion copy
    /// (the experiment's non-localized copy must not leak here); otherwise the standard completion.
    private func endOfJourneyForStandardFlow() -> OnboardingEndOfJourneyContent {
        if searchExperienceProvider.didStartAIChatDuringOnboarding {
            return standardContent(message: UserText.Onboarding.DuckAIQuery.completionOnboardingMessage)
        }
        return standardContent()
    }

    /// The Try-AI variant — Duck.ai icon, two buttons, not manually dismissable.
    private func tryAIVariantContent(_ tryAI: OnboardingEndOfJourneyTryAIContent) -> OnboardingEndOfJourneyContent {
        OnboardingEndOfJourneyContent(
            icon: .duckAI,
            title: tryAI.title,
            message: tryAI.message,
            primaryCTA: tryAI.primaryCTA,
            primaryAction: .tryDuckAI,
            secondaryCTA: tryAI.secondaryCTA,
            secondaryAction: .skip,
            daxAnimation: nil,
            isManuallyDismissable: false
        )
    }

    /// The standard "You've got this!" end-of-journey — single button, Dax animation, manually dismissable.
    private func standardContent(message: String = UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenMessage) -> OnboardingEndOfJourneyContent {
        OnboardingEndOfJourneyContent(
            icon: nil,
            title: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenTitle,
            message: message,
            primaryCTA: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenButton,
            primaryAction: .completeAndActivateSearch,
            secondaryCTA: nil,
            secondaryAction: nil,
            daxAnimation: nil,
            isManuallyDismissable: true
        )
    }

}
