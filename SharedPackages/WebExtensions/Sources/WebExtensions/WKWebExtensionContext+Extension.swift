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
private let requiresExtractionKey = "appleRequiresExtraction"

/// Extension types identified via manifest `browser_specific_settings.duckduckgo.id`.
@available(macOS 15.4, iOS 18.4, *)
public enum DuckDuckGoWebExtensionType: String, Codable {
    /// Embedded web extension (e.g. autoconsent/CPM).
    case embedded = "com.duckduckgo.web-extension.embedded"
    case darkReader = "org.duckduckgo.web-extension.darkreader"
}

/// Metadata extracted from a web extension without loading it into a controller.
@available(macOS 15.4, iOS 18.4, *)
public struct WebExtensionMetadata {
    public let type: DuckDuckGoWebExtensionType?
    public let version: String?
    public let displayName: String?
    public let requiresExtraction: Bool
}

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtension {

    /// Returns the extension type from manifest `browser_specific_settings.duckduckgo.id`, if present and recognized.
    /// Example manifest entry:
    /// `"browser_specific_settings": { "duckduckgo": { "id": "com.duckduckgo.web-extension.embedded" } }`
    var duckDuckGoWebExtensionType: DuckDuckGoWebExtensionType? {
        guard let browserSpecific = manifest[browserSpecificSettingsKey] as? [String: Any],
              let duckduckgo = browserSpecific[duckduckgoKey] as? [String: Any],
              let idString = duckduckgo[idKey] as? String else {
            return nil
        }
        return DuckDuckGoWebExtensionType(rawValue: idString)
    }

    /// Returns whether the extension requires extraction from zip before loading.
    /// Read from manifest `browser_specific_settings.duckduckgo.appleRequiresExtraction`.
    var requiresExtraction: Bool {
        guard let browserSpecific = manifest[browserSpecificSettingsKey] as? [String: Any],
              let duckduckgo = browserSpecific[duckduckgoKey] as? [String: Any],
              let requiresExtraction = duckduckgo[requiresExtractionKey] as? Bool else {
            return false
        }
        return requiresExtraction
    }

    /// Reads metadata from a web extension at the given URL without loading it into a controller.
    /// This can be used to inspect version and type before deciding whether to install/upgrade.
    /// - Parameter url: URL to the extension (folder or zip file)
    /// - Returns: Metadata containing type, version, and display name
    @MainActor
    static func metadata(from url: URL) async throws -> WebExtensionMetadata {
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        return WebExtensionMetadata(
            type: webExtension.duckDuckGoWebExtensionType,
            version: webExtension.version,
            displayName: webExtension.displayName,
            requiresExtraction: webExtension.requiresExtraction
        )
    }
}

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtensionContext {

    /// Convenience proxy to the underlying web extension's type.
    var duckDuckGoWebExtensionType: DuckDuckGoWebExtensionType? {
        webExtension.duckDuckGoWebExtensionType
    }
}
