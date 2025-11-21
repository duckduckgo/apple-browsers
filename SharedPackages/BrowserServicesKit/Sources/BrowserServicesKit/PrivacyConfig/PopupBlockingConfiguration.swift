//
//  PopupBlockingConfiguration.swift
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

/// Provides access to popup blocking configuration settings from privacy config.
public protocol PopupBlockingConfiguration {
    /// The timeout in seconds for user-initiated popups.
    /// Set to 0 or negative to disable the timeout check entirely.
    /// Default: 6.0
    var userInitiatedPopupThreshold: TimeInterval { get }
}

/// Default implementation of PopupBlockingConfiguration that reads from privacy config.
public final class DefaultPopupBlockingConfiguration: PopupBlockingConfiguration {

    private enum Defaults {
        static let userInitiatedPopupThreshold: TimeInterval = 6.0
    }
    /// Keys used for popup blocking configuration settings.
    public enum PopupBlockingConfigurationKeys {
        public static let userInitiatedPopupThreshold = "userInitiatedPopupThreshold"
    }

    private let privacyConfigurationManager: PrivacyConfigurationManaging

#if DEBUG
    var assertionHandler: (Bool, String) -> Void = { condition, message in
        assert(condition, message)
    }
#else
    @inlinable
    var assertionHandler: (Bool, String) -> Void { { _, _ in } }
#endif

    public init(privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    public var userInitiatedPopupThreshold: TimeInterval {
        let settings = privacyConfigurationManager.privacyConfig.settings(for: .popupBlocking)

        var threshold: TimeInterval?

        // Try to read as Double, Int, or String
        if let doubleValue = settings[PopupBlockingConfigurationKeys.userInitiatedPopupThreshold] as? Double {
            threshold = doubleValue
        } else if let intValue = settings[PopupBlockingConfigurationKeys.userInitiatedPopupThreshold] as? Int {
            threshold = TimeInterval(intValue)
        } else if let stringValue = settings[PopupBlockingConfigurationKeys.userInitiatedPopupThreshold] as? String,
                  let doubleValue = Double(stringValue) {
            threshold = doubleValue
        } else {
            assertionHandler(settings[PopupBlockingConfigurationKeys.userInitiatedPopupThreshold] == nil,
                             "userInitiatedPopupThreshold has unexpected type")
        }

        // Validate threshold is positive, return default if not
        if let threshold {
            assertionHandler(threshold > 0, "userInitiatedPopupThreshold must be positive, got \(threshold)")
            guard threshold > 0 else {
                return Defaults.userInitiatedPopupThreshold
            }
            return threshold
        }

        return Defaults.userInitiatedPopupThreshold
    }
}
