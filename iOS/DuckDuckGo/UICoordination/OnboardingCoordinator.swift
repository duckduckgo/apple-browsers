//
//  OnboardingCoordinator.swift
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
import PrivacyConfig
import BrowserServicesKit

@MainActor
protocol OnboardingCoordinating: AnyObject {
    func startOnboardingFlowIfNotSeenBefore(url: URL?)
}

protocol OnboardingPresenting: AnyObject {
    func presentOnboardingFlowIfNotSeenBefore()
}

final class OnboardingCoordinator: OnboardingCoordinating {
    let manager: OnboardingManager
    private var presenter: OnboardingPresenting?

    init(appSettings: AppSettings, featureFlagger: FeatureFlagger, variantManager: VariantManager) {
        self.manager = OnboardingManager(appDefaults: appSettings, featureFlagger: featureFlagger, variantManager: variantManager, tutorialSettings: DefaultTutorialSettings())
    }

    func setPresenter(_ presenter: OnboardingPresenting) {
        self.presenter = presenter
    }

    @MainActor
    func startOnboardingFlowIfNotSeenBefore(url: URL?) {
        // 1. Determine onboarding flow to show
        manager.configureOnboardingFlow(from: url)
        // 2. Present onboarding if needed
        presenter?.presentOnboardingFlowIfNotSeenBefore()
    }
}
