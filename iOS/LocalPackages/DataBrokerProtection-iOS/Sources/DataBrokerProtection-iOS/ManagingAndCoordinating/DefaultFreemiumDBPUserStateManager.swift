//
//  DefaultFreemiumDBPUserStateManager.swift
//  DuckDuckGo
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

/// UserDefaults-backed implementation of `FreemiumDBPUserStateManaging`.
/// Every read and write goes through a single `NSLock` so concurrent callers
/// cannot race on guarded read-modify-write sequences.
public final class DefaultFreemiumDBPUserStateManager: FreemiumDBPUserStateManaging {

    private enum Keys {
        static let didActivate = "ios.browser.freemium.dbp.did.activate"
        static let firstProfileSavedTimestamp = "ios.browser.freemium.dbp.first.profile.saved.timestamp"
        static let firstScanResult = "ios.browser.freemium.dbp.first.scan.result"
        static let upgradeToSubscriptionTimestamp = "ios.browser.freemium.dbp.upgrade.to.subscription.timestamp"
    }

    private let userDefaults: UserDefaults
    private let isUserAuthenticated: () async -> Bool
    private let isFreemiumEnabled: () -> Bool
    private let lock = NSLock()

    public init(
        userDefaults: UserDefaults,
        isUserAuthenticated: @escaping () async -> Bool,
        isFreemiumEnabled: @escaping () -> Bool
    ) {
        self.userDefaults = userDefaults
        self.isUserAuthenticated = isUserAuthenticated
        self.isFreemiumEnabled = isFreemiumEnabled
    }

    // MARK: - Read-side getters

    public var didActivate: Bool {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.bool(forKey: Keys.didActivate)
    }

    public var firstProfileSavedTimestamp: Date? {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.object(forKey: Keys.firstProfileSavedTimestamp) as? Date
    }

    public var firstScanResult: FreemiumFirstScanResult? {
        lock.lock()
        defer { lock.unlock() }
        guard let raw = userDefaults.string(forKey: Keys.firstScanResult) else { return nil }
        return FreemiumFirstScanResult(rawValue: raw)
    }

    public var upgradeToSubscriptionTimestamp: Date? {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.object(forKey: Keys.upgradeToSubscriptionTimestamp) as? Date
    }

    // MARK: - Write-side methods

    public func recordProfileSavedIfNeeded() async {
        guard isFreemiumEnabled() else { return }
        guard await !isUserAuthenticated() else { return }
        persistProfileSaved()
    }

    public func recordFirstScanResultIfNeeded(hasMatches: Bool) async {
        guard isFreemiumEnabled() else { return }
        guard await !isUserAuthenticated() else { return }
        persistFirstScanResultIfAbsent(hasMatches: hasMatches)
    }

    public func recordSubscriptionUpgradeIfEligible() async {
        // By contract, the caller drives this from a real purchase-success / transition
        // signal, so we do NOT check isUserAuthenticated here. See spec §3.
        guard isFreemiumEnabled() else { return }
        persistSubscriptionUpgradeIfEligible()
    }

    // MARK: - Private synchronous helpers

    // Each helper re-checks `isFreemiumEnabled()` under the lock so the gate is atomic with
    // the write. The async callers also check upfront as a fast path, but the flag can
    // transition off while those methods are suspended on `await isUserAuthenticated()`;
    // re-checking here keeps the "flag off ⇒ no writes" invariant regardless of timing.

    private func persistProfileSaved() {
        lock.lock()
        defer { lock.unlock() }
        guard isFreemiumEnabled() else { return }
        userDefaults.set(true, forKey: Keys.didActivate)
        if userDefaults.object(forKey: Keys.firstProfileSavedTimestamp) == nil {
            userDefaults.set(Date(), forKey: Keys.firstProfileSavedTimestamp)
        }
    }

    private func persistFirstScanResultIfAbsent(hasMatches: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard isFreemiumEnabled() else { return }
        guard userDefaults.string(forKey: Keys.firstScanResult) == nil else { return }
        let value: FreemiumFirstScanResult = hasMatches ? .matchesFound : .noMatches
        userDefaults.set(value.rawValue, forKey: Keys.firstScanResult)
    }

    private func persistSubscriptionUpgradeIfEligible() {
        lock.lock()
        defer { lock.unlock() }
        guard isFreemiumEnabled() else { return }
        guard userDefaults.bool(forKey: Keys.didActivate) else { return }
        guard userDefaults.object(forKey: Keys.upgradeToSubscriptionTimestamp) == nil else { return }
        userDefaults.set(Date(), forKey: Keys.upgradeToSubscriptionTimestamp)
    }

    public func resetAllState() {
        lock.lock()
        defer { lock.unlock() }
        userDefaults.removeObject(forKey: Keys.didActivate)
        userDefaults.removeObject(forKey: Keys.firstProfileSavedTimestamp)
        userDefaults.removeObject(forKey: Keys.firstScanResult)
        userDefaults.removeObject(forKey: Keys.upgradeToSubscriptionTimestamp)
    }
}
