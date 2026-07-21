//
//  PIRDebugPrivacyConfigurationManager.swift
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
import Combine
import PrivacyConfig

/// A headless `PrivacyConfigurationManaging` built from embedded config `Data`, avoiding
/// `DBPPrivacyConfigurationManager` (which `fatalError`s in a bare process because it requires
/// `macos-config.json` in `Bundle.main`). Constructed exactly as the spike's
/// `SpikePrivacyConfigManager`, via `AppPrivacyConfiguration`. Does not alter
/// `DBPPrivacyConfigurationManager`.
public final class PIRDebugPrivacyConfigurationManager: PrivacyConfigurationManaging {

    private final class InMemoryDomainsProtectionStore: DomainsProtectionStore {
        var unprotectedDomains: Set<String> = []
        func disableProtection(forDomain domain: String) { unprotectedDomains.insert(domain) }
        func enableProtection(forDomain domain: String) { unprotectedDomains.remove(domain) }
    }

    private final class InMemoryInternalUserStore: InternalUserStoring {
        var isInternalUser: Bool = false
    }

    public let currentConfig: Data
    public var updatesPublisher: AnyPublisher<Void, Never> = Just(()).eraseToAnyPublisher()
    public let internalUserDecider: InternalUserDecider
    public let privacyConfig: PrivacyConfiguration

    /// The ephemeral UserDefaults suite backing `AppPrivacyConfiguration` (experiment cohorts),
    /// removed on teardown so nothing is persisted to `UserDefaults.standard`.
    private let userDefaultsSuiteName: String
    private let userDefaults: UserDefaults

    /// - Parameter configData: Real `macos-config.json` bytes with a `features` dict, so the DBP
    ///   override can inject `brokerProtection: enabled` into `$CONTENT_SCOPE$`.
    public init(configData: Data) throws {
        guard let data = try? PrivacyConfigurationData(data: configData) else {
            throw PIRDebugError.invalidPrivacyConfiguration
        }
        self.currentConfig = configData

        let internalUserDecider = DefaultInternalUserDecider(store: InMemoryInternalUserStore())
        self.internalUserDecider = internalUserDecider

        let suiteName = "com.duckduckgo.pir-debug.privacy-config.\(UUID().uuidString)"
        self.userDefaultsSuiteName = suiteName
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            throw PIRDebugError.ephemeralDefaultsUnavailable
        }
        self.userDefaults = userDefaults

        self.privacyConfig = AppPrivacyConfiguration(
            data: data,
            identifier: UUID().uuidString,
            localProtection: InMemoryDomainsProtectionStore(),
            internalUserDecider: internalUserDecider,
            userDefaults: userDefaults
        )
    }

    /// Builds a manager from the `macos-config.json` shipped as a PIRDebugKit resource.
    public static func bundled() throws -> PIRDebugPrivacyConfigurationManager {
        guard let url = Bundle.module.url(forResource: "macos-config", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw PIRDebugError.missingPrivacyConfigurationResource
        }
        return try PIRDebugPrivacyConfigurationManager(configData: data)
    }

    deinit {
        UserDefaults.standard.removeSuite(named: userDefaultsSuiteName)
    }

    @discardableResult
    public func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        .downloaded
    }
}
