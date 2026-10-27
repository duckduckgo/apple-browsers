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

public enum ChromeWebStoreID: String {
    case bitwarden = "nngceckbapebfimnlniiiahkandclblb"
    case onePassword = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
    case iCloudPasswords = "pejdijmoenmkgeppbflobdenhhabjlaj"
}

public struct ChromeWebStoreListing: Equatable, Identifiable {
    public let entry: ExtensionsCatalogSubfeature
    public let name: String
    public let publisher: String
    public let iconURL: URL?
    public let storeURL: URL

    public var id: String { entry.rawValue }

    public var isPasswordManager: Bool {
        switch entry {
        case .bitwarden, .onePassword, .lastPass, .iCloudPasswords: true
        case .darkReader: false
        }
    }
}

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

    /// The catalog's entry for the extension with the Chrome Web Store `identifier`, such as `.bitwarden`,
    /// whether or not the catalog offers it right now. `nil` for an extension the catalog doesn't list.
    func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature?

    /// The entry's store listing, or `nil` when its `name` or `cwsUri` is missing.
    func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing?
}

public extension ChromeWebStoreCatalogProviding {
    func contains(_ identifier: String) -> Bool {
        ChromeWebStoreURL.isValidExtensionID(identifier) && extensionIDs.contains(identifier)
    }

    func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature? {
        nil
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
              config.isSubfeatureEnabled(ExtensionManagementSubfeature.isLaunchedExtensions) else { return [] }

        let featureSettings = config.settings(for: .extensionManagement)
        let excluded = Set(featureSettings["hiddenExtensionIds"] as? [String] ?? [])
            .union(featureSettings["disabledExtensionIds"] as? [String] ?? [])

        // Each extension is its own subfeature, so Privacy Config evaluates its state,
        // rollout and minimum version. Subfeatures this build doesn't know are ignored.
        let entries: [(id: String, order: Double)] = ExtensionsCatalogSubfeature.allCases.compactMap { subfeature in
            guard config.isSubfeatureEnabled(subfeature),
                  let settings = Self.settings(of: subfeature, in: config),
                  let id = settings["id"] as? String,
                  ChromeWebStoreURL.isValidExtensionID(id), !excluded.contains(id) else { return nil }
            return (id, (settings["order"] as? NSNumber)?.doubleValue ?? .infinity)
        }

        // Ascending `order`; entries without one sort last, ties keep declaration order.
        return entries.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element.id)
    }

    public func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature? {
        let config = configurationManager.privacyConfig
        return ExtensionsCatalogSubfeature.allCases.first { subfeature in
            Self.settings(of: subfeature, in: config)?["id"] as? String == identifier
        }
    }

    public func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing? {
        guard let settings = Self.settings(of: subfeature, in: configurationManager.privacyConfig),
              let name = settings["name"] as? String,
              let storeURL = (settings["cwsUri"] as? String).flatMap(URL.init(string:)) else { return nil }

        return ChromeWebStoreListing(entry: subfeature,
                                     name: name,
                                     publisher: settings["publisher"] as? String ?? "",
                                     iconURL: (settings["iconUri"] as? String).flatMap(URL.init(string:)),
                                     storeURL: storeURL)
    }

    private static func settings(of subfeature: ExtensionsCatalogSubfeature, in config: PrivacyConfiguration) -> [String: Any]? {
        guard let settingsJSON = config.settings(for: subfeature),
              let data = settingsJSON.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
