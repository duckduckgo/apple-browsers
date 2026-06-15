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
import DuckAiDataStore
import Foundation
import os.log
import Persistence

/// Coordinates server-side AI Chat deletion to mirror local clears (Fire/AutoClear).
/// Stores a timestamp when local data is cleared and retries the DELETE on next trigger until it succeeds.
public protocol AIChatSyncCleaning: AnyObject {
    func recordAutoClearBackgroundTimestamp(date: Date?) async
    func recordLocalClear(date: Date?) async
    func recordLocalClearFromAutoClearBackgroundTimestampIfPresent() async
    func recordChatDeletion(chatID: String) async
    func deleteIfNeeded() async
    func recordChatUpdate(chatID: String) async
    func updateIfNeeded() async
    func scheduleSync()
}

public final class AIChatSyncCleaner: AIChatSyncCleaning {

    public enum Keys {
        public static let lastClearTimestamp = "com.duckduckgo.aichat.sync.lastClearTimestamp"
        public static let autoClearBackgroundTimestamp = "com.duckduckgo.aichat.sync.autoClearBackgroundTimestamp"
        public static let chatIDsToDelete = "com.duckduckgo.aichat.sync.chatIDsToDelete"
        public static let chatIDsToUpdate = "com.duckduckgo.aichat.sync.chatIDsToUpdate"
    }

    private let sync: DDGSyncing
    private let keyValueStore: ThrowingKeyValueStoring
    private let featureFlagProvider: AIChatFeatureFlagProviding
    private let dateProvider: () -> Date
    private let state: AIChatSyncState
    private let storageHandler: DuckAiNativeStorageHandling?
    private let httpRequestErrorHandler: ((Error) -> Void)?

    private var canUseAIChatSyncDelete: Bool {
        guard featureFlagProvider.isAIChatSyncEnabled() else {
            return false
        }

        guard featureFlagProvider.supportsSyncChatsDeletion() else {
            return false
        }

        guard sync.authState != .inactive else {
            return false
        }

        return isChatHistoryEnabled
    }

    private var canUseAIChatSyncUpdate: Bool {
        guard featureFlagProvider.isAIChatSyncEnabled() else { return false }
        guard featureFlagProvider.supportsSyncChatsUpdate() else { return false }
        guard sync.authState != .inactive else { return false }
        return isChatHistoryEnabled
    }

    private var isChatHistoryEnabled: Bool {
        sync.isAIChatHistoryEnabled
    }

    public init(sync: DDGSyncing,
                keyValueStore: ThrowingKeyValueStoring,
                featureFlagProvider: AIChatFeatureFlagProviding,
                storageHandler: DuckAiNativeStorageHandling? = nil,
                dateProvider: @escaping () -> Date = Date.init,
                httpRequestErrorHandler: ((Error) -> Void)? = nil) {
        self.sync = sync
        self.keyValueStore = keyValueStore
        self.featureFlagProvider = featureFlagProvider
        self.storageHandler = storageHandler
        self.dateProvider = dateProvider
        self.state = AIChatSyncState(store: keyValueStore)
        self.httpRequestErrorHandler = httpRequestErrorHandler
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

    public func recordChatDeletion(chatID: String) async {
        guard canUseAIChatSyncDelete else {
            return
        }

        await state.addChatToBeDeleted(chatID: chatID)
    }

    /// If a clear timestamp exists, attempt to delete AI Chats up to that time on the server.
    /// On success, the timestamp is removed; on failure it is retained for a later retry.
    public func deleteIfNeeded() async {
        guard canUseAIChatSyncDelete else {
            return
        }

        await deleteByTimestamp()
        await deletePendingChats()
    }

    public func scheduleSync() {
        guard canUseAIChatSyncDelete else {
            return
        }

        sync.scheduler.notifyDataChanged()
    }

    private func deleteByTimestamp() async {
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
            httpRequestErrorHandler?(error)
            Logger.aiChat.debug("Failed to delete AI Chats: \(error.localizedDescription)")
        }
    }

    private func deletePendingChats() async {
        guard let pendingChats = await state.readChatIDsToBeDeleted(),
              !pendingChats.isEmpty else {
            Logger.aiChat.debug("No chat IDs pending deletion")
            return
        }

        let chatsToDelete = Set(pendingChats)
        do {
            try await sync.deleteAIChats(chatIds: Array(chatsToDelete))
            // Only remove the specific chat IDs that were successfully deleted
            await state.removeChatsFromPending(chatIDs: chatsToDelete)
        } catch {
            httpRequestErrorHandler?(error)
            Logger.aiChat.debug("Failed to delete pending ai chats: \(error.localizedDescription)")
        }
    }

