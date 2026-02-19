//
//  WKWebExtensionContext+Extension.swift
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
import WebKit

private let browserSpecificSettingsKey = "browser_specific_settings"
private let duckduckgoKey = "duckduckgo"
private let idKey = "id"

/// Extension types identified via manifest `browser_specific_settings.duckduckgo.id`.
@available(macOS 15.4, iOS 18.4, *)
public enum DuckDuckGoWebExtensionType: String {
    /// Embedded web extension (e.g. autoconsent/CPM).
    case embedded = "com.duckduckgo.web-extension.embedded"
}

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtensionContext {

    /// Returns the extension type from manifest `browser_specific_settings.duckduckgo.id`, if present and recognized.
    /// Example manifest entry:
    /// `"browser_specific_settings": { "duckduckgo": { "id": "com.duckduckgo.web-extension.embedded" } }`
    var duckDuckGoWebExtensionType: DuckDuckGoWebExtensionType? {
        guard let browserSpecific = webExtension.manifest[browserSpecificSettingsKey] as? [String: Any],
              let duckduckgo = browserSpecific[duckduckgoKey] as? [String: Any],
              let idString = duckduckgo[idKey] as? String else {
            return nil
        }
        return DuckDuckGoWebExtensionType(rawValue: idString)
    }
}
