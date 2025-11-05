//
//  DefaultBrowserAndDockPromptFeatureFlagger.swift
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
import FeatureFlags

public protocol DefaultBrowserAndDockPromptActiveUserFeatureFlagProvider {
    /// A Boolean value indicating whether Set Default Browser (SAD) and Add To Dock (ATT) are enabled for active users.
    /// - Returns: `true` if the feature is enabled; otherwise, `false`.
    var isDefaultBrowserAndDockPromptForActiveUsersFeatureEnabled: Bool { get }
}

public protocol DefaultBrowserAndDockPromptInactiveUserFeatureFlagProvider {
    /// A Boolean value indicating whether Set Default Browser (SAD) and Add To Dock (ATT) are enabled for inactive users.
    /// - Returns: `true` if the feature is enabled; otherwise, `false`.
    var isDefaultBrowserAndDockPromptForInactiveUsersFeatureEnabled: Bool { get }
}

public typealias DefaultBrowserAndDockPromptFeatureFlagProvider = DefaultBrowserAndDockPromptActiveUserFeatureFlagProvider & DefaultBrowserAndDockPromptInactiveUserFeatureFlagProvider

public protocol DefaultBrowserAndDockPromptActiveUserFeatureFlagsSettingsProvider {
    /// The number of days to wait after app installation before showing the first popover
    var firstPopoverDelayDays: Int { get }
    /// The number of days to wait after the popover has been shown before displaying the banner.
    var bannerAfterPopoverDelayDays: Int { get }
    /// The number of days between subsequent displays of the banner.
    var bannerRepeatIntervalDays: Int { get }
}

public protocol DefaultBrowserAndDockPromptInactiveUserFeatureFlagsSettingsProvider {
    /// The number of days to wait after app installation before showing the inactive user modal.
    var inactiveModalNumberOfDaysSinceInstall: Int { get }
    /// The number of inactive days to wait before showing the inactive user modal.
    var inactiveModalNumberOfInactiveDays: Int { get }
}

public typealias DefaultBrowserAndDockPromptFeatureFlagsSettingsProvider = DefaultBrowserAndDockPromptActiveUserFeatureFlagsSettingsProvider & DefaultBrowserAndDockPromptInactiveUserFeatureFlagsSettingsProvider

/// An enum representing the different settings for Set Default Browser (SAD) and Add to Dock (ATT) feature flag.
public enum DefaultBrowserAndDockPromptFeatureSettings: String {
    /// The setting for the number of days to wait after app installation before showing the first popover. Default to 14 days.
    case firstPopoverDelayDays
    /// The setting for the number of days to wait after the popover has been shown before displaying the banner. Default to 14 days.
    case bannerAfterPopoverDelayDays
    /// The settings for the number of days between subsequent displays of the banner. Default to 14 days.
    case bannerRepeatIntervalDays
    /// The setting for the number of days to wait after app installation before showing the inactive user modal.
    case inactiveModalNumberOfDaysSinceInstall
    /// The setting for the number of inactive days to wait before showing the inactive user modal.
    case inactiveModalNumberOfInactiveDays

    public var defaultValue: Int {
        switch self {
        case .firstPopoverDelayDays: return 14
        case .bannerAfterPopoverDelayDays: return 14
        case .bannerRepeatIntervalDays: return 14
        case .inactiveModalNumberOfDaysSinceInstall: return 28
        case .inactiveModalNumberOfInactiveDays: return 7
        }
    }
}

typealias DefaultBrowserAndDockPromptFeatureFlagger = DefaultBrowserAndDockPromptFeatureFlagProvider & DefaultBrowserAndDockPromptFeatureFlagsSettingsProvider

final class DefaultBrowserAndDockPromptFeatureFlag {
    private let privacyConfigManager: PrivacyConfigurationManaging
    private let featureFlagger: FeatureFlagger

    private var remoteSettings: PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        privacyConfigManager.privacyConfig.settings(for: .setAsDefaultAndAddToDock)
    }

    public init(privacyConfigManager: PrivacyConfigurationManaging, featureFlagger: FeatureFlagger) {
        self.privacyConfigManager = privacyConfigManager
        self.featureFlagger = featureFlagger
    }
}

// MARK: - DefaultBrowserAndDockPromptFeatureFlagger

extension DefaultBrowserAndDockPromptFeatureFlag: DefaultBrowserAndDockPromptFeatureFlagProvider {

    public var isDefaultBrowserAndDockPromptForActiveUsersFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.scheduledSetDefaultBrowserAndAddToDockPrompts)
    }

    public var isDefaultBrowserAndDockPromptForInactiveUsersFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.scheduledDefaultBrowserAndDockPromptsInactiveUser)
    }

}

// MARK: - DefaultBrowserAndDockPromptFeatureFlagsSettingsProvider

extension DefaultBrowserAndDockPromptFeatureFlag: DefaultBrowserAndDockPromptFeatureFlagsSettingsProvider {

    public var firstPopoverDelayDays: Int {
        getSettings(.firstPopoverDelayDays)
    }

    public var bannerAfterPopoverDelayDays: Int {
        getSettings(.bannerAfterPopoverDelayDays)
    }

    public var bannerRepeatIntervalDays: Int {
        getSettings(.bannerRepeatIntervalDays)
    }

    var inactiveModalNumberOfDaysSinceInstall: Int {
        getSettings(.inactiveModalNumberOfDaysSinceInstall)
    }

    var inactiveModalNumberOfInactiveDays: Int {
        getSettings(.inactiveModalNumberOfInactiveDays)
    }

    private func getSettings(_ value: DefaultBrowserAndDockPromptFeatureSettings) -> Int {
        remoteSettings[value.rawValue] as? Int ?? value.defaultValue
    }

}
