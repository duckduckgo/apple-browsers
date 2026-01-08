//
//  AIChatSyncCleaner.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import DDGSync
import Foundation
import os.log
import Persistence

/// Coordinates server-side AI Chat deletion to mirror local clears (Fire/AutoClear).
/// Stores a timestamp when local data is cleared and retries the DELETE on next trigger until it succeeds.
public protocol AIChatSyncCleaning: AnyObject {
    func recordAutoClearBackgroundTimestamp(date: Date?) async
    func recordLocalClear(date: Date?) async
    func recordLocalClearFromAutoClearBackgroundTimestampIfPresent() async
    func deleteIfNeeded() async
}

public final class AIChatSyncCleaner: AIChatSyncCleaning {

    public enum Keys {
        public static let lastClearTimestamp = "com.duckduckgo.aichat.sync.lastClearTimestamp"
        public static let autoClearBackgroundTimestamp = "com.duckduckgo.aichat.sync.autoClearBackgroundTimestamp"
    }

    private let sync: DDGSyncing
    private let keyValueStore: ThrowingKeyValueStoring
    private let featureFlagProvider: AIChatFeatureFlagProviding
    private let dateProvider: () -> Date
    private let state: AIChatSyncState

    private var canUseAIChatSyncDelete: Bool {
        guard featureFlagProvider.isAIChatSyncEnabled() else {
            return false
        }

        guard sync.authState != .inactive else {
            return false
        }

        return isChatHistoryEnabled
    }

    private var isChatHistoryEnabled: Bool {
        sync.isAIChatHistoryEnabled
    }

    public init(sync: DDGSyncing,
                keyValueStore: ThrowingKeyValueStoring,
                featureFlagProvider: AIChatFeatureFlagProviding,
                dateProvider: @escaping () -> Date = Date.init) {
        self.sync = sync
        self.keyValueStore = keyValueStore
        self.featureFlagProvider = featureFlagProvider
        self.dateProvider = dateProvider
        self.state = AIChatSyncState(store: keyValueStore)
    }

    /// Record the time of a local clear (Fire/autoclear). This timestamp will be used for the next delete call.
    public func recordLocalClear(date: Date? = nil) async {
        guard canUseAIChatSyncDelete else {
            return
        }

        let timestamp = (date ?? dateProvider()).timeIntervalSince1970

        await state.setLastClear(timestamp: timestamp)
    }

    /// Records the timestamp when the app is backgrounded with AutoClear enabled.
    /// This timestamp will later be promoted to a delete-until timestamp once the local AutoClear actually runs.
    public func recordAutoClearBackgroundTimestamp(date: Date? = nil) async {
        guard canUseAIChatSyncDelete else {
            return
        }

        let timestamp = (date ?? dateProvider()).timeIntervalSince1970
        await state.setAutoClearBackground(timestamp: timestamp)
    }

    /// Converts the persisted AutoClear background timestamp into a delete-until timestamp, if present.
    ///
    /// This is used to avoid deleting server-side AI Chats before a local AutoClear actually runs.
    public func recordLocalClearFromAutoClearBackgroundTimestampIfPresent() async {
        guard canUseAIChatSyncDelete else {
            return
        }

        await state.promoteAutoClearToLastClear()
    }

    /// If a clear timestamp exists, attempt to delete AI Chats up to that time on the server.
    /// On success, the timestamp is removed; on failure it is retained for a later retry.
    public func deleteIfNeeded() async {
        guard canUseAIChatSyncDelete else {
            return
        }

        guard let timestampValue = await state.readLastClear() else {
            return
        }

        let untilDate = Date(timeIntervalSince1970: timestampValue)
        Logger.aiChat.debug("Deleting AI Chats up until \(untilDate)")

        do {
            try await sync.deleteAIChats(until: untilDate)

            // Only clear the stored timestamp if it hasn't been updated since we read it.
            await state.clearLastClearIf(unchanged: timestampValue)
        } catch {
            Logger.aiChat.debug("Failed to delete AI Chats: \(error.localizedDescription)")
        }
    }
}

private actor AIChatSyncState {
    private let store: ThrowingKeyValueStoring

    init(store: ThrowingKeyValueStoring) {
        self.store = store
    }

    func setAutoClearBackground(timestamp: Double) {
        try? store.set(timestamp, forKey: AIChatSyncCleaner.Keys.autoClearBackgroundTimestamp)
    }

    func setLastClear(timestamp: Double) {
        try? store.set(timestamp, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
    }

    func promoteAutoClearToLastClear() {
        guard let timestampValue = try? store.object(forKey: AIChatSyncCleaner.Keys.autoClearBackgroundTimestamp) as? Double else {
            return
        }

        try? store.set(timestampValue, forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        try? store.removeObject(forKey: AIChatSyncCleaner.Keys.autoClearBackgroundTimestamp)
    }

    func readLastClear() -> Double? {
        try? store.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp) as? Double
    }

    func clearLastClearIf(unchanged expected: Double) {
        if let currentTimestamp = try? store.object(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp) as? Double,
           currentTimestamp == expected {
            try? store.removeObject(forKey: AIChatSyncCleaner.Keys.lastClearTimestamp)
        }
    }
}
