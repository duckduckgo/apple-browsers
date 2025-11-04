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
import BrowserServicesKit

final class OnboardingSearchExperienceSelectionHandler {
    private let contextualOnboardingLogic: ContextualOnboardingLogic
    private let aiChatSettings: AIChatSettingsProvider
    private let featureFlagger: FeatureFlagger
    private var onboardingSearchExperienceProvider: OnboardingSearchExperienceProvider

    private var cancellables: Set<AnyCancellable> = []

    init(contextualOnboardingLogic: ContextualOnboardingLogic, aiChatSettings: AIChatSettingsProvider, featureFlagger: FeatureFlagger, onboardingSearchExperienceProvider: OnboardingSearchExperienceProvider) {
        self.contextualOnboardingLogic = contextualOnboardingLogic
        self.aiChatSettings = aiChatSettings
        self.featureFlagger = featureFlagger
        self.onboardingSearchExperienceProvider = onboardingSearchExperienceProvider
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        contextualOnboardingLogic.isDismissedPublisher
            .sink { [weak self] isDismissed in
                print("🇳🇴🟡 [OnboardingSearchExperienceSelectionHandler] isDismissed changed to: \(isDismissed) (so isEnabled is: \(!isDismissed))")
                self?.updateAIChatSettings(isDaxDialogsOnboardingDismissed: isDismissed)
            }
            .store(in: &cancellables)
    }
    private func updateAIChatSettings(isDaxDialogsOnboardingDismissed: Bool) {
        guard featureFlagger.isFeatureOn(.onboardingSearchExperience) else { return }
        guard isDaxDialogsOnboardingDismissed else { return }
        guard onboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings == false else { return }

        aiChatSettings.enableAIChatSearchInputUserSettings(enable: onboardingSearchExperienceProvider.didEnableAIChatSearchInputDuringOnboarding)
        onboardingSearchExperienceProvider.didApplyOnboardingChoiceSettings = true
    }
}
