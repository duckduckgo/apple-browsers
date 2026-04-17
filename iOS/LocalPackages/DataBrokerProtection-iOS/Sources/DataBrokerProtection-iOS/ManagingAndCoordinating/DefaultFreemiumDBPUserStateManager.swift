//
//  DefaultFreemiumDBPUserStateManager.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
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
    private let lock = NSLock()

    public init(userDefaults: UserDefaults, isUserAuthenticated: @escaping () async -> Bool) {
        self.userDefaults = userDefaults
        self.isUserAuthenticated = isUserAuthenticated
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

    // MARK: - Write-side methods (implemented in later tasks)

    public func recordProfileSavedIfNeeded() async {
        fatalError("Not implemented")
    }

    public func recordFirstScanResultIfNeeded(hasMatches: Bool) async {
        fatalError("Not implemented")
    }

    public func recordSubscriptionUpgradeIfNeeded() async {
        fatalError("Not implemented")
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
