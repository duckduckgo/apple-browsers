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

    /// Set of domains that are allowed to open popups without user permission.
    ///
    /// Supports two formats:
    /// - Exact domain match: `"example.com"` (only matches example.com exactly)
    /// - Wildcard eTLD+1: `"*.example.com"` (matches example.com and all subdomains like accounts.example.com)
    ///
    /// The matching logic:
    /// 1. First checks for exact domain match
    /// 2. Then extracts eTLD+1 from the source domain and checks for `"*.etld+1"` pattern
    @MainActor var allowlist: Set<String> { get }
}

/// Default implementation of PopupBlockingConfiguration that reads from privacy config.
public final class DefaultPopupBlockingConfiguration: PopupBlockingConfiguration {

    private enum Defaults {
        static let userInitiatedPopupThreshold: TimeInterval = 6.0
    }
    /// Keys used for popup blocking configuration settings.
    public enum PopupBlockingConfigurationKeys {
        public static let userInitiatedPopupThreshold = "userInitiatedPopupThreshold"
        public static let allowlist = "allowlist"
    }

    private let privacyConfigurationManager: PrivacyConfigurationManaging

    // Static cache for allowlist to avoid repeated array-to-set conversion
    // Shared across all instances and survives instance recreation
    @MainActor private static var cachedAllowlist: Set<String>?
    @MainActor private static var cachedConfigIdentifier: String?

#if DEBUG
    var assertionHandler: (Bool, String) -> Void = { condition, message in
        assert(condition, message)
    }

    // For testing: clear the static cache to prevent test pollution
    @MainActor static func clearCache() {
        cachedAllowlist = nil
        cachedConfigIdentifier = nil
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

    @MainActor public var allowlist: Set<String> {
        let currentIdentifier = privacyConfigurationManager.privacyConfig.identifier

        // Check if cache is valid (config hasn't changed)
        if let cachedAllowlist = Self.cachedAllowlist,
           let cachedConfigIdentifier = Self.cachedConfigIdentifier,
           cachedConfigIdentifier == currentIdentifier {
            return cachedAllowlist
        }

        // Cache miss or invalidated - rebuild from config
        let settings = privacyConfigurationManager.privacyConfig.settings(for: .popupBlocking)
        let allowlistSet: Set<String>

        if let allowlistArray = settings[PopupBlockingConfigurationKeys.allowlist] as? [String] {
            allowlistSet = Set(allowlistArray)
        } else {
            assertionHandler(settings[PopupBlockingConfigurationKeys.allowlist] == nil,
                             "allowlist has unexpected type")
            allowlistSet = []
        }

        // Update static cache
        Self.cachedAllowlist = allowlistSet
        Self.cachedConfigIdentifier = currentIdentifier

        return allowlistSet
    }
}
