//
//  SubscriptionTokenRefreshDebugSettings.swift
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
import Persistence
import Subscription

/// One run of the token keep-alive, kept so the debug menu can show what happened last.
struct SubscriptionTokenRefreshRun: Codable, Equatable {

    /// What started the run.
    enum Trigger: String, Codable {
        case foreground
        case signIn
        case backgroundTask
        case debugMenu
    }

    /// When the run finished.
    let date: Date
    let trigger: Trigger
    /// The keep-alive outcome, as `SubscriptionTokenKeepAlive.Outcome.description`.
    let outcome: String
    /// When the background task was scheduled for, or nil when it was cancelled.
    let nextCheck: Date?
}

/// Debug overrides for the token keep-alive intervals, and the record of its last run.
protocol SubscriptionTokenRefreshDebugStoring: AnyObject {

    /// Replaces `SubscriptionTokenKeepAlive.defaultMaxRefreshTokenAge` for internal users. Nil uses the default.
    var maxRefreshTokenAgeOverride: TimeInterval? { get set }

    /// Replaces `SubscriptionTokenKeepAlive.defaultRetryInterval` for internal users. Nil uses the default.
    var retryIntervalOverride: TimeInterval? { get set }

    /// The last keep-alive run, or nil when it hasn't run since the record was cleared.
    var lastRun: SubscriptionTokenRefreshRun? { get set }
}

/// `SubscriptionTokenRefreshDebugStoring` backed by a key-value store.
final class SubscriptionTokenRefreshDebugSettings: SubscriptionTokenRefreshDebugStoring {

    private enum Key: String {
        case maxRefreshTokenAgeOverride = "subscription-token-refresh-debug-max-refresh-token-age"
        case retryIntervalOverride = "subscription-token-refresh-debug-retry-interval"
        case lastRun = "subscription-token-refresh-debug-last-run"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    /// - Parameter keyValueStore: Where the overrides and the last run are stored.
    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var maxRefreshTokenAgeOverride: TimeInterval? {
        get { (try? keyValueStore.object(forKey: Key.maxRefreshTokenAgeOverride.rawValue)) as? TimeInterval }
        set { try? keyValueStore.set(newValue, forKey: Key.maxRefreshTokenAgeOverride.rawValue) }
    }

    var retryIntervalOverride: TimeInterval? {
        get { (try? keyValueStore.object(forKey: Key.retryIntervalOverride.rawValue)) as? TimeInterval }
        set { try? keyValueStore.set(newValue, forKey: Key.retryIntervalOverride.rawValue) }
    }

    var lastRun: SubscriptionTokenRefreshRun? {
        get {
            guard let data = (try? keyValueStore.object(forKey: Key.lastRun.rawValue)) as? Data else { return nil }
            return try? JSONDecoder().decode(SubscriptionTokenRefreshRun.self, from: data)
        }
        set {
            let data = newValue.flatMap { try? JSONEncoder().encode($0) }
            try? keyValueStore.set(data, forKey: Key.lastRun.rawValue)
        }
    }
}

/// The intervals the token keep-alive uses: the debug overrides for internal users, the defaults for everyone else.
/// Both are resolved on every call, so a change in the debug menu applies to the next run.
struct SubscriptionTokenRefreshIntervals {

    private let debugSettings: SubscriptionTokenRefreshDebugStoring
    private let isInternalUser: () -> Bool

    /// - Parameters:
    ///   - debugSettings: Where the overrides are read from.
    ///   - isInternalUser: Whether the overrides apply.
    init(debugSettings: SubscriptionTokenRefreshDebugStoring, isInternalUser: @escaping () -> Bool) {
        self.debugSettings = debugSettings
        self.isInternalUser = isInternalUser
    }

    /// The refresh token age after which the token is refreshed.
    func maxRefreshTokenAge() -> TimeInterval {
        override(debugSettings.maxRefreshTokenAgeOverride) ?? SubscriptionTokenKeepAlive.defaultMaxRefreshTokenAge
    }

    /// The delay before trying again after a failed refresh.
    func retryInterval() -> TimeInterval {
        override(debugSettings.retryIntervalOverride) ?? SubscriptionTokenKeepAlive.defaultRetryInterval
    }

    private func override(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value > 0, isInternalUser() else { return nil }
        return value
    }
}

extension Notification.Name {

    /// Posted by the debug menu to run the token keep-alive now.
    static let subscriptionTokenRefreshDebugRunRequested = Notification.Name("com.duckduckgo.subscription.tokenRefresh.debugRunRequested")

    /// Posted by `SubscriptionTokenRefreshTask` after each run, once `SubscriptionTokenRefreshDebugStoring.lastRun` is updated.
    static let subscriptionTokenRefreshDidRun = Notification.Name("com.duckduckgo.subscription.tokenRefresh.didRun")
}
