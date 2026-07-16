//
//  SearchTokenFetcher.swift
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

import Common
import Foundation
import os.log

/// Fetches and caches a short-lived, opaque search token for the Search Token (Dindex) experiment.
///
/// Pure mechanism — no cohort/experiment logic; the caller gates on `.cohort == .treatment`. Thread-safe
/// via a single `NSLock` held only for cache reads/writes, never across the network call. The network
/// request itself is delegated to an injected `SearchTokenRequesting`.
///
/// - `fetchIfNeeded(userAgent:)` fetches only when there is no live token or the current token is within
///   `window` seconds of expiry (refresh-ahead), and coalesces concurrent triggers into one request.
/// - `retrieveToken()` returns the cached token synchronously while it is still within its TTL, else `nil`.
final class SearchTokenFetcher {

    private let requester: SearchTokenRequesting
    private let ttlProvider: () -> TimeInterval
    private let windowProvider: () -> TimeInterval
    private let now: () -> Date

    private let lock = NSLock()
    private var cachedToken: String?
    private var fetchedAt: Date?
    private var isFetching = false

    init(requester: SearchTokenRequesting,
         ttlProvider: @escaping () -> TimeInterval = { 300 },
         windowProvider: @escaping () -> TimeInterval = { 120 },
         now: @escaping () -> Date = Date.init) {
        self.requester = requester
        self.ttlProvider = ttlProvider
        self.windowProvider = windowProvider
        self.now = now
    }

    /// The cached token while it is still within its TTL, otherwise `nil`. Synchronous, non-blocking.
    func retrieveToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let cachedToken, let fetchedAt else { // Token Exists
            return nil
        }
        guard now().timeIntervalSince(fetchedAt) < ttlProvider() else { // Token is valid
            return nil
        }
        return cachedToken
    }

    /// Executes a refresh-ahead fetch if one is warranted. Skips when a fetch is already in
    /// flight or the current token still has more than `window` seconds of life.
    ///
    /// All locking is confined to the synchronous helpers below; the lock is never touched across the
    /// `await`, keeping this async-safe.
    func fetchIfNeeded(userAgent: String) async {
        guard beginFetching() else { return }
        defer { endFetching() }

        do {
            let token = try await requester.requestToken(userAgent: userAgent)
            store(token: token)
            Logger.general.debug("SearchToken: fetched (len=\(token.count, privacy: .public))")
        } catch {
            Logger.general.debug("SearchToken: fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Synchronous, lock-guarded state transitions

    /// Marks a fetch as in flight and returns whether the caller should proceed. Skips if a fetch is
    /// already running or the current token still has more than `window` seconds of life.
    private func beginFetching() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isFetching { return false }
        if let fetchedAt, cachedToken != nil, // Token exists
           ttlProvider() - now().timeIntervalSince(fetchedAt) > windowProvider() { // Token is fresh
            return false
        }
        isFetching = true
        return true
    }

    private func store(token: String) {
        lock.lock(); defer { lock.unlock() }
        cachedToken = token
        fetchedAt = now()
    }

    private func endFetching() {
        lock.lock(); defer { lock.unlock() }
        isFetching = false
    }
}
