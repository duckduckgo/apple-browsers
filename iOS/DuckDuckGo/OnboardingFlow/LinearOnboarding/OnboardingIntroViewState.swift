//
//  OnboardingIntroViewState.swift
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

enum OnboardingIntroViewState: Equatable {
    case landing(OnboardingLandingContent)
    case onboarding(Intro)

    var intro: Intro? {
        switch self {
        case .landing:
            return nil
        case let .onboarding(intro):
            return intro
        }
    }
}

extension OnboardingIntroViewState {

    struct Intro: Equatable {
        let type: IntroType
        let step: StepInfo
    }

}

extension OnboardingIntroViewState.Intro {

    enum IntroDialogType: Equatable {
        case `default`
        case restoreData
        case skipTutorial
    }

    enum IntroType: Equatable {
        case startOnboardingDialog(content: OnboardingIntroStepContent, type: IntroDialogType)
        case setDefaultBrowserDialog(content: OnboardingComparisonContent)
        case aiIntroDialog(content: OnboardingComparisonContent)
        case addToDockPromoDialog(content: OnboardingAddToDockContent)
        case chooseAppIconDialog(content: OnboardingAppIconColorContent)
        case chooseAddressBarPositionDialog(content: OnboardingAddressBarPositionContent)
        case chooseSearchExperienceDialog(content: OnboardingSearchExperienceContent)
        case duckAIQueryDialog(content: OnboardingDuckAIQueryContent, defaultMode: DuckAIQueryMode)
    }

    struct StepInfo: Equatable {
        let currentStep: Int
        let totalSteps: Int

        static let hidden = StepInfo(currentStep: 0, totalSteps: 0)
    }

}

extension OnboardingIntroViewState.Intro.IntroType {
    var isDuckAIQueryScreen: Bool {
        if case .duckAIQueryDialog = self {
            return true
        } else {
            return false
        }
    }

}
