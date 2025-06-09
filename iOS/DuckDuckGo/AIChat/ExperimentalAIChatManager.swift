//
//  ExperimentalAIChatManager.swift
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
import BrowserServicesKit

struct ExperimentalAIChatManager {
    private let featureFlagger: FeatureFlagger
    private let userDefaults: UserDefaults
    private let experimentalAIChatSettingsKey = "experimentalAIChatSettingsEnabled"

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         userDefaults: UserDefaults = .standard) {
        self.featureFlagger = featureFlagger
        self.userDefaults = userDefaults
    }

    var isExperimentalAIChatFeatureFlagEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.experimentalAIChat)
    }

    var isExperimentalTransitionEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.experimentalSwitcherBarTransition, allowOverride: true)
    }

    var isExperimentalAIChatSettingsEnabled: Bool {
        get {
            isExperimentalAIChatFeatureFlagEnabled && userDefaults.bool(forKey: experimentalAIChatSettingsKey)
        }
        set {
            userDefaults.set(newValue, forKey: experimentalAIChatSettingsKey)
        }
    }

    mutating func toggleExperimentalTheming() {
        isExperimentalAIChatSettingsEnabled.toggle()
    }

    mutating func toggleExperimentalTransition() {
        featureFlagger.localOverrides?.toggleOverride(for: FeatureFlag.experimentalSwitcherBarTransition)
    }
}
