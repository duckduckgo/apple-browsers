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

}

// This class is not final because we override allowed domains in WebCacheManagerTests
public class UserDefaultsFireproofing: Fireproofing {

    enum ETLDPlus1Key: String {
        case allowedDomains = "com.duckduckgo.ios.fireproofing.etldplus1.allowed-domains"
    }

    public struct Notifications {
        public static let loginDetectionStateChanged = Foundation.Notification.Name("com.duckduckgo.ios.PreserveLogins.loginDetectionStateChanged")
    }

    public init() {}

    @UserDefaultsWrapper(key: .fireproofingAllowedDomains, defaultValue: [])
    private(set) public var allowedDomains: [String]

    @UserDefaultsWrapper(key: .fireproofingDetectionEnabled, defaultValue: false)
    public var loginDetectionEnabled: Bool {
        didSet {
            NotificationCenter.default.post(name: Notifications.loginDetectionStateChanged, object: nil)
        }
    }

    private let tld: TLD
    private let keyValueStore: KeyValueStoring
    private let isFireproofingETLDPlus1Enabled: () -> Bool

    public init(
        tld: TLD = TLD(),
        keyValueStore: KeyValueStoring = UserDefaults.app,
        isFireproofingETLDPlus1Enabled: @escaping () -> Bool = { true }
    ) {
        self.tld = tld
        self.keyValueStore = keyValueStore
        self.isFireproofingETLDPlus1Enabled = isFireproofingETLDPlus1Enabled
    }

    // MARK: - eTLD+1 Store

    var etldPlus1AllowedDomains: [String] {
        get { keyValueStore.object(forKey: ETLDPlus1Key.allowedDomains.rawValue) as? [String] ?? [] }
        set { keyValueStore.set(newValue, forKey: ETLDPlus1Key.allowedDomains.rawValue) }
    }

    private var activeAllowedDomains: [String] {
        isFireproofingETLDPlus1Enabled() ? etldPlus1AllowedDomains : allowedDomains
    }

    private var activeAllowedDomainsIncludingDuckDuckGo: [String] {
        activeAllowedDomains + [
            URL.ddg.host ?? "",
            URL.duckAi.host ?? "",
        ]
    }

    public func addToAllowed(domain: String) {
        allowedDomains += [domain]

        guard let normalized = tld.eTLDplus1(domain) else { return }
        if !etldPlus1AllowedDomains.contains(normalized) {
            etldPlus1AllowedDomains += [normalized]
        }
    }

    public func isAllowed(cookieDomain: String) -> Bool {
        if isFireproofingETLDPlus1Enabled() {
            let cleaned = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()) : cookieDomain
            guard let normalized = tld.eTLDplus1(cleaned) else { return false }
            return activeAllowedDomainsIncludingDuckDuckGo.contains(normalized)
        }
        return activeAllowedDomainsIncludingDuckDuckGo.contains(where: { HTTPCookie.cookieDomain(cookieDomain, matchesTestDomain: $0) })
    }

    public func remove(domain: String) {
        allowedDomains = allowedDomains.filter { $0 != domain }

        guard let normalized = tld.eTLDplus1(domain) else { return }
        etldPlus1AllowedDomains = etldPlus1AllowedDomains.filter { $0 != normalized }
    }

    public func clearAll() {
        allowedDomains = []
        etldPlus1AllowedDomains = []
    }

    public func isAllowed(fireproofDomain domain: String) -> Bool {
        if isFireproofingETLDPlus1Enabled() {
            guard let normalized = tld.eTLDplus1(domain) else { return false }
            return activeAllowedDomainsIncludingDuckDuckGo.contains(normalized)
        }
        return activeAllowedDomainsIncludingDuckDuckGo.contains(domain)
    }

}
