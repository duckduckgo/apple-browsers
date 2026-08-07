//
//  OnboardingStepsHelper.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Onboarding
@testable import DuckDuckGo

struct OnboardingStepsHelper {
    static func expectedIPhoneSteps(isReturningUser: Bool) -> [OnboardingIntroStep] {
        [
            .introDialog(isReturningUser: isReturningUser),
            .setDefaultBrowser,
            .addToDockPromo,
            .appIconSelection,
            .addressBarPositionSelection,
            .searchExperienceSelection
        ]
    }

    static func expectedIPadSteps(isReturningUser: Bool) -> [OnboardingIntroStep] {
        [
            .introDialog(isReturningUser: isReturningUser),
            .setDefaultBrowser,
            .appIconSelection
        ]
    }

    static func expectedIPadStepsWithSearchExperience(isReturningUser: Bool) -> [OnboardingIntroStep] {
        expectedIPadSteps(isReturningUser: isReturningUser) + [.searchExperienceSelection]
    }

    static func expectedDuckAISteps(isReturningUser: Bool) -> [OnboardingIntroStep] {
        [
            .introDialog(isReturningUser: isReturningUser),
            .aiIntro,
            .duckAIQuerySelection,
            .interlude(.duckAI),
            .addToDockPromo,
            .setDefaultBrowser,
            .addressBarPositionSelection
        ]
    }

    /// The remaining steps that follow the Download Screen for a given reason
    static func expectedRemainingSteps(for reason: OnboardingDownloadReason) -> [OnboardingIntroStep] {
        let commonSteps: [OnboardingIntroStep] = [.addressBarPositionSelection, .addToDockPromo, .appIconSelection, .duckAIQuerySelection]

        let personalisationSteps: [OnboardingIntroStep]
        switch reason {
        case .browserPrivately:
            personalisationSteps = [.searchPrivacySettingsSelection, .searchExperienceSelection]
        case .privateAIChat:
            personalisationSteps = [.aiModelSelection, .toggleInputModeSelection]
        case .noAI:
            personalisationSteps = [.aiSearchSettingsSelection, .keepDuckAISelection]
        case .blockAds:
            personalisationSteps = [.duckPlayerSelection, .searchExperienceSelection]
        }

        return [.setDefaultBrowser] + personalisationSteps + commonSteps
    }
}
