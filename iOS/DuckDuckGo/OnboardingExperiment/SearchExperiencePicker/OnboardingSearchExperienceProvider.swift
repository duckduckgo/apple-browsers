//
//  OnboardingSearchExperienceProvider.swift
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

import Foundation
import Core
import Persistence

protocol OnboardingSearchExperienceProvider {
    var didEnableAIChatSearchInputDuringOnboarding: Bool { get }
    func enableAIChatSearchInputDuringOnboarding(enable: Bool)
}

final class OnboardingSearchExperience: OnboardingSearchExperienceProvider {
    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults()) {
        self.keyValueStore = keyValueStore
    }

    var didEnableAIChatSearchInputDuringOnboarding: Bool {
        (
            keyValueStore.object(forKey: .didEnableAIChatSearchInputDuringOnboardingKey) as? Bool
        ) ?? .didEnableAIChatSearchInputDuringOnboardingDefaultValue
    }

    func enableAIChatSearchInputDuringOnboarding(enable: Bool) {
        keyValueStore.set(enable, forKey: .didEnableAIChatSearchInputDuringOnboardingKey)
#warning("🇳🇴 implement pixels")
    }
}

private extension String {
    static let didEnableAIChatSearchInputDuringOnboardingKey = "onboarding.didEnableAIChatSearchInputDuringOnboarding"
}

private extension Bool {
    static let didEnableAIChatSearchInputDuringOnboardingDefaultValue: Bool = true
}
