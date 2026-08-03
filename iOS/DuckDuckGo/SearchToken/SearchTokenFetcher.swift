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
/// - `fetchIfNeeded(userAgent:)` fetches when there is no live token, the current token is within `window`
///   seconds of expiry (refresh-ahead), or the cached token was minted for a different UA; concurrent
///   triggers coalesce into one request.
/// - `retrieveToken()` returns the cached token while within its TTL
/// else `nil`. Only fetching is UA-aware; retrieval never withholds a live token.
final class SearchTokenFetcher {

    private let requester: SearchTokenRequesting
    private let ttlProvider: () -> TimeInterval
    private let windowProvider: () -> TimeInterval
    private let now: () -> Date

    private let lock = NSLock()
    private var cachedToken: String?
    private var cachedUserAgent: String?
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
        guard let cachedToken, let fetchedAt else { // Token exists
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
        guard beginFetching(userAgent: userAgent) else { return }
        defer { endFetching() }

        do {
            let token = try await requester.requestToken(userAgent: userAgent)
            store(token: token, userAgent: userAgent)
            Logger.general.debug("SearchToken: fetched (len=\(token.count, privacy: .public))")
        } catch {
            Logger.general.debug("SearchToken: fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Synchronous, lock-guarded state transitions

    /// Marks a fetch as in flight and returns whether the caller should proceed. Skips only if a fetch is
    /// already running, or a fresh token is already cached *for this same UA*; a UA change forces a refetch
    /// so the cached token tracks the current desktop/mobile state.
    private func beginFetching(userAgent: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isFetching { return false }
        if let fetchedAt, cachedToken != nil, cachedUserAgent == userAgent, // Fresh token already cached for this UA
           ttlProvider() - now().timeIntervalSince(fetchedAt) > windowProvider() { // Token is fresh
            return false
        }
        isFetching = true
        return true
    }

    private func store(token: String, userAgent: String) {
        lock.lock(); defer { lock.unlock() }
        cachedToken = token
        cachedUserAgent = userAgent
        fetchedAt = now()
    }

    private func endFetching() {
        lock.lock(); defer { lock.unlock() }
        isFetching = false
    }
}
