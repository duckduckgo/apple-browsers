//
//  Fireproofing.swift
//  Core
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Common
import FoundationExtensions
import Foundation
import Persistence
import Subscription

public protocol Fireproofing {

    var loginDetectionEnabled: Bool { get set }
    var allowedDomains: [String] { get }

    func isAllowed(cookieDomain: String) -> Bool
    func isAllowed(fireproofDomain domain: String) -> Bool
    func addToAllowed(domain: String)
    func remove(domain: String)
    func clearAll()

    func displayDomain(for domain: String) -> String

    @discardableResult
    func migrateFireproofDomainsToETLDPlus1IfNeeded() -> Bool

}

public class UserDefaultsFireproofing: Fireproofing {

    enum ETLDPlus1Key: String {
        case allowedDomains = "com.duckduckgo.ios.fireproofing.etldplus1.allowed-domains"
        case migrationDone = "com.duckduckgo.ios.fireproofing.etldplus1.migration-done"
    }

    public struct Notifications {
        public static let loginDetectionStateChanged = Foundation.Notification.Name("com.duckduckgo.ios.PreserveLogins.loginDetectionStateChanged")
    }

    @UserDefaultsWrapper(key: .fireproofingAllowedDomains, defaultValue: [])
    var legacyAllowedDomains: [String]

    public var allowedDomains: [String] {
        etldPlus1AllowedDomains
    }

    @UserDefaultsWrapper(key: .fireproofingDetectionEnabled, defaultValue: false)
    public var loginDetectionEnabled: Bool {
        didSet {
            NotificationCenter.default.post(name: Notifications.loginDetectionStateChanged, object: nil)
        }
    }

    private let tld: TLD
    private let keyValueStore: KeyValueStoring

    public init(
        tld: TLD = TLD(),
        keyValueStore: KeyValueStoring = UserDefaults.app
    ) {
        self.tld = tld
        self.keyValueStore = keyValueStore
    }

    var etldPlus1AllowedDomains: [String] {
        get { keyValueStore.object(forKey: ETLDPlus1Key.allowedDomains.rawValue) as? [String] ?? [] }
        set { keyValueStore.set(newValue, forKey: ETLDPlus1Key.allowedDomains.rawValue) }
    }

    private var allowedDomainsIncludingDuckDuckGo: [String] {
        allowedDomains + [
            URL.ddg.host ?? "",
            URL.duckAi.host ?? "",
        ]
    }

    public func addToAllowed(domain: String) {
        guard let normalized = tld.eTLDplus1(domain) else { return }
        if !etldPlus1AllowedDomains.contains(normalized) {
            etldPlus1AllowedDomains += [normalized]
        }
    }

    public func isAllowed(cookieDomain: String) -> Bool {
        let cleaned = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
        guard let normalized = tld.eTLDplus1(cleaned) else { return false }
        return allowedDomainsIncludingDuckDuckGo.contains(normalized)
    }

    public func remove(domain: String) {
        guard let normalized = tld.eTLDplus1(domain) else { return }
        etldPlus1AllowedDomains = etldPlus1AllowedDomains.filter { $0 != normalized }
    }

    public func clearAll() {
        etldPlus1AllowedDomains = []
    }

    public func displayDomain(for domain: String) -> String {
        tld.eTLDplus1(domain) ?? domain.droppingWwwPrefix()
    }

    public func isAllowed(fireproofDomain domain: String) -> Bool {
        guard let normalized = tld.eTLDplus1(domain) else { return false }
        return allowedDomainsIncludingDuckDuckGo.contains(normalized)
    }

    // MARK: - Migration

    private var isETLDPlus1MigrationDone: Bool {
        get { keyValueStore.object(forKey: ETLDPlus1Key.migrationDone.rawValue) as? Bool ?? false }
        set { keyValueStore.set(newValue, forKey: ETLDPlus1Key.migrationDone.rawValue) }
    }

    @discardableResult
    public func migrateFireproofDomainsToETLDPlus1IfNeeded() -> Bool {
        guard !isETLDPlus1MigrationDone else { return false }

        let existing = legacyAllowedDomains
        guard !existing.isEmpty else {
            isETLDPlus1MigrationDone = true
            return false
        }

        var normalized = Set<String>()
        for domain in existing {
            if let etldPlus1 = tld.eTLDplus1(domain) {
                normalized.insert(etldPlus1)
            }
        }

        etldPlus1AllowedDomains = Array(normalized)
        legacyAllowedDomains = []
        isETLDPlus1MigrationDone = true

        return true
    }

}
