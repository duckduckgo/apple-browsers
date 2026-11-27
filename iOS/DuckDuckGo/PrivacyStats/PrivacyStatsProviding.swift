//
//  PrivacyStatsProviding.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PixelKit
import PrivacyStats

protocol PrivacyStatsProviding {
    func recordBlockedTracker(_ name: String) async
    func fetchPrivacyStatsTotalCount() async -> Int64
    func clearPrivacyStats() async -> Result<Void, Error>
    func handleAppTermination() async
}

extension PrivacyStats: PrivacyStatsProviding { }

/// Stands in for `PrivacyStats` when its store cannot be opened: nothing is recorded and counts read as zero.
/// Clearing still deletes the store's files, so the Fire button removes stats left from earlier sessions.
final class UnavailablePrivacyStats: PrivacyStatsProviding {

    private let storeLocation: URL

    init(storeLocation: URL) {
        self.storeLocation = storeLocation
    }

    func recordBlockedTracker(_ name: String) async {}
    func fetchPrivacyStatsTotalCount() async -> Int64 { 0 }
    func handleAppTermination() async {}

    func clearPrivacyStats() async -> Result<Void, Error> {
        Result { try PrivacyStatsDatabase.deleteStoreFiles(at: storeLocation) }
    }
}

/// Loads the Privacy Stats store on a background queue so launch never waits on Core Data or disk I/O.
/// Calls made while the store loads wait for it, except the total count, which reads zero until the store has loaded.
final class DeferredPrivacyStats: PrivacyStatsProviding {

    private let loadTask: Task<PrivacyStatsProviding, Never>
    /// Lets the count read the loaded store without waiting for the load.
    private let loaded: Locked<PrivacyStatsProviding?>

    init(load: @escaping () -> PrivacyStatsProviding = { DeferredPrivacyStats.loadStore() }) {
        let loaded = Locked<PrivacyStatsProviding?>(wrappedValue: nil)
        self.loaded = loaded
        // The load blocks on Core Data, so it runs on a GCD queue rather than a Swift concurrency thread.
        loadTask = Task {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let stats = load()
                    loaded.wrappedValue = stats
                    continuation.resume(returning: stats)
                }
            }
        }
    }

    /// Opens the store, recovering from corruption, and falls back to `UnavailablePrivacyStats` when it can't be opened.
    static func loadStore(location: URL = PrivacyStatsDatabase.defaultLocation,
                          pixelFiring: (any PixelKitFiring)? = PixelKit.shared) -> PrivacyStatsProviding {
        assert(!Thread.isMainThread, "The Privacy Stats store must not load on the main thread")
        if let database = PrivacyStatsDatabase(location: location, pixelFiring: pixelFiring) {
            return PrivacyStats(databaseProvider: database)
        }
        return UnavailablePrivacyStats(storeLocation: location)
    }

    func recordBlockedTracker(_ name: String) async {
        await loadTask.value.recordBlockedTracker(name)
    }

    /// The tab switcher awaits this before it opens, so it reads zero rather than wait for a slow load.
    func fetchPrivacyStatsTotalCount() async -> Int64 {
        await loaded.wrappedValue?.fetchPrivacyStatsTotalCount() ?? 0
    }

    func clearPrivacyStats() async -> Result<Void, Error> {
        await loadTask.value.clearPrivacyStats()
    }

    func handleAppTermination() async {
        await loadTask.value.handleAppTermination()
    }
}
