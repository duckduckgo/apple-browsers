//
//  PromptCooldownIntervalProvider.swift
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
import BrowserServicesKit

/// A type providing the cooldown interval, in hours, between prompt presentations.
protocol PromptCooldownIntervalProviding {
    /// The cooldown interval in hours between prompt presentations.
    var cooldownInterval: Int { get }
}

enum PromptCooldownIntervalSettings: String {
    /// The setting for prompt cooldown period.
    case promptCooldownInterval

    public var defaultValue: Int {
        switch self {
        case .promptCooldownInterval: return 24 // Default cooldown for prompt is 24 hours.
        }
    }
}

struct PromptCooldownIntervalProvider {
    private let privacyConfigManager: PrivacyConfigurationManaging

    private var remoteSettings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        privacyConfigManager.privacyConfig.settings(for: .iOSBrowserConfig)
    }

    init(privacyConfigManager: PrivacyConfigurationManaging) {
        self.privacyConfigManager = privacyConfigManager
    }
}

// MARK: - PromptCooldownPeriodProviding

extension PromptCooldownIntervalProvider: PromptCooldownIntervalProviding {

    var cooldownInterval: Int {
        getSettings(PromptCooldownIntervalSettings.promptCooldownInterval)
    }

    private func getSettings(_ value: PromptCooldownIntervalSettings) -> Int {
        remoteSettings[value.rawValue] as? Int ?? value.defaultValue
    }

}
