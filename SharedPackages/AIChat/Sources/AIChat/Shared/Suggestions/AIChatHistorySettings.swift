//
//  AIChatHistorySettings.swift
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
import PrivacyConfig

/// Helper for reading AI Chat history settings from privacy configuration.
public struct AIChatHistorySettings {

    public enum SettingsKey: String {
        case maxHistoryCount
#if os(macOS)
        public static let defaultMaxHistoryCount = 5
#else
        public static let defaultMaxHistoryCount = 10
#endif
    }

    private let privacyConfig: PrivacyConfigurationManaging?

    public init(privacyConfig: PrivacyConfigurationManaging?) {
        self.privacyConfig = privacyConfig
    }

    public var maxHistoryCount: Int {
        let settings = privacyConfig?.privacyConfig.settings(for: .duckAiChatHistory)
        let value = (settings?[SettingsKey.maxHistoryCount.rawValue] as? Int) ?? SettingsKey.defaultMaxHistoryCount
        return max(0, value)
    }
}