    // MARK: - Updates

    public func recordChatUpdate(chatID: String) async {
        guard canUseAIChatSyncUpdate else { return }
        await state.addChatToBeUpdated(chatID: chatID)
        sync.scheduler.notifyDataChanged()
    }

    public func updateIfNeeded() async {
        guard canUseAIChatSyncUpdate, let storageHandler else { return }
        let pending = await state.readChatIDsToBeUpdated() ?? []
        guard !pending.isEmpty else { return }

        // Delete-wins: skip ids that are also queued for deletion.
        let pendingDeletes = Set((await state.readChatIDsToBeDeleted()) ?? [])
        let candidates = Array(Set(pending).subtracting(pendingDeletes))
        guard !candidates.isEmpty else { return }

        let updates = buildPendingUpdates(for: candidates)
        await dropUnresolvablePendingUpdates(candidates: Set(candidates), updates: updates)

        guard !updates.isEmpty else { return }

        let resolvedIDs = Set(updates.map(\.chatId))
        do {
            try await sync.patchAIChats(updates: updates)
            await state.removeChatsFromPendingUpdates(chatIDs: resolvedIDs)
        } catch {
            httpRequestErrorHandler?(error)
            Logger.aiChat.debug("Failed to patch pending ai chats: \(error.localizedDescription)")
        }
    }

    private func buildPendingUpdates(for candidates: [String]) -> [AIChatUpdate] {
        guard let storageHandler else { return [] }
        return candidates.compactMap { chatId in
            guard let record = try? storageHandler.getChat(chatId: chatId) else { return nil }
            return AIChatUpdate(record: record)
        }
    }

    private func dropUnresolvablePendingUpdates(candidates: Set<String>, updates: [AIChatUpdate]) async {
        // Ids that no longer resolve in storage (e.g. chat deleted locally) can never be synced —
        // drop them now so they don't linger in the queue and get retried on every cycle.
        let resolvedIDs = Set(updates.map(\.chatId))
        let unresolvableIDs = candidates.subtracting(resolvedIDs)
        guard !unresolvableIDs.isEmpty else { return }
        await state.removeChatsFromPendingUpdates(chatIDs: unresolvableIDs)
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

    func addChatToBeDeleted(chatID: String) {
        var currentIDs: Set<String> = Set((try? store.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]) ?? [])
        currentIDs.insert(chatID)
        try? store.set(Array(currentIDs), forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
    }

    func readChatIDsToBeDeleted() -> [String]? {
        try? store.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]
    }

    func removeChatsFromPending(chatIDs: Set<String>) {
        var currentIDs = Set((try? store.object(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete) as? [String]) ?? [])
        currentIDs.subtract(chatIDs)
        if currentIDs.isEmpty {
            try? store.removeObject(forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
        } else {
            try? store.set(Array(currentIDs), forKey: AIChatSyncCleaner.Keys.chatIDsToDelete)
        }
    }

    // MARK: - Update queue

    func addChatToBeUpdated(chatID: String) {
        var current: Set<String> = Set((try? store.object(forKey: AIChatSyncCleaner.Keys.chatIDsToUpdate) as? [String]) ?? [])
        current.insert(chatID)
        try? store.set(Array(current), forKey: AIChatSyncCleaner.Keys.chatIDsToUpdate)
    }

    func readChatIDsToBeUpdated() -> [String]? {
        try? store.object(forKey: AIChatSyncCleaner.Keys.chatIDsToUpdate) as? [String]
    }

    func removeChatsFromPendingUpdates(chatIDs: Set<String>) {
        var current = Set((try? store.object(forKey: AIChatSyncCleaner.Keys.chatIDsToUpdate) as? [String]) ?? [])
        current.subtract(chatIDs)
        if current.isEmpty {
            try? store.removeObject(forKey: AIChatSyncCleaner.Keys.chatIDsToUpdate)
        } else {
            try? store.set(Array(current), forKey: AIChatSyncCleaner.Keys.chatIDsToUpdate)
        }
    }
}

extension AIChatUpdate {

    /// Builds an update from a stored chat record, reading the `pinned` flag from its raw JSON blob.
    /// Returns `nil` when the blob can't be parsed as a JSON object.
    init?(record: DuckAiChatRecord) {
        guard let json = try? JSONSerialization.jsonObject(with: record.data) as? [String: Any] else {
            return nil
        }
        self.init(chatId: record.chatId, pinned: (json["pinned"] as? Bool) ?? false)
    }
}
