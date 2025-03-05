//
//  DefaultBrowserAndDockPromptExperimentDeciding.swift
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

protocol DefaultBrowserAndDockPromptExperimentDeciding {
    var isUserEligibleForExperiment: Bool { get }
}

final class DefaultBrowserAndDockPromptExperimentDecider: DefaultBrowserAndDockPromptExperimentDeciding {
    private let wasOnboardingCompleted: Bool
    private let isNewUser: Bool
    private let isEligibleForPrompt: Bool

    init(wasOnboardingCompleted: Bool = Application.appDelegate.onboardingStateMachine.state == .onboardingCompleted && OnboardingViewModel._isOnboardingFinished,
         isNewUser: Bool = AppDelegate.isNewUser,
         isEligibleForPrompt: Bool) {
        self.wasOnboardingCompleted = wasOnboardingCompleted
        self.isNewUser = isNewUser
        self.isEligibleForPrompt = isEligibleForPrompt
    }

    var isUserEligibleForExperiment: Bool {
        return !isNewUser && wasOnboardingCompleted && isEligibleForPrompt
    }
}
