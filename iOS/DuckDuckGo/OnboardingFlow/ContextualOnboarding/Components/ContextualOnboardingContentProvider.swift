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

    init(
        tryAIContentProvider: OnboardingEndOfJourneyTryAIContentProviding = OnboardingEndOfJourneyTryAIProvider(),
        downloadReasonProvider: OnboardingDownloadReasonHandling = OnboardingManager()
    ) {
        self.tryAIContentProvider = tryAIContentProvider
        self.downloadReasonProvider = downloadReasonProvider
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
        if let tryAI = tryAIContentProvider.dialogContent {
            return OnboardingEndOfJourneyContent(
                icon: .duckAI,
                title: tryAI.title,
                message: tryAI.message,
                primaryCTA: tryAI.primaryCTA,
                primaryAction: .tryDuckAI,
                secondaryCTA: tryAI.secondaryCTA,
                secondaryAction: .skip,
                daxAnimation: OnboardingRebranding.contextualThumbsUpDaxAnimation,
                isManuallyDismissable: false
            )
        }
        if downloadReasonProvider.currentDownloadReason == .privateAIChat {
            return standardContent(message: UserText.Onboarding.ContextualOnboarding.EndOfJourney.aiMessage)
        }
        return standardContent()
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
            daxAnimation: OnboardingRebranding.contextualThumbsUpDaxAnimation,
            isManuallyDismissable: true
        )
    }

}
