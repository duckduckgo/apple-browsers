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

import Onboarding
import SystemSettingsPiPTutorial
import UIKit

@MainActor
enum OnboardingIntroFactory {

    /// Builds a view model wired with all dependencies the linear onboarding needs.
    static func makeViewModel(
        pixelReporter: OnboardingPixelReporting,
        systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
        daxDialogsManager: DaxDialogsManaging,
        syncAutoRestoreHandler: SyncAutoRestoreHandling,
        onboardingManager: OnboardingManaging
    ) -> OnboardingIntroViewModel {
        OnboardingIntroViewModel(
            pixelReporter: pixelReporter,
            systemSettingsPiPTutorialManager: systemSettingsPiPTutorialManager,
            daxDialogsManager: daxDialogsManager,
            restorePromptHandler: OnboardingRestorePromptHandler(
                configuration: .enabled,
                syncAutoRestoreHandler: syncAutoRestoreHandler
            ),
            onboardingManager: onboardingManager
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
