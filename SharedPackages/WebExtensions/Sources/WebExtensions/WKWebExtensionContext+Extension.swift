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
private let actionKey = "action"
private let browserActionKey = "browser_action"
private let pageActionKey = "page_action"

/// Extension types identified via manifest `browser_specific_settings.duckduckgo.id`.
@available(macOS 15.4, iOS 18.4, *)
public enum DuckDuckGoWebExtensionType: String, Codable, CaseIterable, Sendable {
    /// Embedded web extension (e.g. autoconsent/CPM).
    case embedded = "com.duckduckgo.web-extension.embedded"
    case darkReader = "org.duckduckgo.web-extension.darkreader"
    case adBlockingExtension = "com.duckduckgo.content-blocker-extension"
    case searchToken = "com.duckduckgo.web-extension.search-token"

    /// Short human-readable label used in breakage reports.
    public var shortLabel: String {
        switch self {
        case .embedded: return "embedded"
        case .darkReader: return "darkMode"
        case .adBlockingExtension: return "adBlocking"
        case .searchToken: return "searchToken"
        }
    }
}

/// Returns the extension type from a raw manifest dictionary's `browser_specific_settings.duckduckgo.id`.
///
/// Shared by everything that must decide whether an extension is one of ours, including code that
/// runs before a `WKWebExtension` exists (see `WebExtensionBackgroundPagePatcher`).
@available(macOS 15.4, iOS 18.4, *)
func webExtensionType(fromManifest manifest: [String: Any]) -> DuckDuckGoWebExtensionType? {
    guard let browserSpecific = manifest[browserSpecificSettingsKey] as? [String: Any],
          let duckduckgo = browserSpecific[duckduckgoKey] as? [String: Any],
          let idString = duckduckgo[idKey] as? String else {
        return nil
    }
    return DuckDuckGoWebExtensionType(rawValue: idString)
}

/// Returns whether a raw manifest dictionary declares `browser_specific_settings.duckduckgo`, which only our own
/// extensions do. Any such extension is ours, even one whose id `DuckDuckGoWebExtensionType` does not know yet.
///
/// Shared by everything that must decide whether an extension gets the Chrome-compatibility shims, including code
/// that runs before a `WKWebExtension` exists (see `WebExtensionBackgroundPagePatcher`). The shim scripts apply the
/// same rule in JavaScript (see `WebExtensionAPIStubScript` and `WebExtensionWindowCloseScript`).
func declaresDuckDuckGoSettings(inManifest manifest: [String: Any]) -> Bool {
    let browserSpecific = manifest[browserSpecificSettingsKey] as? [String: Any]
    return browserSpecific?[duckduckgoKey] is [String: Any]
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
        webExtensionType(fromManifest: manifest)
    }

    /// Whether the extension is a third-party one that needs the Chrome-compatibility shims
    /// (API stubs, background page conversion, optional permission grants, native messaging
    /// pass-through, toolbar button, keyboard shortcuts).
    ///
    /// This is the single source of truth for those shims: they apply only when the extension is
    /// not one of ours, so DuckDuckGo's own extensions behave as they did before the shims existed.
    var needsChromeCompatibility: Bool {
        !declaresDuckDuckGoSettings(inManifest: manifest)
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

    /// Convenience proxy to `WKWebExtension.needsChromeCompatibility`.
    var needsChromeCompatibility: Bool {
        webExtension.needsChromeCompatibility
    }

    /// Returns whether the extension declares a toolbar action in its manifest.
    ///
    /// Manifest V3 uses `action`; Manifest V2 uses `browser_action` or `page_action`.
    /// Extensions without one of these keys have no user-facing button, so the browser
    /// must not put them in the navigation bar. Not every one of our own extensions is in that
    /// group (Dark Reader declares an action popup), so the browser also checks
    /// `needsChromeCompatibility`.
    var declaresToolbarAction: Bool {
        let manifest = webExtension.manifest
        return manifest[actionKey] != nil || manifest[browserActionKey] != nil || manifest[pageActionKey] != nil
    }
}
