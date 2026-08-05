//
//  OnboardingEndOfJourneyTryAIProvider.swift
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

/// Content for the alternative Search-flow end-of-journey dialog ("Chat privately with popular AIs in Duck.ai").
struct OnboardingEndOfJourneyTryAIContent: Equatable {
    let title: String
    let message: String
    let primaryCTA: String
    let secondaryCTA: String
}

/// Decides whether the Search-flow end-of-journey should show the Duck.ai chat completion
/// instead of the standard "You've got this!" dialog, and supplies its content.
protocol OnboardingEndOfJourneyTryAIContentProviding {
    /// Returns the content for the Try AI EOJ dialog or `nil` for the standard end-of-journey dialog.
    var dialogContent: OnboardingEndOfJourneyTryAIContent? { get }
}

protocol OnboardingEndOfJourneyTryAIDialogDeciding {
    /// Returns `true` if the EOJ Try AI Dialog should be presented, false otherwise
    /// Qualifies only when all hold:
    /// - The Default onboarding flow (not the Duck.ai CPP flow).
    /// - A Search-path download reason — `browserPrivately` / `noAI` / `blockAds`.
    /// - The user opted into AI chat in the address bar during onboarding (Toggle = ON).
    /// - The user performed a Search and not an AI chat.
    var shouldPresentTryAIDialog: Bool { get }
}

struct OnboardingEndOfJourneyTryAIProvider {
    /// Search-path reasons — those whose tailored flow includes an AI-chat address-bar toggle screen, so
    /// `didEnableAIChatSearchInputDuringOnboarding` reflects a real choice rather than the default.
    private static let searchPathReasons: Set<OnboardingDownloadReason> = [.browserPrivately, .noAI, .blockAds]

    private let onboardingManager: OnboardingFlowProviding & OnboardingDownloadReasonHandling
    private let searchExperienceProvider: OnboardingSearchExperienceProvider

    init(
        onboardingManager: OnboardingFlowProviding & OnboardingDownloadReasonHandling = OnboardingManager(),
        searchExperienceProvider: OnboardingSearchExperienceProvider = OnboardingSearchExperience()
    ) {
        self.onboardingManager = onboardingManager
        self.searchExperienceProvider = searchExperienceProvider
    }
}

// MARK: - OnboardingEndOfJourneyTryAIDialogDeciding

extension OnboardingEndOfJourneyTryAIProvider: OnboardingEndOfJourneyTryAIDialogDeciding {

    var shouldPresentTryAIDialog: Bool {
        dialogContent != nil
    }
}

// MARK: - OnboardingEndOfJourneyTryAIContentProviding

extension OnboardingEndOfJourneyTryAIProvider: OnboardingEndOfJourneyTryAIContentProviding {

    var dialogContent: OnboardingEndOfJourneyTryAIContent? {
        guard
            // The Default onboarding flow (not the Duck.ai CPP flow)
            onboardingManager.currentOnboardingFlow == .default,
            // The user selected one of `.browserPrivately`, `.noAI`, `.blockAds` download reasons
            let reason = onboardingManager.currentDownloadReason,
            Self.searchPathReasons.contains(reason),
            // The user opted into AI chat in the address bar during onboarding
            searchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding,
            // The user performed a Search and not an AI chat.
            !searchExperienceProvider.didStartAIChatDuringOnboarding
        else {
            return nil
        }

        return OnboardingEndOfJourneyTryAIContent(
            title: UserText.Onboarding.ContextualOnboarding.EndOFJourney.title,
            message: UserText.Onboarding.ContextualOnboarding.EndOFJourney.message,
            primaryCTA: UserText.Onboarding.ContextualOnboarding.EndOFJourney.primaryButton,
            secondaryCTA: UserText.Onboarding.ContextualOnboarding.EndOFJourney.secondaryButton
        )
    }
    
}
