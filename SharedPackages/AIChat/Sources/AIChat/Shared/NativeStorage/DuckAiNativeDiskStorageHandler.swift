//
//  DuckAiNativeDiskStorageHandler.swift
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
import DuckAiDataStore
import Persistence

/// On-disk `DuckAiNativeStorageHandling`.
///
/// Entries are persisted as JSON in a key-value file store; chats and files are
/// delegated to a `DuckAiNativeDataStoring` (GRDB + filesystem). Construct via
/// `DuckAiNativeStorageHandler(.disk(path:...))`, which handles key derivation
/// and SQLCipher setup.
public final class DuckAiNativeDiskStorageHandler: DuckAiNativeStorageHandling {

    private let settingsStore: any ThrowingKeyedStoring<DuckAiNativeStorageSettings>
    private let dataStore: DuckAiNativeDataStoring
    private let settingsLock = NSLock()

    public init(
        settingsStore: any ThrowingKeyedStoring<DuckAiNativeStorageSettings>,
        dataStore: DuckAiNativeDataStoring
    ) {
        self.settingsStore = settingsStore
        self.dataStore = dataStore
    }

    // MARK: - Entries

    public func putEntry(key: String, value: Any) throws {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        var entries = try loadSettingsBlob()
        entries[key] = value
        try saveSettingsBlob(entries)
    }

    public func getEntry(key: String) throws -> Any? {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        let entries = try loadSettingsBlob()
        return entries[key]
    }

    public func getAllEntries() throws -> [String: Any] {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        return try loadSettingsBlob()
    }

    public func deleteEntry(key: String) throws {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        var entries = try loadSettingsBlob()
        entries.removeValue(forKey: key)
        try saveSettingsBlob(entries)
    }

    public func deleteAllEntries() throws {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        try settingsStore.set(nil, for: \.settings)
    }

    public func replaceAllEntries(_ entries: [String: Any]) throws {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        try saveSettingsBlob(entries)
    }

    // MARK: - Chats (delegation)

    public func putChat(chatId: String, data: Data) throws {
        try dataStore.putChat(chatId: chatId, data: data)
    }

    public func putChats(_ chats: [DuckAiChatRecord]) throws {
        try dataStore.putChats(chats)
    }

    public func getChat(chatId: String) throws -> DuckAiChatRecord? {
        try dataStore.getChat(chatId: chatId)
    }

    public func getAllChats() throws -> [DuckAiChatRecord] {
        try dataStore.getAllChats()
    }

    public func deleteChat(chatId: String) throws {
        try dataStore.deleteChat(chatId: chatId)
    }

    public func deleteAllChats() throws {
        try dataStore.deleteAllChats()
    }

    // MARK: - Files (delegation)

    public func putFile(uuid: String, chatId: String, data: Data) throws {
        try dataStore.putFile(uuid: uuid, chatId: chatId, data: data)
    }

    public func getFile(uuid: String) throws -> DuckAiFileContent? {
        try dataStore.getFile(uuid: uuid)
    }

    public func listFiles() throws -> [DuckAiFileMetadata] {
        try dataStore.listFiles()
    }

    public func deleteFile(uuid: String) throws {
        try dataStore.deleteFile(uuid: uuid)
    }

    public func deleteFiles(chatId: String) throws {
        try dataStore.deleteFiles(chatId: chatId)
    }

    public func deleteAllFiles() throws {
        try dataStore.deleteAllFiles()
    }

    // MARK: - Migration

    public func isMigrationDone() throws -> Bool {
        try DuckAiMigrationKey.allKeys.allSatisfy { try isMigrationDone(key: $0) }
    }

    public func isMigrationDone(key: String) throws -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        guard let data = try settingsStore.value(for: \.migrationStatus) else {
            return false
        }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Bool] else {
            return false
        }
        return dict[key] ?? false
    }

    public func markMigrationDone(key: String) throws {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        var dict: [String: Bool] = [:]
        // try? so corrupt JSON self-heals instead of blocking future markMigrationDone calls
        if let data = try settingsStore.value(for: \.migrationStatus),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] {
            dict = existing
        }
        dict[key] = true
        let data = try JSONSerialization.data(withJSONObject: dict)
        try settingsStore.set(data, for: \.migrationStatus)
    }

    // MARK: - Private helpers

    private func loadSettingsBlob() throws -> [String: Any] {
        guard let data = try settingsStore.value(for: \.settings) else {
            return [:]
        }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func saveSettingsBlob(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [])
        try settingsStore.set(data, for: \.settings)
    }
}
