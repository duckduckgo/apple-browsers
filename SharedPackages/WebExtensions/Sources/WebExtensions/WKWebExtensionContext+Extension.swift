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
import ZIPFoundation

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

/// Metadata extracted from a web extension without loading it into a controller.
@available(macOS 15.4, iOS 18.4, *)
public struct WebExtensionMetadata: Sendable {
    public let type: DuckDuckGoWebExtensionType?
    public let version: String?
    public let requiresExtraction: Bool
}

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionMetadata {

    /// Parses metadata from a manifest dictionary.
    /// Type and extraction come from `browser_specific_settings.duckduckgo`, e.g.
    /// `"browser_specific_settings": { "duckduckgo": { "id": "com.duckduckgo.web-extension.embedded", "appleRequiresExtraction": true } }`
    init(manifest: [String: Any]) {
        let browserSpecific = manifest[browserSpecificSettingsKey] as? [String: Any]
        let duckduckgo = browserSpecific?[duckduckgoKey] as? [String: Any]
        self.init(
            type: (duckduckgo?[idKey] as? String).flatMap(DuckDuckGoWebExtensionType.init(rawValue:)),
            version: manifest["version"] as? String,
            requiresExtraction: duckduckgo?[requiresExtractionKey] as? Bool ?? false
        )
    }

    /// Reads metadata from the `manifest.json` at the root of a zipped extension.
    /// Unlike `WKWebExtension.metadata(from:)`, this doesn't make WebKit unzip the whole archive
    /// on the main thread, and it runs off the main actor.
    static func fromZip(at url: URL) async throws -> WebExtensionMetadata {
        let archive = try Archive(url: url, accessMode: .read)
        guard let entry = archive["manifest.json"] else {
            throw WebExtensionError.invalidManifest
        }

        var data = Data()
        _ = try archive.extract(entry) { data.append($0) }

        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebExtensionError.invalidManifest
        }
        return WebExtensionMetadata(manifest: manifest)
    }
}

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtension {

    /// Returns the extension type from manifest `browser_specific_settings.duckduckgo.id`, if present and recognized.
    var duckDuckGoWebExtensionType: DuckDuckGoWebExtensionType? {
        WebExtensionMetadata(manifest: manifest).type
    }

    /// Returns whether the extension declares a toolbar action in its manifest.
    ///
    /// Manifest V3 uses `action`; Manifest V2 uses `browser_action` or `page_action`.
    /// Extensions without one of these keys have no user-facing button, so the browser
    /// must not put them in the navigation bar.
    ///
    /// Our own embedded extensions are currently forced to not display a toolbar action at all.
    var declaresToolbarAction: Bool {
        if duckDuckGoWebExtensionType != nil {
            return false
        }
        return manifest[actionKey] != nil || manifest[browserActionKey] != nil || manifest[pageActionKey] != nil
    }

    /// Returns whether the extension requires extraction from zip before loading.
    /// Read from manifest `browser_specific_settings.duckduckgo.appleRequiresExtraction`.
    var requiresExtraction: Bool {
        WebExtensionMetadata(manifest: manifest).requiresExtraction
    }

    /// Reads metadata from a web extension at the given URL without loading it into a controller.
    /// This can be used to inspect version and type before deciding whether to install/upgrade.
    /// Given a zip, WebKit unzips the whole archive on the main thread, so prefer
    /// `WebExtensionMetadata.fromZip(at:)` for zips known to have `manifest.json` at the root.
    /// - Parameter url: URL to the extension (folder or zip file)
    /// - Returns: Metadata containing type, version and whether extraction is required
    @MainActor
    static func metadata(from url: URL) async throws -> WebExtensionMetadata {
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        return WebExtensionMetadata(manifest: webExtension.manifest)
    }
}

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtensionContext {

    /// Convenience proxy to the underlying web extension's type.
    var duckDuckGoWebExtensionType: DuckDuckGoWebExtensionType? {
        webExtension.duckDuckGoWebExtensionType
    }

    /// Convenience proxy to the underlying web extension's toolbar action declaration.
    var declaresToolbarAction: Bool {
        webExtension.declaresToolbarAction
    }
}
