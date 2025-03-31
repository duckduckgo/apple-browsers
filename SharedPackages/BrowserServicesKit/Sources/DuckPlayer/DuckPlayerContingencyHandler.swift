//
//  DuckPlayerContingencyHandler.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common
import BrowserServicesKit

/// A protocol that defines the requirements for handling DuckPlayer contingency scenarios.
/// >Tech Design: https://app.asana.com/0/481882893211075/1207926753747908/f
public protocol DuckPlayerContingencyHandler {
    /// A Boolean value indicating whether a contingency message should be displayed.
    var shouldDisplayContingencyMessage: Bool { get }

    /// A URL pointing to a "Learn More" page for additional information.
    var learnMoreURL: URL? { get }
}

/// A default implementation of the `DuckPlayerContingencyHandler` protocol uses `PrivacyConfigurationManaging` to define its values.
public struct DefaultDuckPlayerContingencyHandler: DuckPlayerContingencyHandler {
    private let privacyConfigurationManager: PrivacyConfigurationManaging

    /// A Boolean value indicating whether a contingency message should be displayed.
    /// The message should be displayed if the `learnMoreURL` is not nil and the DuckPlayer feature is not enabled.
    public var shouldDisplayContingencyMessage: Bool {
        learnMoreURL != nil && !isDuckPlayerFeatureEnabled
    }

    private var isDuckPlayerFeatureEnabled: Bool {
        privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .duckPlayer)
    }

    /// A URL pointing to a "Learn More" page for additional information.
    /// The URL is derived from the privacy configuration settings.
    public var learnMoreURL: URL? {
        let settings = privacyConfigurationManager.privacyConfig.settings(for: .duckPlayer)
        guard let link = settings[.duckPlayerDisabledHelpPageLink] as? String,
              let pageLink = URL(string: link) else { return nil }
        return pageLink
    }

    public init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }
}

// MARK: - Settings key for Dictionary extension

private enum SettingsKey: String {
    case duckPlayerDisabledHelpPageLink
}

private extension Dictionary where Key == String {
    subscript(key: SettingsKey) -> Value? {
        return self[key.rawValue]
    }
}
