//
//  OnboardingIntroFactory.swift
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

import AIChat
import Onboarding
import Persistence
import SystemSettingsPiPTutorial
import UIKit
import WebExtensions

@MainActor
enum OnboardingIntroFactory {

    /// Builds a view model wired with all dependencies the linear onboarding needs.
    static func makeViewModel(
        pixelReporter: OnboardingPixelReporting,
        systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
        daxDialogsManager: DaxDialogsManaging,
        syncAutoRestoreHandler: SyncAutoRestoreHandling,
        onboardingManager: OnboardingManaging,
        keyValueStore: ThrowingKeyValueStoring,
        adBlockingAvailability: AdBlockingAvailabilityProviding
    ) -> OnboardingIntroViewModel {
        OnboardingIntroViewModel(
            pixelReporter: pixelReporter,
            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
            daxDialogsManager: daxDialogsManager,
            restorePromptHandler: OnboardingRestorePromptHandler(
                configuration: .enabled,
                syncAutoRestoreHandler: syncAutoRestoreHandler
            ),
            onboardingManager: onboardingManager,
            personalizationManager: OnboardingPersonalizationManager.make(
                keyValueStore: keyValueStore,
                adBlockingAvailability: adBlockingAvailability
            )
        )
    }

    /// Wraps an existing view model in the legacy or rebranded onboarding view.
    /// 
    /// - Parameters:
    ///   - viewModel: The ViewModel to wire.
    ///   - delegate: The delegate for the onboarding flow.
    /// - Returns: A new instance of the linear onboarding view controller with the provided view model.
    static func makeController(
        viewModel: OnboardingIntroViewModel,
        delegate: OnboardingDelegate
    ) -> UIViewController {
        let controller = OnboardingIntroViewController(
                rootView: OnboardingView(model: viewModel),
                viewModel: viewModel
            )
        controller.delegate = delegate
        return controller
    }
}

// MARK: - Personalization manager composition

private extension OnboardingPersonalizationManager {

    /// Builds the personalization facade wired to the app's concrete settings stores.
    ///
    /// Most stores are stateless wrappers over persistence and are created inline. The two that need
    /// shared, app-lifetime instances are injected: `keyValueStore` (where the settings actually live)
    /// and `adBlockingAvailability` (session state owned by the app).
    static func make(
        keyValueStore: ThrowingKeyValueStoring,
        adBlockingAvailability: AdBlockingAvailabilityProviding
    ) -> OnboardingPersonalizationManaging {
        let serpSettings = SERPSettingsProvider(aiChatProvider: AIChatSettings())
        serpSettings.keyValueStore = keyValueStore   // otherwise safe-search reads/writes no-op

        return OnboardingPersonalizationManager(
            appSettings: AppUserDefaults(),
            serpSettings: serpSettings,
            aiChatSettings: AIChatSettings(),
            aiModelSettings: OnboardingAIModelAdapter(persistor: AIChatPreferencesPersistor()),
            youTubeAdBlocking: OnboardingYouTubeAdBlockingAdapter(
                keyValueStore: keyValueStore,
                adBlockingAvailability: adBlockingAvailability
            )
        )
    }
}
