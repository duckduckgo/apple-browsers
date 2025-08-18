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

public protocol DefaultBrowserPromptActiveUserFeatureFlagProvider {
    /// A Boolean value indicating whether Set Default Browser Prompts are enabled for active users.
    /// - Returns: `true` if the feature is enabled; otherwise, `false`.
    var isDefaultBrowserPromptsForActiveUsersFeatureEnabled: Bool { get }
}

public protocol DefaultBrowserPromptInactiveUserFeatureFlagProvider {
    /// A Boolean value indicating whether Set Default Browser Prompts are enabled for inactive users.
    /// - Returns: `true` if the feature is enabled; otherwise, `false`.
    var isDefaultBrowserPromptsForInactiveUsersFeatureEnabled: Bool { get }
}

public typealias DefaultBrowserPromptFeatureFlagProvider = DefaultBrowserPromptActiveUserFeatureFlagProvider & DefaultBrowserPromptInactiveUserFeatureFlagProvider

public protocol DefaultBrowserPromptFeatureFlagSettingsProvider {
    // A dictionary representing the settings for the feature.
    var defaultBrowserPromptFeatureSettings: [String: Any] { get }
}

/// An enum representing the different settings for Set Default Browser Prompts feature flag.
public enum DefaultBrowserPromptFeatureSettings: String {
    /// The setting for the number of days to wait after app installation before showing the first modal. Default to 1 day.
    case firstActiveModalDelayDays
    /// The setting for the number of days to wait after the first modal has been shown before displaying the second modal. Default to 4 days.
    case secondActiveModalDelayDays
    /// The settings for the number of days between subsequent displays of the modal. Default to 14 days.
    case subsequentActiveModalRepeatIntervalDays
    /// The setting for the number of days to wait after app installation before showing the modal to inactive users. Default to 28.
    case inactiveModalNumberOfDaysSinceInstall
    /// The setting for the number of inactive days to wait before showing the modal to inactive users. Default to 7.
    case inactiveModalNumberOfInactiveDays

    public var defaultValue: Int {
        switch self {
        case .firstActiveModalDelayDays: return 1
        case .secondActiveModalDelayDays: return 4
        case .subsequentActiveModalRepeatIntervalDays: return 14
        case .inactiveModalNumberOfDaysSinceInstall: return 28
        case .inactiveModalNumberOfInactiveDays: return 7
        }
    }
}

package protocol DefaultBrowserPromptActiveUserFeatureFlagger: DefaultBrowserPromptActiveUserFeatureFlagProvider {
    /// The number of active days to wait after app installation before showing the first modal for active users. Default is 1.
    var firstActiveModalDelayDays: Int { get }
    /// The number of active days to wait after the first modal has been shown before displaying the second modal for active users. Default is 4.
    var secondActiveModalDelayDays: Int { get }
    /// The number of active days between subsequent displays of the modal for active users. Default is 14.
    var subsequentActiveModalRepeatIntervalDays: Int { get }
}

package protocol DefaultBrowserPromptInactiveUserFeatureFlagger: DefaultBrowserPromptInactiveUserFeatureFlagProvider {
    /// The setting for the number of days to wait after app installation before showing the modal to inactive users. Default to 28.
    var inactiveModalNumberOfDaysSinceInstall: Int { get }
    /// The setting for the number of inactive days to wait before showing the modal to inactive users. Default to 7.
    var inactiveModalNumberOfInactiveDays: Int { get }
}

package typealias DefaultBrowserPromptFeatureFlagger = DefaultBrowserPromptActiveUserFeatureFlagger & DefaultBrowserPromptInactiveUserFeatureFlagger

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

    public var isDefaultBrowserPromptsForActiveUsersFeatureEnabled: Bool {
        featureFlagProvider.isDefaultBrowserPromptsForActiveUsersFeatureEnabled
    }

    public var isDefaultBrowserPromptsForInactiveUsersFeatureEnabled: Bool {
        featureFlagProvider.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled
    }

    package var firstActiveModalDelayDays: Int {
        getSettings(.firstActiveModalDelayDays)
    }

    package var secondActiveModalDelayDays: Int {
        getSettings(.secondActiveModalDelayDays)
    }

    package var subsequentActiveModalRepeatIntervalDays: Int {
        getSettings(.subsequentActiveModalRepeatIntervalDays)
    }

    package var inactiveModalNumberOfDaysSinceInstall: Int {
        getSettings(.inactiveModalNumberOfDaysSinceInstall)
    }

    package var inactiveModalNumberOfInactiveDays: Int {
        getSettings(.inactiveModalNumberOfInactiveDays)
    }

    private func getSettings(_ value: DefaultBrowserPromptFeatureSettings) -> Int {
        settingsProvider.defaultBrowserPromptFeatureSettings[value.rawValue] as? Int ?? value.defaultValue
    }

}
