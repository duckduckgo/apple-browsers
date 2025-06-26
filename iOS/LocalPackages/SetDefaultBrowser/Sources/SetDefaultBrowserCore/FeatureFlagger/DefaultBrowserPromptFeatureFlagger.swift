//
//  DefaultBrowserPromptFeatureFlagger.swift
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

public protocol DefaultBrowserPromptFeatureFlagProvider {
    /// A Boolean value indicating whether Set Default Browser Prompts are enabled.
    /// - Returns: `true` if the feature is enabled; otherwise, `false`.
    var isDefaultBrowserPromptsFeatureEnabled: Bool { get }
}

public protocol DefaultBrowserPromptFeatureFlagSettingsProvider {
    // A dictionary representing the settings for the feature.
    var featureSettings: [String: Any] { get }
}

/// An enum representing the different settings for Set Default Browser Prompts feature flag.
enum DefaultBrowserPromptFeatureSettings: String {
    /// The setting for the number of days to wait after app installation before showing the first modal. Default to 1 day.
    case firstModalDelayDays
    /// The setting for the number of days to wait after the first modal has been shown before displaying the second modal. Default to 4 days.
    case secondModalDelayDays
    /// The settings for the number of days between subsequent displays of the modal. Default to 14 days.
    case subsequentModalRepeatIntervalDays

    var defaultValue: Int {
        switch self {
        case .firstModalDelayDays: return 1
        case .secondModalDelayDays: return 4
        case .subsequentModalRepeatIntervalDays: return 14
        }
    }
}

package protocol DefaultBrowserPromptFeatureFlagger: DefaultBrowserPromptFeatureFlagProvider {
    /// The number of active days to wait after app installation before showing the first modal. Default is 1.
    var firstModalDelayDays: Int { get }
    /// The number of active days to wait after the first modal has been shown before displaying the second modal. Default is 4.
    var secondModalDelayDays: Int { get }
    /// The number of active days between subsequent displays of the modal. Default is 14.
    var subsequentModalRepeatIntervalDays: Int { get }
}

package final class DefaultBrowserPromptFeatureFlag {
    private let settingsProvider: DefaultBrowserPromptFeatureFlagSettingsProvider
    private let featureFlagProvider: DefaultBrowserPromptFeatureFlagProvider

    package init(settingsProvider: DefaultBrowserPromptFeatureFlagSettingsProvider, featureFlagProvider: DefaultBrowserPromptFeatureFlagProvider) {
        self.settingsProvider = settingsProvider
        self.featureFlagProvider = featureFlagProvider
    }
}

// MARK: - DefaultBrowserPromptFeatureFlagger

extension DefaultBrowserPromptFeatureFlag: DefaultBrowserPromptFeatureFlagger {

    public var isDefaultBrowserPromptsFeatureEnabled: Bool {
        featureFlagProvider.isDefaultBrowserPromptsFeatureEnabled
    }

    package var firstModalDelayDays: Int {
        getSettings(.firstModalDelayDays)
    }

    package var secondModalDelayDays: Int {
        getSettings(.secondModalDelayDays)
    }

    package var subsequentModalRepeatIntervalDays: Int {
        getSettings(.subsequentModalRepeatIntervalDays)
    }

    private func getSettings(_ value: DefaultBrowserPromptFeatureSettings) -> Int {
        settingsProvider.featureSettings[value.rawValue] as? Int ?? value.defaultValue
    }

}
