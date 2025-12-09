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
import Common
import BrowserServicesKit

struct ExperimentalAIChatManager {
    private let featureFlagger: FeatureFlagger
    private let userDefaults: UserDefaults
    private let experimentalAIChatSettingsKey = "experimentalAIChatSettingsEnabled"
    private let devicePlatform: DevicePlatformProviding.Type

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         userDefaults: UserDefaults = .standard,
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.featureFlagger = featureFlagger
        self.userDefaults = userDefaults
        self.devicePlatform = devicePlatform
    }

    var isExperimentalAIChatFeatureFlagEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.experimentalAddressBar, allowOverride: true)
    }
    
    var fullDuckAIModeExperimentalSettingFlagEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.fullDuckAIModeExperimentalSetting, allowOverride: true) && devicePlatform.isIphone
    }

    var isExperimentalAIChatSettingsEnabled: Bool {
        get {
            isExperimentalAIChatFeatureFlagEnabled && userDefaults.bool(forKey: experimentalAIChatSettingsKey)
        }
        set {
            userDefaults.set(newValue, forKey: experimentalAIChatSettingsKey)
        }
    }

    var isStandaloneMigrationSupported: Bool {
        featureFlagger.isFeatureOn(.standaloneMigration)
    }

    mutating func toggleExperimentalTheming() {
        isExperimentalAIChatSettingsEnabled.toggle()
    }
}
