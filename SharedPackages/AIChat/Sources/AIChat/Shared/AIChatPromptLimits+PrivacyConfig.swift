//
//  AIChatPromptLimits+PrivacyConfig.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

public extension AIChatPromptLimits {

    enum SettingsKey: String {
        case pasteConversionThreshold
        case maxCharacters
    }

    /// Limits from a subfeature's settings, each missing or non-positive value taken from `fallback`.
    init(privacyConfig: PrivacyConfiguration, subfeature: any PrivacySubfeature, fallback: AIChatPromptLimits = .current) {
        self.init(settingsJSON: privacyConfig.settings(for: subfeature), fallback: fallback)
    }

    /// A threshold above the maximum would never convert, so that combination falls back entirely.
    init(settingsJSON: String?, fallback: AIChatPromptLimits = .current) {
        let settings = settingsJSON?.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let maxCharacters = Self.positiveInt(settings?[SettingsKey.maxCharacters.rawValue]) ?? fallback.maxCharacters
        let threshold = Self.positiveInt(settings?[SettingsKey.pasteConversionThreshold.rawValue]) ?? fallback.pasteConversionThreshold
        guard threshold <= maxCharacters else {
            self = fallback
            return
        }
        self.init(maxCharacters: maxCharacters, pasteConversionThreshold: threshold)
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let int = value as? Int, int > 0 else { return nil }
        return int
    }
}
