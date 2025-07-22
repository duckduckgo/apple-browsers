//
//  FirefoxPreferences.swift
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
import Common
import CommonCrypto
import BrowserServicesKit

final class FirefoxPreferences {

    struct ImportError: DataImportError {
        enum OperationType: Int {
            case fileRead
            case parsePreferences
        }

        var action: DataImportAction { .favorites }
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            switch type {
            case .fileRead: .noData
            case .parsePreferences: .dataCorrupted
            }
        }
    }

    enum Constants {
        static let preferencesFileName = "prefs.js"

        enum PreferenceKeys {
            static let topSites = "browser.newtabpage.activity-stream.feeds.topsites"
            static let topSitesRows = "browser.newtabpage.activity-stream.topSitesRows"
            static let pinned = "browser.newtabpage.pinned"
            static let blocked = "browser.newtabpage.blocked"
        }
    }

    struct PinnedSite: Decodable {
        let url: String
        let label: String?
    }

    private let preferences: [String: String]

    lazy var newTabFavoritesEnabled: Bool = {
        (preferences[Constants.PreferenceKeys.topSites]?.lowercased() ?? "true") == "true" // Defaults to enabled
    }()

    /// Maximum number of favorites shown on the new tab page.
    lazy var newTabFavoritesCount: Int = {
        guard let rowCountString = preferences[Constants.PreferenceKeys.topSitesRows],
              let rowCount = Int(rowCountString) else {
            return 8 // Default is a single row of 8 sites
        }
        return rowCount * 8
    }()

    /// Sites pinned in favorites on the new tab page.
    /// Includes nil entries for empty slots (to be filled with frecent sites from browsing history).
    lazy var newTabPinnedSites: [PinnedSite?] = {
        let pinnedSitesJSONString = preferences[Constants.PreferenceKeys.pinned]
        return parseJSONValue(pinnedSitesJSONString, as: [PinnedSite?].self) ?? []
    }()

    /// Set of hashed site URLs that are blocked from the favorites section on the new tab page.
    private lazy var newTabBlockedSiteHashes: Set<String> = {
        let blockedSitesJSONString = preferences[Constants.PreferenceKeys.blocked]
        let blockedSitesDict = parseJSONValue(blockedSitesJSONString, as: [String: Int].self) ?? [:]
        return Set(blockedSitesDict.keys.map { $0 })
    }()

    init(profileURL: URL, fileStore: FileManager = FileManager.default) throws {
        guard let preferencesData = fileStore.loadData(at: profileURL.appendingPathComponent(Constants.preferencesFileName)) else {
            throw ImportError(type: .fileRead, underlyingError: CocoaError(.fileReadUnknown))
        }
        var preferences: [String: String] = [:]
        let keys = [Constants.PreferenceKeys.topSites,
                    Constants.PreferenceKeys.pinned,
                    Constants.PreferenceKeys.topSitesRows,
                    Constants.PreferenceKeys.blocked]
        preferencesData.utf8String()?.enumerateLines { line, _ in
            for key in keys {
                guard preferences[key] == nil else { continue } // Skip if already found
                if let value = Self.parsePreferenceLine(line, withKey: key) {
                    preferences[key] = value
                    continue
                }
            }
        }
        self.preferences = preferences
    }

    func isURLBlockedOnNewTab(_ urlString: String) -> Bool {
        guard let hashedURL = hashURLString(urlString) else {
            return false
        }
        return newTabBlockedSiteHashes.contains(hashedURL)
    }

    /// Provides a hashed, encoded representation of a string.
    /// This is the hashing Firefox uses for blocked sites on the new tab page.
    ///
    /// Do not use this for security purposes; it uses MD5 hashing which is not secure.
    private func hashURLString(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else { return nil }

        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))

        data.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count), &digest)
        }

        return Data(digest).base64EncodedString()
    }

    /// Decodes a JSON string value from a preference as the given type.
    private func parseJSONValue<T: Decodable>(_ value: String?, as type: T.Type) -> T? {
        guard let value else { return nil }

        let unescapedJSON = value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")

        guard let jsonData = unescapedJSON.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: jsonData)
    }

    /// Parses a single preference line and extracts the value as a `String`.
    ///
    /// Handles the Firefox preference format: `user_pref("key", value);` where value can be a string (quoted), boolean, or number.
    /// Returns the raw value string for further processing.
    private static func parsePreferenceLine(_ pref: String, withKey key: String) -> String? {
        guard pref.hasPrefix("user_pref(\"\(key)\",") else {
            return nil
        }

        let regex = regex("user_pref\\(\"\(key)\",\\s*([^\\)]+)\\);")

        guard let match = regex.firstMatch(in: pref, options: [], range: pref.fullRange),
              let valueRange = Range(match.range(at: 1), in: pref) else {
            return nil
        }

        var value = String(pref[valueRange])

        // Remove quotes from value if present
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }

        return value
    }
}
