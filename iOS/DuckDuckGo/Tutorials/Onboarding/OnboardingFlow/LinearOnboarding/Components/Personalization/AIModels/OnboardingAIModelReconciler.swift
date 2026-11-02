//
//  OnboardingAIModelReconciler.swift
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
import AIChat
import Persistence

/// Keeps the AI model picked during onboarding usable when that specific model is replaced.
///
/// Onboarding persists the chosen model id (read by Duck.ai) and its provider. When the model is retired, Duck.ai would
/// fall back to its default model. Instead, this moves the user to the first available model of the provider they chose.
@MainActor
final class OnboardingAIModelReconciler {
    private let tutorialSettings: TutorialSettings
    private var preferences: AIChatPreferencesPersisting
    private let providerStore: any KeyedStoring<OnboardingAIModelStoringKeys>
    private let prefetcher: OnboardingAIModelsPrefetching

    init(
        tutorialSettings: TutorialSettings = DefaultTutorialSettings(),
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        providerStore: any KeyedStoring<OnboardingAIModelStoringKeys> = UserDefaults.app.keyedStoring(),
        prefetcher: OnboardingAIModelsPrefetching? = nil
    ) {
        self.tutorialSettings = tutorialSettings
        self.preferences = preferences
        self.providerStore = providerStore
        self.prefetcher = prefetcher ?? OnboardingAIModelsPrefetcher()
    }

    func reconcile() async {
        // Only for users who picked the private AI chat download reason.
        guard tutorialSettings.onboardingDownloadReason == .privateAIChat else { return }

        // Only on a successful models fetch.
        await prefetcher.prefetch().value
        guard let models = prefetcher.fetchedModels, !models.isEmpty else { return }

        let selectedModel = preferences.selectedModelId.flatMap { id in models.first { $0.id == id } }

        guard let provider = providerStore.selectedModelProvider else {
            // No provider stored, model still available: back-fill the provider and keep the model, which may have been changed after onboarding.
            // No provider stored, model not available: do nothing, so Duck.ai uses its default.
            if let selectedModel {
                providerStore.selectedModelProvider = selectedModel.provider
            }
            return
        }

        // Provider stored, model still available: do nothing.
        guard selectedModel == nil else { return }

        // Provider stored, model not available or cleared: select the provider's first available model.
        guard let replacement = models.first(where: { $0.provider == provider }) else { return }
        preferences.selectedModelId = replacement.id
        preferences.selectedModelShortName = replacement.modelShortName
    }
}

// MARK: - Launch Task

struct OnboardingAIModelReconcileLaunchTask: LaunchTask {

    var name: String = "Reconcile Onboarding AI Model"

    func run(context: LaunchTaskContext) {
        Task { @MainActor in
            await OnboardingAIModelReconciler().reconcile()
            context.finish()
        }
    }

}
