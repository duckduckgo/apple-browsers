//
//  SubscriptionCachingService.swift
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
import Common
import os.log

/// Manages caching of `DuckDuckGoSubscription` with thread-safe access and expiration logic.
public protocol SubscriptionCachingService {

    /// Returns `true` if a non-expired cached subscription exists. Safe to call synchronously.
    var isPresent: Bool { get }

    /// Returns the cached subscription if it exists and has not expired.
    func get() async -> DuckDuckGoSubscription?

    /// Stores a subscription in the cache with appropriate expiration.
    func set(_ subscription: DuckDuckGoSubscription) async

    /// Clears the cached subscription. Synchronous: guaranteed complete on return.
    func reset()
}

/// Default implementation backed by `UserDefaultsCache<DuckDuckGoSubscription>`.
///
/// Actor isolation provides mutual exclusion for all mutations. Reads and the synchronous
/// `isPresent` property are `nonisolated` because `UserDefaultsCache` (backed by
/// `UserDefaults`) is documented as thread-safe by Apple.
///
/// Expiration is determined by:
/// - In DEBUG builds: default 20-minute expiration (avoids immediate invalidation of short-lived test subscriptions)
/// - In release builds: the subscription's `expiresOrRenewsAt` date if it is in the future, otherwise default expiration
public actor DefaultSubscriptionCachingService: SubscriptionCachingService {

    // nonisolated(unsafe): UserDefaultsCache is backed by UserDefaults which is thread-safe.
    // All mutations go through actor-isolated methods; concurrent reads via isPresent/get() are safe.
    nonisolated(unsafe) private let subscriptionCache: UserDefaultsCache<DuckDuckGoSubscription>

    public nonisolated var isPresent: Bool { subscriptionCache.get() != nil }

    public init(subscriptionCache: UserDefaultsCache<DuckDuckGoSubscription> = UserDefaultsCache<DuckDuckGoSubscription>(
        key: UserDefaultsCacheKey.subscription,
        settings: UserDefaultsCacheSettings(defaultExpirationInterval: .minutes(20))
    )) {
        self.subscriptionCache = subscriptionCache
    }

    public func get() -> DuckDuckGoSubscription? {
        subscriptionCache.get()
    }

    public func set(_ subscription: DuckDuckGoSubscription) {
        let expiryDate = subscription.expiresOrRenewsAt
#if DEBUG
        // In DEBUG the subscription duration is just a few minutes, we want to avoid the cache to be immediately invalidated
        let isInTheFuture = false
#else
        let isInTheFuture = expiryDate.isInTheFuture()
#endif
        if isInTheFuture {
            Logger.subscriptionCachingService.debug("Subscription cache set with expiration date: \(expiryDate, privacy: .public)")
            subscriptionCache.set(subscription, expires: expiryDate)
        } else {
            Logger.subscriptionCachingService.debug("Subscription cache set with default expiration date")
            subscriptionCache.set(subscription)
        }
    }

    // nonisolated: subscriptionCache is nonisolated(unsafe) and UserDefaults is thread-safe,
    // so no actor isolation is needed. This preserves the synchronous clearing guarantee.
    public nonisolated func reset() {
        subscriptionCache.reset()
    }
}
