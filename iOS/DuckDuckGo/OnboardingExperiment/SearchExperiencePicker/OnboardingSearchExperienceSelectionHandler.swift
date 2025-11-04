//
//  OnboardingSearchExperienceSelectionHandler.swift
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

import Combine
import AIChat

protocol OnboardingSearchExperienceStoring {
    //
}

struct OnboardingSearchExperienceStorage: OnboardingSearchExperienceStoring {
    //
}

final class OnboardingSearchExperienceSelectionHandler {
    private let contextualOnboardingLogic: ContextualOnboardingLogic
    private let aiChatSettings: AIChatSettingsProvider
    private var cancellables: Set<AnyCancellable> = []

    init(contextualOnboardingLogic: ContextualOnboardingLogic, aiChatSettings: AIChatSettingsProvider) {
        self.contextualOnboardingLogic = contextualOnboardingLogic
        self.aiChatSettings = aiChatSettings
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        contextualOnboardingLogic.isDismissedPublisher
            .sink { isDismissed /*[weak self]*/ in
                print("🇳🇴🟡 [OnboardingSearchExperienceSelectionHandler] isDismissed changed to: \(isDismissed) (so isEnabled is: \(!isDismissed))")
//                self?.updateAIChatSettings()
            }
            .store(in: &cancellables)
    }
    private func updateAIChatSettings() {
        //        store in user defaults that I did this setting, this will be my first guard
//         read & guard user-defaults storage (user selection)
//         toggle as a default (if onboarding skipped)
//         I'll use OnboardingSearchExperienceStoring during onboarding and in DefaultOmniBarViewController (if needed)
//         Use feature flag guard here as well
//         subscribe to publisher, confirm with isEnabled (not sure if needed)
        aiChatSettings.enableAIChatSearchInputUserSettings(enable: true)
    }
}
