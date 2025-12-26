//
//  BaseURLDebugSettings.swift
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

/// Protocol for accessing and modifying base URL debug settings.
///
/// These settings allow internal users to override the default DuckDuckGo base URLs
/// for testing purposes (e.g., pointing to local servers or dev instances).
public protocol BaseURLDebugSettingsRepresentable {
    /// Custom BASE_URL override (e.g., "http://localhost:8080")
    var customBaseURL: String? { get set }

    /// Custom DUCKAI_BASE_URL override
    var customDuckAIBaseURL: String? { get set }

    /// Resets all custom URLs to defaults
    func reset()
}

/// Default implementation of `BaseURLDebugSettingsRepresentable` using UserDefaults.
///
/// ## Usage
///
/// This is used by the Debug menu to allow internal users to change base URLs at runtime:
///
/// ```swift
/// let settings = BaseURLDebugSettings()
/// settings.customBaseURL = "http://localhost:8080"
/// // All URLs using URL.base will now use this custom URL
///
/// settings.reset()
/// // URLs return to production defaults
/// ```
public final class BaseURLDebugSettings: BaseURLDebugSettingsRepresentable {
    private let userDefaults: UserDefaults

    public init(_ userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var customBaseURL: String? {
        get { userDefaults[.debugCustomBaseURL] }
        set { userDefaults[.debugCustomBaseURL] = newValue }
    }

    public var customDuckAIBaseURL: String? {
        get { userDefaults[.debugCustomDuckAIBaseURL] }
        set { userDefaults[.debugCustomDuckAIBaseURL] = newValue }
    }

    public func reset() {
        customBaseURL = nil
        customDuckAIBaseURL = nil
    }

    // MARK: - Computed Helpers

    /// Returns the current base URL (custom override or environment variable or default)
    public var effectiveBaseURL: String {
        if let custom = customBaseURL, !custom.isEmpty {
            return custom
        }
        return ProcessInfo.processInfo.environment["BASE_URL", default: "https://duckduckgo.com"]
    }

    /// Returns the current Duck.ai base URL (custom override or environment variable or default)
    public var effectiveDuckAIBaseURL: String {
        if let custom = customDuckAIBaseURL, !custom.isEmpty {
            return custom
        }
        return ProcessInfo.processInfo.environment["DUCKAI_BASE_URL", default: "https://duck.ai"]
    }

    /// Returns the current help base URL (derived from base URL when overridden)
    public var effectiveHelpBaseURL: String {
        let baseURL = effectiveBaseURL
        if baseURL != "https://duckduckgo.com" {
            return baseURL
        }
        return "https://help.duckduckgo.com"
    }

    /// Returns true if any custom URL is currently set
    public var hasCustomURLs: Bool {
        return (customBaseURL != nil && !customBaseURL!.isEmpty) ||
               (customDuckAIBaseURL != nil && !customDuckAIBaseURL!.isEmpty)
    }
}

// MARK: - UserDefaults Extension

private extension UserDefaults {
    enum BaseURLDebugKey: String {
        case debugCustomBaseURL = "debug.customBaseURL"
        case debugCustomDuckAIBaseURL = "debug.customDuckAIBaseURL"
    }

    subscript<T>(key: BaseURLDebugKey) -> T? where T: Any {
        get { value(forKey: key.rawValue) as? T }
        set { set(newValue, forKey: key.rawValue) }
    }
}
