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
import struct Common.CodableHelper
import FeatureFlags

public protocol DefaultBrowserAndDockPromptFeatureFlagProvider {
    /// A Boolean value indicating whether Set Default Browser (SAD) and Add To Dock (ATT) are enabled.
    /// - Returns: `true` if the feature is enabled; otherwise, `false`.
    var isDefaultBrowserAndDockPromptFeatureEnabled: Bool { get }
}

public protocol DefaultBrowserAndDockPromptFeatureFlagsSettingsProvider {
    /// The number of days to wait after app installation before showing the first popover
    var firstPopoverDelayDays: Int { get }
    /// The number of days to wait after the popover has been shown before displaying the banner.
    var bannerAfterPopoverDelayDays: Int { get }
    /// The number of days between subsequent displays of the banner.
    var bannerRepeatIntervalDays: Int { get }
}

typealias DefaultBrowserAndDockPromptFeatureFlagger = DefaultBrowserAndDockPromptFeatureFlagProvider & DefaultBrowserAndDockPromptFeatureFlagsSettingsProvider

final class DefaultBrowserAndDockPromptFeatureFlag {
    private let privacyConfigManager: PrivacyConfigurationManaging
    private let featureFlagger: FeatureFlagger

    private var remoteSubfeatureSettings: ScheduledDefaultBrowserAndDockPromptSettings {
        guard
            let subFeatureJSON = privacyConfigManager.privacyConfig.settings(for: SetAsDefaultAndAddToDockSubfeature.scheduledSetDefaultBrowserAndAddToDockPrompts),
            let data = subFeatureJSON.data(using: .utf8),
            let decodedSettings: ScheduledDefaultBrowserAndDockPromptSettings = CodableHelper.decode(jsonData: data)
        else {
            // Return default values if cannot
            return ScheduledDefaultBrowserAndDockPromptSettings()
        }
        return decodedSettings
    }

    public init(privacyConfigManager: PrivacyConfigurationManaging, featureFlagger: FeatureFlagger) {
        self.privacyConfigManager = privacyConfigManager
        self.featureFlagger = featureFlagger
    }
}

// MARK: - DefaultBrowserAndDockPromptFeatureFlagger

extension DefaultBrowserAndDockPromptFeatureFlag: DefaultBrowserAndDockPromptFeatureFlagProvider {

    public var isDefaultBrowserAndDockPromptFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.scheduledSetDefaultBrowserAndAddToDockPrompts)
    }

}

// MARK: - DefaultBrowserAndDockPromptFeatureFlagsSettingsProvider

extension DefaultBrowserAndDockPromptFeatureFlag: DefaultBrowserAndDockPromptFeatureFlagsSettingsProvider {

    public var firstPopoverDelayDays: Int {
        remoteSubfeatureSettings.firstPopoverDelayDays
    }

    public var bannerAfterPopoverDelayDays: Int {
        remoteSubfeatureSettings.bannerAfterPopoverDelayDays
    }

    public var bannerRepeatIntervalDays: Int {
        remoteSubfeatureSettings.bannerRepeatIntervalDays
    }

}

// MARK: - ScheduledDefaultBrowserAndDockPromptSettings

/// An struct representing the different settings for Set Default Browser (SAD) and Add to Dock (ATT) feature flag.
struct ScheduledDefaultBrowserAndDockPromptSettings: Codable {
    /// The setting for the number of days to wait after app installation before showing the first popover. Default to 14 days.
    private(set) var firstPopoverDelayDays: Int = 14
    /// The setting for the number of days to wait after the popover has been shown before displaying the banner. Default to 14 days.
    private(set) var bannerAfterPopoverDelayDays: Int = 14
    /// The settings for the number of days between subsequent displays of the banner. Default to 14 days.
    private(set) var bannerRepeatIntervalDays: Int = 14
}
