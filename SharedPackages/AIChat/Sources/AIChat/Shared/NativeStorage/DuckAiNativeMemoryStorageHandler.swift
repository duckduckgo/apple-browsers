//
//  DuckAiNativeMemoryStorageHandler.swift
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

/// In-memory `DuckAiNativeStorageHandling` for fire-mode contexts.
///
/// All chats, files, entries, and migration markers live for the lifetime
/// of the instance only. Releasing the instance — or closing the fire window
/// that owns it — discards the data with no on-disk residue.
///
/// `seedSource` is consulted once at init time to copy a small allow-list of
/// consent keys (see `DuckAiNativeStorageHandler.consentSeededEntryKeys`). This
/// lets a user who has accepted Duck.ai T&C / voice-mode consent in normal mode
/// avoid being re-prompted in fire mode. Updates the FE makes to these keys in
/// fire mode stay in memory and never reach disk.
public final class DuckAiNativeMemoryStorageHandler: DuckAiNativeStorageHandling {

    private let lock = NSLock()
    private var entries: [String: Any] = [:]
    private var chats: [String: Data] = [:]
    private var files: [String: DuckAiFileContent] = [:]
    private var migrations: [String: Bool] = [:]

    public init(seedSource: DuckAiNativeStorageHandling? = nil) {
        DuckAiNativeStorageHandler.seedConsentEntries(into: self, from: seedSource)
    }

    // MARK: - Entries

    public func putEntry(key: String, value: Any) throws {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = value
    }

    public func getEntry(key: String) throws -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    public func getAllEntries() throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func deleteEntry(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }

    public func deleteAllEntries() throws {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    public func replaceAllEntries(_ entries: [String: Any]) throws {
        lock.lock()
        defer { lock.unlock() }
        self.entries = entries
    }

    // MARK: - Chats

    public func putChat(chatId: String, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        chats[chatId] = data
    }

    public func putChats(_ chats: [DuckAiChatRecord]) throws {
        lock.lock()
        defer { lock.unlock() }
        for chat in chats where !chat.chatId.isEmpty {
            self.chats[chat.chatId] = chat.data
        }
    }

    public func getChat(chatId: String) throws -> DuckAiChatRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = chats[chatId] else { return nil }
        return DuckAiChatRecord(chatId: chatId, data: data)
    }

    public func getAllChats() throws -> [DuckAiChatRecord] {
        lock.lock()
        defer { lock.unlock() }
        return chats.map { DuckAiChatRecord(chatId: $0.key, data: $0.value) }
    }

    public func deleteChat(chatId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        chats.removeValue(forKey: chatId)
    }

    public func deleteAllChats() throws {
        lock.lock()
        defer { lock.unlock() }
        chats.removeAll()
    }

    // MARK: - Files

    public func putFile(uuid: String, chatId: String, data: Data) throws {
        guard let normalized = UUID(uuidString: uuid)?.uuidString else {
            throw DuckAiNativeDataStoreError.invalidFileIdentifier
        }
        lock.lock()
        defer { lock.unlock() }
        files[normalized] = DuckAiFileContent(uuid: normalized, chatId: chatId, data: data)
    }

    public func getFile(uuid: String) throws -> DuckAiFileContent? {
        guard let normalized = UUID(uuidString: uuid)?.uuidString else {
            throw DuckAiNativeDataStoreError.invalidFileIdentifier
        }
        lock.lock()
        defer { lock.unlock() }
        return files[normalized]
    }

    public func listFiles() throws -> [DuckAiFileMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return files.values.map { DuckAiFileMetadata(uuid: $0.uuid, chatId: $0.chatId, dataSize: $0.data.count) }
    }

    public func deleteFile(uuid: String) throws {
        guard let normalized = UUID(uuidString: uuid)?.uuidString else {
            throw DuckAiNativeDataStoreError.invalidFileIdentifier
        }
        lock.lock()
        defer { lock.unlock() }
        files.removeValue(forKey: normalized)
    }

    public func deleteFiles(chatId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        for (uuid, file) in files where file.chatId == chatId {
            files.removeValue(forKey: uuid)
        }
    }

    public func deleteAllFiles() throws {
        lock.lock()
        defer { lock.unlock() }
        files.removeAll()
    }

    // MARK: - Migration

    public func isMigrationDone() throws -> Bool {
        try DuckAiMigrationKey.allKeys.allSatisfy { try isMigrationDone(key: $0) }
    }

    public func isMigrationDone(key: String) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return migrations[key] ?? false
    }

    public func markMigrationDone(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        migrations[key] = true
    }
}
