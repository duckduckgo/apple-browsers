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
    var didApplyOnboardingChoiceSettings: Bool { get set }

    func storeAIChatSearchInputDuringOnboardingChoice(enable: Bool)
}

final class OnboardingSearchExperience: OnboardingSearchExperienceProvider {
    private let storage: KeyValueStoring
    init(keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.storage = keyValueStore
    }

    var didEnableAIChatSearchInputDuringOnboarding: Bool {
        (
            storage.object(forKey: .didEnableAIChatSearchInputDuringOnboardingKey) as? Bool
        ) ?? .didEnableAIChatSearchInputDuringOnboardingDefaultValue
    }

    var didApplyOnboardingChoiceSettings: Bool {
        // Only check if the variable has been set
        get { storage.object(forKey: .didApplyOnboardingChoiceSettings) != nil }
        set { storage.set(newValue, forKey: .didApplyOnboardingChoiceSettings) }
    }

    func storeAIChatSearchInputDuringOnboardingChoice(enable: Bool) {
        storage.set(enable, forKey: .didEnableAIChatSearchInputDuringOnboardingKey)
    }
}

private extension String {
    static let didEnableAIChatSearchInputDuringOnboardingKey = "com.duckduckgo.ios.onboarding.didEnableAIChatSearchInputDuringOnboarding"
    static let didApplyOnboardingChoiceSettings = "com.duckduckgo.ios.onboarding.didApplyOnboardingChoiceSettings"
}

private extension Bool {
    static let didEnableAIChatSearchInputDuringOnboardingDefaultValue: Bool = true
}
