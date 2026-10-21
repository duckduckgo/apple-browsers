//
//  PromptCooldownMigrator.swift
//  DuckDuckGo
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

import Foundation
import Persistence

/// Migrates the `lastModalShownDate` from the old Default Browser storage to the new global cooldown storage.
///
/// Previously, Default Browser kept track of last prompt shown date using `lastModalShownDate` in its own storage.
/// With the introduction of centralised modal coordination, all prompts now share a global cooldown period.
final class PromptCooldownMigrator {

    private let keyValueStore: ThrowingKeyValueStoring

    enum MigrationKey {
        static let defaultBrowserLastModalShownDate = DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey.lastModalShownDate.rawValue
        static let globalCooldownTimestamp = PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp
    }

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    /// Performs the migration if needed.
    /// - Returns: `true` if migration was performed, `false` if already completed or no data to migrate
    @discardableResult
    func migrateIfNeeded() -> Bool {
        Logger.modalPrompt.info("[Modal Prompt Coordination] - Cooldown Migration - Starting migration...")

        // 1. Read old Default Browser storage
        guard let lastModalShownDate = readDefaultBrowserLastModalShownDate() else {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Cooldown Migration - Migration already completed or nothing to migrate.")
            return false
        }

        Logger.modalPrompt.info("[Modal Prompt Coordination] - Found old timestamp to migrate: \(lastModalShownDate)")

        // 2. Check if global cooldown already has a value. Should never happen. Defensive code.
        if let existingGlobalTimestamp = readGlobalCooldownTimestamp() {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Global cooldown already has timestamp \(existingGlobalTimestamp). Using most recent value.")

            // 2.1 Use the most recent timestamp
            let mostRecentTimestamp = max(lastModalShownDate, existingGlobalTimestamp)
            writeGlobalCooldownTimestamp(mostRecentTimestamp)
        } else {
            // 2.2 Write to global cooldown storage
            writeGlobalCooldownTimestamp(lastModalShownDate)
        }

        // 3. Delete old value to mark migration as complete
        deleteDefaultBrowserLastModalShownDate()

        Logger.modalPrompt.info("[Modal Prompt Coordination] - Migration completed successfully. Migrated timestamp: \(lastModalShownDate)")
        return true
    }
}

// MARK: - Private

private extension PromptCooldownMigrator {

    func readDefaultBrowserLastModalShownDate() -> TimeInterval? {
        do {
            return try keyValueStore.object(forKey: MigrationKey.defaultBrowserLastModalShownDate) as? TimeInterval
        } catch {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Cooldown Migration - Failed to read Default Browser lastModalShownDate: \(error.localizedDescription)")
            return nil
        }
    }

    func readGlobalCooldownTimestamp() -> TimeInterval? {
        do {
            return try keyValueStore.object(forKey: MigrationKey.globalCooldownTimestamp) as? TimeInterval
        } catch {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Cooldown Migration - Failed to read global cooldown timestamp: \(error.localizedDescription)")
            return nil
        }
    }

    func writeGlobalCooldownTimestamp(_ timestamp: TimeInterval) {
        do {
            try keyValueStore.set(timestamp, forKey: MigrationKey.globalCooldownTimestamp)
        } catch {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Cooldown Migration - Failed to write global cooldown timestamp: \(error.localizedDescription)")
        }
    }

    func deleteDefaultBrowserLastModalShownDate() {
        do {
            try keyValueStore.removeObject(forKey: MigrationKey.defaultBrowserLastModalShownDate)
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Cooldown Migration - Deleted old Default Browser lastModalShownDate.")
        } catch {
            Logger.modalPrompt.info("[Modal Prompt Coordination] - Cooldown Migration - Failed to delete old Default Browser lastModalShownDate: \(error.localizedDescription)")
        }
    }
}
