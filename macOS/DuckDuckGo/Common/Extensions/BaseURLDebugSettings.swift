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
import Persistence

/// Settings for accessing and modifying base URL overrides for debugging and development.
///
/// These settings allow internal users to override the default DuckDuckGo base URLs
/// for testing purposes (e.g., pointing to local servers or dev instances).
///
/// ## Usage
///
/// This is used by the Debug menu to allow internal users to change base URLs at runtime:
///
/// ```swift
/// let settings: any KeyedStoring<BaseURLDebugSettings> = UserDefaults.standard.keyedStoring()
/// settings.customBaseURL = "http://localhost:8080"
/// // All URLs using URL.base will now use this custom URL
///
/// settings.reset()
/// // URLs return to production defaults
/// ```
struct BaseURLDebugSettings: StoringKeys {
    let customBaseURL = StorageKey<String>(.debugCustomBaseURL)
    let customDuckAIBaseURL = StorageKey<String>(.debugCustomDuckAIBaseURL)
}

extension KeyedStoring where Keys == BaseURLDebugSettings {

    func reset() {
        self.customBaseURL = nil
        self.customDuckAIBaseURL = nil
    }

    // MARK: - Computed Helpers

    /// Returns the current base URL (custom override or environment variable or default)
    var effectiveBaseURL: String {
        if let custom = self.customBaseURL, !custom.isEmpty {
            return custom
        }
        return ProcessInfo.processInfo.environment["BASE_URL", default: "https://duckduckgo.com"]
    }

    /// Returns the current Duck.ai base URL (custom override or environment variable or default)
    var effectiveDuckAIBaseURL: String {
        if let custom = self.customDuckAIBaseURL, !custom.isEmpty {
            return custom
        }
        return ProcessInfo.processInfo.environment["DUCKAI_BASE_URL", default: "https://duck.ai"]
    }

    /// Returns the current help base URL (derived from base URL when overridden)
    var effectiveHelpBaseURL: String {
        let baseURL = self.effectiveBaseURL
        if baseURL != "https://duckduckgo.com" {
            return baseURL
        }
        return "https://help.duckduckgo.com"
    }

    /// Returns true if any custom URL is currently set
    var hasCustomURLs: Bool {
        return (self.customBaseURL != nil && !self.customBaseURL!.isEmpty) ||
        (self.customDuckAIBaseURL != nil && !self.customDuckAIBaseURL!.isEmpty)
    }
}
