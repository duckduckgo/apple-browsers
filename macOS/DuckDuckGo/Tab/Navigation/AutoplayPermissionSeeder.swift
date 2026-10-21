//
//  AutoplayPermissionSeeder.swift
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

final class AutoplayPermissionSeeder {

    /// # Default Allow List: Included for reviewing purposes
    static let defaultAllowlistDomains: Set<String> = ["youtube.com"]

    private let autoplayPreferences: AutoplayPreferences
    private let permissionManager: PermissionManagerProtocol
    private let privacyConfigurationManager: PrivacyConfigurationManaging

    private var cachedAllowlistDomains: Set<String>?
    private var cachedAllowlistID: String?

    init(autoplayPreferences: AutoplayPreferences, permissionManager: PermissionManagerProtocol, privacyConfigurationManager: PrivacyConfigurationManaging) {
        self.autoplayPreferences = autoplayPreferences
        self.permissionManager = permissionManager
        self.privacyConfigurationManager = privacyConfigurationManager
    }

    func seedIfNeeded(domain: String) {
        let domainWithoutPrefix = domain.droppingWwwPrefix()
        guard allowlistDomains.contains(domainWithoutPrefix), !autoplayPreferences.seededDomains.contains(domainWithoutPrefix) else {
            return
        }

        permissionManager.setPermission(.allow, forDomain: domainWithoutPrefix, permissionType: .autoplayPolicy)
        autoplayPreferences.seededDomains.append(domainWithoutPrefix)
    }
}

private extension AutoplayPermissionSeeder {

    var allowlistDomains: Set<String> {
        let latestID = loadSettingsIdentifier()

        if let cachedAllowlistDomains, cachedAllowlistID == latestID {
            return cachedAllowlistDomains
        }

        let domains = loadAndDecodeSettings() ?? Self.defaultAllowlistDomains

        cachedAllowlistDomains = domains
        cachedAllowlistID = latestID

        return domains
    }

    func loadSettingsIdentifier() -> String? {
        privacyConfigurationManager.privacyConfig.identifier
    }

    func loadAndDecodeSettings() -> Set<String>? {
        guard
            let settingsString = privacyConfigurationManager.privacyConfig.settings(for: MacOSBrowserConfigSubfeature.autoplayPolicy),
            let settingsData = settingsString.data(using: .utf8),
            let settings = try? JSONDecoder().decode(Settings.self, from: settingsData)
        else {
            return nil
        }

        let lowercased = settings.domainsAllowList.map { $0.lowercased() }
        return Set(lowercased)
    }
}

private extension AutoplayPermissionSeeder {
    struct Settings: Decodable {
        let domainsAllowList: [String]
    }
}
