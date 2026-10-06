//
//  ChromeWebStoreCatalog.swift
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

public enum ChromeWebStoreStatus: String, Codable {
    case installable, installed, unsupported, unknown
}

public enum ChromeWebStoreError: Error {
    case invalidRequest, unavailable, invalidPackage, invalidSignature, unsupportedManifest, downloadFailed
}

public enum ChromeWebStoreURL {
    public static let host = "chromewebstore.google.com"
    public static let prodversionQueryItem = URLQueryItem(name: "prodversion", value: "154.0.0.0")

    public static func isValidExtensionID(_ identifier: String) -> Bool {
        identifier.utf8.count == 32 && identifier.utf8.allSatisfy { (97...112).contains($0) }
    }

    public static func downloadURL(for identifier: String) throws -> URL {
        guard isValidExtensionID(identifier) else { throw ChromeWebStoreError.invalidRequest }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "clients2.google.com"
        components.path = "/service/update2/crx"
        components.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            Self.prodversionQueryItem,
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(identifier)&installsource=ondemand&uc")
        ]
        guard let url = components.url else { throw ChromeWebStoreError.invalidRequest }
        return url
    }

    public static func isValidDownloadURL(_ url: URL, for identifier: String) -> Bool {
        guard let expected = try? downloadURL(for: identifier),
              let actual = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let canonical = URLComponents(url: expected, resolvingAgainstBaseURL: false),
              actual.scheme == canonical.scheme, actual.host == canonical.host, actual.path == canonical.path,
              actual.port == nil, actual.user == nil, actual.password == nil, actual.fragment == nil,
              let query = actual.queryItems, query.count == canonical.queryItems?.count else { return false }
        return Set(query) == Set(canonical.queryItems ?? [])
    }

    static func isAllowedDownloadDestination(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        return ["clients2.google.com", "clients2.googleusercontent.com"].contains(url.host ?? "")
    }
}

@MainActor
public protocol ChromeWebStoreCatalogProviding {
    /// Identifiers of all web extensions supported by the browser, in catalog order.
    var extensionIDs: [String] { get }

    /// Checks if the web extension with a given `identifier` is supported by the browser.
    func contains(_ identifier: String) -> Bool
}

public extension ChromeWebStoreCatalogProviding {
    func contains(_ identifier: String) -> Bool {
        ChromeWebStoreURL.isValidExtensionID(identifier) && extensionIDs.contains(identifier)
    }
}

/// This class uses configuration from Privacy Config to decide about supported extensions.
@MainActor
public final class ChromeWebStoreCatalog: ChromeWebStoreCatalogProviding {

    private let configurationManager: PrivacyConfigurationManaging

    public init(configurationManager: PrivacyConfigurationManaging) {
        self.configurationManager = configurationManager
    }

    public var extensionIDs: [String] {
        let config = configurationManager.privacyConfig

        // Store integration remains available when site privacy protections are off,
        // matching C-S-S platformSpecificFeatures. Explicit feature exceptions still apply.
        guard config.isEnabled(featureKey: .chromeWebstorePatching),
              !config.isInExceptionList(domain: ChromeWebStoreURL.host, forFeature: .chromeWebstorePatching),
              config.isSubfeatureEnabled(ExtensionManagementSubfeature.isLaunchedExtensions),
              config.isSubfeatureEnabled(ExtensionManagementSubfeature.curatedExtensions),
              let settingsJSON = config.settings(for: ExtensionManagementSubfeature.curatedExtensions),
              let data = settingsJSON.data(using: .utf8),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let internalCatalog = configurationManager.internalUserDecider.isInternalUser ? settings["catalogInternal"] as? [[String: Any]] : nil
        let catalog = internalCatalog ?? settings["catalog"] as? [[String: Any]] ?? []
        let featureSettings = config.settings(for: .extensionManagement)
        let excluded = Set(featureSettings["hiddenExtensionIds"] as? [String] ?? [])
            .union(featureSettings["disabledExtensionIds"] as? [String] ?? [])
        return catalog.compactMap { $0["id"] as? String }
            .filter { ChromeWebStoreURL.isValidExtensionID($0) && !excluded.contains($0) }
    }
}
